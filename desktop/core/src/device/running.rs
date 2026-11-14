//! Whether Poki is running on the device, and closing it before an update replaces it. Uses the
//! Instruments services (process list, kill): through the CoreDevice tunnel on iOS 17 and later,
//! through lockdown before. Both need the developer disk image, which setup mounts.
use super::Phone;
use crate::{Error, Result};
use idevice::dvt::{device_info::DeviceInfoClient, process_control::ProcessControlClient, remote_server::RemoteServerClient};
use idevice::{IdeviceService, ReadWrite, RsdService, core_device_proxy::CoreDeviceProxy, rsd::RsdHandshake};

/// A running Poki process (the app itself, not its extensions).
#[derive(Debug, Clone, serde::Serialize)]
pub struct Running {
    pub pid: u64,
    pub name: String,
}

/// Instruments on the device, and what keeps its tunnel open while it is used.
struct Instruments {
    server: RemoteServerClient<Box<dyn ReadWrite>>,
    _tunnel: Option<idevice::tcp::handle::AdapterHandle>,
}

async fn connect(phone: &Phone) -> Result<Instruments> {
    let provider = phone.provider()?;
    // iOS 17 and later: the CoreDevice tunnel, then the service hub over RSD.
    let tunneled: std::result::Result<Instruments, idevice::IdeviceError> = async {
        let proxy = CoreDeviceProxy::connect(&*provider).await?;
        let port = proxy.tunnel_info().server_rsd_port;
        let mut adapter = proxy.create_software_tunnel()?.to_async_handle();
        let mut rsd = RsdHandshake::new(adapter.connect(port).await?).await?;
        let server = RemoteServerClient::connect_rsd(&mut adapter, &mut rsd).await?;
        Ok(Instruments { server, _tunnel: Some(adapter) })
    }
    .await;
    match tunneled {
        Ok(i) => Ok(i),
        Err(first) => match RemoteServerClient::<Box<dyn ReadWrite>>::connect(&*provider).await {
            Ok(server) => Ok(Instruments { server, _tunnel: None }),
            Err(_) => Err(Error::device(format!("Poki Setup could not see the apps running on the device ({first})."))),
        },
    }
}

/// `/private/var/containers/Bundle/Application/<id>/Poki.app/Poki` is Poki; its extensions
/// (`Poki.app/PlugIns/…`) are not apps and end with it.
fn is_poki(real_app_name: &str, is_application: bool) -> bool {
    is_application && real_app_name.contains("/Poki.app/") && !real_app_name.contains("/PlugIns/")
}

/// Runs Instruments work on its own thread: idevice's tunnel futures are not `Send`, and the
/// bridge and the Tauri app run every command on a multi-threaded runtime.
async fn on_own_thread<T: Send + 'static>(phone: &Phone, work: impl AsyncFnOnce(&Phone) -> Result<T> + Send + 'static) -> Result<T> {
    let phone = phone.clone();
    let (tx, rx) = tokio::sync::oneshot::channel();
    std::thread::spawn(move || {
        let answer = tokio::runtime::Builder::new_current_thread().enable_all().build().map_err(Error::from).and_then(|rt| rt.block_on(work(&phone)));
        let _ = tx.send(answer);
    });
    rx.await.map_err(|_| Error::device("Poki Setup lost its connection to the device's Instruments."))?
}

/// Poki's processes now running (in front or in the background).
pub async fn poki(phone: &Phone) -> Result<Vec<Running>> { on_own_thread(phone, async |p: &Phone| poki_here(p).await).await }

/// Closes Poki and checks it is gone. Returns how many processes were ended.
pub async fn close_poki(phone: &Phone) -> Result<usize> { on_own_thread(phone, async |p: &Phone| close_here(p).await).await }

async fn poki_here(phone: &Phone) -> Result<Vec<Running>> {
    let mut i = connect(phone).await?;
    let mut info = DeviceInfoClient::new(&mut i.server).await?;
    Ok(info
        .running_processes()
        .await?
        .into_iter()
        .filter(|p| is_poki(&p.real_app_name, p.is_application))
        .map(|p| Running { pid: p.pid as u64, name: p.name })
        .collect())
}

async fn close_here(phone: &Phone) -> Result<usize> {
    let running = poki_here(phone).await?;
    if running.is_empty() {
        return Ok(0);
    }
    {
        let mut i = connect(phone).await?;
        let mut control = ProcessControlClient::new(&mut i.server).await?;
        for p in &running {
            control.kill_app(p.pid).await?;
        }
    }
    for _ in 0..10 {
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
        if poki_here(phone).await?.is_empty() {
            return Ok(running.len());
        }
    }
    Err(Error::NeedsPerson("Poki is still open on the device. Close it from the app switcher, then try again.".into()))
}

#[cfg(test)]
mod tests {
    #[test]
    fn only_the_app_counts() {
        assert!(super::is_poki("/private/var/containers/Bundle/Application/X/Poki.app/Poki", true));
        assert!(!super::is_poki("/private/var/containers/Bundle/Application/X/Poki.app/PlugIns/W.appex/W", false));
        assert!(!super::is_poki("/Applications/MobileSafari.app/MobileSafari", true));
    }
}
