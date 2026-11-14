import { useEffect, useState } from "react";
import { api, failureText, type Account, type AppInfo, type ChannelInfo, type UpdateInfo } from "../api";
import { setLang, t, useLang } from "../i18n";
import { Capsule, Card, Copy, displayVersion, ErrorBox, Field } from "../ui";

export default function Settings({ info }: { info: AppInfo | null }) {
  const lang = useLang();
  const [acct, setAcct] = useState<Account | null>(null);
  const [server, setServer] = useState("https://ani.sidestore.io");
  const [update, setUpdate] = useState<UpdateInfo | null>(null);
  const [updating, setUpdating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [channels, setChannels] = useState<ChannelInfo[]>([]);
  const [prompt, setPrompt] = useState<string | null>(null);
  const load = () => api.account().then((a) => { setAcct(a); if (a.anisette.kind === "remote") setServer(a.anisette.url); }).catch(() => {});
  useEffect(() => { load(); api.channels().then(setChannels).catch((e) => setError(failureText(e))); api.agentPrompt().then(setPrompt).catch(() => {}); }, []);
  const chosen = channels.find((c) => c.selected);
  const system = acct?.anisette.kind === "system";
  const sep = t(", ");
  return (
    <>
      <h1 className="page-title">{t("Settings")}</h1>
      <ErrorBox error={error} />
      <Card>
        <h2>{t("Language")}</h2>
        <div className="seg">
          <button className={lang === "system" ? "on" : ""} onClick={() => setLang("system")}>{t("Follow System")}</button>
          <button className={lang === "en" ? "on" : ""} onClick={() => setLang("en")}>English</button>
          <button className={lang === "zh-Hans" ? "on" : ""} onClick={() => setLang("zh-Hans")}>简体中文</button>
          <button className={lang === "zh-Hant" ? "on" : ""} onClick={() => setLang("zh-Hant")}>繁體中文</button>
        </div>
      </Card>
      <Card>
        <h2>{t("Anisette")}</h2>
        <p className="muted small">{t(info?.can_use_system_anisette ? "Apple sign-in requires a device header (Anisette). On macOS, Poki Setup can use this Mac directly or a remote server." : "Apple sign-in requires a device header (Anisette). A remote server provides it and never sees your Apple Account or password.")}</p>
        <div className="row" style={{ alignItems: "flex-end" }}>
          {info?.can_use_system_anisette && <div className="seg"><button className={system ? "on" : ""} onClick={() => api.setAnisette({ kind: "system" }).then(load).catch((e) => setError(failureText(e)))}>{t("This Mac")}</button><button className={!system ? "on" : ""} onClick={() => api.setAnisette({ kind: "remote", url: server }).then(load).catch((e) => setError(failureText(e)))}>{t("Server")}</button></div>}
          {!system && <div className="grow"><Field label={t("Server")}><div className="row"><input className="input mono grow" value={server} onChange={(e) => setServer(e.target.value)} /><Capsule kind="ghost" onClick={() => api.setAnisette({ kind: "remote", url: server }).then(load).catch((e) => setError(failureText(e)))}>{t("Apply")}</Capsule></div></Field></div>}
        </div>
      </Card>
      <Card>
        <h2>{t("Updates")}</h2>
        <p className="muted small">{chosen?.title ? t(chosen.title) : t("Beta")}</p>
        <div className="row" style={{ alignItems: "center" }}>
          <span className="muted small">{chosen?.latest ? `${t("Newest Poki")}: ${chosen.latest.version} (${chosen.latest.build})` : t("None published")}</span>
        </div>
        {chosen?.latest?.source_notice && <p className="muted small">{chosen.latest.source_notice}</p>}
      </Card>
      <Card>
        <h2>{t("Set Up with an Agent")}</h2>
        <p className="muted small">{t("An agent on this computer (such as Claude Code or Codex) can run Poki Setup from the command line. Copy these instructions into your agent, and it will prompt you whenever it needs a tap on your iPhone or your password.")}</p>
        <div className="row">{prompt && <Copy text={prompt} />}</div>
      </Card>
      <Card>
        <h2>{t("About")}</h2>
        <p className="muted small" style={{ userSelect: "text" }}>Poki Setup {displayVersion(info?.version)}{sep}{info?.os} {info?.arch}{sep}{info?.data_dir}</p>
        <div className="row">
          <Capsule kind="ghost" onClick={() => api.checkUpdate().then(setUpdate).catch((e) => setError(failureText(e)))}>{t("Check for Updates")}</Capsule>
          {update && (update.newer ? <Capsule disabled={updating} onClick={() => { setUpdating(true); api.installUpdate().then(() => {}).catch((e) => setError(failureText(e))).finally(() => setUpdating(false)); }}>{updating ? t("Downloading…") : `${t("Install Update")}: ${displayVersion(update.latest)}`}</Capsule> : <span className="muted">{t("Up to date")}</span>)}
          <Capsule kind="ghost" onClick={async () => { const { openUrl } = await import("@tauri-apps/plugin-opener"); openUrl("https://github.com/JosssphZhou/poki/blob/main/desktop/README.md"); }}>README</Capsule>
        </div>
        {update?.source_notice && <p className="muted small">{update.source_notice}</p>}
        <p className="muted small" style={{ marginBottom: 0 }}>{t("Open-source software under AGPL-3.0. See THIRD_PARTY_NOTICES.md for sign-in, signing, device, and font attributions.")}</p>
      </Card>
    </>
  );
}
