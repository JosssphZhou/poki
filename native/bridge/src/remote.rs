use super::{Request, Result, execute_connected};
use idevice::{
    remote_pairing::{
        RemotePairingClient, RpPairingFile, RpPairingSocket, connect_tls_psk_tunnel_native,
    },
    rsd::RsdHandshake,
    tcp::handle::AdapterHandle,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{io::Write, time::Duration};
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
    net::TcpStream,
};

/// A parsed SOCKS5 endpoint. The tunnel traffic is already encrypted by
/// RPPairing, so the proxy itself only needs the no-authentication method.
#[derive(Debug, Clone)]
struct ProxyAddr {
    host: String,
    port: u16,
}

impl ProxyAddr {
    fn parse(value: &str) -> Option<Self> {
        let rest = value.strip_prefix("socks5://")?;
        let (host, port_text) = rest.rsplit_once(':')?;
        let port = port_text.parse().ok()?;
        if host.is_empty() {
            return None;
        }
        Some(Self { host: host.to_string(), port })
    }
}

#[derive(Deserialize)]
struct Config {
    id: String,
    host: String,
    port: u16,
    pairing_file: String,
    proxy: Option<String>,
}

type Control = RemotePairingClient<RpPairingSocket<TcpStream>>;

/// Opens a raw byte stream to `host:port`, either directly or through the
/// configured SOCKS5 proxy. The halves are reunited into a `TcpStream` so
/// the pairing and tunnel layers keep their existing types.
async fn connect_stream(config: &Config, host: &str, port: u16) -> Result<TcpStream> {
    let Some(proxy_text) = config.proxy.as_deref() else {
        let socket = TcpStream::connect((host, port)).await?;
        socket.set_nodelay(true)?;
        return Ok(socket);
    };
    let proxy = ProxyAddr::parse(proxy_text)
        .ok_or_else(|| format!("Invalid proxy URL: {proxy_text}"))?;
    let socket = TcpStream::connect((proxy.host.as_str(), proxy.port))
        .await
        .map_err(|e| format!("Cannot reach the SOCKS5 proxy at {}: {e}", proxy.host))?;
    socket.set_nodelay(true)?;
    let (mut reader, mut writer) = socket.into_split();

    // SOCKS5 greeting: offer only the no-authentication method.
    writer.write_all(&[0x05, 0x01, 0x00]).await?;
    let mut method = [0u8; 2];
    reader.read_exact(&mut method).await?;
    if method != [0x05, 0x00] {
        return Err("The SOCKS5 proxy refused the no-authentication method".into());
    }

    // CONNECT with a domain name; the proxy resolves DNS itself.
    let mut request = vec![0x05, 0x01, 0x00, 0x03, host.len() as u8];
    request.extend_from_slice(host.as_bytes());
    request.extend_from_slice(&port.to_be_bytes());
    writer.write_all(&request).await?;
    let mut header = [0u8; 4];
    reader.read_exact(&mut header).await?;
    if header[1] != 0x00 {
        return Err(format!("The SOCKS5 proxy rejected CONNECT with reply code {}", header[1]).into());
    }
    // Consume the bound address so the next bytes are the tunnel payload.
    let skip = match header[3] {
        0x01 => 6,
        0x03 => 1 + reader.read_u8().await? as usize + 2,
        0x04 => 18,
        other => return Err(format!("Unknown SOCKS5 address type {other} in the proxy reply").into()),
    };
    let mut bound = vec![0u8; skip];
    reader.read_exact(&mut bound).await?;

    Ok(reader.reunite(writer)?)
}

struct Session {
    config: Config,
    control: Option<Control>,
    connection: Option<(AdapterHandle, RsdHandshake)>,
}

impl Session {
    async fn connect(&mut self) -> Result<()> {
        if self.control.is_none() {
            let socket = connect_stream(&self.config, &self.config.host, self.config.port).await
                .map_err(|e| format!("Remote pairing is unreachable: {e}. Keep the proxy and tunnel connected; reconnect the iPhone to Wi-Fi to establish a new session."))?;
            let mut control = RemotePairingClient::new(RpPairingSocket::new(socket), "poki-mcp");
            let mut record = RpPairingFile::read_from_file(&self.config.pairing_file).await?;
            control.attempt_pair_verify().await?;
            // Never fall back to pairing or request consent during an ordinary operation.
            control.validate_pairing(&mut record).await?;
            self.control = Some(control);
        }
        let control = self.control.as_mut().unwrap();
        let port = match control.create_tcp_listener().await {
            Ok(port) => port,
            Err(error) => {
                self.control = None;
                return Err(format!("The remote pairing control connection closed: {error}. Reconnect the iPhone to Wi-Fi, then reconnect the device.").into());
            }
        };
        let socket = connect_stream(&self.config, &self.config.host, port).await
            .map_err(|e| format!("The iPhone refused a new tunnel: {e}. Reconnect it to Wi-Fi, then reconnect the device."))?;
        let tunnel = connect_tls_psk_tunnel_native(socket, control.encryption_key()).await?;
        let info = tunnel.info.clone();
        let mut adapter = idevice::tcp::adapter::Adapter::new(
            Box::new(tunnel.into_inner()),
            info.client_address.parse()?,
            info.server_address.parse()?,
        )
        .to_async_handle();
        let rsd = RsdHandshake::new(adapter.connect(info.server_rsd_port).await?).await?;
        if rsd
            .properties
            .get("UniqueDeviceID")
            .and_then(plist::Value::as_string)
            != Some(self.config.id.as_str())
        {
            return Err("Remote device identity does not match the configured iPhone".into());
        }
        self.connection = Some((adapter, rsd));
        Ok(())
    }

    async fn request(&mut self, request: Value) -> Result<Value> {
        // Keep the working tunnel until its replacement has actually connected.
        // A failed reconnect must not destroy the only usable cellular session.
        if self.connection.is_none() || request["op"] == "reconnect" {
            let result = tokio::time::timeout(Duration::from_secs(25), self.connect()).await;
            match result {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    self.control = None;
                    return Err(error);
                }
                Err(error) => {
                    self.control = None;
                    return Err(error.into());
                }
            }
        }
        if request["op"] == "connect" || request["op"] == "reconnect" {
            return Ok(
                json!({"connected":true,"transport":"remote_pairing","device":self.config.id}),
            );
        }
        let request: Request = serde_json::from_value(request)?;
        request.validate()?;
        if matches!(
            request,
            Request::InstallApp { .. } | Request::UninstallApp { .. }
        ) {
            return Err("App installation over remote pairing is not supported".into());
        }
        let (adapter, rsd) = self.connection.as_mut().unwrap();
        let result = tokio::time::timeout(
            Duration::from_secs(90),
            execute_connected(adapter, rsd, None, request),
        )
        .await;
        match result {
            Ok(Ok(value)) => Ok(value),
            failure => {
                self.connection = None;
                // Delivery can be ambiguous: the caller must inspect, never replay automatically.
                let message = match failure {
                    Ok(Err(e)) => e.to_string(),
                    Err(_) => "Remote operation timed out".into(),
                    _ => unreachable!(),
                };
                Err(format!(
                    "{message}. Input may have been delivered; inspect the screen before retrying."
                )
                .into())
            }
        }
    }
}

fn load(path: &str) -> Result<Session> {
    Ok(Session {
        config: serde_json::from_slice(&std::fs::read(path)?)?,
        control: None,
        connection: None,
    })
}

async fn reply(session: &mut Session, line: &str) -> Value {
    let response = if line.len() > 2 * 1024 * 1024 {
        Err("Remote request exceeds size limit".into())
    } else {
        match serde_json::from_str::<Value>(line) {
            Ok(request) => session.request(request).await,
            Err(e) => Err(e.into()),
        }
    };
    response.unwrap_or_else(|e| json!({"isError":true,"transport_error":true,"error":e.to_string(),"screen_change_verified":false}))
}

pub async fn serve(path: &str) -> Result<Value> {
    let mut session = load(path)?;
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    while let Some(line) = lines.next_line().await? {
        println!("{}", reply(&mut session, &line).await);
        std::io::stdout().flush()?;
    }
    Ok(json!({"closed":true}))
}

pub async fn serve_socket(path: &str, socket_path: &str) -> Result<Value> {
    use std::os::unix::fs::PermissionsExt;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let mut session = load(path)?;
    let listener = tokio::net::UnixListener::bind(socket_path)?;
    std::fs::set_permissions(socket_path, std::fs::Permissions::from_mode(0o600))?;
    println!("{}", json!({"ready":true}));
    std::io::stdout().flush()?;
    loop {
        let (mut socket, _) = listener.accept().await?;
        let hello = format!("{}\n", json!({"pid":std::process::id()}));
        if socket.write_all(hello.as_bytes()).await.is_err() {
            continue;
        }
        let mut stream = BufReader::new(socket);
        let mut line = String::new();
        // The local directory is private. Bound incomplete requests so an abandoned client cannot hold the device.
        if !matches!(tokio::time::timeout(Duration::from_secs(5), (&mut stream).take(2 * 1024 * 1024 + 1).read_line(&mut line)).await, Ok(Ok(n)) if n > 0)
        {
            continue;
        }
        if line.len() > 2 * 1024 * 1024 {
            continue;
        }
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
        let mut byte = [0u8; 1];
        let output = tokio::select! {
            output = reply(&mut session, &line) => output,
            _ = stream.read(&mut byte) => {
                // The requester disappeared while delivery may be in flight. Exit, closing every owned service.
                return Err("Remote operation cancelled; inspect the device before retrying input".into());
            }
        };
        let mut bytes = serde_json::to_vec(&output)?;
        bytes.push(b'\n');
        let _ = stream.get_mut().write_all(&bytes).await;
    }
    let _ = std::fs::remove_file(socket_path);
    Ok(json!({"closed":true}))
}
