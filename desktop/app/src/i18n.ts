import { useSyncExternalStore } from "react";

export type Lang = "system" | "en" | "zh-Hans" | "zh-Hant";
export type ResolvedLang = "en" | "zh-Hans" | "zh-Hant";

const zhHans: Record<string, string> = {
  ", ": "，",
  "Set Up": "安装",
  "iPhones": "iPhone",
  "Advanced": "高级",
  "for iPhone": "iPhone 版",
  "Apple Account": "Apple 账户",
  "Relay": "中继",
  "Connectors": "连接器",
  "Diagnostics": "诊断",
  "Settings": "设置",
  "Set Up Poki on This iPhone": "在这台 iPhone 上安装 Poki",
  "Connect your iPhone with a cable to install and pair Poki. Works on every iOS version.": "用数据线连接 iPhone 即可安装并配对 Poki，支持所有 iOS 版本。",
  "Connect your iPhone with a cable, unlock it, and tap Trust if prompted.": "请用数据线连接 iPhone 并解锁，出现提示时轻点“信任”。",
  "Looking for an iPhone…": "正在查找 iPhone…",
  "Install Poki": "安装 Poki",
  "Installing…": "正在安装…",
  "Sign in with your Apple Account first.": "请先登录 Apple 账户。",
  "Sign In": "登录",
  "Sign Out": "退出登录",
  "Password": "密码",
  "Keep me signed in to renew Poki automatically": "保持登录以自动续签 Poki",
  "Automatic renewal on": "已开启自动续签",
  "Two-Factor Authentication": "双重认证",
  "Verification code": "验证码",
  "Enter the verification code shown on your other Apple devices.": "输入其他 Apple 设备上显示的验证码。",
  "Enter the verification code sent to your phone number.": "输入通过短信收到的验证码。",
  "Continue": "继续",
  "Team": "团队",
  "Free": "免费",
  "Free (7-day signing)": "免费团队（每次签名有效 7 天）",
  "Paid": "付费团队",
  "With a free Apple Account, Poki stays signed for 7 days at a time. Poki Setup renews it automatically while this computer is on.": "使用免费 Apple 账户签名时，Poki 每次有效 7 天。电脑开机期间，Poki Setup 会自动续签。",
  "Your Apple Account and password go only to Apple over TLS pinned to Apple's root certificate.": "你的 Apple 账户和密码仅通过绑定 Apple 根证书的加密连接直接发送给 Apple。",
  "The Anisette server provides a device header and never sees your Apple Account or password.": "Anisette 服务器仅提供设备校验头，绝不会接触你的 Apple 账户或密码。",
  "Done": "完成",
  "Apply": "应用",
  "Replace Certificate": "替换证书",
  "Cancel": "取消",
  "Renew": "续签",
  "Renewing…": "正在续签…",
  "Forget": "移除",
  "{d} days left": "剩余 {d} 天",
  "Expired": "已过期",
  "Show Pairing QR": "显示配对二维码",
  "Scan with your iPhone Camera on the same Wi-Fi network. Poki opens and saves the pairing file.": "在同一 Wi-Fi 网络下用 iPhone 相机扫描，Poki 会打开并保存配对文件。",
  "Scan this QR code in Poki on your iPhone while on the same Wi-Fi network.": "在同一 Wi-Fi 网络下，打开 iPhone 上的 Poki 扫描此二维码。",
  "Stop": "停止",
  "No iPhones set up on this computer yet.": "这台电脑尚未安装配置过任何 iPhone。",
  "Deploy a private Cloudflare Worker to your own account so AI agents can reach your iPhone from anywhere. Screenshots and actions pass only through your Worker and nothing is stored.": "在你的 Cloudflare 账户中部署专属 Worker，让智能体可从任何地方连接你的 iPhone。截图和操作仅经过你自己的 Worker，不保存任何数据。",
  "Your Relay": "你的中继",
  "Relay Code": "中继代码",
  "Built into Poki Setup": "内置于 Poki Setup",
  "From release {v}": "来自版本 {v}",
  "Poki Setup deploys the relay matching the Poki release on your iPhone.": "Poki Setup 会部署与你 iPhone 上 Poki 版本一致的中继。",
  "Relay update available": "中继有可用更新",
  "Download worker.js": "下载 worker.js",
  "Deploy Manually…": "手动部署说明…",
  "Deploy to Cloudflare": "部署到 Cloudflare",
  "Create an API token at dash.cloudflare.com/profile/api-tokens using the Edit Cloudflare Workers template. Poki Setup stores the token in your system credential store so you can update the relay later.": "前往 dash.cloudflare.com/profile/api-tokens 使用“Edit Cloudflare Workers”模板创建令牌。Poki Setup 会将令牌保存在系统凭据存储中，方便后续更新中继。",
  "Cloudflare API Token": "Cloudflare API 令牌",
  "Saved in system credential store": "已保存在系统凭据存储中",
  "Cloudflare Account": "Cloudflare 账户",
  "In Poki on your iPhone, open Settings › Relay and scan this code, or enter the relay address manually.": "在 iPhone 上打开 Poki 的“设置 › 中继”扫描此二维码，或手动输入中继地址。",
  "Deploy": "部署",
  "Deploying…": "正在部署…",
  "Check": "检查",
  "Answering": "正常",
  "Not Answering": "无响应",
  "Show QR Code": "显示二维码",
  "Copy": "拷贝",
  "Copied": "已拷贝",
  "Inspect the live iPhone log, mount the Developer Disk Image, or save a support bundle with passwords and tokens removed.": "查看 iPhone 实时日志、挂载开发者磁盘映像，或导出已去除密码和令牌的诊断包。",
  "Start": "开始",
  "Clear": "清空",
  "Filter": "筛选",
  "Save Support Bundle…": "保存诊断包…",
  "Mount Developer Disk Image": "挂载开发者磁盘映像",
  "Developer Disk Image mounted.": "开发者磁盘映像已挂载。",
  "Paired.": "已配对。",
  "Developer Mode is on.": "开发者模式已开启。",
  "Turn On Developer Mode": "开启开发者模式",
  "Language": "语言",
  "Follow System": "跟随系统",
  "Anisette": "Anisette",
  "Apple sign-in requires a device header (Anisette). On macOS, Poki Setup can use this Mac directly or a remote server.": "Apple 登录需要设备校验头（Anisette）。在 macOS 上，Poki Setup 可直接使用本机生成或连接远程服务器。",
  "Apple sign-in requires a device header (Anisette). A remote server provides it and never sees your Apple Account or password.": "Apple 登录需要设备校验头（Anisette）。远程服务器仅提供校验头，绝不会接触你的 Apple 账户或密码。",
  "This Mac": "这台 Mac",
  "Server": "服务器",
  "Check for Updates": "检查更新",
  "Set Up with an Agent": "用智能体安装",
  "An agent on this computer (such as Claude Code or Codex) can run Poki Setup from the command line. Copy these instructions into your agent, and it will prompt you whenever it needs a tap on your iPhone or your password.": "这台电脑上的智能体（如 Claude Code 或 Codex）可通过命令行运行 Poki Setup。拷贝这段说明并发送给智能体，需要你在 iPhone 上点按或输入密码时它会提示你。",
  "Updates": "更新",
  "Channel": "更新渠道",
  "Stable": "正式版",
  "Beta": "Beta 版",
  "Alpha": "Alpha 版",
  "Pre-alpha": "Pre-alpha 版",
  "Newest Poki": "最新 Poki",
  "None published": "暂无发布版本",
  "Up to date": "已是最新",
  "Update available": "有可用更新",
  "Install Update": "安装更新",
  "Poki Setup {v} is available.": "Poki Setup {v} 已发布。",
  "Restart to Update": "重新启动以更新",
  "Updating…": "正在更新…",
  "Later": "稍后",
  "The installer is open. Finish it to update Poki Setup.": "安装程序已打开，完成安装即可更新 Poki Setup。",
  "Downloading…": "正在下载…",
  "About": "关于",
  "Open-source software under AGPL-3.0. See THIRD_PARTY_NOTICES.md for sign-in, signing, device, and font attributions.": "基于 AGPL-3.0 协议开源。登录、签名、设备通信与字体归属说明见 THIRD_PARTY_NOTICES.md。",
  "Not Signed In": "未登录",
  "Developer Mode": "开发者模式",
  "On": "已开启",
  "Off": "未开启",
  "Paired": "已配对",
  "Not Paired": "未配对",
  "Pair": "配对",
  "Turn On": "开启",
  "Poki {v} is installed on {name}.": "Poki {v} 已安装到 {name}。",
  "Poki {v}": "Poki {v}",
  "iPhone": "iPhone",
  "Pairing": "配对",
  "Release": "版本",
  "Signing": "签名",
  "Install": "安装",
  "Pairing File": "配对文件",
  "Latest Release": "最新版本",
  "Use Latest Release": "改用最新版本",
  "Choose IPA File…": "选择 IPA 文件…",
};

const zhHant: Record<string, string> = {
  ", ": "，",
  "Set Up": "安裝",
  "iPhones": "iPhone",
  "Advanced": "進階",
  "for iPhone": "iPhone 版",
  "Apple Account": "Apple 帳號",
  "Relay": "中繼",
  "Connectors": "連接器",
  "Diagnostics": "診斷",
  "Settings": "設定",
  "Set Up Poki on This iPhone": "在這部 iPhone 上安裝 Poki",
  "Connect your iPhone with a cable to install and pair Poki. Works on every iOS version.": "使用傳輸線連接 iPhone 即可安裝並配對 Poki，支援所有 iOS 版本。",
  "Connect your iPhone with a cable, unlock it, and tap Trust if prompted.": "請使用傳輸線連接 iPhone 並解鎖，出現提示時點一下「信任」。",
  "Looking for an iPhone…": "正在尋找 iPhone…",
  "Install Poki": "安裝 Poki",
  "Installing…": "正在安裝…",
  "Sign in with your Apple Account first.": "請先登入 Apple 帳號。",
  "Sign In": "登入",
  "Sign Out": "登出",
  "Password": "密碼",
  "Keep me signed in to renew Poki automatically": "保持登入以自動續簽 Poki",
  "Automatic renewal on": "已開啟自動續簽",
  "Two-Factor Authentication": "雙重認證",
  "Verification code": "驗證碼",
  "Enter the verification code shown on your other Apple devices.": "輸入其他 Apple 裝置上顯示的驗證碼。",
  "Enter the verification code sent to your phone number.": "輸入透過簡訊收到的驗證碼。",
  "Continue": "繼續",
  "Team": "團隊",
  "Free": "免費",
  "Free (7-day signing)": "免費團隊（每次簽名有效 7 天）",
  "Paid": "付費團隊",
  "With a free Apple Account, Poki stays signed for 7 days at a time. Poki Setup renews it automatically while this computer is on.": "使用免費 Apple 帳號簽名時，Poki 每次有效 7 天。電腦開機期間，Poki Setup 會自動續簽。",
  "Your Apple Account and password go only to Apple over TLS pinned to Apple's root certificate.": "你的 Apple 帳號和密碼僅透過綁定 Apple 根憑證的加密連線直接傳送給 Apple。",
  "The Anisette server provides a device header and never sees your Apple Account or password.": "Anisette 伺服器僅提供裝置驗證標頭，絕不會接觸你的 Apple 帳號或密碼。",
  "Done": "完成",
  "Apply": "套用",
  "Replace Certificate": "替換憑證",
  "Cancel": "取消",
  "Renew": "續簽",
  "Renewing…": "正在續簽…",
  "Forget": "移除",
  "{d} days left": "剩餘 {d} 天",
  "Expired": "已過期",
  "Show Pairing QR": "顯示配對二維碼",
  "Scan with your iPhone Camera on the same Wi-Fi network. Poki opens and saves the pairing file.": "在同一 Wi-Fi 網路下使用 iPhone 相機掃描，Poki 會打開並儲存配對檔案。",
  "Scan this QR code in Poki on your iPhone while on the same Wi-Fi network.": "在同一 Wi-Fi 網路下，打開 iPhone 上的 Poki 掃描此二維碼。",
  "Stop": "停止",
  "No iPhones set up on this computer yet.": "這台電腦尚未安裝設定過任何 iPhone。",
  "Deploy a private Cloudflare Worker to your own account so AI agents can reach your iPhone from anywhere. Screenshots and actions pass only through your Worker and nothing is stored.": "在你的 Cloudflare 帳號中部署專屬 Worker，讓代理程式可從任何地方連線你的 iPhone。截圖和操作僅經過你自己的 Worker，不儲存任何資料。",
  "Your Relay": "你的中繼",
  "Relay Code": "中繼程式碼",
  "Built into Poki Setup": "內建於 Poki Setup",
  "From release {v}": "來自版本 {v}",
  "Poki Setup deploys the relay matching the Poki release on your iPhone.": "Poki Setup 會部署與你 iPhone 上 Poki 版本一致的中繼。",
  "Relay update available": "中繼有可用更新",
  "Download worker.js": "下載 worker.js",
  "Deploy Manually…": "手動部署說明…",
  "Deploy to Cloudflare": "部署到 Cloudflare",
  "Create an API token at dash.cloudflare.com/profile/api-tokens using the Edit Cloudflare Workers template. Poki Setup stores the token in your system credential store so you can update the relay later.": "前往 dash.cloudflare.com/profile/api-tokens 使用「Edit Cloudflare Workers」範本建立權杖。Poki Setup 會將權杖儲存在系統憑證存放區，方便日後更新中繼。",
  "Cloudflare API Token": "Cloudflare API 權杖",
  "Saved in system credential store": "已儲存在系統憑證存放區",
  "Cloudflare Account": "Cloudflare 帳號",
  "In Poki on your iPhone, open Settings › Relay and scan this code, or enter the relay address manually.": "在 iPhone 上打開 Poki 的「設定 › 中繼」掃描此二維碼，或手動輸入中繼位址。",
  "Deploy": "部署",
  "Deploying…": "正在部署…",
  "Check": "檢查",
  "Answering": "正常",
  "Not Answering": "無回應",
  "Show QR Code": "顯示二維碼",
  "Copy": "複製",
  "Copied": "已複製",
  "Inspect the live iPhone log, mount the Developer Disk Image, or save a support bundle with passwords and tokens removed.": "檢視 iPhone 即時日誌、掛載開發者磁碟映像，或匯出已去除密碼與權杖的診斷套件。",
  "Start": "開始",
  "Clear": "清除",
  "Filter": "篩選",
  "Save Support Bundle…": "儲存診斷套件…",
  "Mount Developer Disk Image": "掛載開發者磁碟映像",
  "Developer Disk Image mounted.": "開發者磁碟映像已掛載。",
  "Paired.": "已配對。",
  "Developer Mode is on.": "開發者模式已開啟。",
  "Turn On Developer Mode": "開啟開發者模式",
  "Language": "語言",
  "Follow System": "跟隨系統",
  "Anisette": "Anisette",
  "Apple sign-in requires a device header (Anisette). On macOS, Poki Setup can use this Mac directly or a remote server.": "Apple 登入需要裝置驗證標頭（Anisette）。在 macOS 上，Poki Setup 可直接使用這台 Mac 產生或連線遠端伺服器。",
  "Apple sign-in requires a device header (Anisette). A remote server provides it and never sees your Apple Account or password.": "Apple 登入需要裝置驗證標頭（Anisette）。遠端伺服器僅提供標頭，絕不會接觸你的 Apple 帳號或密碼。",
  "This Mac": "這台 Mac",
  "Server": "伺服器",
  "Check for Updates": "檢查更新",
  "Set Up with an Agent": "透過代理程式安裝",
  "An agent on this computer (such as Claude Code or Codex) can run Poki Setup from the command line. Copy these instructions into your agent, and it will prompt you whenever it needs a tap on your iPhone or your password.": "這台電腦上的代理程式（例如 Claude Code 或 Codex）可透過命令列執行 Poki Setup。複製這段說明並傳送給代理程式，需要你在 iPhone 上點按或輸入密碼時它會提示你。",
  "Updates": "更新",
  "Channel": "更新通道",
  "Stable": "正式版",
  "Beta": "Beta 版",
  "Alpha": "Alpha 版",
  "Pre-alpha": "Pre-alpha 版",
  "Newest Poki": "最新 Poki",
  "None published": "尚無發布版本",
  "Up to date": "已是最新",
  "Update available": "有可用更新",
  "Install Update": "安裝更新",
  "Poki Setup {v} is available.": "Poki Setup {v} 已發布。",
  "Restart to Update": "重新啟動以更新",
  "Updating…": "正在更新…",
  "Later": "稍後",
  "The installer is open. Finish it to update Poki Setup.": "安裝程式已打開，完成安裝即可更新 Poki Setup。",
  "Downloading…": "正在下載…",
  "About": "關於",
  "Open-source software under AGPL-3.0. See THIRD_PARTY_NOTICES.md for sign-in, signing, device, and font attributions.": "採用 AGPL-3.0 授權條款開源。登入、簽名、裝置通訊與字型歸屬說明請參閱 THIRD_PARTY_NOTICES.md。",
  "Not Signed In": "未登入",
  "Developer Mode": "開發者模式",
  "On": "已開啟",
  "Off": "未開啟",
  "Paired": "已配對",
  "Not Paired": "未配對",
  "Pair": "配對",
  "Turn On": "開啟",
  "Poki {v} is installed on {name}.": "Poki {v} 已安裝到 {name}。",
  "Poki {v}": "Poki {v}",
  "iPhone": "iPhone",
  "Pairing": "配對",
  "Release": "版本",
  "Signing": "簽名",
  "Install": "安裝",
  "Pairing File": "配對檔案",
  "Latest Release": "最新版本",
  "Use Latest Release": "改用最新版本",
  "Choose IPA File…": "選擇 IPA 檔案…",
};

function detectSystemLang(): ResolvedLang {
  const prefs = navigator.languages?.length ? navigator.languages : [navigator.language];
  for (const raw of prefs) {
    const tag = raw.toLowerCase();
    if (tag.startsWith("en")) return "en";
    if (tag.startsWith("zh")) {
      if (tag.includes("hant") || tag.includes("-tw") || tag.includes("-hk") || tag.includes("-mo")) {
        return "zh-Hant";
      }
      return "zh-Hans";
    }
  }
  return "en";
}

function resolveLang(pref: Lang): ResolvedLang {
  return pref === "system" ? detectSystemLang() : pref;
}

const VALID_PREFS = new Set<Lang>(["system", "en", "zh-Hans", "zh-Hant"]);
const stored = localStorage.getItem("lang") as Lang | null;
let pref: Lang = stored && VALID_PREFS.has(stored) ? stored : "system";
const listeners = new Set<() => void>();

function syncDocumentLang() {
  const resolved = resolveLang(pref);
  document.documentElement.dataset.lang = resolved;
  document.documentElement.lang = resolved;
}

syncDocumentLang();
if (typeof window !== "undefined") {
  window.addEventListener("languagechange", () => {
    if (pref === "system") {
      syncDocumentLang();
      listeners.forEach((f) => f());
    }
  });
}

export function setLang(next: Lang) {
  pref = next;
  localStorage.setItem("lang", next);
  syncDocumentLang();
  listeners.forEach((f) => f());
}

export function useLang(): Lang {
  return useSyncExternalStore(
    (f) => {
      listeners.add(f);
      return () => listeners.delete(f);
    },
    () => pref,
  );
}

export function t(key: string): string {
  const active = resolveLang(pref);
  if (active === "zh-Hans") return zhHans[key] ?? key;
  if (active === "zh-Hant") return zhHant[key] ?? key;
  return key;
}
