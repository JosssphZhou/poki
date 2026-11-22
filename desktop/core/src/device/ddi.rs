//! The personalized developer disk image (iOS 17 and later). Poki downloads it itself on the
//! phone, from the same mirror; this module has it on the computer too, to mount it once as a
//! proof that automation can start, and to pre-seed Poki's container so the phone skips the
//! download. Files are checked against the SHA-384 digests in `BuildManifest.plist`, as Poki does.
use super::Phone;
use crate::{Error, Reporter, Result, paths};
use idevice::{IdeviceService, lockdown::LockdownClient, mobile_image_mounter::ImageMounter};
use sha2::{Digest, Sha384};
use std::path::{Path, PathBuf};

const MIRROR_BASE: &str = "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/main/PersonalizedImages";

/// The same repository through jsDelivr's CDN, for networks where GitHub's raw host does not answer
/// (common in mainland China). Every file is checked against the SHA-384 digests in the
/// BuildManifest.plist that comes from the same mirror, which catches a broken or partial download
/// but does not prove the manifest itself. The phone still checks Apple's signature when it mounts.
const CDN_BASES: [&str; 3] = [
    "https://cdn.jsdelivr.net/gh/doronz88/DeveloperDiskImage@main/PersonalizedImages",
    "https://gcore.jsdelivr.net/gh/doronz88/DeveloperDiskImage@main/PersonalizedImages",
    "https://testingcf.jsdelivr.net/gh/doronz88/DeveloperDiskImage@main/PersonalizedImages",
];

/// Which image a phone takes. iOS 26.4 and later install a Cryptex1 cryptex; earlier iOS mounts the
/// personalized image through the image mounter. Poki on the phone picks by the same rule.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Cryptex,
    Personalized,
}

impl Kind {
    /// The image for an iOS version ("18.7.7"); the cryptex when the version cannot be read.
    pub fn for_ios(ios: &str) -> Self {
        let mut parts = ios.trim().split('.');
        let Some(major) = parts.next().and_then(|p| p.parse::<u32>().ok()) else { return Kind::Cryptex };
        let minor = parts.next().and_then(|p| p.parse::<u32>().ok()).unwrap_or(0);
        if (major, minor) >= (26, 4) { Kind::Cryptex } else { Kind::Personalized }
    }

    fn folder(self) -> &'static str {
        if self == Kind::Cryptex { "Xcode_iOS_DDI_Cryptex" } else { "Xcode_iOS_DDI_Personalized" }
    }

    pub fn mirror(self) -> String {
        format!("{MIRROR_BASE}/{}", self.folder())
    }

    /// Every place the image is downloaded from, in the order they are tried.
    pub fn mirrors(self) -> Vec<String> {
        std::iter::once(MIRROR_BASE).chain(CDN_BASES).map(|b| format!("{b}/{}", self.folder())).collect()
    }

    pub fn files(self) -> &'static [&'static str] {
        match self {
            Kind::Cryptex => &["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache", "Image.dmg.cryptex_info", "Image.dmg.root_hash"],
            Kind::Personalized => &["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"],
        }
    }

    fn payload_keys(self) -> &'static [&'static str] {
        match self {
            Kind::Cryptex => &["Cryptex1,GenericDmg", "Cryptex1,GenericTrustCache", "Cryptex1,CryptexInfoPlist", "Cryptex1,GenericVolume"],
            Kind::Personalized => &["PersonalizedDMG", "LoadableTrustCache"],
        }
    }
}

/// The image this phone takes, by the iOS version lockdown reports.
pub async fn kind_of(phone: &Phone) -> Kind {
    let ios = async {
        let provider = phone.provider().ok()?;
        let mut lockdown = LockdownClient::connect(&*provider).await.ok()?;
        lockdown.get_value(Some("ProductVersion"), None).await.ok()?.as_string().map(str::to_string)
    }
    .await;
    Kind::for_ios(ios.as_deref().unwrap_or(""))
}

pub fn dir(kind: Kind) -> Result<PathBuf> {
    Ok(paths::cache_dir()?.join(if kind == Kind::Cryptex { "ddi" } else { "ddi-personalized" }))
}

/// Checks one build identity's payloads against the files in `dir`.
fn check(entries: &plist::Dictionary, keys: &[&str], dir: &Path) -> Result<()> {
    for key in keys {
        let entry = entries.get(key).and_then(|e| e.as_dictionary());
        let path = entry
            .and_then(|e| e.get("Info"))
            .and_then(|i| i.as_dictionary())
            .and_then(|i| i.get("Path"))
            .and_then(|p| p.as_string())
            .filter(|p| !p.is_empty() && !p.starts_with('/') && !p.split('/').any(|s| s == ".."))
            .ok_or_else(|| Error::msg(format!("BuildManifest.plist gives no usable path for {key}")))?;
        let digest = entry.and_then(|e| e.get("Digest")).and_then(|d| d.as_data()).ok_or_else(|| Error::msg(format!("no digest for {key}")))?;
        let bytes = std::fs::read(dir.join(path)).map_err(|_| Error::msg(format!("{path} is missing")))?;
        if Sha384::digest(&bytes).as_slice() != digest {
            return Err(Error::msg(format!("{path} does not match its SHA-384 digest")));
        }
    }
    Ok(())
}

/// Checks every payload in `dir` against the manifest; returns the image's build. The cryptex
/// manifest is checked by its first identity. The personalized manifest lists the same file names
/// with different digests for different chips, so the files must match any one identity whole.
pub fn verify(dir: &Path, kind: Kind) -> Result<String> {
    let manifest: plist::Dictionary = plist::from_file(dir.join("BuildManifest.plist"))
        .map_err(|_| Error::msg("BuildManifest.plist is missing or unreadable"))?;
    let keys = kind.payload_keys();
    let identities = manifest.get("BuildIdentities").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let candidates: Vec<&plist::Dictionary> = identities
        .iter()
        .filter_map(|v| v.as_dictionary())
        .filter_map(|id| id.get("Manifest").and_then(|m| m.as_dictionary()))
        .filter(|m| keys.iter().all(|k| m.contains_key(*k)))
        .collect();
    let mut first = None;
    for entries in candidates.iter().take(if kind == Kind::Cryptex { 1 } else { usize::MAX }) {
        match check(entries, keys, dir) {
            Ok(()) => return Ok(manifest.get("ProductBuildVersion").and_then(|v| v.as_string()).unwrap_or("unknown").to_string()),
            Err(e) => first = first.or(Some(e)),
        }
    }
    Err(first.unwrap_or_else(|| Error::msg("BuildManifest.plist has no build identity for this kind of image")))
}

/// Makes sure the image is on this computer, downloading it when it is not. Returns its build.
/// A folder named by `POKI_DDI_DIR` (holding the same files) is used first when it verifies.
pub async fn ensure(reporter: &Reporter, kind: Kind) -> Result<(PathBuf, String)> {
    let dir = dir(kind)?;
    if let Ok(build) = verify(&dir, kind) {
        return Ok((dir, build));
    }
    if let Some(local) = std::env::var_os("POKI_DDI_DIR").map(PathBuf::from) {
        match verify(&local, kind) {
            Ok(build) => return Ok((local, build)),
            Err(e) => tracing::warn!(error = %e, dir = %local.display(), "POKI_DDI_DIR does not hold this image"),
        }
    }
    reporter.step("ddi", "Downloading the developer disk image");
    let partial = dir.with_extension("partial");
    let client = reqwest::Client::builder()
        .user_agent(concat!("PokiSetup/", env!("CARGO_PKG_VERSION")))
        .connect_timeout(std::time::Duration::from_secs(10))
        .timeout(std::time::Duration::from_secs(180))
        .build()?;
    let build = download_any(&client, &kind.mirrors(), kind, &partial, &dir, reporter).await?;
    Ok((dir, build))
}

/// Tries each mirror in order and keeps the first download that verifies, moved into `dir`.
async fn download_any(client: &reqwest::Client, mirrors: &[String], kind: Kind, partial: &Path, dir: &Path, reporter: &Reporter) -> Result<String> {
    let mut failures = Vec::new();
    for mirror in mirrors {
        let host = mirror.split('/').nth(2).unwrap_or("").to_string();
        match download_from(client, mirror, kind, partial, reporter).await {
            Ok(build) => {
                let _ = std::fs::remove_dir_all(dir);
                std::fs::rename(partial, dir)?;
                reporter.done("ddi", Some(format!("Image build {build}, from {host}.")));
                return Ok(build);
            }
            Err(e) => {
                let _ = std::fs::remove_dir_all(partial);
                tracing::warn!(error = %e, %host, "developer disk image download failed; trying the next mirror");
                failures.push(format!("{host}: {e}"));
            }
        }
    }
    Err(Error::msg(format!(
        "The developer disk image could not be downloaded from GitHub or its mirrors ({}). Check the network or the system proxy, then try again.",
        failures.join("; ")
    )))
}

/// Downloads every file of the image from one mirror into `partial` and verifies it.
async fn download_from(client: &reqwest::Client, mirror: &str, kind: Kind, partial: &Path, reporter: &Reporter) -> Result<String> {
    let files = kind.files();
    let _ = std::fs::remove_dir_all(partial);
    std::fs::create_dir_all(partial)?;
    for (i, name) in files.iter().enumerate() {
        reporter.part("ddi", i as f64 / files.len() as f64, Some(format!("Downloading {name}")));
        let res = client.get(format!("{mirror}/{name}")).send().await?;
        if !res.status().is_success() {
            return Err(Error::msg(format!("downloading {name} failed with HTTP {}", res.status())));
        }
        std::fs::write(partial.join(name), res.bytes().await?)?;
    }
    verify(partial, kind)
}

/// Present only while a developer disk image is mounted, whichever way it went on (the same markers
/// the launcher on the phone checks).
const MOUNTED_MARKERS: [&str; 2] = ["com.apple.instruments.dtservicehub", "com.apple.dt.testmanagerd.remote"];

/// Whether a developer disk image is mounted right now: the CoreDevice service list on iOS 17 and
/// later (a Cryptex1 cryptex is not listed by the image mounter), the image mounter before.
pub async fn mounted(phone: &Phone) -> Result<bool> {
    let by_tunnel = super::running::on_own_thread(phone, async |p: &Phone| {
        let t = super::running::tunnel(p).await.map_err(Error::device)?;
        Ok(MOUNTED_MARKERS.iter().any(|m| t.rsd.services.contains_key(*m)))
    })
    .await;
    match by_tunnel {
        Ok(true) => return Ok(true),
        Ok(false) if kind_of(phone).await == Kind::Cryptex => return Ok(false),
        Ok(false) => {}
        Err(e) => tracing::info!(error = %e, "no CoreDevice tunnel for the disk image check; asking the image mounter"),
    }
    let provider = phone.provider()?;
    let mut mounter = ImageMounter::connect(&*provider).await?;
    let images = mounter.copy_devices().await?;
    Ok(images.iter().any(|i| {
        i.as_dictionary()
            .and_then(|d| d.get("DiskImageType"))
            .and_then(|t| t.as_string())
            .is_some_and(|t| t == "Personalized")
    }))
}

/// Mounts the image from this computer (needs internet for Apple's TSS signature). Poki mounts it
/// again by itself after every restart; this is the proof that the phone accepts it.
pub async fn mount(phone: &Phone, reporter: &Reporter) -> Result<()> {
    if mounted(phone).await? {
        reporter.note("mount", "The developer disk image is already mounted.");
        return Ok(());
    }
    let kind = kind_of(phone).await;
    let (dir, _) = ensure(reporter, kind).await?;
    reporter.step("mount", "Mounting the developer disk image");
    if kind == Kind::Cryptex {
        return mount_cryptex(phone, dir, reporter).await;
    }
    let image = tokio::fs::read(dir.join("Image.dmg")).await?;
    let trust_cache = tokio::fs::read(dir.join("Image.dmg.trustcache")).await?;
    let manifest = tokio::fs::read(dir.join("BuildManifest.plist")).await?;
    // Through the CoreDevice tunnel first (iOS 17.4 and later), the way Poki's launcher mounts it on
    // the phone and the way the cryptex goes on. The tunnel is opened with the one record the USB
    // service holds. The lockdown route below used to start its session with the record Poki Setup
    // saved and then open the image mounter with the USB service's record, so it needed both to be
    // trusted. On Windows the USB service is Apple's driver, which keeps its own record (see #421).
    let tunnel = {
        let (image, trust_cache, manifest, r) = (image.clone(), trust_cache.clone(), manifest.clone(), reporter.clone());
        super::running::on_own_thread(phone, async move |p: &Phone| mount_personalized_tunnel(p, image, trust_cache, manifest, &r).await).await
    };
    match tunnel {
        Ok(()) => {
            reporter.done("mount", None);
            return Ok(());
        }
        Err(e @ Error::NeedsPerson(_)) => return Err(e),
        Err(e) => tracing::info!(error = %e, "personalized image over the CoreDevice tunnel failed; trying lockdown"),
    }
    mount_personalized_lockdown(phone, image, trust_cache, manifest, reporter).await?;
    reporter.done("mount", None);
    Ok(())
}

fn personalized_error(e: idevice::IdeviceError) -> Error {
    match e {
        idevice::IdeviceError::DeveloperModeNotEnabled => Error::NeedsPerson("Turn on Developer Mode on the iPhone first.".into()),
        other => Error::device(format!("Mounting failed: {other}. Apple's signing service must be reachable, and the phone must be unlocked.")),
    }
}

/// The image mounter behind the CoreDevice tunnel (`mobile_image_mounter.shim.remote`), with the
/// chip id from the tunnel's trusted lockdown.
async fn mount_personalized_tunnel(phone: &Phone, image: Vec<u8>, trust_cache: Vec<u8>, manifest: Vec<u8>, reporter: &Reporter) -> Result<()> {
    use idevice::RsdService;
    let mut t = super::running::tunnel(phone).await.map_err(Error::device)?;
    if !t.rsd.services.contains_key(ImageMounter::rsd_service_name().as_ref()) {
        return Err(Error::device("the CoreDevice tunnel offers no image mounter"));
    }
    let chip = {
        let mut lockdown = LockdownClient::connect_rsd(&mut t.adapter, &mut t.rsd).await?;
        lockdown.get_value(Some("UniqueChipID"), None).await?.as_unsigned_integer().ok_or_else(|| Error::device("no UniqueChipID"))?
    };
    let mut mounter = ImageMounter::connect_rsd(&mut t.adapter, &mut t.rsd).await?;
    let r = reporter.clone();
    mounter
        .mount_personalized_with_callback_rsd(&mut t.adapter, &mut t.rsd, image, trust_cache, &manifest, None, chip, move |((n, d), _)| {
            let r = r.clone();
            async move { r.part("mount", if d == 0 { 0.0 } else { n as f64 / d as f64 }, None) }
        }, ())
        .await
        .map_err(personalized_error)
}

/// Through lockdown over USB (iOS 17.0 to 17.3, or when the tunnel does not come up). The session
/// uses the record the USB service holds, the same one the image mounter connection uses, and the
/// record Poki Setup saved only when the USB service has none.
async fn mount_personalized_lockdown(phone: &Phone, image: Vec<u8>, trust_cache: Vec<u8>, manifest: Vec<u8>, reporter: &Reporter) -> Result<()> {
    let provider = phone.provider()?;
    let record = match provider.get_pairing_file().await {
        Ok(r) => r,
        Err(_) => super::pairing::saved(&phone.udid)?.ok_or_else(|| Error::device("Pair the iPhone first."))?,
    };
    let mut lockdown = LockdownClient::connect(&*provider).await?;
    lockdown.start_session(&record).await?;
    let chip = lockdown.get_value(Some("UniqueChipID"), None).await?.as_unsigned_integer().ok_or_else(|| Error::device("no UniqueChipID"))?;
    let mut mounter = ImageMounter::connect(&*provider).await?;
    let r = reporter.clone();
    mounter
        .mount_personalized_with_callback(&*provider, image, trust_cache, &manifest, None, chip, move |((n, d), _)| {
            let r = r.clone();
            async move { r.part("mount", if d == 0 { 0.0 } else { n as f64 / d as f64 }, None) }
        }, ())
        .await
        .map_err(personalized_error)
}

/// iOS 26.4 and later: the image goes on as a Cryptex1 cryptex through cryptexd, over the CoreDevice
/// tunnel. Apple's signing server personalizes it for this phone's chip and nonce, as on the phone.
async fn mount_cryptex(phone: &Phone, dir: PathBuf, reporter: &Reporter) -> Result<()> {
    reporter.part("mount", 0.2, Some("Asking Apple to sign the image for this device".into()));
    super::running::on_own_thread(phone, async move |p: &Phone| {
        let mut t = super::running::tunnel(p).await.map_err(Error::device)?;
        if !t.rsd.services.contains_key("com.apple.security.cryptexd.remote") {
            return Err(Error::NeedsPerson("The device does not offer cryptexd. Turn on Developer Mode (Settings, Privacy and Security, Developer Mode), then try again.".into()));
        }
        let assets = idevice::cryptexd::Cryptex1Assets::load(&dir).await.map_err(|e| Error::device(format!("The developer disk image on this computer is unreadable ({e}). Delete it and try again.")))?;
        idevice::cryptexd::install_ddi(&mut t.adapter, &mut t.rsd, &assets)
            .await
            .map_err(|e| Error::device(format!("Mounting failed: {e}. Apple's signing service must be reachable, and the device must be unlocked.")))?;
        Ok(())
    })
    .await?;
    reporter.done("mount", None);
    Ok(())
}

/// The Mount button: mounts the image when it is not mounted, and copies it into Poki on the phone
/// either way, because Poki needs its own copy to mount it again after every restart. Without the
/// copy Poki keeps asking for the image even while it is mounted, and on a network that cannot reach
/// GitHub it cannot download it itself.
/// Says whether the image is mounted and copied into Poki, or why it was only mounted.
pub async fn mount_and_give_poki(phone: &Phone, reporter: &Reporter) -> Result<Given> {
    mount(phone, reporter).await?;
    let target = match crate::keeper::get(&phone.udid).ok().flatten() {
        Some(rec) => Ok(Some(rec.bundle_id)),
        None => super::install::find_apps(phone, crate::POKI_BUNDLE_ID)
            .await
            .map(|apps| apps.into_iter().next().map(|a| a.bundle_id))
            .map_err(|e| e.to_string()),
    };
    give(target, |id| async move { seed_container(phone, &id, reporter).await }, reporter).await
}

/// What the Mount button did.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(tag = "outcome", content = "reason", rename_all = "snake_case")]
pub enum Given {
    /// Mounted, and Poki on the phone has its own copy.
    Copied,
    /// Mounted only: Poki is not installed on this phone.
    NotInstalled,
    /// Mounted only: the list of installed apps could not be read, so Poki was not found.
    LookupFailed(String),
}

impl Given {
    /// One line for the Debug screen and the CLI.
    pub fn message(&self) -> String {
        match self {
            Given::Copied => "The developer disk image is mounted and copied into Poki.".into(),
            Given::NotInstalled => "The developer disk image is mounted. Poki is not installed on this phone, so nothing was copied.".into(),
            Given::LookupFailed(e) => format!("The developer disk image is mounted, but it was not copied into Poki because the installed apps could not be read: {e}"),
        }
    }
}

/// Copies into Poki when it was found, whether or not the image was mounted before.
async fn give<F, Fut>(target: std::result::Result<Option<String>, String>, seed: F, reporter: &Reporter) -> Result<Given>
where
    F: FnOnce(String) -> Fut,
    Fut: std::future::Future<Output = Result<()>>,
{
    match target {
        Ok(Some(id)) => seed(id).await.map(|()| Given::Copied),
        Ok(None) => {
            reporter.note("seed", "Poki is not installed on this device, so the image was only mounted.");
            Ok(Given::NotInstalled)
        }
        Err(e) => {
            reporter.note("seed", format!("The installed apps could not be read, so the image was only mounted: {e}"));
            Ok(Given::LookupFailed(e))
        }
    }
}

/// Copies the image into Poki's container so the phone does not download it.
pub async fn seed_container(phone: &Phone, bundle_id: &str, reporter: &Reporter) -> Result<()> {
    let kind = kind_of(phone).await;
    let (dir, _) = ensure(reporter, kind).await?;
    let files = kind.files();
    reporter.step("seed", "Copying the disk image into Poki");
    if kind == Kind::Personalized {
        // A cryptex left by an older Poki, or by an iOS update and downgrade: Poki refuses a
        // personalized image that sits beside cryptex files and downloads it again.
        for name in Kind::Cryptex.files().iter().filter(|n| !Kind::Personalized.files().contains(n)) {
            let _ = super::container::remove_file(phone, bundle_id, &format!("{}/ddi/{name}", super::container::SUPPORT_DIR)).await;
        }
    }
    for (i, name) in files.iter().enumerate() {
        let bytes = std::fs::read(dir.join(name))?;
        super::container::write_file(phone, bundle_id, &format!("{}/ddi/{name}", super::container::SUPPORT_DIR), &bytes).await?;
        reporter.part("seed", (i + 1) as f64 / files.len() as f64, Some(name.to_string()));
    }
    reporter.done("seed", None);
    Ok(())
}

#[cfg(test)]
mod mirror_tests {
    use super::*;

    #[test]
    fn github_first_then_the_cdn_for_each_kind() {
        let m = Kind::Personalized.mirrors();
        assert_eq!(m[0], Kind::Personalized.mirror());
        assert!(m.len() > 1);
        assert!(m.iter().all(|u| u.ends_with("/Xcode_iOS_DDI_Personalized")));
        assert!(m[1..].iter().all(|u| u.contains("jsdelivr.net/gh/doronz88/DeveloperDiskImage@main/")));
        assert!(Kind::Cryptex.mirrors().iter().all(|u| u.ends_with("/Xcode_iOS_DDI_Cryptex")));
    }

    /// A personalized image whose manifest names its own two payloads by SHA-384.
    fn image() -> Vec<(&'static str, Vec<u8>)> {
        let (dmg, trust) = (b"disk image".to_vec(), b"trust cache".to_vec());
        let payload = |path: &str, bytes: &[u8]| {
            let mut info = plist::Dictionary::new();
            info.insert("Path".into(), path.into());
            let mut entry = plist::Dictionary::new();
            entry.insert("Info".into(), info.into());
            entry.insert("Digest".into(), plist::Value::Data(Sha384::digest(bytes).to_vec()));
            plist::Value::Dictionary(entry)
        };
        let mut entries = plist::Dictionary::new();
        entries.insert("PersonalizedDMG".into(), payload("Image.dmg", &dmg));
        entries.insert("LoadableTrustCache".into(), payload("Image.dmg.trustcache", &trust));
        let mut identity = plist::Dictionary::new();
        identity.insert("Manifest".into(), entries.into());
        let mut manifest = plist::Dictionary::new();
        manifest.insert("ProductBuildVersion".into(), "TEST1".into());
        manifest.insert("BuildIdentities".into(), plist::Value::Array(vec![identity.into()]));
        let mut xml = Vec::new();
        plist::to_writer_xml(&mut xml, &plist::Value::Dictionary(manifest)).unwrap();
        vec![("BuildManifest.plist", xml), ("Image.dmg", dmg), ("Image.dmg.trustcache", trust)]
    }

    /// Serves 503 under /primary/ and the image under /mirror/, and counts the requests.
    async fn serve() -> (String, std::sync::Arc<std::sync::atomic::AtomicUsize>) {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let primary_hits = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let hits = primary_hits.clone();
        let files = image();
        tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else { return };
                let mut buf = vec![0u8; 4096];
                let n = socket.read(&mut buf).await.unwrap_or(0);
                let request = String::from_utf8_lossy(&buf[..n]).to_string();
                let path = request.split_whitespace().nth(1).unwrap_or("").to_string();
                let found = path.strip_prefix("/mirror/x/").and_then(|name| files.iter().find(|(n, _)| *n == name));
                if path.starts_with("/primary/") {
                    hits.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                }
                let (status, body): (&str, Vec<u8>) = match found {
                    Some((_, bytes)) => ("200 OK", bytes.clone()),
                    None if path.starts_with("/primary/") => ("503 Service Unavailable", vec![]),
                    None => ("404 Not Found", vec![]),
                };
                let head = format!("HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len());
                let _ = socket.write_all(head.as_bytes()).await;
                let _ = socket.write_all(&body).await;
                let _ = socket.shutdown().await;
            }
        });
        (base, primary_hits)
    }

    #[tokio::test]
    async fn a_failing_primary_falls_back_to_the_mirror() {
        let (base, primary_hits) = serve().await;
        let root = std::env::temp_dir().join(format!("poki-ddi-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let (partial, dir) = (root.join("ddi.partial"), root.join("ddi"));
        let client = reqwest::Client::builder().no_proxy().build().unwrap();
        let mirrors = vec![format!("{base}/primary/x"), format!("{base}/mirror/x")];
        let build = download_any(&client, &mirrors, Kind::Personalized, &partial, &dir, &Reporter::silent()).await.unwrap();
        assert_eq!(build, "TEST1");
        assert!(primary_hits.load(std::sync::atomic::Ordering::SeqCst) >= 1, "the primary was tried first");
        assert_eq!(verify(&dir, Kind::Personalized).unwrap(), "TEST1");
        assert!(!partial.exists());
        // Every mirror failing is an error that names each host.
        let none = vec![format!("{base}/primary/x"), format!("{base}/missing/x")];
        let err = download_any(&client, &none, Kind::Personalized, &partial, &root.join("other"), &Reporter::silent()).await.unwrap_err();
        assert!(err.to_string().contains("127.0.0.1"), "{err}");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[tokio::test]
    async fn the_image_is_copied_into_poki_whether_or_not_it_was_mounted_before() {
        // mount() returns early when the image is already mounted; the copy depends only on Poki
        // being found, so an already mounted image is still written into Poki's container.
        let copied = std::sync::Mutex::new(vec![]);
        let seed = |id: String| {
            copied.lock().unwrap().push(id);
            async { Ok(()) }
        };
        let given = give(Ok(Some("app.poki.ios".into())), seed, &Reporter::silent()).await.unwrap();
        assert_eq!(given, Given::Copied);
        assert_eq!(*copied.lock().unwrap(), ["app.poki.ios"]);
        // Not installed and a failed lookup are told apart from a copy, and nothing is copied.
        let never = |_: String| async { panic!("nothing to copy into") };
        assert_eq!(give(Ok(None), never, &Reporter::silent()).await.unwrap(), Given::NotInstalled);
        let failed = give(Err("installation_proxy refused".into()), never, &Reporter::silent()).await.unwrap();
        assert_eq!(failed, Given::LookupFailed("installation_proxy refused".into()));
        assert!(failed.message().contains("not copied"));
        // A copy that fails is an error, not "copied".
        let broken = |_: String| async { Err(Error::msg("afc write failed")) };
        assert!(give(Ok(Some("app.poki.ios".into())), broken, &Reporter::silent()).await.is_err());
    }
}
