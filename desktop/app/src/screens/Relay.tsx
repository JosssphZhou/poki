import { useEffect, useRef, useState, type FormEvent } from "react";
import { api, failureKind, onProgress, type CfAccount, type Deployed, type WorkerStatus } from "../api";
import { t } from "../i18n";
import { Capsule, Card, Copy, ErrorBox, Pill, Qr, Steps, useSteps } from "../ui";

const cloudflareErrors: Record<string, string> = {
  cloudflare_permission: "This token doesn't have permission to deploy Workers in that account. Check the permissions and account scope in Cloudflare.",
  cloudflare_no_accounts: "This token doesn't have access to any Cloudflare account. Check its account scope in Cloudflare.",
  cloudflare_subdomain_taken: "Cloudflare couldn't register a workers.dev address. Choose an available address in the Cloudflare dashboard, then retry.",
  cloudflare_free_limit: "This account has reached a Workers limit or its plan doesn't support this deployment. Check your usage and plan in Cloudflare, then retry.",
  cloudflare_network: "Poki Setup couldn't reach Cloudflare. Check your connection and try again.",
  cloudflare_not_ready: "The Worker was uploaded but the relay didn't answer yet. Wait a minute, then retry Deploy.",
  cloudflare_unsupported_migration: "This version of Poki Setup can't update the existing Worker's migration. Use a compatible relay release and run deploy/cf-relay/deploy.sh to deploy manually.",
  cloudflare_invalid_token: "Cloudflare rejected the API token. Create a new token or check that you copied it correctly.",
  cloudflare_api: "Cloudflare couldn't complete the request. Try again or check the Cloudflare dashboard.",
};

async function open(url: string) {
  const { openUrl } = await import("@tauri-apps/plugin-opener");
  await openUrl(url);
}

function looksLikeToken(value: string): boolean {
  return /^[A-Za-z0-9_-]{20,256}$/.test(value);
}

function cloudflareErrorKind(error: unknown): string {
  const kind = failureKind(error);
  return Object.hasOwn(cloudflareErrors, kind) ? kind : "cloudflare_api";
}

export default function Relay() {
  const [relay, setRelay] = useState<Deployed | null>(null);
  const token = useRef("");
  const [accounts, setAccounts] = useState<CfAccount[]>([]);
  const [accountId, setAccountId] = useState("");
  const [busy, setBusy] = useState<"load" | "open" | "lookup" | "forget" | "deploy" | null>("load");
  const [stage, setStage] = useState<"start" | "browser" | "manual">("start");
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [up, setUp] = useState<boolean | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [worker, setWorker] = useState<WorkerStatus | null>(null);
  const [saved, setSaved] = useState(false);
  const { steps, apply, fail, reset } = useSteps([{ id: "relay", title: "Deploy" }]);
  useEffect(() => {
    let active = true;
    Promise.all([
      api.relayState().catch(() => null),
      api.relayTokenSaved().catch(() => false),
    ]).then(([deployed, tokenSaved]) => {
      if (!active) return;
      setRelay(deployed);
      setSaved(tokenSaved);
      setBusy(null);
    });
    api.relayWorker().then(setWorker).catch(() => {});
    const un = onProgress("relay", apply);
    return () => { active = false; un.then((f) => f()); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const cancel = () => {
    token.current = "";
    setAccounts([]);
    setAccountId("");
    setStage("start");
    setError(null);
    setNotice("Cloudflare setup canceled in Poki Setup.");
    reset();
  };
  const connect = async () => {
    setBusy("open");
    setError(null);
    setNotice(null);
    reset();
    try {
      await open(await api.relayTokenSetupUrl());
      setStage("browser");
    } catch {
      setError("Couldn't open Cloudflare in your browser. Try again or paste a token manually.");
    } finally {
      setBusy(null);
    }
  };
  const lookup = async (candidate: string) => {
    try {
      const available = await api.relayAccounts(candidate);
      if (available.length === 0) {
        setError("cloudflare_no_accounts");
        return;
      }
      token.current = candidate;
      setAccounts(available);
      setAccountId(available.length === 1 ? available[0].id : available.find((account) => account.id === relay?.account_id)?.id ?? "");
    } catch (e) {
      setError(cloudflareErrorKind(e));
    }
  };
  const useSaved = async () => {
    setBusy("lookup");
    setError(null);
    setNotice(null);
    reset();
    await lookup("");
    setBusy(null);
  };
  const importCopied = async () => {
    setBusy("lookup");
    setError(null);
    let candidate: string;
    try {
      candidate = (await navigator.clipboard.readText()).trim();
    } catch {
      setStage("manual");
      setError("Couldn't read the clipboard. Paste the token into the secure field instead.");
      setBusy(null);
      return;
    }
    if (!looksLikeToken(candidate)) {
      setError("Copy the API token from Cloudflare, then try importing it again.");
    } else {
      await lookup(candidate);
    }
    setBusy(null);
  };
  const pasteManually = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const candidate = String(new FormData(event.currentTarget).get("token") ?? "").trim();
    event.currentTarget.reset();
    setError(null);
    if (!looksLikeToken(candidate)) {
      setError("Paste the API token you copied from Cloudflare.");
      return;
    }
    setBusy("lookup");
    await lookup(candidate);
    setBusy(null);
  };
  const showManual = () => {
    setStage("manual");
    setError(null);
    setNotice(null);
    reset();
  };
  const forget = async () => {
    setBusy("forget");
    setError(null);
    setNotice(null);
    try {
      await api.relayForgetToken();
      setSaved(false);
    } catch {
      setError("Couldn't forget the saved Cloudflare token. Try again.");
    } finally {
      setBusy(null);
    }
  };
  const deploy = async () => {
    setBusy("deploy");
    setError(null);
    reset();
    try {
      const deployed = await api.relayDeploy(token.current, accountId);
      token.current = "";
      setRelay(deployed);
      setUp(true);
      setQr(null);
      setAccounts([]);
      setAccountId("");
      setStage("start");
      api.relayWorker().then(setWorker).catch(() => {});
      apply({ job: "relay", kind: "done", id: "relay", detail: deployed.address });
      const tokenSaved = await api.relayTokenSaved().catch(() => null);
      setSaved(tokenSaved === true);
      if (tokenSaved === false) setNotice("No Cloudflare token is saved. Connect again to update the relay later.");
      if (tokenSaved === null) setNotice("Poki Setup couldn't check whether a Cloudflare token is saved.");
    } catch (e) {
      fail("");
      setError(cloudflareErrorKind(e));
    } finally {
      setBusy(null);
    }
  };
  const status = busy === "open" ? "Opening Cloudflare…" : busy === "lookup" ? "Checking Cloudflare accounts…" : notice;
  return (
    <>
      <h1 className="page-title">{t("Relay")}</h1>
      <p className="page-sub">{t("Poki has no shared relay. This deploys a Worker to your own Cloudflare account, so screenshots and taps pass only through a Worker you control.")}</p>
      {relay && (
        <Card>
          <div className="row between">
            <div className="grow"><h2 style={{ margin: 0 }}>{t("Your relay")}</h2><code className="small" style={{ userSelect: "text" }}>{relay.address}</code><div className="muted small">{relay.account_name}</div></div>
            {up !== null && <Pill tone={up ? "ok" : "bad"}>{t(up ? "Answering" : "Not answering")}</Pill>}
            <Copy text={relay.address} />
            <Capsule kind="ghost" sm onClick={() => api.relayCheck(relay.address).then(setUp)}>{t("Check")}</Capsule>
            <Capsule kind="ghost" sm onClick={() => api.qrSvg(relay.phone_link).then(setQr)}>{t("Show QR for the phone")}</Capsule>
          </div>
          {qr && <div className="row" style={{ marginTop: 14, alignItems: "flex-start" }}><Qr svg={qr} /><div className="grow"><p style={{ marginTop: 0 }}>{t("In Poki on the iPhone, open Connect and scan this, or type the address under Relay address.")}</p><code className="small" style={{ userSelect: "text" }}>{relay.phone_link}</code></div></div>}
        </Card>
      )}
      {worker && (
        <Card>
          <h2>{t("Relay code")}</h2>
          <p className="muted small">{worker.source === "built in" ? t("Built into Poki Setup") : `${t("From release")} ${worker.source}`}. {t("Poki Setup deploys the relay from the same release as the Poki on your iPhone.")}</p>
          {worker.update_available && <p><Pill tone="warn">{t("Relay update available")}</Pill></p>}
          <div className="row">
            <Capsule kind="ghost" sm onClick={() => open(worker.download_url)}>{t("Download worker.js")}</Capsule>
            <Capsule kind="ghost" sm onClick={() => open(worker.guide_url)}>{t("Deploy it yourself")}</Capsule>
          </div>
        </Card>
      )}
      <Card>
        <h2>{t("Deploy to my Cloudflare account")}</h2>
        <div className="stack">
          {error && <div role="alert"><ErrorBox error={cloudflareErrors[error] ?? error} /></div>}
          {error === "cloudflare_unsupported_migration" && worker && (
            <div><Capsule kind="ghost" onClick={() => open(worker.guide_url)}>{t("Open manual deployment guide")}</Capsule></div>
          )}
          {accounts.length > 0 ? (
            <>
              {accounts.length === 1 ? (
                <div className="field"><span className="muted small">{t("Cloudflare account")}</span><strong>{accounts[0].name}</strong></div>
              ) : (
                <div className="field">
                  <label htmlFor="relay-account">{t("Cloudflare account")}</label>
                  <select id="relay-account" className="input" style={{ appearance: "auto" }} value={accountId} onChange={(e) => setAccountId(e.target.value)} disabled={busy !== null}>
                    <option value="" disabled>{t("Choose an account")}</option>
                    {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
                  </select>
                </div>
              )}
              <p className="muted small">{t("If this account doesn't have a workers.dev address yet, Poki Setup can register one when you deploy.")}</p>
              <div className="row wrap">
                <Capsule onClick={deploy} disabled={busy !== null || !accountId}>{busy === "deploy" ? t("Deploying…") : t("Deploy")}</Capsule>
                <Capsule kind="ghost" onClick={cancel} disabled={busy !== null}>{t("Cancel")}</Capsule>
              </div>
            </>
          ) : stage === "start" ? (
            <>
              <p className="muted small">{t("Create a Workers API token in your browser and restrict it to the Cloudflare account where you want to deploy.")}</p>
              <div className="row wrap">
                {saved && <Capsule onClick={useSaved} disabled={busy !== null}>{t("Use saved token")}</Capsule>}
                <Capsule kind={saved ? "ghost" : ""} onClick={connect} disabled={busy !== null}>{t("Connect Cloudflare")}</Capsule>
                <Capsule kind="ghost" onClick={showManual} disabled={busy !== null}>{t("Paste token manually")}</Capsule>
              </div>
              {saved && <div className="row wrap"><span className="muted small">{t("A Cloudflare token is saved in Credential Manager.")}</span><Capsule kind="ghost" sm onClick={forget} disabled={busy !== null}>{t("Forget")}</Capsule></div>}
            </>
          ) : (
            <>
              {stage === "browser" ? (
                <>
                  <p className="muted small" role="status">{t("Cloudflare opened in your browser. Create the token for your intended account only, copy it, then return here to import it.")}</p>
                  <div className="row wrap">
                    <Capsule onClick={importCopied} disabled={busy !== null}>{t("Import copied token")}</Capsule>
                    <Capsule kind="ghost" onClick={showManual} disabled={busy !== null}>{t("Paste token manually")}</Capsule>
                    <Capsule kind="ghost" onClick={cancel} disabled={busy !== null}>{t("Cancel")}</Capsule>
                  </div>
                </>
              ) : (
                <form className="stack" onSubmit={pasteManually}>
                  <div className="field">
                    <label htmlFor="relay-token">{t("Cloudflare API token")}</label>
                    <input id="relay-token" name="token" className="input mono relay-token" type="password" autoComplete="off" autoCapitalize="none" spellCheck={false} autoFocus required disabled={busy !== null} />
                  </div>
                  <div className="row wrap">
                    <Capsule type="submit" disabled={busy !== null}>{t("Continue")}</Capsule>
                    <Capsule kind="ghost" onClick={cancel} disabled={busy !== null}>{t("Cancel")}</Capsule>
                  </div>
                </form>
              )}
            </>
          )}
          {status && <p className="muted small" role="status">{t(status)}</p>}
          {steps[0].state !== "todo" && <Steps steps={steps} />}
        </div>
      </Card>
    </>
  );
}
