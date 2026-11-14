use super::Phone;
use crate::Reporter;
use idevice::{
    IdeviceService, ReadWrite,
    core_device::AppServiceClient, core_device_proxy::CoreDeviceProxy,
    installation_proxy::InstallationProxyClient, rsd::RsdHandshake,
};
use std::time::Duration;

type Result<T> = std::result::Result<T, &'static str>;

pub(super) const MANUAL_CLOSE: &str = "Close Poki in the iPhone's app switcher if it is open. Keep the iPhone unlocked.";

pub(super) struct Process {
    pid: u32,
    executable: Option<String>,
}

pub(super) trait Processes {
    async fn list(&mut self) -> Result<Vec<Process>>;
    async fn terminate(&mut self, pid: u32) -> Result<()>;
}

pub(super) struct DeviceProcesses {
    service: AppServiceClient<Box<dyn ReadWrite>>,
    _tunnel: idevice::tcp::handle::AdapterHandle,
}

impl Processes for DeviceProcesses {
    async fn list(&mut self) -> Result<Vec<Process>> {
        self.service.list_processes().await.map_err(|_| "process_list_unavailable")?
            .into_iter().map(|p| Ok(Process {
                pid: p.pid,
                executable: p.executable_url.map(|url| device_path(&url.relative)).transpose()?,
            })).collect()
    }

    async fn terminate(&mut self, pid: u32) -> Result<()> {
        self.service.send_signal(pid, 9).await.map_err(|_| "termination_request_failed")?;
        Ok(())
    }
}

pub(super) struct MainApp<S> {
    processes: S,
    executable: String,
}

#[derive(Clone, Copy, PartialEq)]
pub(super) enum Check {
    BeforeUpload,
    BeforeInstall,
}

impl<S: Processes> MainApp<S> {
    async fn pids(&mut self) -> Result<Vec<u32>> {
        let mut pids = Vec::new();
        for process in self.processes.list().await? {
            let executable = process.executable.ok_or("process_identity_unavailable")?;
            if executable == self.executable {
                if process.pid == 0 { return Err("invalid_process_id"); }
                pids.push(process.pid);
            }
        }
        Ok(pids)
    }

    async fn close(&mut self, check: Check, reporter: &Reporter) -> Result<()> {
        for attempt in 0..2 {
            let pids = self.pids().await?;
            if pids.is_empty() { return Ok(()); }
            if check == Check::BeforeInstall || attempt > 0 {
                tracing::warn!("Poki's main app restarted before installation; closing it again");
                reporter.note("install", "Poki reopened. Closing it again before installation.");
            } else {
                tracing::info!("closing Poki's main app before upload");
            }
            for pid in &pids { self.processes.terminate(*pid).await?; }
            tokio::time::timeout(Duration::from_secs(5), async {
                loop {
                    let current = self.pids().await?;
                    if !current.iter().any(|pid| pids.contains(pid)) { return Ok::<(), &'static str>(()); }
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
            }).await.map_err(|_| "termination_not_confirmed")??;
        }
        if self.pids().await?.is_empty() { Ok(()) } else { Err("main_app_keeps_restarting") }
    }
}

impl MainApp<DeviceProcesses> {
    pub(super) async fn recheck(&mut self, reporter: &Reporter) {
        match tokio::time::timeout(Duration::from_secs(15), self.close(Check::BeforeInstall, reporter)).await {
            Ok(Ok(())) => tracing::info!("Poki's main app is absent immediately before installation"),
            Ok(Err(reason)) => manual_close(reason, reporter),
            Err(_) => manual_close("final_process_check_timed_out", reporter),
        }
    }
}

pub(super) async fn prepare(phone: &Phone, bundle_id: &str, reporter: &Reporter) -> Option<MainApp<DeviceProcesses>> {
    let result = tokio::time::timeout(Duration::from_secs(20), async {
        if !phone.is_usb() { return Err("automatic_close_requires_usb"); }
        let provider = phone.provider().map_err(|_| "pairing_unavailable")?;
        let mut installation = InstallationProxyClient::connect(&*provider).await.map_err(|_| "installed_apps_unavailable")?;
        let apps = installation.get_apps(Some("User"), None).await.map_err(|_| "installed_apps_unavailable")?;
        let Some(app) = apps.get(bundle_id) else { return Ok(None); };
        let app = app.as_dictionary().ok_or("main_app_identity_unavailable")?;
        let path = app.get("Path").and_then(|p| p.as_string()).ok_or("main_app_identity_unavailable")?;
        let name = app.get("CFBundleExecutable").and_then(|p| p.as_string()).ok_or("main_app_identity_unavailable")?;
        if name.is_empty() || name.contains('/') || name == "." || name == ".." {
            return Err("invalid_main_executable");
        }
        let executable = device_path(&format!("{}/{name}", path.trim_end_matches('/')))?;
        let proxy = CoreDeviceProxy::connect(&*provider).await.map_err(|_| "developer_service_unavailable")?;
        let port = proxy.tunnel_info().server_rsd_port;
        let mut tunnel = proxy.create_software_tunnel().map_err(|_| "developer_tunnel_unavailable")?.to_async_handle();
        let stream = tunnel.connect(port).await.map_err(|_| "developer_tunnel_unavailable")?;
        let rsd = RsdHandshake::new(stream).await.map_err(|_| "developer_services_unavailable")?;
        let port = rsd.services.get("com.apple.coredevice.appservice").ok_or("app_service_unavailable")?.port;
        let stream = tunnel.connect(port).await.map_err(|_| "app_service_unavailable")?;
        let service = AppServiceClient::new(Box::new(stream) as Box<dyn ReadWrite>).await.map_err(|_| "app_service_unavailable")?;
        let mut app = MainApp { processes: DeviceProcesses { service, _tunnel: tunnel }, executable };
        app.close(Check::BeforeUpload, reporter).await?;
        tracing::info!("Poki's main app is absent before upload");
        Ok(Some(app))
    }).await;
    match result {
        Ok(Ok(app)) => app,
        Ok(Err(reason)) => { manual_close(reason, reporter); None }
        Err(_) => { manual_close("automatic_close_timed_out", reporter); None }
    }
}

fn manual_close(reason: &'static str, reporter: &Reporter) {
    tracing::warn!(reason, "could not confirm that Poki's main app is closed");
    reporter.note("install", "Poki could not be closed automatically.");
    reporter.note("install", MANUAL_CLOSE);
}

fn device_path(value: &str) -> Result<String> {
    let path = if value.starts_with("file:") {
        let url = reqwest::Url::parse(value).map_err(|_| "invalid_process_path")?;
        if !matches!(url.host_str(), None | Some("") | Some("localhost")) || url.query().is_some() || url.fragment().is_some() {
            return Err("invalid_process_path");
        }
        percent_encoding::percent_decode_str(url.path()).decode_utf8().map_err(|_| "invalid_process_path")?.into_owned()
    } else { value.to_string() };
    if !path.starts_with('/') || path.contains('\0') || path.split('/').any(|c| c == "." || c == "..") {
        return Err("invalid_process_path");
    }
    Ok(match path.strip_prefix("/private/var/") {
        Some(rest) => format!("/var/{rest}"),
        None => path,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Progress;
    use std::sync::{Arc, Mutex};

    const MAIN: &str = "/var/containers/Bundle/Application/test/Poki.app/Poki";
    const WIDGET: &str = "/var/containers/Bundle/Application/test/Poki.app/PlugIns/PokiWidgets.appex/PokiWidgets";
    const OTHER: &str = "/var/containers/Bundle/Application/other/Poki.app/Poki";

    struct World {
        processes: Vec<(u32, Option<String>)>,
        ignores_signal: bool,
    }

    struct FakeProcesses(Arc<Mutex<World>>);

    impl Processes for FakeProcesses {
        async fn list(&mut self) -> Result<Vec<Process>> {
            Ok(self.0.lock().unwrap().processes.iter().map(|(pid, executable)| Process {
                pid: *pid, executable: executable.clone(),
            }).collect())
        }
        async fn terminate(&mut self, pid: u32) -> Result<()> {
            let mut world = self.0.lock().unwrap();
            if !world.ignores_signal { world.processes.retain(|(p, _)| *p != pid); }
            Ok(())
        }
    }

    fn process(pid: u32, executable: &str) -> (u32, Option<String>) {
        (pid, Some(executable.into()))
    }

    #[tokio::test(start_paused = true)]
    async fn closes_main_again_after_upload_without_stopping_extensions_or_other_apps() {
        let world = Arc::new(Mutex::new(World {
            processes: vec![process(1, MAIN), process(2, WIDGET), process(3, OTHER)],
            ignores_signal: false,
        }));
        let notes = Arc::new(Mutex::new(Vec::new()));
        let observed = notes.clone();
        let reporter = Reporter::new(move |event| {
            if let Progress::Note { text, .. } = event { observed.lock().unwrap().push(text); }
        });
        let mut app = MainApp { processes: FakeProcesses(world.clone()), executable: MAIN.into() };
        app.close(Check::BeforeUpload, &reporter).await.unwrap();
        assert_eq!(world.lock().unwrap().processes, vec![process(2, WIDGET), process(3, OTHER)]);
        world.lock().unwrap().processes.push(process(4, MAIN));
        app.close(Check::BeforeInstall, &reporter).await.unwrap();
        assert_eq!(world.lock().unwrap().processes, vec![process(2, WIDGET), process(3, OTHER)]);
        assert!(notes.lock().unwrap().iter().any(|n| n == "Poki reopened. Closing it again before installation."));
    }

    #[tokio::test(start_paused = true)]
    async fn a_signal_receipt_does_not_confirm_process_exit() {
        let world = Arc::new(Mutex::new(World { processes: vec![process(1, MAIN)], ignores_signal: true }));
        let mut app = MainApp { processes: FakeProcesses(world.clone()), executable: MAIN.into() };
        assert_eq!(app.close(Check::BeforeUpload, &Reporter::silent()).await, Err("termination_not_confirmed"));
        assert_eq!(world.lock().unwrap().processes, vec![process(1, MAIN)]);
    }

    #[tokio::test]
    async fn ambiguous_identity_or_zero_pid_cannot_authorize_a_signal() {
        for processes in [vec![process(1, MAIN), (2, None)], vec![process(0, MAIN)]] {
            let world = Arc::new(Mutex::new(World { processes: processes.clone(), ignores_signal: false }));
            let mut app = MainApp { processes: FakeProcesses(world.clone()), executable: MAIN.into() };
            assert!(app.close(Check::BeforeUpload, &Reporter::silent()).await.is_err());
            assert_eq!(world.lock().unwrap().processes, processes);
        }
        assert_eq!(device_path("file:///private/var/containers/Poki%20Test.app/Poki").unwrap(), "/var/containers/Poki Test.app/Poki");
        assert!(device_path("file://another-host/var/Poki.app/Poki").is_err());
    }
}
