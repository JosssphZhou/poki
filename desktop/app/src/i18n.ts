import { useSyncExternalStore } from "react";

export type Lang = "system" | "en" | "zh-Hans" | "zh-Hant";
export type ResolvedLang = "en" | "zh-Hans" | "zh-Hant";

const en: Record<string, string> = {
  "Set up": "Set Up",
  "Phones": "iPhones",
  "Advanced": "Advanced",
  "for iPhone": "for iPhone",
  "Apple ID": "Apple Account",
  "Relay": "Relay",
  "Connectors": "Connectors",
  "Debug": "Diagnostics",
  "Settings": "Settings",
  "Set up Poki on this iPhone": "Set Up Poki on This iPhone",
  "Plug the iPhone in with a cable and unlock it.": "Connect your iPhone with a cable, unlock it, and tap Trust if prompted.",
  "Looking for an iPhone…": "Looking for an iPhone…",
  "Set up Poki": "Install Poki",
  "Setting up…": "Installing…",
  "Sign in with your Apple ID first.": "Sign in with your Apple Account first.",
  "Sign in": "Sign In",
  "Sign out": "Sign Out",
  "Password": "Password",
  "Keep me signed in for weekly renewal": "Keep me signed in for automatic renewal",
  "Verification code": "Verification Code",
  "Apple sent a code to your devices.": "Enter the verification code shown on your other Apple devices.",
  "Apple sent a code by text message.": "Enter the verification code sent to your phone number.",
  "Continue": "Continue",
  "Team": "Team",
  "free, Poki is signed 7 days at a time": "Free Apple Account, signed for 7 days at a time",
  "paid": "Paid developer team",
  "Done": "Done",
  "Replace Certificate": "Replace Certificate",
  "Cancel": "Cancel",
  "Renew": "Renew",
  "Renewing…": "Renewing…",
  "Forget": "Forget",
  "days left": "days left",
  "expired": "Expired",
  "Show pairing QR": "Show Pairing QR",
  "Scan this with the iPhone's Camera (same Wi-Fi). Poki opens and takes the pairing file.": "Scan with your iPhone Camera on the same Wi-Fi network. Poki opens and saves the pairing file.",
  "Stop": "Stop",
  "No iPhone set up from this computer yet.": "No iPhones set up on this computer yet.",
  "Your relay": "Your Relay",
  "Deploy to my Cloudflare account": "Deploy to Cloudflare",
  "Cloudflare API token": "Cloudflare API Token",
  "Deploy": "Deploy",
  "Deploying…": "Deploying…",
  "Check": "Check",
  "Answering": "Answering",
  "Not answering": "Not Answering",
  "Show QR for the phone": "Show QR Code",
  "Add": "Add",
  "Name": "Name",
  "Connector link": "Connector Address",
  "Snippets": "Snippets",
  "Copy": "Copy",
  "Copied": "Copied",
  "System log": "System Log",
  "Start": "Start",
  "Filter": "Filter",
  "Support bundle": "Support Bundle",
  "Save support bundle…": "Save Support Bundle…",
  "Mount developer disk image": "Mount Developer Disk Image",
  "Language": "Language",
  "Anisette": "Anisette",
  "This Mac": "This Mac",
  "Server": "Server",
  "Check for updates": "Check for Updates",
  "Use an agent": "Set Up with an Agent",
  "An agent on this computer (Claude Code, Codex or another one) can do the setup with Poki Setup's command line tool. Copy these instructions and paste them into the agent; it tells you when to tap the phone or type your password.": "An agent on this computer (such as Claude Code or Codex) can run Poki Setup from the command line. Copy these instructions into your agent, and it will prompt you whenever it needs a tap on your iPhone or your password.",
  "Updates": "Updates",
  "Channel": "Channel",
  "Stable": "Stable",
  "Beta": "Beta",
  "Alpha": "Alpha",
  "Pre-alpha": "Pre-alpha",
  "Newest Poki": "Newest Poki",
  "None published": "None published",
  "Stable has tested releases only. Beta adds test builds. Alpha adds early builds. Pre-alpha adds every snapshot, which can break. Poki Setup installs and renews Poki from this channel and checks it for its own updates.": "Stable includes verified releases only. Beta adds preview builds, Alpha adds early builds, and Pre-alpha includes every commit build. Poki Setup installs and renews Poki from this channel and checks it for its own updates.",
  "Up to date": "Up to date",
  "Update available": "Update available",
  "Install update": "Install Update",
  "Poki Setup {v} is available.": "Poki Setup {v} is available.",
  "Restart to Update": "Restart to Update",
  "Updating…": "Updating…",
  "Later": "Later",
  "The installer is open. Finish it to update Poki Setup.": "The installer is open. Finish it to update Poki Setup.",
  "Downloading…": "Downloading…",
  "About": "About",
  "Not signed in": "Not Signed In",
  "Developer Mode": "Developer Mode",
  "on": "On",
  "off": "Off",
  "paired": "Paired",
  "not paired": "Not Paired",
  "Pair": "Pair",
  "Turn on": "Turn On",
  "Connect the iPhone with a cable to set it up; this works on every iOS version.": "Connect your iPhone with a cable to install and pair Poki. Works on every iOS version.",
  "Poki is installed.": "Poki installed:",
  "Enter the code": "Two-Factor Authentication",
  "Phone": "iPhone",
  "Pairing": "Pairing",
  "Account": "Apple Account",
  "Release": "Release",
  "Signing": "Signing",
  "Install": "Install",
  "Pairing file": "Pairing File",
  "Latest release": "Latest Release",
  "Use the latest release": "Use Latest Release",
  "Use an IPA file…": "Choose IPA File…",
  "Scan this in Poki on the iPhone (same Wi-Fi).": "Scan this QR code in Poki on your iPhone while on the same Wi-Fi network.",
  "Relay code": "Relay Code",
  "Built into Poki Setup": "Built into Poki Setup",
  "From release": "From release",
  "Poki Setup deploys the relay from the same release as the Poki on your iPhone.": "Poki Setup deploys the relay matching the Poki release on your iPhone.",
  "Relay update available": "Relay update available",
  "Download worker.js": "Download worker.js",
  "Deploy it yourself": "Deploy Manually…",
  "Saved in Credential Manager": "Saved in system credential store",
  ", ": ", ",
  ".": ".",
  ". ": ". ",
  "Follow System": "Follow System",
  "free": "Free",
  "Clear": "Clear",
  "Developer disk image mounted.": "Developer Disk Image mounted.",
  "Paired.": "Paired.",
  "Developer Mode is on.": "Developer Mode is on.",
  "Your Apple ID and password go to Apple only, over TLS pinned to Apple's root.": "Your Apple Account credentials go only to Apple over TLS pinned to Apple's root certificate.",
  "The anisette server sees a machine identity, never your Apple ID or password.": "The anisette server provides a device header and never sees your Apple Account or password.",
  "Poki has no shared relay: this deploys the Worker to your own Cloudflare account, so screenshots and taps pass only through a Worker you control.": "Deploy a private Cloudflare Worker to your own account so agents can reach your iPhone from anywhere. Screenshots and taps pass only through your Worker, and nothing is stored.",
  "In Poki on the iPhone, open Connect and scan this, or type the address under Relay address.": "In Poki on your iPhone, open Settings › Relay and scan this code, or enter the relay address manually.",
  "Make a token at dash.cloudflare.com/profile/api-tokens with the \"Edit Cloudflare Workers\" template. Poki Setup keeps it in Credential Manager so you can update the relay later. The Worker runs inside Workers Paid's included amounts; see deploy/cf-relay/DEPLOY.md.": "Create an API token at dash.cloudflare.com/profile/api-tokens with the \"Edit Cloudflare Workers\" template. Poki Setup stores the token in your system credential store so you can update the relay later. See deploy/cf-relay/DEPLOY.md for plan details.",
  "For maintainers: the iPhone's live log, the developer disk image, and a support bundle with secrets taken out.": "Inspect the live iPhone log, mount the Developer Disk Image, or save a support bundle with passwords and tokens removed.",
  "Apple's sign-in wants a machine identity.": "Apple sign-in requires a device header (Anisette).",
  "On a Mac it comes from macOS itself.": "On macOS, Poki Setup can generate it on this Mac or fetch it from a server.",
  "On Windows a small anisette server provides one; it never sees your Apple ID or password. Run your own with Provision, or use the community server.": "On Windows, an anisette server provides it and never sees your Apple Account or password. Run your own with Provision, or use the community server.",
  "AGPL-3.0. Sign-in protocol after SideStore's icloud-auth (MPL-2.0) and Sideloader (GPL-3.0); signer: apple-codesign (MPL-2.0); device: idevice (MIT); type: Geist (OFL). See THIRD_PARTY_NOTICES.md.": "Open-source software under AGPL-3.0. Sign-in protocol adapted from SideStore icloud-auth (MPL-2.0) and Sideloader (GPL-3.0), signing via apple-codesign (MPL-2.0), device transport via idevice (MIT), and Geist font (OFL). See THIRD_PARTY_NOTICES.md.",
  "Pair with the iPhone first.": "Pair this iPhone first.",
  "Start the sign-in again.": "Start signing in again.",
  "Another setup is running.": "Another setup is already running.",
  "That account is not visible to this token.": "This token cannot access the selected Cloudflare account.",
  "Sign in with an Apple Account first.": "Sign in with your Apple Account first.",
  "Enter a Cloudflare API token, or deploy once so Poki Setup saves it.": "Enter a Cloudflare API token, or deploy once so Poki Setup saves it.",
  "The Cloudflare API token was not accepted.": "Cloudflare rejected this API token. Check the token permissions and try again.",
  "No iPhone is reachable from this computer. Connect it with a cable and unlock it.": "No iPhone is reachable from this computer. Connect your iPhone with a cable and unlock it.",
};

const zhHans: Record<string, string> = {
  "Set up": "安装",
  "Phones": "iPhone",
  "Advanced": "高级",
  "for iPhone": "iPhone 版",
  "Apple ID": "Apple 账户",
  "Relay": "中继",
  "Connectors": "连接器",
  "Debug": "诊断",
  "Settings": "设置",
  "Set up Poki on this iPhone": "在这台 iPhone 上安装 Poki",
  "Plug the iPhone in with a cable and unlock it.": "请用数据线连接 iPhone 并解锁，出现提示时轻点“信任”。",
  "Looking for an iPhone…": "正在查找 iPhone…",
  "Set up Poki": "安装 Poki",
  "Setting up…": "正在安装…",
  "Sign in with your Apple ID first.": "请先登录 Apple 账户。",
  "Sign in": "登录",
  "Sign out": "退出登录",
  "Password": "密码",
  "Keep me signed in for weekly renewal": "保持登录以便每周自动续签",
  "Verification code": "验证码",
  "Apple sent a code to your devices.": "输入其他 Apple 设备上显示的验证码。",
  "Apple sent a code by text message.": "输入通过短信收到的验证码。",
  "Continue": "继续",
  "Team": "团队",
  "free, Poki is signed 7 days at a time": "免费 Apple 账户，每次签名有效 7 天",
  "paid": "付费开发者团队",
  "Done": "完成",
  "Replace Certificate": "替换证书",
  "Cancel": "取消",
  "Renew": "续签",
  "Renewing…": "正在续签…",
  "Forget": "移除",
  "days left": "天后到期",
  "expired": "已过期",
  "Show pairing QR": "显示配对二维码",
  "Scan this with the iPhone's Camera (same Wi-Fi). Poki opens and takes the pairing file.": "在同一 Wi-Fi 网络下用 iPhone 相机扫描，Poki 会打开并保存配对文件。",
  "Stop": "停止",
  "No iPhone set up from this computer yet.": "这台电脑尚未安装配置过任何 iPhone。",
  "Your relay": "你的中继",
  "Deploy to my Cloudflare account": "部署到我的 Cloudflare 账户",
  "Cloudflare API token": "Cloudflare API 令牌",
  "Deploy": "部署",
  "Deploying…": "正在部署…",
  "Check": "检查",
  "Answering": "正常",
  "Not answering": "无响应",
  "Show QR for the phone": "显示二维码",
  "Add": "添加",
  "Name": "名称",
  "Connector link": "连接器地址",
  "Snippets": "配置片段",
  "Copy": "拷贝",
  "Copied": "已拷贝",
  "System log": "系统日志",
  "Start": "开始",
  "Filter": "筛选",
  "Support bundle": "诊断包",
  "Save support bundle…": "保存诊断包…",
  "Mount developer disk image": "挂载开发者磁盘映像",
  "Language": "语言",
  "Anisette": "Anisette",
  "This Mac": "这台 Mac",
  "Server": "服务器",
  "Check for updates": "检查更新",
  "Use an agent": "用智能体安装",
  "An agent on this computer (Claude Code, Codex or another one) can do the setup with Poki Setup's command line tool. Copy these instructions and paste them into the agent; it tells you when to tap the phone or type your password.": "这台电脑上的智能体（如 Claude Code 或 Codex）可通过命令行运行 Poki Setup。拷贝这段说明并发送给智能体，需要你在 iPhone 上点按或输入密码时它会提示你。",
  "Updates": "更新",
  "Channel": "更新渠道",
  "Stable": "正式版",
  "Beta": "Beta 版",
  "Alpha": "Alpha 版",
  "Pre-alpha": "Pre-alpha 版",
  "Newest Poki": "最新 Poki",
  "None published": "暂无发布版本",
  "Stable has tested releases only. Beta adds test builds. Alpha adds early builds. Pre-alpha adds every snapshot, which can break. Poki Setup installs and renews Poki from this channel and checks it for its own updates.": "正式版仅包含经过验证的版本，Beta 版包含测试构建，Alpha 版包含早期构建，Pre-alpha 版包含每次提交快照。Poki Setup 会从此更新渠道安装和续签 Poki，并检查自身更新。",
  "Up to date": "已是最新",
  "Update available": "有可用更新",
  "Install update": "安装更新",
  "Poki Setup {v} is available.": "Poki Setup {v} 已发布。",
  "Restart to Update": "重新启动以更新",
  "Updating…": "正在更新…",
  "Later": "稍后",
  "The installer is open. Finish it to update Poki Setup.": "安装程序已打开，完成安装即可更新 Poki Setup。",
  "Downloading…": "正在下载…",
  "About": "关于",
  "Not signed in": "未登录",
  "Developer Mode": "开发者模式",
  "on": "已开启",
  "off": "未开启",
  "paired": "已配对",
  "not paired": "未配对",
  "Pair": "配对",
  "Turn on": "开启",
  "Connect the iPhone with a cable to set it up; this works on every iOS version.": "用数据线连接 iPhone 即可安装并配对 Poki，支持所有 iOS 版本。",
  "Poki is installed.": "已安装 Poki",
  "Enter the code": "输入验证码",
  "Phone": "iPhone",
  "Pairing": "配对",
  "Account": "账户",
  "Release": "版本",
  "Signing": "签名",
  "Install": "安装",
  "Pairing file": "配对文件",
  "Latest release": "最新版本",
  "Use the latest release": "改用最新版本",
  "Use an IPA file…": "选择 IPA 文件…",
  "Scan this in Poki on the iPhone (same Wi-Fi).": "在同一 Wi-Fi 网络下，打开 iPhone 上的 Poki 扫描此二维码。",
  "Relay code": "中继代码",
  "Built into Poki Setup": "内置于 Poki Setup",
  "From release": "来自版本",
  "Poki Setup deploys the relay from the same release as the Poki on your iPhone.": "Poki Setup 会部署与你 iPhone 上 Poki 版本一致的中继。",
  "Relay update available": "中继有可用更新",
  "Download worker.js": "下载 worker.js",
  "Deploy it yourself": "手动部署说明…",
  "Saved in Credential Manager": "已保存在系统凭据存储中",
  ", ": "，",
  ".": "。",
  ". ": "。",
  "Follow System": "跟随系统",
  "free": "免费",
  "Clear": "清空",
  "Developer disk image mounted.": "开发者磁盘映像已挂载。",
  "Paired.": "已配对。",
  "Developer Mode is on.": "开发者模式已开启。",
  "Your Apple ID and password go to Apple only, over TLS pinned to Apple's root.": "你的 Apple 账户和密码仅通过绑定 Apple 根证书的加密连接直接发送给 Apple。",
  "The anisette server sees a machine identity, never your Apple ID or password.": "Anisette 服务器仅提供设备标头，无法看到你的 Apple 账户或密码。",
  "Poki has no shared relay: this deploys the Worker to your own Cloudflare account, so screenshots and taps pass only through a Worker you control.": "在你的 Cloudflare 账户中部署专属中继 Worker，让智能体可从任何地方连接此 iPhone。截图和轻点仅经过你自己的 Worker，不存储任何数据。",
  "In Poki on the iPhone, open Connect and scan this, or type the address under Relay address.": "在 iPhone 上打开 Poki 的“设置 › 中继”扫描此二维码，或手动输入中继地址。",
  "Make a token at dash.cloudflare.com/profile/api-tokens with the \"Edit Cloudflare Workers\" template. Poki Setup keeps it in Credential Manager so you can update the relay later. The Worker runs inside Workers Paid's included amounts; see deploy/cf-relay/DEPLOY.md.": "前往 dash.cloudflare.com/profile/api-tokens 使用“Edit Cloudflare Workers”模板创建令牌。Poki Setup 会将令牌保存在系统凭据存储中以便后续更新中继，额度说明见 deploy/cf-relay/DEPLOY.md。",
  "For maintainers: the iPhone's live log, the developer disk image, and a support bundle with secrets taken out.": "查看 iPhone 实时日志、挂载开发者磁盘映像，或导出已去除密码和令牌的诊断包。",
  "Apple's sign-in wants a machine identity.": "Apple 登录需要设备标头（Anisette）。",
  "On a Mac it comes from macOS itself.": "在 macOS 上，Poki Setup 可直接由本机生成或连接远程服务器。",
  "On Windows a small anisette server provides one; it never sees your Apple ID or password. Run your own with Provision, or use the community server.": "在 Windows 上由 anisette 服务器提供标头，服务器无法看到你的 Apple 账户或密码。可使用 Provision 自建或使用社区服务器。",
  "AGPL-3.0. Sign-in protocol after SideStore's icloud-auth (MPL-2.0) and Sideloader (GPL-3.0); signer: apple-codesign (MPL-2.0); device: idevice (MIT); type: Geist (OFL). See THIRD_PARTY_NOTICES.md.": "基于 AGPL-3.0 开源。登录协议参考 SideStore icloud-auth（MPL-2.0）与 Sideloader（GPL-3.0），签名使用 apple-codesign（MPL-2.0），设备通信使用 idevice（MIT），字体使用 Geist（OFL），详见 THIRD_PARTY_NOTICES.md。",
  "Pair with the iPhone first.": "请先配对此 iPhone。",
  "Start the sign-in again.": "请重新发起登录。",
  "Another setup is running.": "另一个安装任务正在运行。",
  "That account is not visible to this token.": "此令牌无权访问所选 Cloudflare 账户。",
  "Sign in with an Apple Account first.": "请先登录 Apple 账户。",
  "Enter a Cloudflare API token, or deploy once so Poki Setup saves it.": "请输入 Cloudflare API 令牌，或先部署一次以便 Poki Setup 保存令牌。",
  "The Cloudflare API token was not accepted.": "Cloudflare 拒绝了此 API 令牌，请检查令牌权限后重试。",
  "No iPhone is reachable from this computer. Connect it with a cable and unlock it.": "未检测到连接的 iPhone。请用数据线连接 iPhone 并解锁。",
};

const zhHant: Record<string, string> = {
  "Set up": "安裝",
  "Phones": "iPhone",
  "Advanced": "進階",
  "for iPhone": "iPhone 版",
  "Apple ID": "Apple 帳號",
  "Relay": "中繼",
  "Connectors": "連接器",
  "Debug": "診斷",
  "Settings": "設定",
  "Set up Poki on this iPhone": "在這台 iPhone 上安裝 Poki",
  "Plug the iPhone in with a cable and unlock it.": "請使用傳輸線連接 iPhone 並解鎖，出現提示時輕點「信任」。",
  "Looking for an iPhone…": "正在尋找 iPhone…",
  "Set up Poki": "安裝 Poki",
  "Setting up…": "正在安裝…",
  "Sign in with your Apple ID first.": "請先登入 Apple 帳號。",
  "Sign in": "登入",
  "Sign out": "登出",
  "Password": "密碼",
  "Keep me signed in for weekly renewal": "保持登入以便每週自動續簽",
  "Verification code": "驗證碼",
  "Apple sent a code to your devices.": "輸入其他 Apple 裝置上顯示的驗證碼。",
  "Apple sent a code by text message.": "輸入透過簡訊收到的驗證碼。",
  "Continue": "繼續",
  "Team": "團隊",
  "free, Poki is signed 7 days at a time": "免費 Apple 帳號，每次簽名有效 7 天",
  "paid": "付費開發者團隊",
  "Done": "完成",
  "Replace Certificate": "替換憑證",
  "Cancel": "取消",
  "Renew": "續簽",
  "Renewing…": "正在續簽…",
  "Forget": "移除",
  "days left": "天後到期",
  "expired": "已過期",
  "Show pairing QR": "顯示配對二維碼",
  "Scan this with the iPhone's Camera (same Wi-Fi). Poki opens and takes the pairing file.": "在同一 Wi-Fi 網路下使用 iPhone 相機掃描，Poki 會開啟並儲存配對檔案。",
  "Stop": "停止",
  "No iPhone set up from this computer yet.": "這台電腦尚未安裝設定過任何 iPhone。",
  "Your relay": "你的中繼",
  "Deploy to my Cloudflare account": "部署到我的 Cloudflare 帳號",
  "Cloudflare API token": "Cloudflare API 權杖",
  "Deploy": "部署",
  "Deploying…": "正在部署…",
  "Check": "檢查",
  "Answering": "正常",
  "Not answering": "無回應",
  "Show QR for the phone": "顯示二維碼",
  "Add": "新增",
  "Name": "名稱",
  "Connector link": "連接器位址",
  "Snippets": "設定片段",
  "Copy": "複製",
  "Copied": "已複製",
  "System log": "系統日誌",
  "Start": "開始",
  "Filter": "篩選",
  "Support bundle": "診斷套件",
  "Save support bundle…": "儲存診斷套件…",
  "Mount developer disk image": "掛載開發者磁碟映像",
  "Language": "語言",
  "Anisette": "Anisette",
  "This Mac": "這台 Mac",
  "Server": "伺服器",
  "Check for updates": "檢查更新",
  "Use an agent": "透過代理程式安裝",
  "An agent on this computer (Claude Code, Codex or another one) can do the setup with Poki Setup's command line tool. Copy these instructions and paste them into the agent; it tells you when to tap the phone or type your password.": "這台電腦上的代理程式（例如 Claude Code 或 Codex）可透過命令列執行 Poki Setup。複製這段說明並傳送給代理程式，需要你在 iPhone 上點按或輸入密碼時它會提示你。",
  "Updates": "更新",
  "Channel": "更新通道",
  "Stable": "正式版",
  "Beta": "Beta 版",
  "Alpha": "Alpha 版",
  "Pre-alpha": "Pre-alpha 版",
  "Newest Poki": "最新 Poki",
  "None published": "尚無發布版本",
  "Stable has tested releases only. Beta adds test builds. Alpha adds early builds. Pre-alpha adds every snapshot, which can break. Poki Setup installs and renews Poki from this channel and checks it for its own updates.": "正式版僅包含經過驗證的版本，Beta 版包含測試建置，Alpha 版包含早期建置，Pre-alpha 版包含每次提交快照。Poki Setup 會從此更新通道安裝和續簽 Poki，並檢查自身更新。",
  "Up to date": "已是最新",
  "Update available": "有可用更新",
  "Install update": "安裝更新",
  "Poki Setup {v} is available.": "Poki Setup {v} 已發布。",
  "Restart to Update": "重新啟動以更新",
  "Updating…": "正在更新…",
  "Later": "稍後",
  "The installer is open. Finish it to update Poki Setup.": "安裝程式已開啟，完成安裝即可更新 Poki Setup。",
  "Downloading…": "正在下載…",
  "About": "關於",
  "Not signed in": "未登入",
  "Developer Mode": "開發者模式",
  "on": "已開啟",
  "off": "未開啟",
  "paired": "已配對",
  "not paired": "未配對",
  "Pair": "配對",
  "Turn on": "開啟",
  "Connect the iPhone with a cable to set it up; this works on every iOS version.": "使用傳輸線連接 iPhone 即可安裝並配對 Poki，支援所有 iOS 版本。",
  "Poki is installed.": "已安裝 Poki",
  "Enter the code": "輸入驗證碼",
  "Phone": "iPhone",
  "Pairing": "配對",
  "Account": "帳號",
  "Release": "版本",
  "Signing": "簽名",
  "Install": "安裝",
  "Pairing file": "配對檔案",
  "Latest release": "最新版本",
  "Use the latest release": "改用最新版本",
  "Use an IPA file…": "選擇 IPA 檔案…",
  "Scan this in Poki on the iPhone (same Wi-Fi).": "在同一 Wi-Fi 網路下，開啟 iPhone 上的 Poki 掃描此二維碼。",
  "Relay code": "中繼程式碼",
  "Built into Poki Setup": "內建於 Poki Setup",
  "From release": "來自版本",
  "Poki Setup deploys the relay from the same release as the Poki on your iPhone.": "Poki Setup 會部署與你 iPhone 上 Poki 版本一致的中繼。",
  "Relay update available": "中繼有可用更新",
  "Download worker.js": "下載 worker.js",
  "Deploy it yourself": "手動部署說明…",
  "Saved in Credential Manager": "已儲存在系統憑證存放區",
  ", ": "，",
  ".": "。",
  ". ": "。",
  "Follow System": "跟隨系統",
  "free": "免費",
  "Clear": "清除",
  "Developer disk image mounted.": "開發者磁碟映像已掛載。",
  "Paired.": "已配對。",
  "Developer Mode is on.": "開發者模式已開啟。",
  "Your Apple ID and password go to Apple only, over TLS pinned to Apple's root.": "你的 Apple 帳號和密碼僅透過綁定 Apple 根憑證的加密連線直接傳送給 Apple。",
  "The anisette server sees a machine identity, never your Apple ID or password.": "Anisette 伺服器僅提供裝置標頭，無法看到你的 Apple 帳號或密碼。",
  "Poki has no shared relay: this deploys the Worker to your own Cloudflare account, so screenshots and taps pass only through a Worker you control.": "在你的 Cloudflare 帳號中部署專屬中繼 Worker，讓代理程式可從任何地方連線此 iPhone。截圖和輕點僅經過你自己的 Worker，不儲存任何資料。",
  "In Poki on the iPhone, open Connect and scan this, or type the address under Relay address.": "在 iPhone 上開啟 Poki 的「設定 › 中繼」掃描此二維碼，或手動輸入中繼位址。",
  "Make a token at dash.cloudflare.com/profile/api-tokens with the \"Edit Cloudflare Workers\" template. Poki Setup keeps it in Credential Manager so you can update the relay later. The Worker runs inside Workers Paid's included amounts; see deploy/cf-relay/DEPLOY.md.": "前往 dash.cloudflare.com/profile/api-tokens 使用「Edit Cloudflare Workers」範本建立權杖。Poki Setup 會將權杖儲存在系統憑證存放區以便日後更新中繼，額度說明請參閱 deploy/cf-relay/DEPLOY.md。",
  "For maintainers: the iPhone's live log, the developer disk image, and a support bundle with secrets taken out.": "檢視 iPhone 即時日誌、掛載開發者磁碟映像，或匯出已去除密碼與權杖的診斷套件。",
  "Apple's sign-in wants a machine identity.": "Apple 登入需要裝置標頭（Anisette）。",
  "On a Mac it comes from macOS itself.": "在 macOS 上，Poki Setup 可直接由這台 Mac 產生或連線遠端伺服器。",
  "On Windows a small anisette server provides one; it never sees your Apple ID or password. Run your own with Provision, or use the community server.": "在 Windows 上由 anisette 伺服器提供標頭，伺服器無法看到你的 Apple 帳號或密碼。可使用 Provision 自建或使用社群伺服器。",
  "AGPL-3.0. Sign-in protocol after SideStore's icloud-auth (MPL-2.0) and Sideloader (GPL-3.0); signer: apple-codesign (MPL-2.0); device: idevice (MIT); type: Geist (OFL). See THIRD_PARTY_NOTICES.md.": "採用 AGPL-3.0 授權條款開源。登入協定參考 SideStore icloud-auth（MPL-2.0）與 Sideloader（GPL-3.0），簽名使用 apple-codesign（MPL-2.0），裝置通訊使用 idevice（MIT），字型使用 Geist（OFL），詳見 THIRD_PARTY_NOTICES.md。",
  "Pair with the iPhone first.": "請先配對此 iPhone。",
  "Start the sign-in again.": "請重新發起登入。",
  "Another setup is running.": "另一個安裝任務正在執行。",
  "That account is not visible to this token.": "此權杖無權取用所選 Cloudflare 帳號。",
  "Sign in with an Apple Account first.": "請先登入 Apple 帳號。",
  "Enter a Cloudflare API token, or deploy once so Poki Setup saves it.": "請輸入 Cloudflare API 權杖，或先部署一次以便 Poki Setup 儲存權杖。",
  "The Cloudflare API token was not accepted.": "Cloudflare 拒絕了此 API 權杖，請檢查權杖權限後重試。",
  "No iPhone is reachable from this computer. Connect it with a cable and unlock it.": "未偵測到連線的 iPhone。請使用傳輸線連接 iPhone 並解鎖。",
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
  return en[key] ?? key;
}

export function tError(raw: string): string {
  const active = resolveLang(pref);
  const direct = active === "zh-Hans" ? zhHans[raw] : active === "zh-Hant" ? zhHant[raw] : en[raw];
  if (direct) return direct;
  const anisetteMatch = /^anisette(?: server)? (?:at )?(.*?): (.*)$/i.exec(raw) ?? /^could not reach (?:the )?anisette server(?: at ([^:]+))?: (.*)$/i.exec(raw);
  if (anisetteMatch) {
    const detail = anisetteMatch[2] ?? raw;
    if (active === "zh-Hans") return `无法连接 Anisette 服务器（${detail}）。请检查服务器地址与网络连接。`;
    if (active === "zh-Hant") return `無法連線 Anisette 伺服器（${detail}）。請檢查伺服器位址與網路連線。`;
    return `Could not reach the Anisette server (${detail}). Check the server address and network connection.`;
  }
  if (/anisette/i.test(raw) && /(connect|reach|error sending request|connection refused|timed out)/i.test(raw)) {
    if (active === "zh-Hans") return "无法连接 Anisette 服务器，请检查服务器地址与网络连接。";
    if (active === "zh-Hant") return "無法連線 Anisette 伺服器，請檢查伺服器位址與網路連線。";
    return "Could not reach the Anisette server. Check the server address and network connection.";
  }
  if (raw.startsWith("Could not reach Cloudflare:")) {
    const detail = raw.slice("Could not reach Cloudflare:".length).trim();
    if (active === "zh-Hans") return `无法连接 Cloudflare（${detail}）。请检查网络后重试。`;
    if (active === "zh-Hant") return `無法連線 Cloudflare（${detail}）。請檢查網路後重試。`;
    return `Could not reach Cloudflare (${detail}). Check your network and try again.`;
  }
  if (raw.startsWith("Apple sign-in")) {
    const detail = raw.replace(/^Apple sign-in[^:]*:\s*/i, "");
    if (active === "zh-Hans") return `Apple 登录失败：${detail}`;
    if (active === "zh-Hant") return `Apple 登入失敗：${detail}`;
    return `Apple sign-in failed: ${detail}`;
  }
  return raw;
}
