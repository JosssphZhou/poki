//! Deploys Poki's relay Worker (`deploy/cf-relay/worker.js`, bundled into this binary) to the
//! person's own Cloudflare account through the API, the same upload DEPLOY.md documents.
//! The API token is kept in the system keychain, so the relay can be updated without pasting it.
use crate::{Reporter, Result};
use reqwest::{Method, StatusCode};
use serde::{Deserialize, Serialize};
use std::time::Duration;

pub const WORKER_JS: &str = include_str!("../../../deploy/cf-relay/worker.js");
pub const SCRIPT_NAME: &str = "poki-relay";
pub const COMPATIBILITY_DATE: &str = "2025-10-01";
const API: &str = "https://api.cloudflare.com/client/v4";
const MANUAL_DEPLOY_PATH: &str = "deploy/cf-relay/DEPLOY.md#deploy-with-the-script";

pub fn token_setup_url() -> String {
    let permissions = serde_json::json!([
        {"key": "workers_scripts", "type": "edit"},
        {"key": "account_settings", "type": "read"},
    ]);
    let mut url = reqwest::Url::parse("https://dash.cloudflare.com/profile/api-tokens").unwrap();
    url.query_pairs_mut()
        .append_pair("permissionGroupKeys", &permissions.to_string())
        .append_pair("accountId", "*")
        .append_pair("zoneId", "all")
        .append_pair("name", "Poki Setup Relay");
    url.into()
}

pub const VARS: [(&str, &str); 7] = [
    ("MAX_BODY", "4194304"),
    ("REQ_TIMEOUT_MS", "180000"),
    ("PER_MINUTE", "60"),
    ("CONCURRENT", "4"),
    ("LABEL_DAILY", "5000"),
    ("GLOBAL_DAILY", "8000"),
    ("GLOBAL_DAILY_SECONDS", "80000"),
];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Deployed {
    pub account_id: String,
    pub account_name: String,
    pub address: String,
    pub first_deploy: bool,
    pub deployed_at: i64,
    /// `poki://setup?relay=<address>`, for the QR the phone scans.
    pub phone_link: String,
    /// SHA-256 of the Worker code deployed, to tell when a newer relay is out.
    #[serde(default)]
    pub worker_sha256: Option<String>,
    /// Where that code came from: a release tag, or "built in".
    #[serde(default)]
    pub worker_source: Option<String>,
}

/// The Poki the relay must match: the one this computer installed or renewed most recently.
fn relay_for() -> crate::release::RelayFor {
    let newest = crate::keeper::all().ok().and_then(|all| all.into_iter().max_by_key(|r| r.signed_at));
    match newest {
        Some(r) => crate::release::RelayFor {
            tag: (!r.release_tag.starts_with("local:")).then(|| r.release_tag.clone()),
            version: Some(r.version.clone()),
            build: Some(r.build.clone()),
        },
        None => Default::default(),
    }
}

/// The relay code to deploy: `poki-relay-worker.js` from the release of the Poki on the iPhone
/// (else the newest on the chosen channel), checked against that release's SHA256SUMS; the copy
/// built into this app when no release has one or GitHub can't be reached.
pub async fn worker_code() -> (String, String) {
    let (code, source, _) = worker_code_and_link().await;
    (code, source)
}

/// The relay's source in the release repo, for deploying it by hand.
pub fn source_link() -> String { format!("https://github.com/{}/tree/standalone/deploy/cf-relay", crate::release::repo()) }

/// The code, where it came from, and a link to that exact file (the release asset, or the source).
pub async fn worker_code_and_link() -> (String, String, String) {
    match crate::release::relay_worker(&relay_for()).await {
        Ok(Some((tag, code, url))) => (code, tag, url),
        Ok(None) => (WORKER_JS.to_string(), "built in".into(), source_link()),
        Err(e) => {
            tracing::warn!("relay from releases unavailable, using the built-in copy: {e}");
            (WORKER_JS.to_string(), "built in".into(), source_link())
        }
    }
}

pub fn sha256_hex(s: &str) -> String {
    use sha2::Digest;
    hex::encode(sha2::Sha256::digest(s.as_bytes()))
}

/// Whether the relay you deployed differs from the one Poki Setup would deploy now.
#[derive(Debug, Clone, Serialize)]
pub struct WorkerStatus {
    pub source: String,
    /// The worker.js to deploy by hand (the release's `poki-relay-worker.js`, or the source folder).
    pub download_url: String,
    /// DEPLOY.md, the steps for deploying it by hand.
    pub guide_url: String,
    pub sha256: String,
    pub deployed_sha256: Option<String>,
    pub update_available: bool,
}

pub async fn worker_status() -> Result<WorkerStatus> {
    let (code, source, download_url) = worker_code_and_link().await;
    let sha256 = sha256_hex(&code);
    let at = if source == "built in" { "main" } else { source.as_str() };
    let guide_url = format!("https://github.com/{}/blob/{at}/{MANUAL_DEPLOY_PATH}", crate::release::repo());
    let deployed_sha256 = remembered()?.and_then(|d| d.worker_sha256);
    // A relay deployed before Poki Setup recorded hashes counts as older.
    let update_available = remembered()?.is_some() && deployed_sha256.as_deref() != Some(sha256.as_str());
    Ok(WorkerStatus { source, download_url, guide_url, sha256, deployed_sha256, update_available })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Account {
    pub id: String,
    pub name: String,
}

#[derive(Deserialize)]
struct Envelope {
    success: bool,
    #[serde(default)]
    errors: Vec<ApiError>,
    #[serde(default)]
    result: serde_json::Value,
    result_info: Option<ResultInfo>,
}
#[derive(Deserialize)]
struct ApiError {
    code: i64,
}
#[derive(Deserialize)]
struct ResultInfo {
    total_pages: Option<u32>,
}

#[derive(Debug, thiserror::Error)]
pub enum CloudflareError {
    #[error("Copy the API token Cloudflare shows after you create it.")]
    InvalidToken,
    #[error("Cloudflare did not grant access. Check that the token is active and allows Workers Scripts Edit and Account Settings Read for this account.")]
    Permission,
    #[error("No matching Cloudflare account is available to this token.")]
    NoAccounts,
    #[error("The suggested workers.dev names were taken. Try again later or use another Cloudflare account.")]
    SubdomainTaken,
    #[error("This Cloudflare account reached a Workers limit or its plan does not allow this deploy. Check Workers usage and plan in Cloudflare.")]
    PlanLimit,
    #[error("Could not reach Cloudflare. Check your internet connection and try again.")]
    Network,
    #[error("The relay was uploaded but is not answering yet. Wait a minute and try again.")]
    NotReady,
    #[error("This version of Poki Setup can't update the existing Worker's migration. Use a compatible relay release and run deploy/cf-relay/deploy.sh to deploy manually.")]
    UnsupportedMigration,
    #[error("Cloudflare could not complete the request. Try again later.")]
    Api,
}

impl CloudflareError {
    pub(crate) fn kind(&self) -> &'static str {
        match self {
            Self::InvalidToken => "cloudflare_invalid_token",
            Self::Permission => "cloudflare_permission",
            Self::NoAccounts => "cloudflare_no_accounts",
            Self::SubdomainTaken => "cloudflare_subdomain_taken",
            Self::PlanLimit => "cloudflare_free_limit",
            Self::Network => "cloudflare_network",
            Self::NotReady => "cloudflare_not_ready",
            Self::UnsupportedMigration => "cloudflare_unsupported_migration",
            Self::Api => "cloudflare_api",
        }
    }
}

struct Reply {
    status: StatusCode,
    envelope: Option<Envelope>,
}

impl Reply {
    fn has_code(&self, code: i64) -> bool {
        self.envelope.as_ref().is_some_and(|env| !env.success && env.errors.iter().any(|e| e.code == code))
    }

    fn result<T: serde::de::DeserializeOwned>(self) -> Result<T> {
        if [10015, 10027, 10037, 10055].into_iter().any(|code| self.has_code(code)) {
            return Err(CloudflareError::PlanLimit.into());
        }
        if matches!(self.status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN)
            || [10000, 10001, 9109].into_iter().any(|code| self.has_code(code))
        {
            return Err(CloudflareError::Permission.into());
        }
        let env = self.envelope.filter(|env| self.status.is_success() && env.success).ok_or(CloudflareError::Api)?;
        serde_json::from_value(env.result).map_err(|_| CloudflareError::Api.into())
    }
}

#[derive(Deserialize)]
struct Subdomain {
    subdomain: String,
}

impl Subdomain {
    fn validated(self) -> Result<String> {
        let name = self.subdomain;
        if name.is_empty() || name.len() > 63 || name.starts_with('-') || name.ends_with('-')
            || !name.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-')
        {
            return Err(CloudflareError::Api.into());
        }
        Ok(name)
    }
}

pub struct Cloudflare {
    http: reqwest::Client,
    token: String,
    api: String,
}

impl Cloudflare {
    pub fn new(token: &str) -> Result<Self> {
        Self::with_api(token, API)
    }

    fn with_api(token: &str, api: &str) -> Result<Self> {
        let token = token.trim();
        if !(20..=256).contains(&token.len())
            || !token.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
        {
            return Err(CloudflareError::InvalidToken.into());
        }
        let http = reqwest::Client::builder().timeout(Duration::from_secs(120))
            .redirect(reqwest::redirect::Policy::none()).build()?;
        Ok(Self { http, token: token.into(), api: api.into() })
    }

    fn request(&self, method: Method, path: &str) -> reqwest::RequestBuilder {
        self.http.request(method, format!("{}{path}", self.api)).bearer_auth(&self.token)
    }

    async fn send(request: reqwest::RequestBuilder) -> Result<Reply> {
        let res = request.send().await.map_err(|_| CloudflareError::Network)?;
        let status = res.status();
        let bytes = res.bytes().await.map_err(|_| CloudflareError::Network)?;
        Ok(Reply { status, envelope: serde_json::from_slice(&bytes).ok() })
    }

    pub async fn accounts(&self) -> Result<Vec<Account>> {
        let mut list = Vec::new();
        let mut page = 1;
        loop {
            let res = Self::send(self.request(Method::GET, &format!("/accounts?per_page=50&page={page}"))).await?;
            let pages = res.envelope.as_ref().and_then(|e| e.result_info.as_ref()).and_then(|i| i.total_pages).unwrap_or(1);
            list.extend(res.result::<Vec<Account>>()?);
            if page >= pages {
                break;
            }
            page += 1;
        }
        if list.is_empty() {
            return Err(CloudflareError::NoAccounts.into());
        }
        Ok(list)
    }

    pub async fn account(&self, id: &str) -> Result<Account> {
        self.accounts().await?.into_iter().find(|a| a.id == id).ok_or_else(|| CloudflareError::NoAccounts.into())
    }

    async fn account_subdomain(&self, path: &str) -> Result<Option<String>> {
        let res = Self::send(self.request(Method::GET, path)).await?;
        if res.has_code(10007) && !matches!(res.status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN) {
            return Ok(None);
        }
        let sub = res.result::<Subdomain>()?;
        if sub.subdomain.is_empty() {
            return Ok(None);
        }
        Ok(Some(sub.validated()?))
    }

    async fn ensure_subdomain(&self, account: &str) -> Result<String> {
        let path = format!("/accounts/{account}/workers/subdomain");
        let hash = sha256_hex(account);
        for start in (0..hash.len()).step_by(16) {
            if let Some(subdomain) = self.account_subdomain(&path).await? {
                return Ok(subdomain);
            }
            let name = format!("poki-{}", &hash[start..start + 16]);
            let res = Self::send(self.request(Method::PUT, &path).json(&serde_json::json!({"subdomain": name}))).await?;
            if res.has_code(10031) && !matches!(res.status, StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN) {
                continue;
            }
            return res.result::<Subdomain>()?.validated();
        }
        Err(CloudflareError::SubdomainTaken.into())
    }

    async fn has_secret(&self, account: &str) -> Result<Option<bool>> {
        let res = Self::send(self.request(Method::GET, &format!("/accounts/{account}/workers/scripts/{SCRIPT_NAME}/secrets"))).await?;
        if res.status == StatusCode::NOT_FOUND {
            return Ok(None);
        }
        #[derive(Deserialize)]
        struct S {
            name: String,
        }
        let list: Vec<S> = res.result()?;
        Ok(Some(list.iter().any(|s| s.name == "TOKEN_SECRET")))
    }

    async fn migration_tag(&self, account: &str) -> Result<Option<String>> {
        let res = Self::send(self.request(Method::GET, &format!("/accounts/{account}/workers/services/{SCRIPT_NAME}"))).await?;
        if res.status == StatusCode::NOT_FOUND {
            return Ok(None);
        }
        let v: serde_json::Value = res.result()?;
        Ok(Some(v["default_environment"]["script"]["migration_tag"].as_str().unwrap_or("").to_string()))
    }

    /// Uploads the Worker. Keeps an existing TOKEN_SECRET, makes one on the first deploy.
    pub async fn deploy(&self, account: &Account, reporter: &Reporter) -> Result<Deployed> {
        self.deploy_with(account, reporter, worker_code, async |address| verify_relay(address).await).await
    }

    async fn deploy_with(
        &self,
        account: &Account,
        reporter: &Reporter,
        load_worker: impl AsyncFnOnce() -> (String, String),
        verify: impl AsyncFnOnce(&str) -> Result<()>,
    ) -> Result<Deployed> {
        if account.id.len() != 32 || !account.id.bytes().all(|b| b.is_ascii_hexdigit()) {
            return Err(CloudflareError::NoAccounts.into());
        }
        reporter.step("relay", "Deploy");
        reporter.part("relay", 0.1, Some("Checking the account".into()));
        let existing_secret = self.has_secret(&account.id).await?;
        let tag = self.migration_tag(&account.id).await?;
        let first_deploy = existing_secret.is_none();
        let mut bindings = vec![
            serde_json::json!({"type": "durable_object_namespace", "name": "DEVICE", "class_name": "DeviceRelay"}),
            serde_json::json!({"type": "durable_object_namespace", "name": "BUDGET", "class_name": "Budget"}),
        ];
        for (k, v) in VARS {
            bindings.push(serde_json::json!({"type": "plain_text", "name": k, "text": v}));
        }
        let mut metadata = serde_json::json!({
            "main_module": "index.js",
            "compatibility_date": COMPATIBILITY_DATE,
            "bindings": bindings,
            "observability": {"enabled": false},
        });
        if existing_secret == Some(true) {
            metadata["keep_bindings"] = serde_json::json!(["secret_text"]);
        } else {
            use rand::RngCore;
            let mut raw = [0u8; 32];
            rand::thread_rng().fill_bytes(&mut raw);
            metadata["bindings"].as_array_mut().unwrap().push(serde_json::json!({"type": "secret_text", "name": "TOKEN_SECRET", "text": hex::encode(raw)}));
        }
        match tag.as_deref() {
            None | Some("") => metadata["migrations"] = serde_json::json!({"new_tag": "v1", "new_sqlite_classes": ["DeviceRelay", "Budget"]}),
            Some("v1") => {}
            Some(_) => return Err(CloudflareError::UnsupportedMigration.into()),
        }
        reporter.part("relay", 0.2, Some("Setting up the workers.dev address".into()));
        let sub = self.ensure_subdomain(&account.id).await?;
        let address = format!("https://{SCRIPT_NAME}.{sub}.workers.dev");
        reporter.part("relay", 0.3, Some("Getting the newest relay".into()));
        let (code, source) = load_worker().await;
        reporter.part("relay", 0.4, Some(format!("Uploading the Worker ({source})")));
        let form = reqwest::multipart::Form::new()
            .part("metadata", reqwest::multipart::Part::text(metadata.to_string()).mime_str("application/json").unwrap())
            .part("index.js", reqwest::multipart::Part::text(code.clone()).file_name("index.js").mime_str("application/javascript+module").unwrap());
        let script = format!("/accounts/{}/workers/scripts/{SCRIPT_NAME}", account.id);
        Self::send(self.request(Method::PUT, &script).multipart(form)).await?.result::<serde_json::Value>()?;

        reporter.part("relay", 0.7, Some("Turning on the workers.dev address".into()));
        let route = self.request(Method::POST, &format!("{script}/subdomain"))
            .json(&serde_json::json!({"enabled": true, "previews_enabled": false}));
        Self::send(route).await?.result::<serde_json::Value>()?;

        reporter.part("relay", 0.9, Some("Checking the relay answers".into()));
        verify(&address).await?;
        Ok(Deployed { account_id: account.id.clone(), account_name: account.name.clone(), address: address.clone(), first_deploy, deployed_at: crate::keeper::now(), phone_link: phone_link(&address), worker_sha256: Some(sha256_hex(&code)), worker_source: Some(source) })
    }
}

async fn verify_relay(address: &str) -> Result<()> {
    let mut answered = false;
    for attempt in 0..10 {
        if attempt > 0 {
            tokio::time::sleep(Duration::from_secs(3)).await;
        }
        if let Ok(res) = crate::mcp::relay_probe(address).await {
            answered = true;
            if res.status().is_success() {
                return Ok(());
            }
            if matches!(res.status(), StatusCode::SERVICE_UNAVAILABLE | StatusCode::TOO_MANY_REQUESTS)
                && res.text().await.is_ok_and(|text| text.to_ascii_lowercase().contains("error code: 1027"))
            {
                return Err(CloudflareError::PlanLimit.into());
            }
        }
    }
    Err(if answered { CloudflareError::NotReady } else { CloudflareError::Network }.into())
}

const TOKEN_NAME: &str = "cloudflare-relay-token";

/// The Cloudflare API token saved in the keychain, if any.
pub fn saved_token() -> Option<String> { crate::apple::store::secret_get(TOKEN_NAME) }
pub fn save_token(token: &str) -> Result<()> { crate::apple::store::secret_set(TOKEN_NAME, token.trim()) }
pub fn forget_token() -> Result<()> { crate::apple::store::secret_delete(TOKEN_NAME) }

/// The token to use: the one given, else the saved one.
pub fn token_or_saved(given: Option<String>) -> Result<String> {
    given.filter(|t| !t.trim().is_empty()).or_else(saved_token).ok_or_else(|| CloudflareError::InvalidToken.into())
}

pub fn phone_link(address: &str) -> String { format!("poki://setup?relay={}", urlencode(address)) }

fn path() -> Result<std::path::PathBuf> { Ok(crate::paths::state_dir()?.join("relay.json")) }
pub fn remembered() -> Result<Option<Deployed>> { Ok(std::fs::read_to_string(path()?).ok().and_then(|t| serde_json::from_str(&t).ok())) }
pub fn remember(d: &Deployed) -> Result<()> {
    std::fs::write(path()?, serde_json::to_vec_pretty(d)?)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Error;
    use serde_json::{Value, json};
    use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};

    const TOKEN: &str = "not-a-token-test-fixture";
    const ACCOUNT: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const OTHER: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    type Route = (String, &'static str, String);

    fn ok(route: impl Into<String>, result: Value) -> Route {
        (route.into(), "200 OK", json!({"success": true, "result": result}).to_string())
    }

    fn failure(route: impl Into<String>, status: &'static str, code: i64) -> Route {
        (route.into(), status, json!({"success": false, "errors": [{"code": code}]}).to_string())
    }

    async fn mock(routes: Vec<Route>) -> (String, tokio::task::JoinHandle<Vec<String>>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            let mut bodies = Vec::new();
            for (route, status, response) in routes {
                let (socket, _) = listener.accept().await.unwrap();
                let mut socket = BufReader::new(socket);
                let mut line = String::new();
                socket.read_line(&mut line).await.unwrap();
                assert_eq!(line.trim_end(), format!("{route} HTTP/1.1"));
                let mut length = 0;
                let mut authorized = false;
                loop {
                    line.clear();
                    if socket.read_line(&mut line).await.unwrap() == 0 || line == "\r\n" {
                        break;
                    }
                    let (name, value) = line.split_once(':').unwrap();
                    if name.eq_ignore_ascii_case("content-length") {
                        length = value.trim().parse().unwrap();
                    }
                    if name.eq_ignore_ascii_case("authorization") {
                        authorized = value.trim() == format!("Bearer {TOKEN}");
                    }
                }
                assert_eq!(authorized, !route.contains("/.well-known/"));
                let mut body = vec![0; length];
                socket.read_exact(&mut body).await.unwrap();
                bodies.push(String::from_utf8(body).unwrap());
                socket.get_mut().write_all(format!(
                    "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{response}", response.len()
                ).as_bytes()).await.unwrap();
            }
            bodies
        });
        (url, server)
    }

    #[test]
    fn dashboard_prefills_only_the_scopes_used_by_setup() {
        let url = reqwest::Url::parse(&token_setup_url()).unwrap();
        assert_eq!(url.origin().ascii_serialization(), "https://dash.cloudflare.com");
        assert_eq!(url.path(), "/profile/api-tokens");
        let query: std::collections::HashMap<_, _> = url.query_pairs().collect();
        assert_eq!(query["accountId"], "*");
        assert_eq!(serde_json::from_str::<Value>(&query["permissionGroupKeys"]).unwrap(), json!([
            {"key": "workers_scripts", "type": "edit"},
            {"key": "account_settings", "type": "read"},
        ]));
        assert!(matches!(Cloudflare::new("a secret from a different clipboard app"), Err(Error::Cloudflare(CloudflareError::InvalidToken))));
    }

    #[tokio::test]
    async fn deploys_and_verifies_for_the_selected_account_with_or_without_a_subdomain() {
        let account_path = format!("/accounts/{ACCOUNT}/workers");
        let script = format!("{account_path}/scripts/{SCRIPT_NAME}");
        let subdomain = format!("{account_path}/subdomain");
        let health = format!("GET /.well-known/oauth-protected-resource/v1/{}/{}/mcp", "a".repeat(52), "a".repeat(43));
        let hash = sha256_hex(ACCOUNT);
        let first_name = format!("poki-{}", &hash[..16]);
        let second_name = format!("poki-{}", &hash[16..32]);
        for first in [true, false] {
            let name = if first { &second_name } else { "existing-relay" };
            let expected_address = format!("https://{SCRIPT_NAME}.{name}.workers.dev");
            let secrets = format!("GET {script}/secrets");
            let migration = format!("GET {account_path}/services/{SCRIPT_NAME}");
            let get_subdomain = format!("GET {subdomain}");
            let put_subdomain = format!("PUT {subdomain}");
            let chosen = json!({"id": ACCOUNT, "name": "Chosen account"});
            let mut routes = vec![
                ("GET /accounts?per_page=50&page=1".into(), "200 OK",
                    json!({"success":true,"result":[{"id":OTHER,"name":"Other account"}],"result_info":{"total_pages":2}}).to_string()),
                ok("GET /accounts?per_page=50&page=2", json!([chosen])),
            ];
            if first {
                routes.extend([
                    failure(secrets, "404 Not Found", 10007),
                    failure(migration, "404 Not Found", 10007),
                    failure(&get_subdomain, "404 Not Found", 10007),
                    failure(&put_subdomain, "400 Bad Request", 10031),
                    failure(&get_subdomain, "404 Not Found", 10007),
                    ok(&put_subdomain, json!({"subdomain": name})),
                ]);
            } else {
                routes.extend([
                    ok(secrets, json!([{"name":"TOKEN_SECRET"}])),
                    ok(migration, json!({"default_environment":{"script":{"migration_tag":"v1"}}})),
                    ok(&get_subdomain, json!({"subdomain": name})),
                ]);
            }
            let upload_at = routes.len();
            routes.extend([
                ok(format!("PUT {script}"), json!({"id":SCRIPT_NAME})),
                ok(format!("POST {script}/subdomain"), json!(null)),
                (health.clone(), "200 OK", "{}".into()),
            ]);
            let (url, server) = mock(routes).await;
            let cf = Cloudflare::with_api(TOKEN, &url).unwrap();
            let account = cf.account(ACCOUNT).await.unwrap();
            assert_eq!(account.name, "Chosen account");
            let result = cf.deploy_with(&account, &Reporter::new(|_| {}), async || (WORKER_JS.into(), "test release".into()), async |address| {
                assert_eq!(address, expected_address);
                verify_relay(&url).await
            }).await.unwrap();
            assert_eq!(result.address, expected_address);
            assert_eq!(result.account_id, ACCOUNT);
            assert_eq!(result.first_deploy, first);
            assert_eq!(result.phone_link, phone_link(&expected_address));
            assert_eq!(result.worker_sha256, Some(sha256_hex(WORKER_JS)));
            assert_eq!(result.worker_source.as_deref(), Some("test release"));
            let bodies = server.await.unwrap();
            if first {
                assert!(bodies[upload_at - 3].contains(&first_name));
                assert!(bodies[upload_at - 1].contains(&second_name));
            }
            let upload = &bodies[upload_at];
            assert!(upload.contains("DeviceRelay") && upload.contains("application/javascript+module"));
            assert_eq!(upload.contains(r#""new_sqlite_classes":["DeviceRelay","Budget"]"#), first);
            assert_eq!(upload.contains(r#""keep_bindings":["secret_text"]"#), !first);
            assert_eq!(upload.contains(r#""name":"TOKEN_SECRET""#), first);
            assert_eq!(serde_json::from_str::<Value>(&bodies[upload_at + 1]).unwrap(), json!({"enabled": true, "previews_enabled": false}));
        }
    }

    #[tokio::test]
    async fn distinguishes_permissions_worker_limits_and_network_failure() {
        let account = "GET /accounts?per_page=50&page=1";
        for (route, kind) in [
            (failure(account, "403 Forbidden", 9109), "cloudflare_permission"),
            (ok(account, json!([])), "cloudflare_no_accounts"),
            (failure(account, "400 Bad Request", 10037), "cloudflare_free_limit"),
        ] {
            let (url, server) = mock(vec![route]).await;
            let cf = Cloudflare::with_api(TOKEN, &url).unwrap();
            assert_eq!(cf.accounts().await.unwrap_err().kind(), kind);
            server.await.unwrap();
        }
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        drop(listener);
        let cf = Cloudflare::with_api(TOKEN, &url).unwrap();
        assert_eq!(cf.accounts().await.unwrap_err().kind(), "cloudflare_network");
    }

    #[tokio::test]
    async fn deploy_reports_actionable_failures_after_starting_the_progress_step() {
        let script = format!("/accounts/{ACCOUNT}/workers/scripts/{SCRIPT_NAME}");
        let account = Account { id: ACCOUNT.into(), name: "Fixture".into() };
        let secrets = format!("GET {script}/secrets");
        let cases = [
            (vec![failure(&secrets, "403 Forbidden", 9109)], "cloudflare_permission"),
            (vec![
                ok(&secrets, json!([{"name": "TOKEN_SECRET"}])),
                ok(format!("GET /accounts/{ACCOUNT}/workers/services/{SCRIPT_NAME}"),
                    json!({"default_environment": {"script": {"migration_tag": "future"}}})),
            ], "cloudflare_unsupported_migration"),
        ];
        for (routes, kind) in cases {
            let (url, server) = mock(routes).await;
            let cf = Cloudflare::with_api(TOKEN, &url).unwrap();
            let events = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
            let captured = events.clone();
            let reporter = Reporter::new(move |event| captured.lock().unwrap().push(serde_json::to_value(event).unwrap()));
            let error = cf.deploy_with(&account, &reporter, async || panic!("must not fetch a Worker"), async |_| {
                panic!("must not verify a relay")
            }).await.unwrap_err();
            assert_eq!(error.kind(), kind);
            if kind == "cloudflare_unsupported_migration" {
                assert!(error.to_string().contains("deploy/cf-relay/deploy.sh"));
            }
            assert_eq!(*events.lock().unwrap(), [
                json!({"kind": "step", "id": "relay", "title": "Deploy"}),
                json!({"kind": "part", "id": "relay", "fraction": 0.1, "detail": "Checking the account"}),
            ]);
            server.await.unwrap();
        }
    }

    #[tokio::test]
    async fn subdomain_collisions_are_bounded_and_permissions_do_not_trigger_registration() {
        let put = format!("PUT /accounts/{ACCOUNT}/workers/subdomain");
        let get = format!("GET /accounts/{ACCOUNT}/workers/subdomain");
        let routes = (0..4).flat_map(|_| [
            failure(&get, "404 Not Found", 10007),
            failure(&put, "400 Bad Request", 10031),
        ]).collect();
        let (url, server) = mock(routes).await;
        let cf = Cloudflare::with_api(TOKEN, &url).unwrap();
        assert_eq!(cf.ensure_subdomain(ACCOUNT).await.unwrap_err().kind(), "cloudflare_subdomain_taken");
        server.await.unwrap();

        let (url, server) = mock(vec![failure(get, "403 Forbidden", 10007)]).await;
        let cf = Cloudflare::with_api(TOKEN, &url).unwrap();
        assert_eq!(cf.ensure_subdomain(ACCOUNT).await.unwrap_err().kind(), "cloudflare_permission");
        server.await.unwrap();
    }

    #[tokio::test]
    async fn verification_recognizes_cloudflares_free_request_limit() {
        let health = format!("GET /.well-known/oauth-protected-resource/v1/{}/{}/mcp", "a".repeat(52), "a".repeat(43));
        let (url, server) = mock(vec![(health, "503 Service Unavailable", "error code: 1027".into())]).await;
        assert_eq!(verify_relay(&url).await.unwrap_err().kind(), "cloudflare_free_limit");
        server.await.unwrap();
    }

    #[test]
    fn worker_is_bundled() {
        assert!(super::WORKER_JS.contains("DeviceRelay"));
        assert!(super::WORKER_JS.len() > 10_000);
        assert_eq!(super::phone_link("https://poki-relay.me.workers.dev"), "poki://setup?relay=https%3A%2F%2Fpoki-relay.me.workers.dev");
    }
}

fn urlencode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}
