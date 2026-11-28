#[cfg(not(test))]
use super::connect_device;
use super::{
    InputMedia, NoDisplayService, NotSent, Request, Result, ax::MissingAccessibilityService,
    close_input, execute, execute_connected,
};
use idevice::{
    remote_pairing::{
        RemotePairingClient, RpPairingFile, RpPairingSocket, connect_tls_psk_tunnel_native,
    },
    rsd::RsdHandshake,
    tcp::handle::AdapterHandle,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    io::Write,
    net::{IpAddr, SocketAddr},
    time::Duration,
};
use tokio::{
    io::{AsyncBufReadExt, BufReader},
    net::TcpStream,
};

#[derive(Deserialize)]
struct Config {
    id: String,
    host: String,
    port: u16,
    pairing_file: String,
}

impl Config {
    fn uses_bonjour(&self) -> bool {
        // A zone identifier may itself end in .local; numeric IPv6 remains numeric.
        let address = self
            .host
            .split_once('%')
            .map_or(self.host.as_str(), |(address, _)| address);
        if address.parse::<IpAddr>().is_ok() {
            return false;
        }
        let host = self.host.strip_suffix('.').unwrap_or(&self.host);
        host.to_ascii_lowercase().ends_with(".local")
    }
}

struct Control {
    client: RemotePairingClient<RpPairingSocket<TcpStream>>,
    peer: SocketAddr,
}

impl Control {
    async fn open_data_socket(&self, port: u16) -> std::io::Result<TcpStream> {
        let mut endpoint = self.peer;
        endpoint.set_port(port);
        TcpStream::connect(endpoint).await
    }
}

enum Transport {
    Local(String),
    Remote(Config),
}

struct Connection {
    adapter: AdapterHandle,
    rsd: RsdHandshake,
    rsd_port: u16,
    provider: Option<idevice::provider::UsbmuxdProvider>,
    media: Option<InputMedia>,
}

struct Session {
    transport: Transport,
    control: Option<Control>,
    connection: Option<Connection>,
}

impl Session {
    async fn connect(&mut self) -> Result<()> {
        let config = match &self.transport {
            Transport::Local(udid) => {
                // Without a phone, tests hand out tunnels they can unplug.
                #[cfg(test)]
                let connection = tests::connect_local(udid).await?;
                #[cfg(not(test))]
                let connection = {
                    let (adapter, rsd, rsd_port, provider) = connect_device(udid).await?;
                    Connection {
                        adapter,
                        rsd,
                        rsd_port,
                        provider: Some(provider),
                        media: None,
                    }
                };
                self.connection = Some(connection);
                return Ok(());
            }
            Transport::Remote(config) => config,
        };
        if self.control.is_none() {
            let socket = dial(&config.host, config.port).await
                .map_err(|attempts| format!("Remote pairing is unreachable ({attempts}). Keep the iPhone unlocked and check its configured address or Bonjour name; for Tailscale, keep both devices connected."))?;
            socket.set_nodelay(true)?;
            let peer = socket.peer_addr()?;
            let mut control = RemotePairingClient::new(RpPairingSocket::new(socket), "poki-mcp");
            let mut record = RpPairingFile::read_from_file(&config.pairing_file).await?;
            control.attempt_pair_verify().await?;
            // Never fall back to pairing or request consent during an ordinary operation.
            control.validate_pairing(&mut record).await?;
            self.control = Some(Control {
                client: control,
                peer,
            });
        }
        let control = self.control.as_mut().unwrap();
        let port = match control.client.create_tcp_listener().await {
            Ok(port) => port,
            Err(error) => {
                self.control = None;
                return Err(format!("The remote pairing control connection closed: {error}. Reconnect the iPhone to Wi-Fi, then reconnect the device.").into());
            }
        };
        // Use the authenticated control peer, including its IPv6 scope. A
        // second hostname lookup could select a different address mid-session.
        let socket = control.open_data_socket(port).await
            .map_err(|_| "The iPhone refused a new tunnel. Reconnect it to Wi-Fi, then reconnect the device.")?;
        socket.set_nodelay(true)?;
        let tunnel = connect_tls_psk_tunnel_native(socket, control.client.encryption_key()).await?;
        let info = tunnel.info.clone();
        let mut adapter = idevice::tcp::adapter::Adapter::new(
            Box::new(tunnel.into_inner()),
            info.client_address.parse()?,
            info.server_address.parse()?,
        )
        .to_async_handle();
        let rsd = RsdHandshake::new(adapter.connect(info.server_rsd_port).await?).await?;
        if !matches_expected_id(&rsd, &config.id) {
            return Err("Remote device identity does not match the configured iPhone".into());
        }
        self.connection = Some(Connection {
            adapter,
            rsd,
            rsd_port: info.server_rsd_port,
            provider: None,
            media: None,
        });
        Ok(())
    }

    fn input_media_deadline(&self) -> Option<tokio::time::Instant> {
        let media = self.connection.as_ref()?.media.as_ref()?;
        Some(
            (media.last_activity + INPUT_MEDIA_IDLE_TIMEOUT)
                .min(media.last_input + INPUT_MEDIA_MAX_READ_HOLD),
        )
    }

    async fn release_input(&mut self) -> Result<()> {
        if let Some(connection) = &mut self.connection {
            close_input(&mut connection.media).await?;
        }
        Ok(())
    }

    async fn request(&mut self, request: Value) -> Result<Value> {
        if self
            .input_media_deadline()
            .is_some_and(|deadline| tokio::time::Instant::now() >= deadline)
        {
            let _ = self.release_input().await;
        }
        if request["op"] == "release_input" {
            self.release_input().await?;
            return Ok(json!({"released":true}));
        }
        let action = if request["op"] == "connect" || request["op"] == "reconnect" {
            None
        } else {
            let parsed: Result<Request> =
                serde_json::from_value(request.clone()).map_err(Into::into);
            let action = match parsed.and_then(|action| action.validate().map(|()| action)) {
                Ok(action) => action,
                Err(error) => return refused_reply(&request, error),
            };
            if matches!(
                action,
                Request::InstallApp { .. } | Request::UninstallApp { .. }
            ) {
                let _ = self.release_input().await;
                return match &self.transport {
                    Transport::Local(udid) => execute(udid, action).await,
                    Transport::Remote(_) => {
                        Err("App installation over remote pairing is not supported".into())
                    }
                };
            }
            Some(action)
        };
        let Some(action) = action else {
            // Keep the working tunnel until its replacement has actually connected.
            // A failed reconnect must not destroy the only usable cellular session.
            if self.connection.is_none() || request["op"] == "reconnect" {
                let _ = self.release_input().await;
                if request["op"] == "reconnect"
                    && matches!(&self.transport, Transport::Remote(config) if config.uses_bonjour())
                {
                    self.control = None;
                }
                self.open().await?;
            }
            return Ok(
                json!({"connected":true,"transport":match &self.transport { Transport::Local(_) => "local", Transport::Remote(_) => "remote_pairing" },"device":match &self.transport { Transport::Local(id) => id, Transport::Remote(config) => &config.id }}),
            );
        };
        // A tunnel can die while the helper idles: a pulled cable or a restarted phone leaves its adapter closed.
        // Until an input is written nothing can repeat, so the request rebuilds a closed tunnel once and tries again.
        let mut fresh = false;
        let mut refreshed_rsd = false;
        loop {
            if self.connection.is_none() {
                if let Err(error) = self.open().await {
                    return unsent_reply(&action, error);
                }
                fresh = true;
            }
            let Connection {
                adapter,
                rsd,
                rsd_port,
                provider,
                media,
            } = self.connection.as_mut().unwrap();
            let result = tokio::time::timeout(
                Duration::from_secs(90),
                execute_connected(
                    adapter,
                    rsd,
                    provider
                        .as_ref()
                        .map(|p| p as &dyn idevice::provider::IdeviceProvider),
                    action.clone(),
                    media,
                ),
            )
            .await;
            let error = match result {
                Ok(Ok(value)) => {
                    if !action.uses_input_media()
                        && value["outcome"] != "not_sent"
                        && value["sent"] != false
                        && let Some(m) = media.as_mut()
                    {
                        m.last_activity = tokio::time::Instant::now();
                    }
                    if self
                        .input_media_deadline()
                        .is_some_and(|deadline| tokio::time::Instant::now() >= deadline)
                    {
                        let _ = self.release_input().await;
                    }
                    return Ok(value);
                }
                Ok(Err(error)) => error,
                Err(_) => "Remote operation timed out".into(),
            };
            let _ = close_input(media).await;
            // A service or file error does not imply the shared tunnel died.
            // bind_udp checks the adapter task locally without opening a phone service.
            // A phone that vanished without a reset leaves the adapter running, so a socket error also
            // asks the phone for its RSD port.
            let mut closed = adapter.bind_udp(0).await.is_err()
                || (socket_failure(error.as_ref()) && adapter.connect(*rsd_port).await.is_err());
            let not_sent = error.is::<NotSent>();
            // A tunnel opened while the iPhone was locked or before the Developer Disk Image
            // finished mounting caches an incomplete RSD service map. Refresh RSD in place once
            // over the live tunnel before giving up on a missing service.
            if !closed
                && !fresh
                && !refreshed_rsd
                && (not_sent || action.read_only())
                && missing_service(error.as_ref())
            {
                refreshed_rsd = true;
                let expected_id = match &self.transport {
                    Transport::Remote(config) => Some(config.id.as_str()),
                    Transport::Local(_) => None,
                };
                match refresh_rsd(adapter, *rsd_port).await {
                    RsdRefresh::Updated(new_rsd) => {
                        if let Some(expected) = expected_id
                            && !matches_expected_id(&new_rsd, expected)
                        {
                            self.connection = None;
                            self.control = None;
                            return unsent_reply(
                                &action,
                                "Remote device identity does not match the configured iPhone"
                                    .into(),
                            );
                        }
                        let retry = has_new_or_changed_service(rsd, &new_rsd);
                        *rsd = new_rsd;
                        if retry {
                            continue;
                        }
                    }
                    RsdRefresh::ConnectFailed => {
                        closed = true;
                    }
                    RsdRefresh::HandshakeFailed(refresh_err) => {
                        closed = adapter.bind_udp(0).await.is_err()
                            || (socket_failure(&refresh_err)
                                && adapter.connect(*rsd_port).await.is_err());
                    }
                    RsdRefresh::TimedOut => {
                        closed = adapter.bind_udp(0).await.is_err();
                    }
                }
            }
            // Only a dead tunnel is replaced. A live one stays, since a cellular replacement may be refused.
            if closed {
                self.connection = None;
                // Hostname mode must resolve again rather than dial the old
                // control peer. Preserve legacy IP/Tailscale control reuse.
                if matches!(&self.transport, Transport::Remote(config) if config.uses_bonjour()) {
                    self.control = None;
                }
                if (not_sent || action.read_only()) && !fresh {
                    continue;
                }
            }
            if not_sent || action.read_only() {
                return unsent_reply(&action, error);
            }
            // Delivery can be ambiguous: the caller must inspect, never replay automatically.
            return Err(format!(
                "{error}. Input may have been delivered; inspect the screen before retrying."
            )
            .into());
        }
    }

    async fn open(&mut self) -> Result<()> {
        let connected = match tokio::time::timeout(Duration::from_secs(25), self.connect()).await {
            Ok(connected) => connected,
            Err(timeout) => Err(timeout.into()),
        };
        if connected.is_err() {
            self.control = None;
        }
        connected
    }
}

const RSD_HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
const DIAL_TOTAL_BUDGET: Duration = Duration::from_secs(15);
const DIAL_MAX_PER_ADDRESS: Duration = Duration::from_secs(5);

enum RsdRefresh {
    Updated(RsdHandshake),
    TimedOut,
    ConnectFailed,
    HandshakeFailed(idevice::IdeviceError),
}

fn matches_expected_id(rsd: &RsdHandshake, expected: &str) -> bool {
    rsd.properties
        .get("UniqueDeviceID")
        .and_then(plist::Value::as_string)
        == Some(expected)
}

async fn refresh_rsd(adapter: &mut AdapterHandle, rsd_port: u16) -> RsdRefresh {
    // Let jktcp's own connect timeout bound the TCP SYN instead of cancelling connect()
    // early (which would leave jktcp's single-threaded adapter loop blocked for the remaining
    // SYN retry window). Only the post-connect XPC handshake has an outer timeout, where
    // dropping StreamHandle cleanly closes the stream without stalling the adapter.
    let Ok(stream) = adapter.connect(rsd_port).await else {
        return RsdRefresh::ConnectFailed;
    };
    match tokio::time::timeout(RSD_HANDSHAKE_TIMEOUT, RsdHandshake::new(stream)).await {
        Ok(Ok(rsd)) => RsdRefresh::Updated(rsd),
        Ok(Err(error)) => RsdRefresh::HandshakeFailed(error),
        Err(_) => RsdRefresh::TimedOut,
    }
}

// Pure removals still replace the cached handshake (see Session::request) to prune stale entries
// without triggering a redundant retry.
fn has_new_or_changed_service(old: &RsdHandshake, new: &RsdHandshake) -> bool {
    new.services.iter().any(|(name, service)| {
        old.services.get(name).is_none_or(|previous| {
            previous.port != service.port
                || previous.uses_remote_xpc != service.uses_remote_xpc
                || previous.features != service.features
                || previous.service_version != service.service_version
        })
    })
}

fn missing_service(error: &(dyn std::error::Error + Send + Sync + 'static)) -> bool {
    match error.downcast_ref::<NotSent>() {
        Some(NotSent(error)) => missing_service(error.as_ref()),
        None => {
            error.is::<NoDisplayService>()
                || error.is::<MissingAccessibilityService>()
                || matches!(
                    error.downcast_ref::<idevice::IdeviceError>(),
                    Some(idevice::IdeviceError::ServiceNotFound)
                )
        }
    }
}

fn attempt_timeout(remaining_budget: Duration, remaining_addresses: usize) -> Duration {
    if remaining_budget.is_zero() || remaining_addresses <= 1 {
        return remaining_budget;
    }
    let share = remaining_budget / remaining_addresses as u32;
    share
        .clamp(Duration::from_nanos(1), DIAL_MAX_PER_ADDRESS)
        .min(remaining_budget)
}

// Tries every resolved address in order, as a host-and-port connect does, but keeps
// each address's OS error: the last error alone cannot tell routing from policy.
// Multi-address resolutions share a single 15-second deadline so blackholed early
// addresses (such as link-local IPv6) cannot starve reachable fallback addresses,
// while a single resolved address keeps the full open() budget for slow cellular/
// Tailscale handshakes.
async fn dial(host: &str, port: u16) -> std::result::Result<TcpStream, String> {
    let addresses: Vec<SocketAddr> = tokio::net::lookup_host((host, port))
        .await
        .map_err(|error| format!("{host} did not resolve: {error}"))?
        .collect();
    let budget = (addresses.len() > 1).then_some(DIAL_TOTAL_BUDGET);
    dial_with(host, addresses, budget, TcpStream::connect).await
}

async fn dial_with<F, Fut, S>(
    host: &str,
    addresses: impl IntoIterator<Item = SocketAddr>,
    total_budget: Option<Duration>,
    mut connect: F,
) -> std::result::Result<S, String>
where
    F: FnMut(SocketAddr) -> Fut,
    Fut: std::future::Future<Output = std::io::Result<S>>,
{
    let addresses: Vec<SocketAddr> = addresses.into_iter().collect();
    let total = addresses.len();
    let deadline = total_budget.map(|budget| tokio::time::Instant::now() + budget);
    let mut attempts = Vec::new();
    for (index, address) in addresses.into_iter().enumerate() {
        let outcome = match deadline {
            Some(deadline) => {
                let remaining_budget =
                    deadline.saturating_duration_since(tokio::time::Instant::now());
                if remaining_budget.is_zero() {
                    Err(())
                } else {
                    let limit = attempt_timeout(remaining_budget, total - index);
                    tokio::time::timeout(limit, connect(address))
                        .await
                        .map_err(|_| ())
                }
            }
            None => Ok(connect(address).await),
        };
        match outcome {
            Ok(Ok(socket)) => return Ok(socket),
            Ok(Err(error)) => attempts.push(format!("{}: {error}", endpoint(address))),
            Err(()) => attempts.push(format!("{}: connection timed out", endpoint(address))),
        }
    }
    if attempts.is_empty() {
        return Err(format!("{host} resolved to no address"));
    }
    Err(attempts.join("; "))
}

// Names an IPv6 scope by its interface, so a link-local attempt shows which network it used.
fn endpoint(address: SocketAddr) -> String {
    let SocketAddr::V6(v6) = address else {
        return address.to_string();
    };
    let mut name = [0 as libc::c_char; libc::IF_NAMESIZE];
    if v6.scope_id() == 0
        || unsafe { libc::if_indextoname(v6.scope_id(), name.as_mut_ptr()) }.is_null()
    {
        return address.to_string();
    }
    let interface = unsafe { std::ffi::CStr::from_ptr(name.as_ptr()) }.to_string_lossy();
    format!("[{}%{interface}]:{}", v6.ip(), v6.port())
}

fn socket_failure(error: &(dyn std::error::Error + Send + Sync + 'static)) -> bool {
    match error.downcast_ref::<NotSent>() {
        Some(NotSent(error)) => socket_failure(error.as_ref()),
        None => {
            error.is::<std::io::Error>()
                || matches!(
                    error.downcast_ref::<idevice::IdeviceError>(),
                    Some(idevice::IdeviceError::Socket(_))
                )
        }
    }
}

// The reply for a request whose input never reached the phone.
fn unsent_reply(
    action: &Request,
    error: Box<dyn std::error::Error + Send + Sync>,
) -> Result<Value> {
    match action {
        Request::LaunchApp(_) => Ok(super::apps::not_sent(error)),
        Request::Configuration { .. } => Err(error),
        action if action.read_only() => Err(error),
        _ => {
            let mut reply = json!({"isError":true,"outcome":"not_sent","stop_reason":"error","sent":false,"screen_change_verified":false,"error":error.to_string(),"instruction":"Nothing reached the iPhone. Keep it connected and unlocked, then retry."});
            if error
                .downcast_ref::<NotSent>()
                .is_some_and(|error| error.0.is::<NoDisplayService>())
            {
                reply["reason"] = "display_service_missing".into();
            }
            Ok(reply)
        }
    }
}

// The reply for a request refused before connecting, so before anything could reach the phone.
fn refused_reply(
    request: &Value,
    error: Box<dyn std::error::Error + Send + Sync>,
) -> Result<Value> {
    match request["op"].as_str() {
        Some("launch_app") => Ok(super::apps::not_sent(error)),
        // Reads, settings and app installs report a refusal as an error, as they report any other failure.
        Some(
            "ax_tree" | "screenshot" | "device_info" | "display_info" | "list_apps"
            | "configuration" | "install_app" | "uninstall_app",
        ) => Err(error),
        _ => Ok(
            json!({"isError":true,"outcome":"not_sent","stop_reason":"error","sent":false,"screen_change_verified":false,"error":error.to_string(),"instruction":"Nothing was sent to the iPhone: the helper refused this request before any input. Correct the request before retrying."}),
        ),
    }
}

fn load(path: &str) -> Result<Session> {
    Ok(Session {
        transport: Transport::Remote(serde_json::from_slice(&std::fs::read(path)?)?),
        control: None,
        connection: None,
    })
}

async fn reply(session: &mut Session, line: &str) -> Value {
    let response = if line.len() > 2 * 1024 * 1024 {
        Err("Remote request exceeds size limit".into())
    } else {
        match serde_json::from_str::<Value>(line) {
            Ok(request) => Box::pin(session.request(request)).await,
            Err(e) => Err(e.into()),
        }
    };
    response.unwrap_or_else(|e| json!({"isError":true,"transport_error":true,"error":e.to_string(),"screen_change_verified":false}))
}

const INPUT_MEDIA_IDLE_TIMEOUT: Duration = Duration::from_secs(1);
pub(super) const INPUT_MEDIA_MAX_READ_HOLD: Duration = Duration::from_secs(5);

async fn with_media_deadline<T>(
    session: &mut Session,
    future: impl std::future::Future<Output = T>,
) -> T {
    if session
        .input_media_deadline()
        .is_some_and(|deadline| tokio::time::Instant::now() >= deadline)
    {
        let _ = session.release_input().await;
    }
    let deadline = session.input_media_deadline();
    tokio::pin!(future);
    tokio::select! {
        biased;
        output = &mut future => output,
        () = async {
            match deadline {
                Some(deadline) => tokio::time::sleep_until(deadline).await,
                None => std::future::pending::<()>().await,
            }
        } => {
            let _ = session.release_input().await;
            future.await
        }
    }
}

pub async fn serve(path: &str) -> Result<Value> {
    use tokio::io::AsyncWriteExt;
    let mut session = load(path)?;
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    let mut stdout = tokio::io::stdout();
    while let Some(line) = with_media_deadline(&mut session, lines.next_line()).await? {
        let output = reply(&mut session, &line).await;
        let mut bytes = serde_json::to_vec(&output)?;
        bytes.push(b'\n');
        with_media_deadline(&mut session, async {
            stdout.write_all(&bytes).await?;
            stdout.flush().await
        })
        .await?;
    }
    let _ = session.release_input().await;
    Ok(json!({"closed":true}))
}

pub async fn serve_socket(path: &str, socket_path: &str) -> Result<Value> {
    serve_session(load(path)?, socket_path).await
}

pub async fn serve_local(udid: &str, socket_path: &str) -> Result<Value> {
    // EOF means the owning daemon is gone, including crashes without a shutdown hook.
    let owned_path = socket_path.to_owned();
    tokio::spawn(async move {
        use tokio::io::AsyncReadExt;
        let mut byte = [0u8; 1];
        let _ = tokio::io::stdin().read(&mut byte).await;
        let _ = std::fs::remove_file(owned_path);
        std::process::exit(0);
    });
    serve_session(
        Session {
            transport: Transport::Local(udid.into()),
            control: None,
            connection: None,
        },
        socket_path,
    )
    .await
}

async fn serve_session(mut session: Session, socket_path: &str) -> Result<Value> {
    use std::os::unix::fs::PermissionsExt;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let listener = tokio::net::UnixListener::bind(socket_path)?;
    std::fs::set_permissions(socket_path, std::fs::Permissions::from_mode(0o600))?;
    println!("{}", json!({"ready":true}));
    std::io::stdout().flush()?;
    loop {
        let (mut socket, _) = with_media_deadline(&mut session, listener.accept()).await?;
        let Some((mut stream, line)) = with_media_deadline(&mut session, async {
            let hello = format!("{}\n", json!({"pid":std::process::id()}));
            if socket.write_all(hello.as_bytes()).await.is_err() {
                return None;
            }
            let mut stream = BufReader::new(socket);
            let mut line = String::new();
            // The local directory is private. Bound incomplete requests so an abandoned client cannot hold the device.
            if !matches!(
                tokio::time::timeout(
                    Duration::from_secs(5),
                    (&mut stream).take(2 * 1024 * 1024 + 1).read_line(&mut line),
                )
                .await,
                Ok(Ok(n)) if n > 0
            ) {
                return None;
            }
            if line.len() > 2 * 1024 * 1024 {
                return None;
            }
            Some((stream, line))
        })
        .await
        else {
            continue;
        };
        if serde_json::from_str::<Value>(&line)
            .ok()
            .is_some_and(|v| v["op"] == "disconnect")
        {
            stream
                .get_mut()
                .write_all(b"{\"disconnected\":true}\n")
                .await?;
            break;
        }
        let request = serde_json::from_str::<Request>(&line);
        let screenshot_path = match &request {
            Ok(Request::Screenshot { path }) => Some(path),
            _ => None,
        };
        let read_only = request.as_ref().is_ok_and(Request::read_only);
        let previous_activity = session
            .connection
            .as_ref()
            .and_then(|c| c.media.as_ref())
            .map(|m| m.last_activity);
        let mut byte = [0u8; 1];
        let (output, abandoned) = if read_only {
            // Draining an observation preserves service framing when its caller stops waiting.
            let response = reply(&mut session, &line);
            tokio::pin!(response);
            tokio::select! {
                biased;
                _ = stream.read(&mut byte) => (response.await, true),
                output = &mut response => (output, false),
            }
        } else {
            let result = tokio::select! {
                biased;
                _ = stream.read(&mut byte) => None,
                output = reply(&mut session, &line) => Some(output),
            };
            match result {
                Some(output) => (output, false),
                None => {
                    let _ = session.release_input().await;
                    continue;
                }
            }
        };
        if abandoned {
            if let (Some(previous), Some(media)) = (
                previous_activity,
                session.connection.as_mut().and_then(|c| c.media.as_mut()),
            ) {
                media.last_activity = previous;
            }
            if session
                .input_media_deadline()
                .is_some_and(|deadline| tokio::time::Instant::now() >= deadline)
            {
                let _ = session.release_input().await;
            }
        }
        let mut bytes = serde_json::to_vec(&output)?;
        bytes.push(b'\n');
        let delivered = !abandoned
            && matches!(
                with_media_deadline(
                    &mut session,
                    tokio::time::timeout(
                        Duration::from_secs(5),
                        stream.get_mut().write_all(&bytes),
                    ),
                )
                .await,
                Ok(Ok(()))
            );
        if !delivered && output["saved"] == true {
            if let Some(path) = screenshot_path {
                let _ = tokio::fs::remove_file(path).await;
            }
        }
    }
    let _ = session.release_input().await;
    let _ = std::fs::remove_file(socket_path);
    Ok(json!({"closed":true}))
}

#[cfg(test)]
mod tests {
    use super::*;
    use idevice::{
        ReadWrite, RsdService as _,
        core_device::{AppServiceClient, DisplayServiceClient},
        rsd::RsdService,
        tcp::packets::{Ipv6Packet, ProtocolNumber, TcpFlags, TcpPacket},
    };
    use std::{
        cell::RefCell,
        collections::HashMap,
        net::{IpAddr, Ipv6Addr},
    };
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt, DuplexStream},
        sync::mpsc,
    };

    thread_local! {
        // Receives the phone end of every tunnel the session builds.
        static PHONE: RefCell<Option<mpsc::UnboundedSender<DuplexStream>>> = const { RefCell::new(None) };
    }

    fn encode_rsd_handshake_frame(rsd: &RsdHandshake) -> Vec<u8> {
        use idevice::xpc::{Dictionary, XPCMessage, XPCObject};
        let mut services = Dictionary::new();
        for (name, service) in &rsd.services {
            let mut props = Dictionary::new();
            props.insert(
                "UsesRemoteXPC".into(),
                XPCObject::Bool(service.uses_remote_xpc),
            );
            if let Some(features) = &service.features {
                props.insert(
                    "Features".into(),
                    XPCObject::Array(features.iter().cloned().map(XPCObject::String).collect()),
                );
            }
            if let Some(version) = service.service_version {
                props.insert("ServiceVersion".into(), XPCObject::Int64(version));
            }
            let mut entry = Dictionary::new();
            entry.insert(
                "Entitlement".into(),
                XPCObject::String(service.entitlement.clone()),
            );
            entry.insert("Port".into(), XPCObject::String(service.port.to_string()));
            entry.insert("Properties".into(), XPCObject::Dictionary(props));
            services.insert(name.clone(), XPCObject::Dictionary(entry));
        }
        let mut properties = Dictionary::new();
        for (k, v) in &rsd.properties {
            properties.insert(k.clone(), XPCObject::from(v.clone()));
        }
        let mut root = Dictionary::new();
        root.insert("Services".into(), XPCObject::Dictionary(services));
        root.insert(
            "MessagingProtocolVersion".into(),
            XPCObject::Int64(rsd.protocol_version as i64),
        );
        root.insert("UUID".into(), XPCObject::String(rsd.uuid.clone()));
        root.insert("Properties".into(), XPCObject::Dictionary(properties));

        let xpc_bytes = XPCMessage::new(None, Some(XPCObject::Dictionary(root)), Some(1))
            .encode(1)
            .unwrap();
        let len = (xpc_bytes.len() as u32).to_be_bytes();
        let mut frame = Vec::with_capacity(9 + xpc_bytes.len());
        frame.extend_from_slice(&[len[1], len[2], len[3], 0x00, 0x00]);
        frame.extend_from_slice(&1u32.to_be_bytes());
        frame.extend_from_slice(&xpc_bytes);
        frame
    }

    #[derive(Default)]
    struct MockPhoneStats {
        syns_by_port: HashMap<u16, usize>,
        rsd_handshakes: usize,
        input_deliveries: usize,
    }

    impl MockPhoneStats {
        fn syns(&self, port: u16) -> usize {
            self.syns_by_port.get(&port).copied().unwrap_or(0)
        }
    }

    struct MockConnState {
        server_seq: u32,
        received: Vec<u8>,
        rsd_replied: bool,
    }

    async fn answer_rsd(
        mut wire: DuplexStream,
        mut open: Vec<u16>,
        rsd_port: u16,
        rsd_reply: Option<RsdHandshake>,
    ) -> MockPhoneStats {
        let host: Ipv6Addr = "fd00::1".parse().unwrap();
        let phone: Ipv6Addr = "fd00::2".parse().unwrap();
        let rsd_frame = rsd_reply.as_ref().map(encode_rsd_handshake_frame);
        if rsd_frame.is_some() && !open.contains(&rsd_port) {
            open.push(rsd_port);
        }
        let mut stats = MockPhoneStats::default();
        let mut conns: HashMap<(u16, u16), MockConnState> = HashMap::new();
        'wire: loop {
            let mut header = [0u8; 40];
            if wire.read_exact(&mut header).await.is_err() {
                break;
            }
            let mut packet = vec![0u8; u16::from_be_bytes([header[4], header[5]]) as usize];
            if wire.read_exact(&mut packet).await.is_err() {
                break;
            }
            if header[6] != ProtocolNumber::Tcp as u8 {
                continue;
            }
            let segment = TcpPacket::parse(&packet).unwrap();
            let key = (segment.source_port, segment.destination_port);
            if segment.flags.rst {
                continue;
            }
            if segment.flags.syn {
                *stats
                    .syns_by_port
                    .entry(segment.destination_port)
                    .or_insert(0) += 1;
                let flags = if open.contains(&segment.destination_port) {
                    conns.insert(
                        key,
                        MockConnState {
                            server_seq: 1,
                            received: Vec::new(),
                            rsd_replied: false,
                        },
                    );
                    TcpFlags {
                        syn: true,
                        ack: true,
                        ..Default::default()
                    }
                } else {
                    TcpFlags {
                        rst: true,
                        ack: true,
                        ..Default::default()
                    }
                };
                let ack = segment.sequence_number.wrapping_add(1);
                let reply = TcpPacket::create(
                    IpAddr::V6(phone),
                    IpAddr::V6(host),
                    segment.destination_port,
                    segment.source_port,
                    0,
                    ack,
                    flags,
                    u16::MAX,
                    &[],
                    &[],
                );
                let reply = Ipv6Packet::create(phone, host, ProtocolNumber::Tcp, 64, &reply);
                if wire.write_all(&reply).await.is_err() {
                    break;
                }
                continue;
            }
            if segment.payload.is_empty() && !segment.flags.fin {
                continue;
            }
            let Some(state) = conns.get_mut(&key) else {
                continue;
            };
            state.received.extend_from_slice(&segment.payload);
            let ack = segment
                .sequence_number
                .wrapping_add(segment.payload.len() as u32 + u32::from(segment.flags.fin));
            let ack_pkt = TcpPacket::create(
                IpAddr::V6(phone),
                IpAddr::V6(host),
                segment.destination_port,
                segment.source_port,
                state.server_seq,
                ack,
                TcpFlags {
                    ack: true,
                    ..Default::default()
                },
                u16::MAX,
                &[],
                &[],
            );
            let ack_pkt = Ipv6Packet::create(phone, host, ProtocolNumber::Tcp, 64, &ack_pkt);
            if wire.write_all(&ack_pkt).await.is_err() {
                break;
            }
            if segment.destination_port == rsd_port
                && !state.rsd_replied
                && let Some(frame) = &rsd_frame
                && state
                    .received
                    .windows(b"Handshake\0".len())
                    .any(|w| w == b"Handshake\0")
            {
                state.rsd_replied = true;
                stats.rsd_handshakes += 1;
                for chunk in frame.chunks(1024) {
                    let data_pkt = TcpPacket::create(
                        IpAddr::V6(phone),
                        IpAddr::V6(host),
                        segment.destination_port,
                        segment.source_port,
                        state.server_seq,
                        ack,
                        TcpFlags {
                            psh: true,
                            ack: true,
                            ..Default::default()
                        },
                        u16::MAX,
                        &[],
                        chunk,
                    );
                    let data_pkt =
                        Ipv6Packet::create(phone, host, ProtocolNumber::Tcp, 64, &data_pkt);
                    if wire.write_all(&data_pkt).await.is_err() {
                        break 'wire;
                    }
                    state.server_seq = state.server_seq.wrapping_add(chunk.len() as u32);
                }
            }
        }
        stats.input_deliveries = conns
            .values()
            .map(|state| {
                state
                    .received
                    .windows(b"send\0".len())
                    .filter(|w| *w == b"send\0")
                    .count()
            })
            .sum();
        stats
    }

    fn tunnel() -> (Connection, DuplexStream) {
        let (host, phone) = tokio::io::duplex(1 << 16);
        let adapter = idevice::tcp::adapter::Adapter::new(
            Box::new(host),
            "fd00::1".parse().unwrap(),
            "fd00::2".parse().unwrap(),
        )
        .to_async_handle();
        let services = [
            DisplayServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().to_string(),
            AppServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().to_string(),
            "com.apple.accessibility.axAuditDaemon.remoteAXService".to_string(),
            crate::Hid::rsd_service_name().to_string(),
            "com.apple.coredevice.deviceinfo".to_string(),
        ]
        .into_iter()
        .zip(50000u16..)
        .map(|(name, port)| {
            let service = RsdService {
                entitlement: String::new(),
                port,
                uses_remote_xpc: true,
                features: None,
                service_version: None,
            };
            (name, service)
        })
        .collect();
        let rsd = RsdHandshake {
            services,
            protocol_version: 2,
            properties: HashMap::new(),
            uuid: String::new(),
        };
        let connection = Connection {
            adapter,
            rsd,
            rsd_port: 58783,
            provider: None,
            media: None,
        };
        (connection, phone)
    }

    pub(super) async fn connect_local(_udid: &str) -> Result<Connection> {
        let (connection, phone) = tunnel();
        PHONE.with(|sender| sender.borrow().as_ref().map(|sender| sender.send(phone)));
        Ok(connection)
    }

    // A cable pulled while the helper idles: the tunnel's stream ends and its adapter task exits.
    async fn unplugged() -> Connection {
        let (connection, phone) = tunnel();
        drop(phone);
        while connection.adapter.bind_udp(0).await.is_ok() {}
        connection
    }

    // A phone that answers: it accepts connections to `open` ports, resets the others and acknowledges
    // every segment. It hangs up once a connection has carried `hang_up_on`, and reports whether it did.
    async fn answer(mut wire: DuplexStream, open: Vec<u16>, hang_up_on: Option<&[u8]>) -> bool {
        let host: Ipv6Addr = "fd00::1".parse().unwrap();
        let phone: Ipv6Addr = "fd00::2".parse().unwrap();
        let mut carried: HashMap<u16, Vec<u8>> = HashMap::new();
        loop {
            let mut header = [0u8; 40];
            if wire.read_exact(&mut header).await.is_err() {
                return false;
            }
            let mut packet = vec![0u8; u16::from_be_bytes([header[4], header[5]]) as usize];
            if wire.read_exact(&mut packet).await.is_err() {
                return false;
            }
            if header[6] != ProtocolNumber::Tcp as u8 {
                continue;
            }
            let segment = TcpPacket::parse(&packet).unwrap();
            let (seq, flags) = match segment.flags {
                TcpFlags { syn: true, .. } if open.contains(&segment.destination_port) => (
                    0,
                    TcpFlags {
                        syn: true,
                        ack: true,
                        ..Default::default()
                    },
                ),
                TcpFlags { syn: true, .. } => (
                    0,
                    TcpFlags {
                        rst: true,
                        ack: true,
                        ..Default::default()
                    },
                ),
                _ if segment.payload.is_empty() => continue,
                _ => (
                    1,
                    TcpFlags {
                        ack: true,
                        ..Default::default()
                    },
                ),
            };
            let ack = segment
                .sequence_number
                .wrapping_add(segment.payload.len().max(segment.flags.syn as usize) as u32);
            let reply = TcpPacket::create(
                IpAddr::V6(phone),
                IpAddr::V6(host),
                segment.destination_port,
                segment.source_port,
                seq,
                ack,
                flags,
                u16::MAX,
                &[],
                &[],
            );
            let reply = Ipv6Packet::create(phone, host, ProtocolNumber::Tcp, 64, &reply);
            if wire.write_all(&reply).await.is_err() {
                return false;
            }
            let carried = carried.entry(segment.source_port).or_default();
            carried.extend(&segment.payload);
            if hang_up_on.is_some_and(|marker| carried.windows(marker.len()).any(|w| w == marker)) {
                return true;
            }
        }
    }

    #[tokio::test]
    async fn data_socket_uses_control_peer_address_and_listener_port() {
        use tokio::net::TcpListener;
        let control_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let client = TcpStream::connect(control_listener.local_addr().unwrap())
            .await
            .unwrap();
        let (_phone, _) = control_listener.accept().await.unwrap();
        let data_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let control = Control {
            client: RemotePairingClient::new(RpPairingSocket::new(client), "poki-mcp"),
            peer: control_listener.local_addr().unwrap(),
        };
        let mut socket = control
            .open_data_socket(data_listener.local_addr().unwrap().port())
            .await
            .unwrap();
        let (mut data, _) = data_listener.accept().await.unwrap();
        socket.write_all(b"data").await.unwrap();
        let mut bytes = [0; 4];
        data.read_exact(&mut bytes).await.unwrap();
        assert_eq!(&bytes, b"data");
        assert_eq!(
            socket.peer_addr().unwrap(),
            data_listener.local_addr().unwrap()
        );
    }

    #[test]
    fn only_bonjour_hosts_opt_into_control_refresh() {
        for (host, expected) in [
            ("phone.local", true),
            ("Phone.LOCAL.", true),
            ("phone.tailnet.ts.net", false),
            ("localhost", false),
            ("127.0.0.1", false),
            ("fe80::1%en0", false),
            ("fe80::1%en0.local", false),
        ] {
            let config = Config {
                id: "fixture".into(),
                host: host.into(),
                port: 1,
                pairing_file: "missing".into(),
            };
            assert_eq!(config.uses_bonjour(), expected, "{host}");
        }
    }

    #[tokio::test]
    async fn bonjour_explicit_reconnect_refreshes_control_and_preserves_live_tunnel() {
        use tokio::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let client = TcpStream::connect(listener.local_addr().unwrap())
            .await
            .unwrap();
        let (mut phone, _) = listener.accept().await.unwrap();
        let (live, _wire) = tunnel();
        let mut session = Session {
            transport: Transport::Remote(Config {
                id: "fixture".into(),
                host: "poki-test-missing.local".into(),
                port: 1,
                pairing_file: "/not-real".into(),
            }),
            control: Some(Control {
                client: RemotePairingClient::new(RpPairingSocket::new(client), "poki-mcp"),
                peer: listener.local_addr().unwrap(),
            }),
            connection: Some(live),
        };
        let received = tokio::spawn(async move { phone.read(&mut [0u8; 4096]).await.unwrap_or(0) });
        assert!(session.request(json!({"op":"reconnect"})).await.is_err());
        assert_eq!(
            received.await.unwrap(),
            0,
            "explicit Bonjour reconnect reused stale control"
        );
        assert!(
            session
                .connection
                .as_ref()
                .expect("working tunnel discarded")
                .adapter
                .bind_udp(0)
                .await
                .is_ok()
        );
    }

    #[tokio::test]
    async fn dead_bonjour_tunnel_drops_stale_control() {
        use tokio::net::TcpListener;
        // The old control socket still looks alive, while the underlying tunnel died.
        let old = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let client = TcpStream::connect(old.local_addr().unwrap()).await.unwrap();
        let (mut old_phone, _) = old.accept().await.unwrap();
        let stale = RemotePairingClient::new(RpPairingSocket::new(client), "poki-mcp");
        let mut session = Session {
            transport: Transport::Remote(Config {
                id: "synthetic-phone".into(),
                host: "poki-test-missing.local".into(),
                port: 1,
                pairing_file: "/not-a-real-pairing-file".into(),
            }),
            control: Some(Control {
                client: stale,
                peer: old.local_addr().unwrap(),
            }),
            connection: Some(unplugged().await),
        };
        let received =
            tokio::spawn(async move { old_phone.read(&mut [0u8; 4096]).await.unwrap_or(0) });
        assert!(session.request(json!({"op":"ax_tree"})).await.is_err());
        assert_eq!(
            received.await.unwrap(),
            0,
            "dead Bonjour tunnel reused its stale control"
        );
    }

    #[tokio::test]
    async fn non_bonjour_recovery_keeps_using_its_existing_control() {
        use tokio::net::TcpListener;
        // A nonexistent interface makes an accidental scoped-IP redial fail
        // locally, without probing any real LAN endpoint in this regression.
        for host in [
            "127.0.0.1",
            "fd00::1",
            "fe80::1%poki-no-such-interface",
            "phone.tailnet.ts.net",
            "localhost",
        ] {
            let old = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let client = TcpStream::connect(old.local_addr().unwrap()).await.unwrap();
            let (mut phone, _) = old.accept().await.unwrap();
            let current = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let mut session = Session {
                transport: Transport::Remote(Config {
                    id: "synthetic-phone".into(),
                    host: host.into(),
                    port: current.local_addr().unwrap().port(),
                    pairing_file: "/not-a-real-pairing-file".into(),
                }),
                control: Some(Control {
                    client: RemotePairingClient::new(RpPairingSocket::new(client), "poki-mcp"),
                    peer: old.local_addr().unwrap(),
                }),
                connection: Some(unplugged().await),
            };
            let received =
                tokio::spawn(async move { phone.read(&mut [0u8; 4096]).await.unwrap_or(0) });
            assert!(session.request(json!({"op":"ax_tree"})).await.is_err());
            assert!(
                received.await.unwrap() > 0,
                "fixed-IP recovery dropped its established control"
            );
        }
    }

    #[tokio::test]
    async fn unreachable_control_reports_each_address_and_its_os_error() {
        use tokio::net::TcpListener;
        for (host, address) in [("127.0.0.1", "127.0.0.1"), ("fe80::1%lo0", "[fe80::1%lo0]")] {
            let listener = TcpListener::bind((host, 0)).await.unwrap();
            let port = listener.local_addr().unwrap().port();
            drop(listener);
            let mut session = Session {
                transport: Transport::Remote(Config {
                    id: "synthetic-phone".into(),
                    host: host.into(),
                    port,
                    pairing_file: "/not-a-real-pairing-file".into(),
                }),
                control: None,
                connection: None,
            };
            let error = session
                .request(json!({"op":"connect"}))
                .await
                .unwrap_err()
                .to_string();
            assert!(
                error.starts_with("Remote pairing is unreachable"),
                "{error}"
            );
            assert!(
                error.contains(&format!(
                    "{address}:{port}: Connection refused (os error 61)"
                )),
                "{error}"
            );
        }
    }

    #[tokio::test]
    async fn failed_remote_replacement_keeps_the_working_tunnel() {
        use tokio::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        let (mut live, _phone) = tunnel();
        live.rsd.uuid = "working tunnel".into();
        let mut session = Session {
            transport: Transport::Remote(Config {
                id: "synthetic-phone".into(),
                host: "localhost".into(),
                port,
                pairing_file: "/not-a-real-pairing-file".into(),
            }),
            control: None,
            connection: Some(live),
        };
        assert!(session.request(json!({"op":"reconnect"})).await.is_err());
        let kept = session
            .connection
            .as_ref()
            .expect("working tunnel was discarded");
        assert_eq!(kept.rsd.uuid, "working tunnel");
        assert!(kept.adapter.bind_udp(0).await.is_ok());
    }

    #[tokio::test]
    async fn first_request_after_replug_rebuilds_the_tunnel_and_never_claims_delivery() {
        let mut failures = Vec::new();
        for request in [
            json!({"op":"tap","x":100,"y":200}),
            json!({"op":"launch_app","bundle_id":"local.fixture"}),
            json!({"op":"ax_tree"}),
        ] {
            let (sender, mut phones) = mpsc::unbounded_channel();
            PHONE.with(|slot| *slot.borrow_mut() = Some(sender));
            // The rebuilt tunnel carries the request's first packet; then the phone is gone again.
            let reached = tokio::spawn(async move {
                let mut reached = false;
                while let Some(mut phone) = phones.recv().await {
                    let mut byte = [0u8; 1];
                    reached |= phone.read(&mut byte).await.is_ok_and(|n| n > 0);
                }
                reached
            });
            let mut session = Session {
                transport: Transport::Local("fixture-phone".into()),
                control: None,
                connection: Some(unplugged().await),
            };
            let reply = session.request(request.clone()).await;
            PHONE.with(|slot| slot.borrow_mut().take());
            if !reached.await.unwrap() {
                failures.push(format!(
                    "{request}: did not rebuild the tunnel; reply: {reply:?}"
                ));
            }
            let reported = match (request["op"].as_str().unwrap(), &reply) {
                ("ax_tree", Err(error)) => !error.to_string().contains("delivered"),
                ("tap", Ok(reply)) => {
                    reply["outcome"] == "not_sent" && reply["stop_reason"] == "error"
                }
                ("launch_app", Ok(reply)) => reply["outcome"] == "not_sent",
                _ => false,
            };
            if !reported {
                failures.push(format!(
                    "{request}: nothing was sent, but the reply is {reply:?}"
                ));
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    #[tokio::test]
    async fn a_request_refused_before_any_input_says_nothing_was_sent() {
        let mut failures = Vec::new();
        let stroke = |time_ms: Value| json!({"op":"draw_strokes","strokes":[[{"x":100,"y":100,"time_ms":0},{"x":200,"y":200,"time_ms":time_ms}]]});
        for request in [
            // Refused by validation, and refused while parsing.
            stroke(json!(0)),
            stroke(json!("12")),
            json!({"op":"tap","x":-1,"y":200}),
            json!({"op":"ax_tree","include_offscreen":"yes"}),
        ] {
            // No tunnel is open, so a refusal must come before any connection attempt.
            let mut session = Session {
                transport: Transport::Local("fixture-phone".into()),
                control: None,
                connection: None,
            };
            let reply = session.request(request.clone()).await;
            let reported = match (request["op"].as_str().unwrap(), &reply) {
                ("ax_tree", Err(error)) => !error.to_string().contains("delivered"),
                (_, Ok(reply)) => {
                    reply["outcome"] == "not_sent"
                        && reply["sent"] == false
                        && reply["isError"] == true
                        && !reply["instruction"]
                            .as_str()
                            .unwrap_or("")
                            .contains("delivered")
                }
                _ => false,
            };
            if !reported || session.connection.is_some() {
                failures.push(format!(
                    "{request}: nothing was sent, but the reply is {reply:?}"
                ));
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    #[tokio::test(start_paused = true)]
    async fn a_tunnel_whose_phone_stops_answering_is_rebuilt() {
        let mut failures = Vec::new();
        for request in [json!({"op":"ax_tree"}), json!({"op":"tap","x":100,"y":200})] {
            let (sender, mut phones) = mpsc::unbounded_channel();
            PHONE.with(|slot| *slot.borrow_mut() = Some(sender));
            // The adapter task keeps running, but the phone never answers: Wi-Fi dropped without a reset.
            let (mut silent, _phone) = tunnel();
            silent.rsd.uuid = "silent tunnel".into();
            let mut session = Session {
                transport: Transport::Local("fixture-phone".into()),
                control: None,
                connection: Some(silent),
            };
            let reply = session.request(request.clone()).await;
            PHONE.with(|slot| slot.borrow_mut().take());
            if phones.recv().await.is_none() {
                failures.push(format!(
                    "{request}: a silent tunnel was kept; reply: {reply:?}"
                ));
            }
            if session.connection.as_ref().map(|c| c.rsd.uuid.as_str()) == Some("silent tunnel") {
                failures.push(format!("{request}: the silent tunnel is still in use"));
            }
            let reported = match (request["op"].as_str().unwrap(), &reply) {
                ("ax_tree", Err(error)) => !error.to_string().contains("delivered"),
                ("tap", Ok(reply)) => {
                    reply["outcome"] == "not_sent" && reply["stop_reason"] == "error"
                }
                _ => false,
            };
            if !reported {
                failures.push(format!(
                    "{request}: nothing was sent, but the reply is {reply:?}"
                ));
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    #[tokio::test(start_paused = true)]
    async fn a_service_refused_on_a_live_tunnel_keeps_that_tunnel() {
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));
        // The phone still answers its RSD port, but offers no display service (and its RSD refresh
        // stalls without closing the tunnel), so the live tunnel is preserved before any input.
        let (mut live, phone) = tunnel();
        live.rsd.services.clear();
        live.rsd.uuid = "live tunnel".into();
        let rsd_port = live.rsd_port;
        tokio::spawn(answer(phone, vec![rsd_port], None));
        let mut session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(live),
        };
        let reply = session.request(json!({"op":"tap","x":100,"y":200})).await;
        PHONE.with(|slot| slot.borrow_mut().take());
        let reply = reply.expect("a refused service is a reply, not a transport error");
        assert_eq!(reply["outcome"], "not_sent", "{reply}");
        assert_eq!(reply["stop_reason"], "error", "{reply}");
        assert_eq!(reply["reason"], "display_service_missing", "{reply}");
        assert!(phones.recv().await.is_none(), "a live tunnel was rebuilt");
        let kept = session
            .connection
            .as_ref()
            .expect("the live tunnel was dropped");
        assert_eq!(kept.rsd.uuid, "live tunnel");
        assert!(kept.adapter.bind_udp(0).await.is_ok());
    }

    #[tokio::test(start_paused = true)]
    async fn a_tap_cut_off_after_it_reached_the_phone_is_not_repeated() {
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));
        // An earlier input left the media session open, so the tap goes straight to the touch service.
        let (display, _display_phone) = tokio::io::duplex(1 << 16);
        let now = tokio::time::Instant::now();
        let media = InputMedia {
            client: DisplayServiceClient::from_stream(Box::new(display))
                .await
                .unwrap(),
            receivers: tokio::task::JoinSet::new(),
            ready_at: now,
            last_input: now,
            last_activity: now,
        };
        let (mut connection, phone) = tunnel();
        // This phone advertises device information and refuses the display query, so the tap also
        // shows that such a phone keeps the main touchscreen.
        connection.media = Some(media);
        let touch = connection.rsd.services[crate::Hid::rsd_service_name().as_ref()].port;
        // The touch report reaches the phone; the tunnel goes down before the release.
        let phone = tokio::spawn(async move { answer(phone, vec![touch], Some(b"send\0")).await });
        let mut session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(connection),
        };
        let reply = session.request(json!({"op":"tap","x":100,"y":200})).await;
        PHONE.with(|slot| slot.borrow_mut().take());
        assert!(
            phone.await.unwrap(),
            "the touch never reached the phone; reply: {reply:?}"
        );
        let error = reply.expect_err("a tap that may have landed was reported as a reply");
        assert!(
            error.to_string().contains("Input may have been delivered"),
            "{error}"
        );
        assert!(
            phones.recv().await.is_none(),
            "the tap was repeated on a new tunnel"
        );
        assert!(session.connection.is_none(), "the dead tunnel was kept");
    }

    #[tokio::test(start_paused = true)]
    async fn a_socket_error_on_a_tunnel_whose_phone_still_answers_keeps_that_tunnel() {
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));
        // The phone resets the display service connection but still accepts its RSD port.
        let (mut live, phone) = tunnel();
        live.rsd.uuid = "live tunnel".into();
        tokio::spawn(answer(phone, vec![live.rsd_port], None));
        let mut session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(live),
        };
        let reply = session.request(json!({"op":"tap","x":100,"y":200})).await;
        PHONE.with(|slot| slot.borrow_mut().take());
        let reply = reply.expect("a reset service is a reply, not a transport error");
        assert_eq!(reply["outcome"], "not_sent", "{reply}");
        assert_eq!(reply["stop_reason"], "error", "{reply}");
        assert!(
            phones.recv().await.is_none(),
            "a tunnel whose phone answers was rebuilt"
        );
        let kept = session
            .connection
            .as_ref()
            .expect("the live tunnel was dropped");
        assert_eq!(kept.rsd.uuid, "live tunnel");
    }

    #[tokio::test(start_paused = true)]
    async fn idle_session_releases_input_media_and_keeps_the_tunnel() {
        use tokio::io::AsyncBufReadExt;
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));
        let make_media = |now: tokio::time::Instant| async move {
            let (display, display_phone) = tokio::io::duplex(1 << 16);
            let (media_open, media_closed) = mpsc::unbounded_channel::<()>();
            let mut receivers = tokio::task::JoinSet::new();
            receivers.spawn(async move {
                let _open = media_open;
                std::future::pending::<()>().await;
            });
            let media = InputMedia {
                client: DisplayServiceClient::from_stream(Box::new(display))
                    .await
                    .unwrap(),
                receivers,
                ready_at: now,
                last_input: now,
                last_activity: now,
            };
            drop(display_phone);
            (media, media_closed)
        };

        // 1. In-flight read-only operation crossing INPUT_MEDIA_MAX_READ_HOLD releases media
        // while keeping the live tunnel intact.
        let start = tokio::time::Instant::now();
        let (media, mut slow_read_closed) = make_media(start).await;
        let (mut connection, phone) = tunnel();
        connection.rsd.uuid = "live tunnel".into();
        connection.media = Some(media);
        let rsd_port = connection.rsd_port;
        let ax_port =
            connection.rsd.services["com.apple.accessibility.axAuditDaemon.remoteAXService"].port;
        tokio::spawn(answer(phone, vec![rsd_port, ax_port], None));
        let mut session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(connection),
        };
        tokio::time::advance(INPUT_MEDIA_MAX_READ_HOLD - Duration::from_secs(1)).await;
        session
            .connection
            .as_mut()
            .unwrap()
            .media
            .as_mut()
            .unwrap()
            .last_activity = tokio::time::Instant::now();
        assert_eq!(
            session.input_media_deadline(),
            Some(start + INPUT_MEDIA_MAX_READ_HOLD)
        );
        let closed_at = tokio::spawn(async move {
            assert!(slow_read_closed.recv().await.is_none());
            start.elapsed()
        });
        assert!(session.request(json!({"op":"ax_tree"})).await.is_err());
        assert_eq!(closed_at.await.unwrap(), INPUT_MEDIA_MAX_READ_HOLD);
        assert!(start.elapsed() > INPUT_MEDIA_MAX_READ_HOLD);
        assert!(session.connection.as_ref().unwrap().media.is_none());
        assert!(
            session
                .connection
                .as_ref()
                .unwrap()
                .adapter
                .bind_udp(0)
                .await
                .is_ok()
        );

        // 2. Refused requests and half-open sockets just before the idle deadline cannot delay release.
        let reset_now = tokio::time::Instant::now();
        let (media, _media_closed) = make_media(reset_now).await;
        session.connection.as_mut().unwrap().media = Some(media);
        let refused = session
            .request(json!({"op":"tap","x":-1,"y":200}))
            .await
            .unwrap();
        assert_eq!(refused["outcome"], "not_sent");
        assert_eq!(
            session.input_media_deadline(),
            Some(reset_now + INPUT_MEDIA_IDLE_TIMEOUT)
        );
        // Reconnect releases open input media immediately while preserving the working tunnel if replacement fails.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let dead_port = listener.local_addr().unwrap().port();
        drop(listener);
        let (mut remote_live, _remote_phone) = tunnel();
        let (remote_media, mut remote_media_closed) = make_media(reset_now).await;
        remote_live.media = Some(remote_media);
        let mut remote_session = Session {
            transport: Transport::Remote(Config {
                id: "synthetic-phone".into(),
                host: "127.0.0.1".into(),
                port: dead_port,
                pairing_file: "/not-a-real-pairing-file".into(),
            }),
            control: None,
            connection: Some(remote_live),
        };
        assert!(
            remote_session
                .request(json!({"op":"reconnect"}))
                .await
                .is_err()
        );
        assert!(remote_media_closed.recv().await.is_none());
        assert!(remote_session.connection.as_ref().unwrap().media.is_none());
        assert!(
            remote_session
                .connection
                .as_ref()
                .unwrap()
                .adapter
                .bind_udp(0)
                .await
                .is_ok()
        );

        let reset_now = tokio::time::Instant::now();
        let (media, mut media_closed) = make_media(reset_now).await;
        session.connection.as_mut().unwrap().media = Some(media);

        let dir = std::env::temp_dir().join(format!(
            "poki-idle-media-{}-{}",
            std::process::id(),
            reset_now.elapsed().as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let socket_path = dir.join("session.sock");
        let socket_str = socket_path.to_str().unwrap().to_owned();
        let client_socket = socket_path.clone();
        let client = async move {
            while !client_socket.exists() {
                tokio::task::yield_now().await;
            }
            tokio::time::sleep(INPUT_MEDIA_IDLE_TIMEOUT - Duration::from_millis(100)).await;
            let stalled = tokio::net::UnixStream::connect(&client_socket)
                .await
                .unwrap();
            let mut stalled_reader = BufReader::new(stalled);
            let mut greeting = String::new();
            stalled_reader.read_line(&mut greeting).await.unwrap();

            assert!(
                media_closed.recv().await.is_none(),
                "idle input media session was not closed during stalled client read"
            );
            assert!(
                reset_now.elapsed() >= INPUT_MEDIA_IDLE_TIMEOUT
                    && reset_now.elapsed() < INPUT_MEDIA_IDLE_TIMEOUT + Duration::from_secs(1),
                "stalled client connection delayed idle media release: {:?}",
                reset_now.elapsed()
            );
            drop(stalled_reader);

            let send = |request: &str| {
                let socket_path = client_socket.clone();
                let request = request.to_owned();
                async move {
                    let stream = tokio::net::UnixStream::connect(&socket_path).await.unwrap();
                    let mut reader = BufReader::new(stream);
                    let mut greeting = String::new();
                    reader.read_line(&mut greeting).await.unwrap();
                    reader
                        .get_mut()
                        .write_all(request.as_bytes())
                        .await
                        .unwrap();
                    let mut reply = String::new();
                    reader.read_line(&mut reply).await.unwrap();
                    serde_json::from_str::<Value>(&reply).unwrap()
                }
            };
            let connected = send("{\"op\":\"connect\"}\n").await;
            assert_eq!(connected["connected"], true, "{connected}");
            let disconnected = send("{\"op\":\"disconnect\"}\n").await;
            assert_eq!(disconnected["disconnected"], true, "{disconnected}");
            Ok::<(), Box<dyn std::error::Error + Send + Sync>>(())
        };
        let (result, ()) = tokio::try_join!(
            Box::pin(serve_session(session, &socket_str)),
            Box::pin(client)
        )
        .unwrap();
        assert_eq!(result["closed"], true);
        assert!(
            phones.try_recv().is_err(),
            "releasing idle input media dropped the live tunnel"
        );
        PHONE.with(|slot| slot.borrow_mut().take());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn client_disconnect_during_in_flight_input_releases_media_and_never_replays() {
        std::thread::Builder::new()
            .stack_size(8 * 1024 * 1024)
            .spawn(|| {
                tokio::runtime::Builder::new_current_thread()
                    .enable_all()
                    .start_paused(true)
                    .build()
                    .unwrap()
                    .block_on(
                        client_disconnect_during_in_flight_input_releases_media_and_never_replays_inner(),
                    );
            })
            .unwrap()
            .join()
            .unwrap();
    }

    async fn client_disconnect_during_in_flight_input_releases_media_and_never_replays_inner() {
        use tokio::io::AsyncBufReadExt;
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));

        let now = tokio::time::Instant::now();
        let (display, display_phone) = tokio::io::duplex(1 << 16);
        let (media_open, mut media_closed) = mpsc::unbounded_channel::<()>();
        let mut receivers = tokio::task::JoinSet::new();
        receivers.spawn(async move {
            let _open = media_open;
            std::future::pending::<()>().await;
        });
        let media = InputMedia {
            client: DisplayServiceClient::from_stream(Box::new(display))
                .await
                .unwrap(),
            receivers,
            ready_at: now,
            last_input: now,
            last_activity: now,
        };
        drop(display_phone);
        let (mut connection, mut wire) = tunnel();
        connection.media = Some(media);
        let touch_port = connection.rsd.services[crate::Hid::rsd_service_name().as_ref()].port;

        let (first_send_tx, first_send_rx) = tokio::sync::oneshot::channel::<()>();
        let phone_task = tokio::spawn(async move {
            let host: Ipv6Addr = "fd00::1".parse().unwrap();
            let phone: Ipv6Addr = "fd00::2".parse().unwrap();
            let mut carried: HashMap<u16, Vec<u8>> = HashMap::new();
            let mut touch_syns = 0usize;
            let mut notified = Some(first_send_tx);
            loop {
                let mut header = [0u8; 40];
                if wire.read_exact(&mut header).await.is_err() {
                    break;
                }
                let mut packet = vec![0u8; u16::from_be_bytes([header[4], header[5]]) as usize];
                if wire.read_exact(&mut packet).await.is_err() {
                    break;
                }
                if header[6] != ProtocolNumber::Tcp as u8 {
                    continue;
                }
                let segment = TcpPacket::parse(&packet).unwrap();
                let (seq, flags) = match segment.flags {
                    TcpFlags { syn: true, .. } if segment.destination_port == touch_port => {
                        touch_syns += 1;
                        (
                            0,
                            TcpFlags {
                                syn: true,
                                ack: true,
                                ..Default::default()
                            },
                        )
                    }
                    TcpFlags { syn: true, .. } => (
                        0,
                        TcpFlags {
                            rst: true,
                            ack: true,
                            ..Default::default()
                        },
                    ),
                    _ if segment.payload.is_empty() => continue,
                    _ => (
                        1,
                        TcpFlags {
                            ack: true,
                            ..Default::default()
                        },
                    ),
                };
                let ack = segment
                    .sequence_number
                    .wrapping_add(segment.payload.len().max(segment.flags.syn as usize) as u32);
                let reply = TcpPacket::create(
                    IpAddr::V6(phone),
                    IpAddr::V6(host),
                    segment.destination_port,
                    segment.source_port,
                    seq,
                    ack,
                    flags,
                    u16::MAX,
                    &[],
                    &[],
                );
                let reply = Ipv6Packet::create(phone, host, ProtocolNumber::Tcp, 64, &reply);
                if wire.write_all(&reply).await.is_err() {
                    break;
                }
                let stream_bytes = carried.entry(segment.source_port).or_default();
                stream_bytes.extend(&segment.payload);
                if notified.is_some()
                    && stream_bytes
                        .windows(b"send\0".len())
                        .any(|w| w == b"send\0")
                {
                    let _ = notified.take().unwrap().send(());
                }
            }
            let total_send_calls: usize = carried
                .values()
                .map(|bytes| {
                    bytes
                        .windows(b"send\0".len())
                        .filter(|w| *w == b"send\0")
                        .count()
                })
                .sum();
            (touch_syns, total_send_calls)
        });

        let session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(connection),
        };
        let dir = std::env::temp_dir().join(format!(
            "poki-interrupted-input-{}-{}",
            std::process::id(),
            now.elapsed().as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let socket_path = dir.join("session.sock");
        let socket_str = socket_path.to_str().unwrap().to_owned();
        let client_socket = socket_path.clone();

        let client = async move {
            while !client_socket.exists() {
                tokio::task::yield_now().await;
            }
            let stream = tokio::net::UnixStream::connect(&client_socket)
                .await
                .unwrap();
            let mut reader = BufReader::new(stream);
            let mut greeting = String::new();
            reader.read_line(&mut greeting).await.unwrap();
            reader
                .get_mut()
                .write_all(b"{\"op\":\"tap\",\"x\":100,\"y\":200,\"duration_ms\":1000}\n")
                .await
                .unwrap();
            // Wait until the contact report reached the phone, then drop the client socket mid-tap.
            first_send_rx.await.unwrap();
            drop(reader);

            assert!(
                media_closed.recv().await.is_none(),
                "interrupted input did not discard the media session"
            );
            assert!(
                now.elapsed() < Duration::from_millis(1000),
                "interrupted input was not cancelled immediately before hold completion: {:?}",
                now.elapsed()
            );

            let stream = tokio::net::UnixStream::connect(&client_socket)
                .await
                .unwrap();
            let mut reader = BufReader::new(stream);
            let mut greeting = String::new();
            reader.read_line(&mut greeting).await.unwrap();
            reader
                .get_mut()
                .write_all(b"{\"op\":\"connect\"}\n")
                .await
                .unwrap();
            let mut reply = String::new();
            reader.read_line(&mut reply).await.unwrap();
            let connected: Value = serde_json::from_str(&reply).unwrap();
            assert_eq!(connected["connected"], true);

            let stream = tokio::net::UnixStream::connect(&client_socket)
                .await
                .unwrap();
            let mut reader = BufReader::new(stream);
            let mut greeting = String::new();
            reader.read_line(&mut greeting).await.unwrap();
            reader
                .get_mut()
                .write_all(b"{\"op\":\"disconnect\"}\n")
                .await
                .unwrap();
            let mut reply = String::new();
            reader.read_line(&mut reply).await.unwrap();
            let disconnected: Value = serde_json::from_str(&reply).unwrap();
            assert_eq!(disconnected["disconnected"], true);
            Ok::<(), Box<dyn std::error::Error + Send + Sync>>(())
        };

        let (result, ()) = tokio::try_join!(
            Box::pin(serve_session(session, &socket_str)),
            Box::pin(client)
        )
        .unwrap();
        assert_eq!(result["closed"], true);
        let (touch_syns, total_send_calls) = phone_task.await.unwrap();
        assert_eq!(
            touch_syns, 1,
            "interrupted tap opened Touch service {touch_syns} times (replayed)"
        );
        assert_eq!(
            total_send_calls, 1,
            "interrupted tap was not aborted mid-hold (expected 1 HID send, got {total_send_calls})"
        );
        assert!(
            phones.try_recv().is_err(),
            "interrupted tap rebuilt the tunnel or replayed on a second connection"
        );
        PHONE.with(|slot| slot.borrow_mut().take());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[tokio::test(start_paused = true)]
    async fn missing_service_refreshes_cached_rsd_on_live_tunnel_and_retries_once() {
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));

        // Simulate a tunnel established while the phone was locked (advertising deviceinfo only,
        // before DisplayService is ready), then unlocked so a fresh RSD handshake now advertises
        // DisplayService on a live port.
        let (mut live, phone) = tunnel();
        let full_rsd = live.rsd.clone();
        let device_info_name = "com.apple.coredevice.deviceinfo";
        let device_info_port = full_rsd.services[device_info_name].port;
        let display_port = full_rsd.services
            [DisplayServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().as_ref()]
        .port;
        let touch_port = full_rsd.services[crate::Hid::rsd_service_name().as_ref()].port;
        live.rsd.services.retain(|name, _| name == device_info_name);
        live.rsd.uuid = "live-before-unlock".into();

        let mut updated_rsd = full_rsd.clone();
        updated_rsd.uuid = "live-after-unlock".into();

        // Phone completes the real RemoteXPC RSD handshake on rsd_port and resets the newly
        // advertised display port on retry (proving the retry used the refreshed service map).
        let rsd_port = live.rsd_port;
        let phone_task = tokio::spawn(answer_rsd(
            phone,
            vec![rsd_port],
            rsd_port,
            Some(updated_rsd),
        ));

        let mut session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(live),
        };
        let reply = session
            .request(json!({"op":"tap","x":100,"y":200}))
            .await
            .expect("unsent service reset should return a structured reply");
        PHONE.with(|slot| slot.borrow_mut().take());

        assert!(
            phones.try_recv().is_err(),
            "in-place RSD refresh must keep the existing live tunnel instead of rebuilding it"
        );
        let kept = session
            .connection
            .as_ref()
            .expect("live tunnel was dropped");
        assert_eq!(kept.rsd.uuid, "live-after-unlock");
        assert_eq!(
            kept.rsd.services
                [DisplayServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().as_ref()]
            .port,
            display_port
        );
        // The retry reached the refreshed DisplayService port (which reset TCP) rather than
        // failing with display_service_missing again.
        assert_eq!(reply["outcome"], "not_sent", "{reply}");
        assert_ne!(
            reply["reason"], "display_service_missing",
            "retry did not use the refreshed RSD service map: {reply}"
        );

        drop(session);
        let stats = phone_task.await.unwrap();
        assert_eq!(stats.rsd_handshakes, 1, "RSD refresh should run once");
        assert_eq!(
            stats.syns(device_info_port),
            2,
            "tap should run once before refresh and once after refresh"
        );
        assert_eq!(
            stats.syns(display_port),
            1,
            "refreshed DisplayService port should be dialed once"
        );
        assert_eq!(stats.syns(touch_port), 0);
        assert_eq!(stats.input_deliveries, 0);
    }

    #[tokio::test(start_paused = true)]
    async fn unchanged_rsd_refresh_keeps_live_tunnel_without_redundant_retry() {
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));

        let (mut live, phone) = tunnel();
        let device_info_name = "com.apple.coredevice.deviceinfo";
        let device_info_port = live.rsd.services[device_info_name].port;
        let display_port = live.rsd.services
            [DisplayServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().as_ref()]
        .port;
        let touch_port = live.rsd.services[crate::Hid::rsd_service_name().as_ref()].port;
        live.rsd.services.retain(|name, _| name == device_info_name);
        live.rsd.uuid = "live-no-ddi-unchanged".into();

        // Phone advertises the identical service map on refresh; Session::request must not retry tap.
        let mut unchanged_rsd = live.rsd.clone();
        unchanged_rsd.uuid = "live-no-ddi-refreshed".into();
        let rsd_port = live.rsd_port;
        let phone_task = tokio::spawn(answer_rsd(
            phone,
            vec![rsd_port],
            rsd_port,
            Some(unchanged_rsd),
        ));

        let mut session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(live),
        };
        let reply = session
            .request(json!({"op":"tap","x":100,"y":200}))
            .await
            .expect("missing display service should return a reply");
        PHONE.with(|slot| slot.borrow_mut().take());

        assert_eq!(reply["outcome"], "not_sent", "{reply}");
        assert_eq!(reply["reason"], "display_service_missing", "{reply}");
        assert!(phones.try_recv().is_err(), "live tunnel was rebuilt");
        assert_eq!(
            session.connection.as_ref().unwrap().rsd.uuid,
            "live-no-ddi-refreshed"
        );

        drop(session);
        let stats = phone_task.await.unwrap();
        assert_eq!(stats.rsd_handshakes, 1, "RSD refresh should run once");
        assert_eq!(
            stats.syns(device_info_port),
            1,
            "unchanged service map must not replay tap"
        );
        assert_eq!(stats.syns(display_port), 0);
        assert_eq!(stats.syns(touch_port), 0);
        assert_eq!(stats.input_deliveries, 0);
    }

    #[tokio::test(start_paused = true)]
    async fn rsd_refresh_prunes_removed_services_without_redundant_retry() {
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));

        let (mut live, phone) = tunnel();
        let device_info_name = "com.apple.coredevice.deviceinfo";
        let ax_name = "com.apple.accessibility.axAuditDaemon.remoteAXService";
        let device_info_port = live.rsd.services[device_info_name].port;
        let display_port = live.rsd.services
            [DisplayServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().as_ref()]
        .port;
        let touch_port = live.rsd.services[crate::Hid::rsd_service_name().as_ref()].port;
        live.rsd
            .services
            .retain(|name, _| name == device_info_name || name == ax_name);
        live.rsd.uuid = "live-with-stale-ax".into();

        // Refresh drops ax_name while keeping device_info unchanged and DisplayService absent.
        let mut pruned_rsd = live.rsd.clone();
        pruned_rsd.services.remove(ax_name);
        pruned_rsd.uuid = "live-pruned-ax".into();
        let rsd_port = live.rsd_port;
        let phone_task = tokio::spawn(answer_rsd(
            phone,
            vec![rsd_port],
            rsd_port,
            Some(pruned_rsd),
        ));

        let mut session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(live),
        };
        let reply = session
            .request(json!({"op":"tap","x":100,"y":200}))
            .await
            .expect("missing display service should return a reply");
        PHONE.with(|slot| slot.borrow_mut().take());

        assert_eq!(reply["outcome"], "not_sent", "{reply}");
        assert_eq!(reply["reason"], "display_service_missing", "{reply}");
        assert!(phones.try_recv().is_err(), "live tunnel was rebuilt");
        let kept = session
            .connection
            .as_ref()
            .expect("live tunnel was dropped");
        assert_eq!(kept.rsd.uuid, "live-pruned-ax");
        assert!(
            !kept.rsd.services.contains_key(ax_name),
            "removed service stayed in cached RSD map"
        );

        drop(session);
        let stats = phone_task.await.unwrap();
        assert_eq!(stats.rsd_handshakes, 1);
        assert_eq!(
            stats.syns(device_info_port),
            1,
            "pure service removal must not trigger a redundant retry"
        );
        assert_eq!(stats.syns(display_port), 0);
        assert_eq!(stats.syns(touch_port), 0);
        assert_eq!(stats.input_deliveries, 0);
    }

    #[tokio::test(start_paused = true)]
    async fn missing_service_on_silent_tunnel_marks_closed_and_rebuilds() {
        let (sender, mut phones) = mpsc::unbounded_channel();
        PHONE.with(|slot| *slot.borrow_mut() = Some(sender));

        // Cached RSD is empty AND the phone silently vanished without resetting TCP.
        // Probing rsd_port during refresh must fail cleanly via jktcp's connect timeout,
        // mark the tunnel closed, and rebuild once instead of sticking in a zombie state.
        let (mut silent, _phone) = tunnel();
        silent.rsd.services.clear();
        silent.rsd.uuid = "silent-locked-tunnel".into();

        let mut session = Session {
            transport: Transport::Local("fixture-phone".into()),
            control: None,
            connection: Some(silent),
        };
        let reply = session
            .request(json!({"op":"tap","x":100,"y":200}))
            .await
            .expect("rebuilt dead tunnel returns a structured not_sent reply");
        PHONE.with(|slot| slot.borrow_mut().take());

        assert!(
            phones.recv().await.is_some(),
            "silent tunnel failing RSD refresh was not rebuilt"
        );
        assert_ne!(
            session.connection.as_ref().map(|c| c.rsd.uuid.as_str()),
            Some("silent-locked-tunnel"),
            "silent tunnel was kept"
        );
        assert_eq!(reply["outcome"], "not_sent", "{reply}");
    }

    #[tokio::test(start_paused = true)]
    async fn remote_rsd_refresh_with_mismatched_udid_drops_connection_and_control() {
        use tokio::net::TcpListener;
        for (idx, host) in ["phone.local", "127.0.0.1", "phone.tailnet.ts.net"]
            .into_iter()
            .enumerate()
        {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let client = TcpStream::connect(listener.local_addr().unwrap())
                .await
                .unwrap();
            let (_phone_ctrl, _) = listener.accept().await.unwrap();

            let (mut live, phone) = tunnel();
            let device_info_name = "com.apple.coredevice.deviceinfo";
            let device_info_port = live.rsd.services[device_info_name].port;
            let display_port = live.rsd.services
                [DisplayServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().as_ref()]
            .port;
            let touch_port = live.rsd.services[crate::Hid::rsd_service_name().as_ref()].port;

            let mut wrong_device = live.rsd.clone();
            wrong_device.uuid = format!("wrong-device-{idx}");
            wrong_device.properties.insert(
                "UniqueDeviceID".into(),
                plist::Value::String("other-phone-udid".into()),
            );
            live.rsd.uuid = format!("expected-before-mismatch-{idx}");
            live.rsd.services.retain(|name, _| name == device_info_name);

            let rsd_port = live.rsd_port;
            let phone_task = tokio::spawn(answer_rsd(
                phone,
                vec![rsd_port],
                rsd_port,
                Some(wrong_device),
            ));

            let mut session = Session {
                transport: Transport::Remote(Config {
                    id: "expected-phone-udid".into(),
                    host: host.into(),
                    port: 49152,
                    pairing_file: "/not-real".into(),
                }),
                control: Some(Control {
                    client: RemotePairingClient::new(RpPairingSocket::new(client), "poki-mcp"),
                    peer: listener.local_addr().unwrap(),
                }),
                connection: Some(live),
            };
            let reply = session
                .request(json!({"op":"tap","x":100,"y":200}))
                .await
                .expect("unsent mismatch returns a structured not_sent reply");
            assert_eq!(reply["outcome"], "not_sent", "{host}: {reply}");
            assert!(
                reply["error"]
                    .as_str()
                    .unwrap_or("")
                    .contains("Remote device identity does not match"),
                "{host}: {reply}"
            );
            assert!(
                session.connection.is_none(),
                "{host}: connection with mismatched remote UDID was kept"
            );
            assert!(
                session.control.is_none(),
                "{host}: control session for mismatched remote UDID was kept"
            );

            drop(session);
            let stats = phone_task.await.unwrap();
            assert_eq!(stats.rsd_handshakes, 1, "{host}");
            assert_eq!(stats.syns(device_info_port), 1, "{host}");
            assert_eq!(stats.syns(display_port), 0, "{host}");
            assert_eq!(stats.syns(touch_port), 0, "{host}");
            assert_eq!(stats.input_deliveries, 0, "{host}");
        }
    }

    #[tokio::test(start_paused = true)]
    async fn ax_tree_missing_service_refreshes_cached_rsd_on_live_tunnel() {
        let (mut live, phone) = tunnel();
        let ax_port =
            live.rsd.services["com.apple.accessibility.axAuditDaemon.remoteAXService"].port;
        let mut updated_rsd = live.rsd.clone();
        updated_rsd.properties.insert(
            "UniqueDeviceID".into(),
            plist::Value::String("synthetic-phone-ax".into()),
        );
        updated_rsd.uuid = "ax-after-unlock".into();
        live.rsd.uuid = "ax-before-unlock".into();
        live.rsd.services.clear();

        let rsd_port = live.rsd_port;
        let phone_task = tokio::spawn(answer_rsd(
            phone,
            vec![rsd_port],
            rsd_port,
            Some(updated_rsd),
        ));

        let mut session = Session {
            transport: Transport::Remote(Config {
                id: "synthetic-phone-ax".into(),
                host: "phone.local".into(),
                port: 49152,
                pairing_file: "/not-real".into(),
            }),
            control: None,
            connection: Some(live),
        };
        let err = session
            .request(json!({"op":"ax_tree"}))
            .await
            .expect_err("reset AX port returns an error")
            .to_string();

        assert_eq!(
            session.connection.as_ref().unwrap().rsd.uuid,
            "ax-after-unlock"
        );
        assert!(
            !err.contains("Native accessibility service is unavailable"),
            "retry did not use refreshed AX service port: {err}"
        );
        assert!(
            !err.contains("Input may have been delivered"),
            "read-only ax_tree error falsely claimed input delivery: {err}"
        );

        drop(session);
        let stats = phone_task.await.unwrap();
        assert_eq!(stats.rsd_handshakes, 1);
        assert_eq!(stats.syns(ax_port), 1);
        assert_eq!(stats.input_deliveries, 0);
    }

    #[tokio::test(start_paused = true)]
    async fn remote_read_only_failure_never_claims_input_delivery() {
        let (live, phone) = tunnel();
        let rsd_port = live.rsd_port;
        let ax_port =
            live.rsd.services["com.apple.accessibility.axAuditDaemon.remoteAXService"].port;
        // Phone answers rsd_port and ax_port without sending an AX payload so ax_tree fails on a
        // live RemotePairing tunnel.
        tokio::spawn(answer(phone, vec![rsd_port, ax_port], None));
        let mut session = Session {
            transport: Transport::Remote(Config {
                id: "synthetic-phone-ro".into(),
                host: "phone.local".into(),
                port: 49152,
                pairing_file: "/not-real".into(),
            }),
            control: None,
            connection: Some(live),
        };
        let error = session
            .request(json!({"op":"ax_tree"}))
            .await
            .expect_err("silent ax_tree should return an error")
            .to_string();
        assert!(
            !error.contains("Input may have been delivered"),
            "read-only remote error falsely claimed input delivery: {error}"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn dial_with_allocates_budget_and_falls_back_after_stalled_address() {
        // Single-address targets keep the full open() budget; multi-address targets share 15s.
        assert_eq!(
            attempt_timeout(Duration::from_secs(15), 1),
            Duration::from_secs(15)
        );
        assert_eq!(
            attempt_timeout(Duration::from_secs(15), 2),
            Duration::from_secs(5)
        );
        assert_eq!(
            attempt_timeout(Duration::from_secs(15), 6),
            Duration::from_millis(2500)
        );
        assert_eq!(
            attempt_timeout(Duration::from_secs(15), 12),
            Duration::from_millis(1250)
        );
        assert_eq!(
            attempt_timeout(Duration::from_secs(15), 18),
            Duration::from_nanos(833_333_333)
        );

        let blackholed: SocketAddr = "[fe80::1]:49152".parse().unwrap();
        let reachable: SocketAddr = "127.0.0.1:49152".parse().unwrap();

        // Single-address target (total_budget = None) is not cut off at 15s.
        let single_started = tokio::time::Instant::now();
        let single = dial_with(
            "phone.tailnet.ts.net",
            [reachable],
            None,
            |address| async move {
                tokio::time::sleep(Duration::from_secs(20)).await;
                Ok(address)
            },
        )
        .await
        .expect("single-address target should keep full open() budget past 15s");
        assert_eq!(single, reachable);
        assert_eq!(single_started.elapsed(), Duration::from_secs(20));

        // 2-address fallback: stalled first address falls back at 5s.
        let started = tokio::time::Instant::now();
        let connected = dial_with(
            "phone.local",
            [blackholed, reachable],
            Some(DIAL_TOTAL_BUDGET),
            |address| async move {
                if address == blackholed {
                    std::future::pending::<std::io::Result<SocketAddr>>().await
                } else {
                    Ok(address)
                }
            },
        )
        .await
        .expect("stalled first address should fall through to reachable second address");
        assert_eq!(connected, reachable);
        assert_eq!(started.elapsed(), Duration::from_secs(5));

        // 18-address fallback: 17 blackholed addresses before 1 reachable address must still reach
        // the 18th address well within the shared 15s budget (and 25s open() timeout).
        let stalled_many: Vec<SocketAddr> = (1..=17)
            .map(|i| {
                SocketAddr::new(
                    IpAddr::V6(Ipv6Addr::new(0xfe80, 0, 0, 0, 0, 0, 0, i)),
                    49152,
                )
            })
            .chain(std::iter::once(reachable))
            .collect();
        let started_18 = tokio::time::Instant::now();
        let connected_18 = dial_with(
            "phone.local",
            stalled_many,
            Some(DIAL_TOTAL_BUDGET),
            |address| async move {
                if address == reachable {
                    Ok(address)
                } else {
                    std::future::pending::<std::io::Result<SocketAddr>>().await
                }
            },
        )
        .await
        .expect("18th reachable address should be dialed within the shared 15s budget");
        assert_eq!(connected_18, reachable);
        assert!(
            started_18.elapsed() < DIAL_TOTAL_BUDGET,
            "18-address fallback exceeded shared 15s budget: {:?}",
            started_18.elapsed()
        );

        // 12 stalled addresses: total elapsed time must not exceed the shared 15s deadline.
        let stalled_12: Vec<SocketAddr> = (1..=12)
            .map(|i| {
                SocketAddr::new(
                    IpAddr::V6(Ipv6Addr::new(0xfe80, 0, 0, 0, 0, 0, 0, i)),
                    49152,
                )
            })
            .collect();
        let started_12 = tokio::time::Instant::now();
        let err = dial_with(
            "phone.local",
            stalled_12,
            Some(DIAL_TOTAL_BUDGET),
            |_address| std::future::pending::<std::io::Result<()>>(),
        )
        .await
        .expect_err("all stalled addresses should fail with timeout diagnostics");
        assert!(
            started_12.elapsed() <= DIAL_TOTAL_BUDGET,
            "12 stalled addresses exceeded shared 15s budget: {:?}",
            started_12.elapsed()
        );
        for i in 1..=12 {
            assert!(
                err.contains(&format!("[fe80::{i:x}]:49152: connection timed out")),
                "missing address {i} timeout diagnostic: {err}"
            );
        }
    }

    #[tokio::test(start_paused = true)]
    async fn read_only_list_apps_refreshes_cached_rsd_on_live_remote_tunnel() {
        let (mut live, phone) = tunnel();
        let app_port = live.rsd.services
            [AppServiceClient::<Box<dyn ReadWrite>>::rsd_service_name().as_ref()]
        .port;
        let mut updated_rsd = live.rsd.clone();
        updated_rsd.properties.insert(
            "UniqueDeviceID".into(),
            plist::Value::String("synthetic-phone-apps".into()),
        );
        updated_rsd.uuid = "remote-after-unlock".into();
        live.rsd.uuid = "remote-before-unlock".into();
        live.rsd.services.clear();

        let rsd_port = live.rsd_port;
        let phone_task = tokio::spawn(answer_rsd(
            phone,
            vec![rsd_port],
            rsd_port,
            Some(updated_rsd),
        ));

        let mut session = Session {
            transport: Transport::Remote(Config {
                id: "synthetic-phone-apps".into(),
                host: "phone.local".into(),
                port: 49152,
                pairing_file: "/not-real".into(),
            }),
            control: None,
            connection: Some(live),
        };
        let err = session
            .request(json!({"op":"list_apps"}))
            .await
            .expect_err("reset AppService port returns an error")
            .to_string();

        assert_eq!(
            session.connection.as_ref().unwrap().rsd.uuid,
            "remote-after-unlock"
        );
        assert!(
            !err.contains("Input may have been delivered"),
            "read-only list_apps error falsely claimed input delivery: {err}"
        );
        assert!(
            !err.to_lowercase().contains("service not found"),
            "retry did not use refreshed AppService port: {err}"
        );

        drop(session);
        let stats = phone_task.await.unwrap();
        assert_eq!(stats.rsd_handshakes, 1);
        assert_eq!(stats.syns(app_port), 1);
        assert_eq!(stats.input_deliveries, 0);
    }
}
