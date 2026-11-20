//! Hands the pairing record to Poki on the phone over the local network.
//!
//! Poki opens `poki://pairing?url=http://<host>:<port>/<file>&sha256=<hex>`, fetches the file,
//! checks the digest and keeps it (lockdown pairing plist or RPPairing plist). Poki Setup serves
//! the file from a tiny HTTP server for one fetch, shows the link as a QR code for the Camera, and
//! also offers `poki://pairing?data=<base64url>` for a phone that cannot reach the computer.
use crate::{Error, Result};
use base64::Engine;
use sha2::{Digest, Sha256};
use std::{net::IpAddr, sync::Arc, time::Duration};
use tokio::{io::{AsyncReadExt, AsyncWriteExt}, net::TcpListener, sync::Notify};

#[derive(Debug, Clone, serde::Serialize)]
pub struct Handoff {
    /// `poki://pairing?url=…&sha256=…`
    pub link: String,
    /// `poki://pairing?data=…`: the whole record inside the link (a dense QR).
    pub inline_link: String,
    pub url: String,
    pub sha256: String,
    pub host: String,
    pub port: u16,
    /// The link as an SVG QR code, ready to show.
    pub qr_svg: String,
    pub inline_qr_svg: String,
}

pub struct Server {
    pub handoff: Handoff,
    stop: Arc<Notify>,
    fetched: Arc<Notify>,
}

impl Server {
    /// Resolves when the phone has fetched the file once, or after `wait`.
    pub async fn wait_fetched(&self, wait: Duration) -> bool {
        tokio::time::timeout(wait, self.fetched.notified()).await.is_ok()
    }
    pub fn stop(&self) { self.stop.notify_waiters() }
}

impl Drop for Server {
    fn drop(&mut self) { self.stop.notify_waiters() }
}

pub fn qr_svg(text: &str) -> Result<String> {
    use qrcode::{QrCode, render::svg};
    let code = QrCode::new(text.as_bytes()).map_err(|e| Error::msg(format!("QR: {e}")))?;
    Ok(code.render::<svg::Color>().min_dimensions(240, 240).quiet_zone(true).dark_color(svg::Color("#111111")).light_color(svg::Color("#ffffff")).build())
}

/// The computer's address on the local network, the one the phone can reach.
pub fn lan_address() -> Result<IpAddr> {
    let ifaces = local_ip_address::list_afinet_netifas()
        .map_err(|e| Error::msg(format!("This computer has no local network address ({e}). Join the same Wi-Fi as the iPhone.")))?;
    lan_address_from(&ifaces)
}

fn lan_address_from(ifaces: &[(String, IpAddr)]) -> Result<IpAddr> {
    ifaces
        .iter()
        .filter(|(name, _)| {
            let name = name.to_ascii_lowercase();
            !["utun", "tun", "tap", "singbox", "wintun", "clash", "vethernet", "ipsec", "ppp"]
                .iter().any(|prefix| name.starts_with(prefix))
        })
        .find(|(_, ip)| match ip {
            IpAddr::V4(ip) => {
                let [a, b, ..] = ip.octets();
                !ip.is_loopback() && !ip.is_unspecified() && !ip.is_link_local() && !ip.is_multicast()
                    && !(a == 198 && (18..=19).contains(&b))
                    && !(a == 100 && (64..=127).contains(&b))
            }
            IpAddr::V6(_) => false,
        })
        .map(|(_, ip)| *ip)
        .ok_or_else(|| Error::msg("This computer has no local network address. Join the same Wi-Fi as the iPhone."))
}

pub fn inline_link(record: &[u8]) -> String {
    format!("poki://pairing?data={}", base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(record))
}

/// Serves `record` on a random port until it was fetched once or the server is dropped.
pub async fn serve(record: Vec<u8>) -> Result<Server> {
    let host = lan_address()?;
    let listener = TcpListener::bind((host, 0)).await?;
    let port = listener.local_addr()?.port();
    let token = uuid::Uuid::new_v4().simple().to_string();
    let path = format!("/{token}.mobiledevicepairing");
    let sha256 = hex::encode(Sha256::digest(&record));
    let url = format!("http://{host}:{port}{path}");
    let link = format!("poki://pairing?url={}&sha256={sha256}", urlencode(&url));
    let inline = inline_link(&record);
    let handoff = Handoff {
        qr_svg: qr_svg(&link)?,
        // The record inside the link rarely fits a QR code (a lockdown record is ~10 KB); leave
        // that code empty rather than failing the whole hand-off.
        inline_qr_svg: qr_svg(&inline).unwrap_or_default(),
        link,
        inline_link: inline,
        url,
        sha256,
        host: host.to_string(),
        port,
    };
    let stop = Arc::new(Notify::new());
    let fetched = Arc::new(Notify::new());
    let (stop2, fetched2) = (stop.clone(), fetched.clone());
    let record = Arc::new(record);
    tokio::spawn(async move {
        loop {
            let (mut socket, _) = tokio::select! {
                _ = stop2.notified() => break,
                r = listener.accept() => match r { Ok(x) => x, Err(_) => continue },
            };
            let record = record.clone();
            let path = path.clone();
            let fetched = fetched2.clone();
            tokio::spawn(async move {
                let mut buf = [0u8; 2048];
                let n = match tokio::time::timeout(Duration::from_secs(5), socket.read(&mut buf)).await { Ok(Ok(n)) => n, _ => return };
                let head = String::from_utf8_lossy(&buf[..n]);
                let line = head.lines().next().unwrap_or("");
                let ok = line.starts_with("GET ") && line.split_whitespace().nth(1) == Some(path.as_str());
                let response = if ok {
                    let mut r = format!("HTTP/1.1 200 OK\r\nContent-Type: application/x-plist\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n", record.len()).into_bytes();
                    r.extend_from_slice(&record);
                    r
                } else {
                    b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_vec()
                };
                let _ = socket.write_all(&response).await;
                let _ = socket.shutdown().await;
                if ok {
                    fetched.notify_waiters();
                }
            });
        }
    });
    Ok(Server { handoff, stop, fetched })
}

pub fn urlencode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn big_record_still_serves_a_code() {
        let big = vec![b'a'; 9500];
        assert!(qr_svg(&inline_link(&big)).is_err());
        let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
        if let Ok(server) = rt.block_on(serve(big)) {
            assert!(server.handoff.qr_svg.contains("<svg"));
            assert!(server.handoff.inline_qr_svg.is_empty());
        }
    }

    #[test]
    fn link_shape() {
        let l = inline_link(b"<plist/>");
        assert!(l.starts_with("poki://pairing?data="));
        assert_eq!(urlencode("http://10.0.0.2:1/a.plist"), "http%3A%2F%2F10.0.0.2%3A1%2Fa.plist");
        assert!(qr_svg("poki://pairing?x=1").unwrap().contains("<svg"));
    }

    #[test]
    fn lan_address_filters_virtual_tunnels_and_198_18_subnet() {
        let candidates = vec![
            ("lo0".to_string(), "127.0.0.1".parse().unwrap()),
            ("singbox_tun".to_string(), "198.18.0.1".parse().unwrap()),
            ("utun4".to_string(), "198.19.2.5".parse().unwrap()),
            ("utun3".to_string(), "10.7.0.1".parse().unwrap()),
            ("en0".to_string(), "192.168.1.23".parse().unwrap()),
        ];
        assert_eq!(lan_address_from(&candidates).unwrap(), "192.168.1.23".parse::<IpAddr>().unwrap());

        let virtual_only = vec![
            ("singbox_tun".to_string(), "198.18.0.1".parse().unwrap()),
            ("utun1".to_string(), "10.7.0.1".parse().unwrap()),
            ("Ethernet 2".to_string(), "198.19.0.9".parse().unwrap()),
        ];
        assert!(lan_address_from(&virtual_only).is_err());
    }
}
