import { useEffect, useState } from "react";
import { api, failureText, type Account as AccountT, type AppInfo, type Team } from "../api";
import { t } from "../i18n";
import { Capsule, Card, ErrorBox, Field, Toggle } from "../ui";

export default function Account({ info }: { info: AppInfo | null }) {
  const [acct, setAcct] = useState<AccountT | null>(null);
  const [teams, setTeams] = useState<Team[]>([]);
  const [appleId, setAppleId] = useState("");
  const [password, setPassword] = useState("");
  const [keep, setKeep] = useState(true);
  const [code, setCode] = useState("");
  const [factor, setFactor] = useState<"trusted_device" | "sms" | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const load = () => api.account().then((a) => { setAcct(a); if (a.signed_in) api.teams().then(setTeams).catch((e) => setError(failureText(e))); }).catch((e) => setError(failureText(e)));
  useEffect(() => { load(); }, []);

  const signIn = async () => {
    setBusy(true); setError(null);
    try {
      const f = await api.signIn(appleId, password, keep);
      setFactor(f);
      if (!f) { setPassword(""); load(); }
    } catch (e) { setError(failureText(e)); }
    setBusy(false);
  };
  const finish = async () => {
    setBusy(true); setError(null);
    try { await api.finishSignIn(code); setFactor(null); setCode(""); setPassword(""); load(); } catch (e) { setError(failureText(e)); }
    setBusy(false);
  };
  const anisetteIsSystem = acct?.anisette.kind === "system";
  const sep = t(", ");

  return (
    <>
      <h1 className="page-title">{t("Apple Account")}</h1>
      <p className="page-sub">{info?.os === "macos" ? "" : ""}</p>
      <ErrorBox error={error} />
      {acct?.signed_in ? (
        <Card>
          <div className="row between">
            <div className="grow"><h2 style={{ margin: 0 }}>{acct.name}</h2><div className="muted small">{acct.apple_id}{acct.password_kept ? `${sep}${t("Automatic renewal on")}` : ""}</div></div>
            <Capsule kind="ghost" onClick={() => api.signOut().then(load)}>{t("Sign Out")}</Capsule>
          </div>
          <div className="hair" />
          <h2>{t("Team")}</h2>
          {teams.map((tm) => (
            <label key={tm.team_id} className="row" style={{ padding: "6px 0" }}>
              <input type="radio" name="team" checked={acct.team_id === tm.team_id} onChange={() => api.chooseTeam(tm.team_id).then(load)} />
              <span className="grow">{tm.name} <span className="muted small">{tm.team_id}{sep}{tm.is_free ? t("Free (7-day signing)") : t("Paid")}</span></span>
            </label>
          ))}
        </Card>
      ) : factor ? (
        <Card>
          <h2>{t("Two-Factor Authentication")}</h2>
          <p className="muted">{factor === "sms" ? t("Enter the verification code sent to your phone number.") : t("Enter the verification code shown on your other Apple devices.")}</p>
          <form className="row" onSubmit={(e) => { e.preventDefault(); finish(); }}>
            <input className="input mono" style={{ width: 160, letterSpacing: "0.2em" }} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))} inputMode="numeric" autoFocus aria-label={t("Verification code")} placeholder="000000" />
            <Capsule type="submit" disabled={busy || code.length !== 6}>{t("Continue")}</Capsule>
            <Capsule kind="ghost" onClick={() => setFactor(null)}>{t("Cancel")}</Capsule>
          </form>
        </Card>
      ) : (
        <Card>
          <form className="stack" onSubmit={(e) => { e.preventDefault(); signIn(); }}>
            <Field label={t("Apple Account")}><input className="input" value={appleId} onChange={(e) => setAppleId(e.target.value)} autoComplete="username" placeholder="you@example.com" /></Field>
            <Field label={t("Password")}><input className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" /></Field>
            <Toggle on={keep} onChange={setKeep} label={t("Keep me signed in to renew Poki automatically")} />
            <div><Capsule type="submit" disabled={busy || !appleId || !password}>{busy ? "…" : t("Sign In")}</Capsule></div>
            <p className="muted small" style={{ margin: 0 }}>{t("Your Apple Account and password go only to Apple over TLS pinned to Apple's root certificate.")}{anisetteIsSystem ? "" : ` ${t("The Anisette server provides a device header and never sees your Apple Account or password.")}`}</p>
          </form>
        </Card>
      )}
    </>
  );
}
