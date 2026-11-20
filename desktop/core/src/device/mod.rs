//! The iPhone, over USB through usbmuxd or over Wi-Fi with a pairing record.
//!
//! A [`Phone`] is a UDID plus how to reach it; [`Phone::provider`] gives idevice's connection
//! factory for every service. Nothing here drives the phone's screen: pairing, Developer Mode,
//! installing and files are all lockdown services the person confirms on the phone themselves.
pub mod container;
pub mod ddi;
pub mod devmode;
pub mod info;
pub mod install;
pub mod logs;
pub mod pairing;
pub mod running;

use crate::{Error, Result};
use idevice::{
    pairing_file::PairingFile,
    provider::{IdeviceProvider, TcpProvider, UsbmuxdProvider},
    usbmuxd::{Connection, RawPacket, UsbmuxdAddr, UsbmuxdConnection},
};
use serde::{Deserialize, Serialize};
use std::net::IpAddr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub const LABEL: &str = "poki-setup";

/// How the phone is reached right now.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Link {
    /// Through usbmuxd over the cable.
    Usb,
    /// Through usbmuxd, which found it on the network (macOS and Windows list Wi-Fi-synced phones).
    Muxed { address: IpAddr },
    /// Straight to lockdown on TCP 62078 with our pairing record (any platform, same Wi-Fi).
    Wifi { address: IpAddr },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Phone {
    pub udid: String,
    pub link: Link,
    /// usbmuxd's own id for the attachment, when it came from usbmuxd.
    #[serde(default)]
    pub mux_id: Option<u32>,
}

/// usbmuxd lists a phone once per way it reaches it (a cable and Wi-Fi sync, sometimes two
/// addresses), all with the same udid. People pick a phone, not a link: keep one entry per udid,
/// the USB one when there is one, then the order usbmuxd gave.
fn one_per_phone(mut phones: Vec<Phone>) -> Vec<Phone> {
    phones.sort_by_key(|p| !matches!(p.link, Link::Usb));
    let mut seen = std::collections::HashSet::new();
    phones.retain(|p| seen.insert(p.udid.clone()));
    phones
}

impl Phone {
    /// The phones usbmuxd knows, one entry per phone: USB first, then network ones.
    pub async fn list() -> Result<Vec<Phone>> {
        let mut mux = mux_addr().connect(0).await?;
        let devices = mux.get_devices().await?;
        let phones: Vec<Phone> = devices
            .into_iter()
            .map(|d| Phone {
                link: match d.connection_type {
                    Connection::Usb => Link::Usb,
                    Connection::Network(ip) => Link::Muxed { address: ip },
                    Connection::Unknown(_) => Link::Usb,
                },
                udid: d.udid,
                mux_id: Some(d.device_id),
            })
            .collect();
        Ok(one_per_phone(phones))
    }

    /// A phone on the same Wi-Fi, reached with the pairing record this computer saved for it.
    pub fn over_wifi(udid: impl Into<String>, address: IpAddr) -> Phone {
        Phone { udid: udid.into(), link: Link::Wifi { address }, mux_id: None }
    }

    /// idevice's connection factory for this phone. Over USB it is usbmuxd's; over Wi-Fi it needs
    /// the pairing record from [`pairing::saved`].
    pub fn provider(&self) -> Result<Box<dyn IdeviceProvider>> {
        match &self.link {
            Link::Usb | Link::Muxed { .. } => Ok(Box::new(UsbmuxdProvider {
                addr: mux_addr(),
                tag: 1,
                udid: self.udid.clone(),
                device_id: self.mux_id.unwrap_or(0),
                label: LABEL.into(),
            })),
            Link::Wifi { address } => {
                let pairing_file = pairing::saved(&self.udid)?
                    .ok_or_else(|| Error::device("No pairing record for this iPhone on this computer. Plug it in once to pair."))?;
                Ok(Box::new(TcpProvider { addr: *address, scope_id: None, pairing_file, label: LABEL.into() }))
            }
        }
    }

    pub fn is_usb(&self) -> bool { matches!(self.link, Link::Usb) }
}

fn mux_addr() -> UsbmuxdAddr {
    UsbmuxdAddr::from_env_var().unwrap_or_default()
}

/// The pairing record usbmuxd holds for a UDID (macOS and Windows keep one per trusted phone).
pub async fn mux_pairing_record(udid: &str) -> Result<Option<PairingFile>> {
    // idevice 0.1.68 drops the Result number when PairRecordData is absent.
    let mut socket = mux_addr().to_socket().await.map_err(Error::from)?;
    let request = RawPacket::new(
        plist::Dictionary::from_iter([
            ("MessageType", plist::Value::from("ReadPairRecord")),
            ("PairRecordID", plist::Value::from(udid)),
        ]),
        UsbmuxdConnection::XML_PLIST_VERSION,
        UsbmuxdConnection::PLIST_MESSAGE_TYPE,
        0,
    );
    socket.write_all(&Vec::from(request)).await.map_err(idevice::IdeviceError::from)?;
    let size = socket.read_u32_le().await.map_err(idevice::IdeviceError::from)?;
    if !(16..=1024 * 1024).contains(&size) {
        return Err(Error::device("The iPhone service sent an invalid pairing record response."));
    }
    let mut packet = vec![0; size as usize];
    packet[..4].copy_from_slice(&size.to_le_bytes());
    socket.read_exact(&mut packet[4..]).await.map_err(idevice::IdeviceError::from)?;
    let response = RawPacket::try_from(packet.as_slice())
        .map_err(|_| Error::device("The iPhone service sent an invalid pairing record response."))?;
    if let Some(data) = response.plist.get("PairRecordData").and_then(plist::Value::as_data) {
        return Ok(Some(PairingFile::from_bytes(data)?));
    }
    let number = response.plist.get("Number").and_then(plist::Value::as_unsigned_integer);
    if response.plist.get("MessageType").and_then(plist::Value::as_string) == Some("Result")
        && number == Some(2)
    {
        return Ok(None);
    }
    Err(Error::device("Poki Setup could not read the iPhone's system pairing record. Reconnect the iPhone and try again."))
}

#[cfg(test)]
mod list_tests {
    use super::*;

    #[test]
    fn a_phone_on_cable_and_wifi_is_listed_once_by_cable() {
        let wifi = |u: &str| Phone { udid: u.into(), link: Link::Muxed { address: "192.168.1.5".parse().unwrap() }, mux_id: Some(2) };
        let usb = |u: &str| Phone { udid: u.into(), link: Link::Usb, mux_id: Some(1) };
        let l = one_per_phone(vec![wifi("A"), usb("A"), wifi("B"), wifi("B")]);
        assert_eq!(l.len(), 2);
        assert_eq!(l[0].udid, "A");
        assert!(matches!(l[0].link, Link::Usb));
        assert_eq!(l[1].udid, "B");
    }
}
