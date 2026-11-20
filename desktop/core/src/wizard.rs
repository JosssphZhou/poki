//! USB setup wizard state machine.
use crate::{Error, Progress, Reporter, Result, device, keeper};
use idevice::{IdeviceError, afc::{AfcClient, errors::AfcError, opcode::AfcFopenMode}};
use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::sync::Mutex;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WizardState {
    DeviceDisconnected,
    ChooseDevice,
    DeviceUntrusted,
    DeveloperModeOff,
    AccountSignedOut,
    ReadyToInstall,
    SigningFailed,
    InstallFailed,
    DdiUnmounted,
    AppUntrusted,
    PokiNotStarted,
    PokiUpdateRequired,
    AutomationPending,
    Completed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FailureStage {
    Sign,
    Install,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WizardFailure {
    pub kind: String,
    pub stage: FailureStage,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UsbPhoneView {
    pub udid: String,
    pub name: String,
    pub product_type: String,
    pub ios: String,
    pub paired: bool,
    pub developer_mode: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InstalledPokiView {
    pub bundle_id: String,
    pub version: String,
    pub build: String,
    pub profile_validated: Option<bool>,
    pub team_is_free: bool,
    pub expires_at: Option<i64>,
    pub expired: bool,
}

#[derive(Debug, Clone, Default)]
pub struct WizardProbe {
    pub phone: Option<UsbPhoneView>,
    pub account_signed_in: bool,
    pub installed: Option<InstalledPokiView>,
    pub ddi_mounted: bool,
    pub poki_started: bool,
    pub automation_ready: bool,
    pub poki_update_required: bool,
    pub failure: Option<WizardFailure>,
}

pub fn evaluate(probe: &WizardProbe) -> WizardState {
    let Some(phone) = &probe.phone else { return WizardState::DeviceDisconnected };
    if !phone.paired { return WizardState::DeviceUntrusted; }
    if phone.developer_mode == Some(false) { return WizardState::DeveloperModeOff; }
    if let Some(app) = probe.installed.as_ref().filter(|app| !app.expired) {
        if !probe.ddi_mounted { return WizardState::DdiUnmounted; }
        if probe.poki_update_required { return WizardState::PokiUpdateRequired; }
        if probe.poki_started {
            return if probe.automation_ready { WizardState::Completed } else { WizardState::AutomationPending };
        }
        if app.profile_validated == Some(false) || (app.profile_validated.is_none() && app.team_is_free) {
            return WizardState::AppUntrusted;
        }
        return WizardState::PokiNotStarted;
    }
    if !probe.account_signed_in { return WizardState::AccountSignedOut; }
    match probe.failure.as_ref().map(|failure| failure.stage) {
        Some(FailureStage::Sign) => WizardState::SigningFailed,
        Some(FailureStage::Install) => WizardState::InstallFailed,
        _ => WizardState::ReadyToInstall,
    }
}

#[derive(Debug, Serialize)]
pub struct Snapshot {
    pub state: WizardState,
    pub usb_phones: Vec<UsbPhoneView>,
    pub selected_udid: Option<String>,
    pub installed: Option<InstalledPokiView>,
    pub failure: Option<WizardFailure>,
}

#[derive(Default)]
pub struct Attempts {
    failure: Mutex<Option<(String, WizardFailure)>>,
    automation: Mutex<Option<AutomationCheck>>,
}

impl Attempts {
    pub async fn remember(&self, udid: String, stage: FailureStage, kind: &str, message: &str) {
        *self.failure.lock().await = Some((udid, WizardFailure { stage, kind: kind.to_owned(), message: message.to_owned() }));
    }

    pub async fn clear(&self) { *self.failure.lock().await = None; }

    pub async fn inspect(&self, udid: Option<&str>, account_signed_in: bool) -> Result<Snapshot> {
        let failure = self.failure.lock().await.clone();
        let mut automation = self.automation.lock().await;
        inspect(udid, account_signed_in, failure, &mut automation).await
    }
}

pub fn install_reporter(reporter: Reporter) -> (Reporter, impl Fn() -> FailureStage) {
    let installing = Arc::new(AtomicBool::new(false));
    let flag = installing.clone();
    let reporter = Reporter::new(move |progress| {
        if let Progress::Step { id, .. } = &progress
            && matches!(id.as_str(), "install" | "profiles" | "pairing_file" | "ddi" | "mount")
        {
            flag.store(true, Ordering::Relaxed);
        }
        reporter.emit(progress);
    });
    (reporter, move || if installing.load(Ordering::Relaxed) { FailureStage::Install } else { FailureStage::Sign })
}

pub async fn usb_phone(udid: &str) -> Result<device::Phone> {
    device::Phone::list().await?.into_iter().find(|phone| phone.is_usb() && phone.udid == udid)
        .ok_or_else(|| Error::device("Connect that iPhone with a USB cable and unlock it."))
}

#[derive(Deserialize)]
struct Hello {
    schema: String,
    version: String,
    build: String,
    at: String,
    #[serde(default)]
    ui_automation_ready: bool,
    usb_setup_challenge: Option<String>,
}

impl Hello {
    fn matches(&self, app: &InstalledPokiView, signed_at: Option<i64>) -> bool {
        self.schema == "poki.hello/1" && self.version == app.version && self.build == app.build
            && signed_at.is_none_or(|signed| {
                use time::{OffsetDateTime, format_description::well_known::Rfc3339};
                OffsetDateTime::parse(&self.at, &Rfc3339).is_ok_and(|at| at.unix_timestamp() >= signed)
            })
    }

    fn apply(&self, probe: &mut WizardProbe, challenge: Uuid) {
        probe.poki_update_required = self.usb_setup_challenge.is_none();
        probe.poki_started = self.usb_setup_challenge.as_deref()
            .and_then(|value| Uuid::parse_str(value).ok()) == Some(challenge);
        probe.automation_ready = probe.poki_started && self.ui_automation_ready;
    }
}

struct AutomationCheck {
    udid: String,
    mux_id: Option<u32>,
    bundle_id: String,
    challenge: Uuid,
    afc: AfcClient,
}

impl AutomationCheck {
    async fn connect(phone: &device::Phone, bundle_id: &str) -> Result<Self> {
        let challenge = Uuid::new_v4();
        let mut afc = device::container::afc_for(phone, bundle_id).await?;
        device::container::write_setup_challenge(&mut afc, challenge).await?;
        Ok(Self { udid: phone.udid.clone(), mux_id: phone.mux_id, bundle_id: bundle_id.to_owned(), challenge, afc })
    }

    fn matches(&self, phone: &device::Phone, bundle_id: &str) -> bool {
        self.udid == phone.udid && self.mux_id == phone.mux_id && self.bundle_id == bundle_id
    }

    async fn read(&mut self) -> Result<Option<Hello>> {
        let path = "Documents/PokiSetup/poki-hello.json";
        let mut file = match self.afc.open(path, AfcFopenMode::RdOnly).await {
            Ok(file) => file,
            Err(IdeviceError::Afc(AfcError::ObjectNotFound)) => return Ok(None),
            Err(error) => return Err(error.into()),
        };
        let data = file.read_entire().await?;
        file.close().await?;
        Ok(serde_json::from_slice(&data).ok())
    }
}

/// Read the device's state anew. A saved signing record is metadata for an app that still exists.
async fn inspect(
    udid: Option<&str>,
    account_signed_in: bool,
    failure: Option<(String, WizardFailure)>,
    automation: &mut Option<AutomationCheck>,
) -> Result<Snapshot> {
    // A USB connection cannot survive a reboot, even when usbmuxd reuses the attachment ID.
    let mut check = automation.take();
    let phones: Vec<_> = device::Phone::list().await?.into_iter().filter(device::Phone::is_usb).collect();
    let selected = match (udid, phones.as_slice()) {
        (Some(udid), _) => phones.iter().find(|phone| phone.udid == udid),
        (None, [phone]) => Some(phone),
        _ => None,
    };
    let failure = failure.filter(|(udid, _)| selected.is_some_and(|p| p.udid == *udid)).map(|(_, failure)| failure);
    let mut probe = WizardProbe { account_signed_in, failure, ..Default::default() };
    let mut usb_phones = Vec::with_capacity(phones.len());
    let names = futures_util::future::join_all(phones.iter().map(|phone| async {
        if selected.is_some_and(|selected| selected.udid == phone.udid) {
            return String::new();
        }
        tokio::time::timeout(Duration::from_secs(3), device::info::name(phone))
            .await.ok().and_then(Result::ok).unwrap_or_default()
    })).await;
    for (phone, name) in phones.iter().zip(names) {
        let is_selected = selected.is_some_and(|selected| selected.udid == phone.udid);
        let facts = if is_selected {
            Some(tokio::time::timeout(Duration::from_secs(3), device::info::read_for_wizard(phone))
                .await.map_err(|_| Error::device("Unlock the iPhone to check its USB connection."))??)
        } else {
            None
        };
        let view = UsbPhoneView {
            udid: phone.udid.clone(),
            name: facts.as_ref().map(|f| f.name.clone()).unwrap_or(name),
            product_type: facts.as_ref().map(|f| f.product_type.clone()).unwrap_or_default(),
            ios: facts.as_ref().map(|f| f.ios.clone()).unwrap_or_default(),
            paired: facts.as_ref().is_some_and(|f| f.paired_with_this_computer),
            developer_mode: facts.and_then(|f| f.developer_mode),
        };
        if is_selected {
            probe.phone = Some(view.clone());
        }
        usb_phones.push(view);
    }
    if let Some(phone) = selected.filter(|_| probe.phone.as_ref().is_some_and(|p| p.paired && p.developer_mode != Some(false))) {
        let record = keeper::get(&phone.udid)?;
        let apps = tokio::time::timeout(Duration::from_secs(8), device::install::find_apps(phone, crate::POKI_BUNDLE_ID))
            .await.map_err(|_| Error::device("Unlock the iPhone to check whether Poki is installed."))??;
        let app = record.as_ref().and_then(|r| apps.iter().find(|app| app.bundle_id == r.bundle_id)).or_else(|| apps.first());
        if let Some(app) = app {
            let record = record.as_ref().filter(|r| r.bundle_id == app.bundle_id && r.build == app.build);
            let installed = InstalledPokiView {
                bundle_id: app.bundle_id.clone(),
                version: app.version.clone(),
                build: app.build.clone(),
                profile_validated: app.profile_validated,
                team_is_free: record.is_none_or(|r| r.team_is_free),
                expires_at: record.map(|r| r.profile_expires_at),
                expired: record.is_some_and(|r| r.is_expired()),
            };
            if !installed.expired {
                probe.ddi_mounted = device::ddi::mounted(phone).await?;
                if probe.ddi_mounted {
                    let result = tokio::time::timeout(Duration::from_secs(4), async {
                        let mut check = match check.take() {
                            Some(existing) if existing.matches(phone, &app.bundle_id) => existing,
                            _ => AutomationCheck::connect(phone, &app.bundle_id).await?,
                        };
                        let hello = check.read().await?;
                        Ok::<_, Error>((check, hello))
                    }).await;
                    if let Ok(Ok((check, hello))) = result {
                        if let Some(hello) = hello.filter(|hello| hello.matches(&installed, record.map(|r| r.signed_at))) {
                            hello.apply(&mut probe, check.challenge);
                        }
                        *automation = Some(check);
                    }
                }
            }
            probe.installed = Some(installed);
        }
    }
    Ok(Snapshot {
        state: if selected.is_none() && !phones.is_empty() { WizardState::ChooseDevice } else { evaluate(&probe) },
        usb_phones,
        selected_udid: selected.map(|phone| phone.udid.clone()),
        installed: probe.installed,
        failure: probe.failure,
    })
}

pub async fn pair(udid: &str, reporter: &Reporter) -> Result<()> {
    device::pairing::pair(&usb_phone(udid).await?, reporter, Duration::from_secs(90)).await.map(|_| ())
}

pub async fn reveal_developer_mode(udid: &str) -> Result<()> {
    device::devmode::reveal(&usb_phone(udid).await?).await
}

pub async fn mount(udid: &str, reporter: &Reporter) -> Result<()> {
    let phone = usb_phone(udid).await?;
    device::pairing::pair(&phone, reporter, Duration::from_secs(90)).await?;
    device::ddi::mount(&phone, reporter).await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base_phone(paired: bool, developer_mode: Option<bool>) -> UsbPhoneView {
        UsbPhoneView {
            udid: "00008130-TEST".into(),
            name: "iPhone".into(),
            product_type: "iPhone17,1".into(),
            ios: "27.0".into(),
            paired,
            developer_mode,
        }
    }

    fn installed(profile_validated: Option<bool>, expired: bool) -> InstalledPokiView {
        InstalledPokiView {
            bundle_id: "nz.zheha.poki.TEAM1".into(),
            version: "0.4.4".into(),
            build: "1683".into(),
            profile_validated,
            team_is_free: true,
            expires_at: Some(1_900_000_000),
            expired,
        }
    }

    #[test]
    fn a_remounted_image_requires_a_fresh_automation_confirmation() {
        let current = "eeb029a9-6b71-492f-abef-44bfe8c73ea8".parse().unwrap();
        let hello = |challenge, ready| serde_json::from_value::<Hello>(serde_json::json!({
            "schema": "poki.hello/1",
            "version": "0.4.4",
            "build": "1683",
            "at": "2026-11-20T04:00:00Z",
            "usb_setup_challenge": challenge,
            "ui_automation_ready": ready,
        })).unwrap();
        let mut remounted = WizardProbe {
            phone: Some(base_phone(true, Some(true))),
            installed: Some(installed(Some(true), false)),
            ddi_mounted: true,
            ..Default::default()
        };

        hello("13a30613-30e6-485b-9b69-7b158e75aa47", true).apply(&mut remounted, current);
        assert_eq!(evaluate(&remounted), WizardState::PokiNotStarted);
        hello("eeb029a9-6b71-492f-abef-44bfe8c73ea8", false).apply(&mut remounted, current);
        assert_eq!(evaluate(&remounted), WizardState::AutomationPending);
        hello("eeb029a9-6b71-492f-abef-44bfe8c73ea8", true).apply(&mut remounted, current);
        assert_eq!(evaluate(&remounted), WizardState::Completed);

        let legacy = serde_json::from_value::<Hello>(serde_json::json!({
            "schema": "poki.hello/1",
            "version": "0.4.4",
            "build": "1683",
            "at": "2026-11-20T04:00:00Z",
        })).unwrap();
        legacy.apply(&mut remounted, current);
        assert_eq!(evaluate(&remounted), WizardState::PokiUpdateRequired);
    }

    #[test]
    fn wizard_state_machine_evaluates_all_states_and_recovers_after_unplug_and_reboot() {
        assert_eq!(evaluate(&WizardProbe::default()), WizardState::DeviceDisconnected);

        let untrusted = WizardProbe { phone: Some(base_phone(false, None)), ..Default::default() };
        assert_eq!(evaluate(&untrusted), WizardState::DeviceUntrusted);

        let dev_off = WizardProbe { phone: Some(base_phone(true, Some(false))), ..Default::default() };
        assert_eq!(evaluate(&dev_off), WizardState::DeveloperModeOff);

        let signed_out = WizardProbe {
            phone: Some(base_phone(true, Some(true))),
            account_signed_in: false,
            ..Default::default()
        };
        assert_eq!(evaluate(&signed_out), WizardState::AccountSignedOut);

        let ready = WizardProbe {
            phone: Some(base_phone(true, Some(true))),
            account_signed_in: true,
            ..Default::default()
        };
        assert_eq!(evaluate(&ready), WizardState::ReadyToInstall);

        let sign_err = WizardProbe {
            failure: Some(WizardFailure {
                kind: "not_enough_app_ids".into(),
                stage: FailureStage::Sign,
                message: "Not enough available app IDs".into(),
            }),
            ..ready.clone()
        };
        assert_eq!(evaluate(&sign_err), WizardState::SigningFailed);

        let install_err = WizardProbe {
            failure: Some(WizardFailure {
                kind: "device".into(),
                stage: FailureStage::Install,
                message: "Install failed".into(),
            }),
            ..ready.clone()
        };
        assert_eq!(evaluate(&install_err), WizardState::InstallFailed);

        // Reboot recovery: Poki is already installed and non-expired, account is even signed out,
        // but reboot cleared /System/Developer so DDI is unmounted -> must go to DdiUnmounted, NOT AccountSignedOut!
        let after_reboot = WizardProbe {
            phone: Some(base_phone(true, Some(true))),
            account_signed_in: false,
            installed: Some(installed(Some(true), false)),
            ddi_mounted: false,
            poki_started: true,
            automation_ready: true,
            poki_update_required: false,
            failure: None,
        };
        assert_eq!(evaluate(&after_reboot), WizardState::DdiUnmounted);

        let app_untrusted = WizardProbe {
            phone: Some(base_phone(true, Some(true))),
            account_signed_in: true,
            installed: Some(installed(Some(false), false)),
            ddi_mounted: true,
            poki_started: false,
            ..Default::default()
        };
        assert_eq!(evaluate(&app_untrusted), WizardState::AppUntrusted);

        let not_started = WizardProbe {
            installed: Some(installed(Some(true), false)),
            ..app_untrusted.clone()
        };
        assert_eq!(evaluate(&not_started), WizardState::PokiNotStarted);

        let opened = WizardProbe { poki_started: true, ..not_started };
        assert_eq!(evaluate(&opened), WizardState::AutomationPending);
        let done = WizardProbe { automation_ready: true, ..opened };
        assert_eq!(evaluate(&done), WizardState::Completed);
    }
}
