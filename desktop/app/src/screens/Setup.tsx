import { useEffect, useState } from "react";
import { api, failureKind, failureText, installClosingPoki, onProgress, type Account, type Handoff, type PhoneRow } from "../api";
import { progressLine, t } from "../i18n";
import { Capsule, Card, ErrorBox, INSTALL_WEIGHTS, JobBar, Pill, Qr, useInterval, useSteps } from "../ui";

const STEPS = [
  { id: "phone", title: "Phone" }, { id: "pair", title: "Pairing" }, { id: "devmode", title: "Developer Mode" },
  { id: "account", title: "Account" }, { id: "release", title: "Release" }, { id: "sign", title: "Signing" },
  { id: "install", title: "Install" }, { id: "pairing_file", title: "Pairing file" },
];

export default function Setup({ goAccount }: { goAccount: () => void }) {
  const [rows, setRows] = useState<PhoneRow[] | null>(null);
  const [listError, setListError] = useState<{ kind: string; text: string } | null>(null);
  const [account, setAccount] = useState<Account | null>(null);
  const [accountError, setAccountError] = useState<string | null>(null);
  const [running, setRunning] = useState(false);
  // Set when the Apple Account is at its certificate limit: the person decides whether to replace it.
  const [certQuestion, setCertQuestion] = useState<string | null>(null);
  const [result, setResult] = useState<{ notes: string[]; handoff: Handoff | null; name: string; version: string } | null>(null);
  const { steps, apply, fail, reset } = useSteps(STEPS);
  const [chosen, setChosen] = useState<string | null>(null);

  useInterval(() => {
    if (running) return;
    api.phones().then((r) => { setRows(r); setListError(null); }).catch((e) => { setRows([]); setListError({ kind: failureKind(e), text: failureText(e) }); });
    api.account().then((a) => { setAccount(a); setAccountError(null); }).catch((e) => { setAccount(null); setAccountError(failureText(e)); });
  }, 3000, [running]);

  useEffect(() => {
    const un = onProgress("install", apply);
    return () => { un.then((f) => f()); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const phone = rows?.find((r) => r.phone.udid === chosen) ?? rows?.find((r) => r.phone.link.kind === "usb") ?? rows?.[0] ?? null;

  const start = async (replaceCertificate = false) => {
    if (!phone) return;
    setRunning(true); setResult(null); setCertQuestion(null); reset();
    try {
      if (replaceCertificate) await api.approveCertificateReplacement();
      const r = await installClosingPoki(phone.phone.udid, phone.facts?.name ?? t("Device"), false, null, null, reset);
      setResult({ notes: r.notes, handoff: r.handoff, name: r.record.phone_name, version: r.record.version });
    } catch (e) {
      const kind = failureKind(e);
      if (kind === "certificate_limit") {
        reset();
        setCertQuestion(failureText(e));
      } else if (kind === "cancelled") {
        reset();
      } else if (kind === "needs_code") {
        const pending = await api.account().catch(() => null);
        if (pending?.pending_factor != null) {
          reset();
          setAccount(pending);
        } else fail(failureText(e));
      } else {
        fail(failureText(e));
      }
    } finally {
      setRunning(false);
    }
  };

  return (
    <>
      <div className="hero" style={{ marginBottom: 24 }}>
        <img className="bear" src="/icon.png" alt="" />
        <div>
          <h1>{t("Set up Poki on this device")}</h1>
          <p className="page-sub" style={{ margin: 0 }}>{t("Poki requires iOS or iPadOS 18 or later.")}</p>
        </div>
      </div>

      <Card>
        {listError && listError.kind === "usbmuxd" && <DeviceServiceCard text={listError.text} />}
        {listError && listError.kind !== "usbmuxd" && <div className="note">{listError.text}</div>}
        {!phone && !listError && <div className="row"><span className="muted">{rows === null ? t("Looking for a device…") : t("Use a cable, unlock the device and tap Trust when it asks.")}</span></div>}
        {rows && rows.length > 1 && (
          <div className="seg" style={{ marginBottom: 12 }}>
            {rows.map((r) => <button key={r.phone.udid} className={phone?.phone.udid === r.phone.udid ? "on" : ""} onClick={() => setChosen(r.phone.udid)}>{r.facts?.name ?? r.phone.udid.slice(0, 8)}</button>)}
          </div>
        )}
        {phone && (
          <div className="row between">
            <div className="grow">
              <h2 style={{ margin: 0 }}>{phone.facts?.name ?? t("Device")}</h2>
              <div className="muted small">
                {phone.facts ? `${phone.facts.product_type} · iOS ${phone.facts.ios}` : phone.error && progressLine(phone.error)}
                {phone.record && <> · {t("Last installed by this computer")} {phone.record.version}</>}
              </div>
            </div>
            {phone.facts && <Pill tone={phone.facts.paired_with_this_computer ? "ok" : "warn"}>{t(phone.facts.paired_with_this_computer ? "paired" : "not paired")}</Pill>}
            {phone.facts && <Pill tone={phone.facts.developer_mode == null ? "" : phone.facts.developer_mode ? "ok" : "warn"}>{t("Developer Mode")} {t(phone.facts.developer_mode == null ? "checked during setup" : phone.facts.developer_mode ? "on" : "off")}</Pill>}
          </div>
        )}
        <div className="hair" />
        {accountError ? <ErrorBox error={accountError} /> : account && (!account.signed_in || account.pending_factor != null) ? (
          <div className="row between">
            <span>{t(account.pending_factor != null ? "Finish verifying your Apple Account to continue." : "Sign in with your Apple Account first.")}</span>
            <Capsule onClick={goAccount}>{t(account.pending_factor != null ? "Enter the code" : "Sign in")}</Capsule>
          </div>
        ) : (
          <div className="row between">
            <span className="muted small grow">{account?.name ?? account?.apple_id ?? ""}{account?.team_id ? ` · ${t("Team")} ${account.team_id}` : ""}</span>
            <Capsule big={false} onClick={() => start()} disabled={!phone || running || !account?.signed_in}>{running ? t("Setting up…") : t("Set up Poki")}</Capsule>
          </div>
        )}
      </Card>

      {(running || result != null || steps.some((s) => s.state === "failed")) && (
        <Card>
          <JobBar steps={steps} running={running} weights={INSTALL_WEIGHTS} doneTitle="Poki is installed" detailsOnly={result != null} />
        </Card>
      )}
      {certQuestion && (
        <Card>
          <h2>{t("Replace the Certificate?")}</h2>
          <p>{certQuestion}</p>
          <div className="row">
            <Capsule kind="danger" onClick={() => start(true)}>{t("Replace Certificate")}</Capsule>
            <Capsule kind="ghost" onClick={() => setCertQuestion(null)}>{t("Cancel")}</Capsule>
          </div>
        </Card>
      )}

      {result && (
        <Card white>
          <h2>{t("Poki is installed")}</h2>
          <p style={{ margin: 0 }}>Poki {result.version} · {result.name}</p>
          <p>{t("Open Poki on your device. If it says the developer is untrusted, go to Settings › General › VPN & Device Management and trust your Apple Account.")}</p>
          {result.notes.map((n, i) => <p key={i} className="muted small" style={{ margin: "6px 0 0" }}>{progressLine(n)}</p>)}
          {result.handoff && (
            <div className="row" style={{ marginTop: 14, alignItems: "flex-start" }}>
              <Qr svg={result.handoff.qr_svg} />
              <div className="grow">
                <p style={{ marginTop: 0 }}>{t("Scan this with the device's Camera (same Wi-Fi). Poki opens and takes the pairing file.")}</p>
                <code className="small" style={{ userSelect: "text" }}>{result.handoff.link}</code>
              </div>
            </div>
          )}
        </Card>
      )}
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
