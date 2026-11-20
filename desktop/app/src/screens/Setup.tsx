import { useEffect, useRef, useState } from "react";
import { api, failureKind, failureText, installClosingPoki, onProgress, type USBSetupSnapshot, type USBSetupStep } from "../api";
import { t } from "../i18n";
import { Capsule, Card, ErrorBox, INSTALL_WEIGHTS, JobBar, useSteps } from "../ui";
import Account from "./Account";

const STEPS = [
  { id: "phone", title: "Phone" }, { id: "pair", title: "Pairing" }, { id: "devmode", title: "Developer Mode" },
  { id: "account", title: "Account" }, { id: "release", title: "Release" }, { id: "sign", title: "Signing" },
  { id: "profiles", title: "Profiles" }, { id: "install", title: "Install" }, { id: "pairing_file", title: "Pairing file" },
  { id: "seed", title: "Developer disk image" }, { id: "mount", title: "Mounting the developer disk image" },
];

const COPY: Record<USBSetupStep, [string, string]> = {
  device_disconnected: ["Connect your iPhone or iPad", "Use a USB data cable and unlock the device."],
  choose_device: ["Choose a device", "Select the iPhone or iPad you want to set up. You can also unplug the other devices."],
  device_untrusted: ["Trust This Computer", "On the unlocked iPhone, tap Trust and enter its passcode."],
  developer_mode_off: ["Turn on Developer Mode", "Developer Mode lets iOS run Poki. On your iPhone, open Settings › Privacy & Security › Developer Mode. Turn it on and restart. After the restart, unlock the iPhone, tap Turn On and enter its passcode."],
  account_signed_out: ["Sign in with your Apple Account", "A free Apple Account can sign Poki for this device."],
  ready_to_install: ["Ready to install", "Keep the iPhone connected and unlocked while Poki Setup signs and installs Poki."],
  signing_failed: ["Poki could not be signed", "Check your Apple Account and try again."],
  install_failed: ["Poki could not be installed", "Reconnect and unlock the iPhone, then try again."],
  ddi_unmounted: ["Restore the developer disk image", "Keep the iPhone connected and unlocked. Poki Setup can restore the image without reinstalling Poki."],
  app_untrusted: ["Trust the app developer", "On your iPhone, open Settings › General › VPN & Device Management. Select the developer for your Apple Account and tap Trust. Follow any restart prompt, then open Poki."],
  poki_not_started: ["Open Poki on your iPhone", "Tap Poki on the iPhone Home Screen."],
  poki_update_required: ["Update Poki to finish setup", "Keep Poki installed to preserve its data. Update it with the Apple Account and tool you used to install it, then open it again."],
  automation_pending: ["Enable UI Automation", "On your iPhone, open Settings › Developer and turn on Enable UI Automation. Return to Poki, start automation and enter the iPhone passcode when iOS asks."],
  completed: ["Poki is ready", "You can unplug the USB cable and use Poki on your iPhone."],
};

const ACTIONS = {
  device_untrusted: { run: api.wizardPair, label: "Request Trust Again" },
  developer_mode_off: { run: api.wizardReveal, label: "Show Developer Mode in Settings" },
  ddi_unmounted: { run: api.wizardMount, label: "Restore the developer disk image" },
};

type ActionStep = keyof typeof ACTIONS;
function hasAction(step: USBSetupStep): step is ActionStep { return step in ACTIONS; }

export default function Setup() {
  const [snapshot, setSnapshot] = useState<USBSetupSnapshot | null>(null);
  const [probeError, setProbeError] = useState<{ kind: string; text: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [running, setRunning] = useState(false);
  const [working, setWorking] = useState(false);
  const [certQuestion, setCertQuestion] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const requestedSelection = useRef<string | null>(null);
  const probing = useRef(false);
  const automatic = useRef(new Set<string>());
  const { steps, apply, fail, reset } = useSteps(STEPS);

  useEffect(() => {
    const un = onProgress("install", apply);
    return () => { un.then((f) => f()); };
  }, []);

  const refresh = async (active: () => boolean) => {
    if (running || probing.current) return;
    probing.current = true;
    try {
      const next = await api.wizardState(selected);
      if (!active() || requestedSelection.current !== selected) return;
      setProbeError(null);
      setSnapshot(next);
    } catch (e) {
      if (active() && requestedSelection.current === selected) setProbeError({ kind: failureKind(e), text: failureText(e) });
    } finally { probing.current = false; }
  };

  useEffect(() => {
    let active = true;
    void refresh(() => active);
    const timer = setInterval(() => { void refresh(() => active); }, 2000);
    return () => { active = false; clearInterval(timer); };
  }, [running, selected]);

  const act = async (action: ActionStep, udid: string) => {
    setWorking(true); setError(null);
    try { await ACTIONS[action].run(udid); } catch (e) { setError(failureText(e)); }
    finally { setWorking(false); }
  };

  const udid = snapshot?.selected_udid;
  const state = snapshot?.state;
  useEffect(() => {
    setError(null);
    if (!udid) { automatic.current.clear(); return; }
    if (!state || !hasAction(state) || working || probeError) return;
    const key = udid + state;
    if (automatic.current.has(key)) return;
    automatic.current.add(key);
    void act(state, udid);
  }, [state, udid]);

  const start = async () => {
    if (!snapshot || !udid || running) return;
    setRunning(true); setError(null); setCertQuestion(false); reset();
    try {
      const name = snapshot.usb_phones.find((phone) => phone.udid === udid)?.name || t("Device");
      await installClosingPoki(udid, name, false, null, null, true);
    } catch (e) {
      const text = failureText(e);
      fail(text); setError(text);
      setCertQuestion(failureKind(e) === "certificate_limit");
    } finally { setRunning(false); }
  };

  return (
    <>
      <div className="hero" style={{ marginBottom: 24 }}>
        <img className="bear" src="/icon.png" alt="" />
        <div><h1>{t("Set up Poki on this device")}</h1></div>
      </div>
      <Card>
        {probeError ? (
          probeError.kind === "usbmuxd" ? <DeviceServiceCard text={probeError.text} /> : <ErrorBox error={probeError.text} />
        ) : snapshot ? (
          <>
            {(snapshot.usb_phones.length > 1 || state === "choose_device") && (
              <label className="row">
                {t("Device")}
                <select value={udid ?? ""} disabled={running || working || certQuestion} onChange={(e) => {
                  requestedSelection.current = e.target.value;
                  setSnapshot(null);
                  setSelected(e.target.value);
                }}>
                  <option value="" disabled>{t("Choose a device")}</option>
                  {snapshot.usb_phones.map((phone) => <option value={phone.udid} key={phone.udid}>{phone.name || t("Device")} · {phone.udid.slice(-6)}</option>)}
                </select>
              </label>
            )}
            <h2>{t(COPY[snapshot.state][0])}</h2>
            <p className="muted">{t(COPY[snapshot.state][1])}</p>
            {(state === "signing_failed" || state === "install_failed") && <ErrorBox error={snapshot.failure?.message ?? null} />}
            {udid && state && hasAction(state) && (
              <Capsule disabled={working} onClick={() => act(state, udid)}>
                {t(working ? "Working…" : ACTIONS[state].label)}
              </Capsule>
            )}
            {(state === "ready_to_install" || state === "signing_failed" || state === "install_failed" || state === "completed") && (
              <Capsule onClick={start} disabled={running || certQuestion}>
                {t(running ? "Setting up…" : state === "completed" ? "Reinstall" : state === "ready_to_install" ? "Install Poki" : "Try Again")}
              </Capsule>
            )}
          </>
        ) : <p className="muted">{t("Looking for a device…")}</p>}
        <ErrorBox error={error} />
        {certQuestion && (
          <div className="row">
            <Capsule kind="danger" onClick={async () => {
              try { await api.approveCertificateReplacement(); await start(); } catch (e) { setError(failureText(e)); }
            }}>{t("Replace Certificate")}</Capsule>
            <Capsule kind="ghost" onClick={() => setCertQuestion(false)}>{t("Cancel")}</Capsule>
          </div>
        )}
      </Card>
      {state === "account_signed_out" && !probeError && <Account info={null} embedded />}
      {running && <Card><JobBar steps={steps} running={running} weights={INSTALL_WEIGHTS} doneTitle="Poki is installed" /></Card>}
    </>
  );
}

const isWindows = typeof navigator !== "undefined" && /Windows/i.test(navigator.userAgent);

async function openLink(url: string) {
  try {
    const { openUrl } = await import("@tauri-apps/plugin-opener");
    await openUrl(url);
  } catch {
    window.open(url, "_blank");
  }
}

/** The computer has no iPhone service: say what to install, with links, instead of an empty list. */
function DeviceServiceCard({ text }: { text: string }) {
  if (!isWindows) return <div className="note">{text}</div>;
  return (
    <div className="note">
      <strong>{t("Install Apple Devices to connect the iPhone or iPad")}</strong>
      <p className="small" style={{ margin: "6px 0 10px" }}>{t("Windows needs Apple's device driver to talk to an iPhone or iPad over the cable. It comes with Apple Devices from the Microsoft Store, or with iTunes from apple.com. Install one, open it once, then plug the device in again. Poki Setup checks again by itself.")}</p>
      <div className="row" style={{ gap: 8 }}>
        <Capsule onClick={() => openLink("ms-windows-store://pdp/?productid=9NP83LWLPZ9K")}>{t("Get Apple Devices")}</Capsule>
        <button className="link" onClick={() => openLink("https://www.apple.com/itunes/")}>{t("Download iTunes")}</button>
      </div>
    </div>
  );
}
