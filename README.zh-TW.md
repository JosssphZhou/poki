<p align="center">
  <img src="docs/images/poki-icon.png" width="72" height="72" alt="Poki icon">
</p>

<h1 align="center">Poki 用你的 iPhone，就像你自己在用</h1>

<p align="center">
  <img src="docs/images/poki-home.gif" width="720" alt="Poki 官網首頁動畫">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | 繁體中文 | <a href="README.ja.md">日本語</a> | <a href="README.ko.md">한국어</a> | <a href="README.es.md">Español</a><br>
  <a href="https://poki.bot">poki.bot</a>
</p>

<!-- badges:start -->
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0--only-blue" alt="License: AGPL-3.0-only"></a>
  <a href="https://github.com/JosssphZhou/poki/stargazers"><img src="https://img.shields.io/github/stars/JosssphZhou/poki" alt="GitHub stars"></a>
  <a href="https://github.com/JosssphZhou/poki/forks"><img src="https://img.shields.io/github/forks/JosssphZhou/poki" alt="GitHub forks"></a>
  <a href="https://github.com/JosssphZhou/poki/issues"><img src="https://img.shields.io/github/issues/JosssphZhou/poki" alt="GitHub issues"></a>
  <a href="https://github.com/JosssphZhou/poki/releases"><img src="https://img.shields.io/github/v/release/JosssphZhou/poki?sort=date&amp;display_name=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20Windows-lightgrey" alt="Platform: iOS, macOS and Windows">
</p>
<!-- badges:end -->

Poki 是一個像人一樣操作 iPhone 的代理。它讀取螢幕，在實際應用程式裡點按、輸入和滾動，並在敏感操作前詢問你。

**Poki App** 直接在 iPhone 上執行。你在對話裡交代任務，它就在其他應用程式裡完成。首次安裝需要 Mac 或 Windows 電腦，之後執行任務不需要電腦。

Poki MCP 是早期通過 Mac 上的代理控制 iPhone 的方式，現已停止更新。已有使用者仍可使用，說明保留在頁面後部的 [Poki MCP](#poki-mcp)。

各版本的更新內容見 [CHANGELOG.md](CHANGELOG.md)。

## 在 iPhone 上安裝 Poki

首次安裝需要一台 Mac 或 Windows 電腦。

- **Mac**：讓代理安裝 Poki，或下載 macOS 版 Poki Setup，按視窗操作。
- **Windows**：下載 Windows 版 Poki Setup，按視窗操作。先安裝 Apple Devices 或 iTunes，讓電腦能通過 USB 識別 iPhone。代理也可以使用 Poki Setup 自帶的命令列工具。
- **安裝之後**：Poki 在 iPhone 上獨立執行任務。免費 Apple 帳號的簽章有效期是 7 天，電腦上的 Poki Setup 保持執行時可以續簽，見[常見問題](#常見問題)。

### 讓代理安裝（推薦）

把下面這句話發給 Claude Code 或 Codex 等代理：

```text
從 https://github.com/JosssphZhou/poki 把 Poki 安裝到我的 iPhone。
```

代理按 [install-poki 技能](skills/install-poki/SKILL.md)執行 `bin/install-iphone.mjs`，自動完成可以代做的步驟。你只需完成系統要求本人操作的部分：在 Mac 的 Poki Setup 視窗輸入 Apple 帳號，在手機上點「信任」、開啟開發者模式、信任開發者並開啟 Poki。首次開啟時，Poki 會請求開啟自動化模式，請點「繼續」並輸入鎖屏密碼。取消後重新開啟 Poki，即可再次請求。代理會在每一步用一句話告訴你要做什麼。免費 Apple 帳號也可以使用。

安裝器預設選擇 Alpha 通道，也可以讓代理選擇 Beta 等其他通道。組建先進入 Alpha，經過更多測試後，同一組建再進入 Beta。

沒有 Node.js 24，或使用 Windows？先安裝 Poki Setup，同一句提示詞仍然可用，代理會使用安裝器內的命令列工具。Poki Setup 也能複製給代理的提示詞，Mac 上在 Poki > Copy Prompt for Your Agent，Windows 上在 Settings > Use an agent。

安裝器讀取 GitHub 發布列表時若出現 403 或 429，通常是同一網路共用的匿名請求額度已用完。換一個網路或代理伺服器節點後重試，或等一小時。

### 使用 Poki Setup

想自己點選安裝？從 [Alpha 發布頁](https://github.com/JosssphZhou/poki/releases/tag/app-alpha-latest)下載 macOS 版 `.dmg` 或 Windows 版 `.exe`，按視窗操作。Windows 版由 [ZhehanZhang](https://github.com/ZhehanZhang) 貢獻。Beta 發布頁帶有相同的 Poki Setup 安裝文件。在設定中選擇通道之前，Poki Setup 預設安裝最新 Stable；尚無 Stable 時安裝 Beta。步驟見 [Poki Setup](desktop/README.md)。

### 需要準備什麼

| 項目 | 要求 |
| --- | --- |
| iPhone | iOS 18 或更高版本，即 iPhone XS、XR、SE（第 2 代）或更新機型。真機測試目前使用 iOS 27。 |
| 電腦 | macOS 14 或更高版本的 Mac，或已安裝 Apple Devices 或 iTunes 的 x64 Windows 電腦。Mac 上用代理安裝還需要 Node.js 24 或更高版本，不需要 Xcode。 |
| 資料線與帳號 | USB 資料線和 Apple 帳號。免費帳號的簽章有效期為 7 天，Poki Setup 可以續簽。 |
| 連線 | iPhone 上需要能把 10.7.0.1 連回手機本機的 VPN 應用程式。App Store 上免費的 LocalDevVPN 可以使用，也可以按 Poki 的說明設定 Karing 或 Shadowrocket。 |
| 模型帳號 | 需要自己準備。使用 ChatGPT Plus 或 Pro 登入最方便。也可填寫 Anthropic、OpenAI、Gemini、DeepSeek 或 OpenRouter 的 API 金鑰，或使用自己的 OpenAI 兼容服務。Claude 訂閱不能直接登入，請使用 Anthropic API 金鑰。 |

iOS 27 及以上通過原生服務控制手機。iOS 18 至 26 使用 XCTest 會話，需要在手機的開發者設定中開啟 UI Automation。應用也能安裝到 iPadOS 18 及以上的 iPad。

### 常見問題

**Windows 能安裝嗎？** 可以。Windows 版 Poki Setup 和 Mac 版一樣能安裝、配對和續簽。請先安裝 Apple Devices 或 iTunes，讓電腦能識別 iPhone。見 [Poki Setup](desktop/README.md)。

**裝好以後還需要電腦嗎？** 執行任務不需要，Poki 在手機上獨立執行。使用免費 Apple 帳號時，保持電腦上的 Poki Setup 執行以便每周續簽；也可以在手機的 Poki 中登入 Apple 帳號，讓手機自行續簽。0.4.0 的首次手機登入可能失敗，見[已知問題](#已知問題)和[需要保持執行的內容](skills/install-poki/SKILL.md#what-to-keep-running)。

**免費 Apple 帳號可以用嗎？7 天限制是什麼？** 可以，但簽章只有 7 天有效。電腦保持喚醒、手機可連線且 Poki Setup 開著時，安裝器每 6 小時檢查一次，剩餘 2 天或更少時續簽。不續簽就會到期無法開啟，Poki 會在最後 2 天提醒。見[沒有付費開發者帳號](skills/install-poki/SKILL.md#no-paid-developer-account)。

**需要什麼 iPhone 和系統？** iOS 18 及以上，即 iPhone XS、XR、SE（第 2 代）或更新機型；也支援安裝到 iPadOS 18 及以上。真機測試目前只在 iOS 27 上完成，iOS 18 至 26 使用的另一條控制路徑尚未在真機驗證。見[驗證記錄](docs/verification.md)。

**需要自己的模型帳號嗎？** 需要。可用 ChatGPT Plus 或 Pro 登入，或使用 Anthropic、OpenAI、Gemini、DeepSeek、OpenRouter 的 API 金鑰或自己的 OpenAI 兼容服務。語音對話還需要語音模型金鑰。見[需要準備什麼](#需要準備什麼)。

**看不到更新，例如在中國大陸的網路上，怎麼辦？** Poki 從 GitHub 查更新，部分網路無法訪問或會遇到 403、429 限制。換網路或代理伺服器節點，或在電腦上的 Poki Setup 點 Renew 更新。見[更新 Poki](#更新-poki)。

**會改動手機里的內容嗎？操作前會問嗎？** Poki 在實際應用程式裡執行你交代的任務，包括發消息。螢幕內容會發送給你設定的模型服務。付款、刪除和錢包操作始終需要確認。發消息、輸入密碼等其他敏感步驟，可以在 Settings > Approvals 選擇詢問方式或不詢問。見[已知問題](#已知問題)。

## 更新 Poki

- **手機上**：0.4.0 開啟 Settings > Connection > Signing & Updates，0.3.1 開啟設定中的 Signing 頁面。有新組建時，頁面提供下載並安裝。若要求先登入，說明應用由電腦安裝，手機還沒有 Apple 帳號，請使用安裝時的帳號登入，或改由電腦更新。
- **電腦上**：Poki Setup 的 Renew 會把所選通道的最新組建覆蓋安裝到現有應用。Mac 上也可以讓代理「更新我 iPhone 上的 Poki」，install-poki 技能的更新流程會先檢查版本和簽章身份。
- 卡在「Finishing the update」時，從多任務介面划掉 Poki，再開啟並核對設定中的版本。版本未變則用電腦上的 Poki Setup 更新。不要為修復更新而刪除 Poki，刪除應用也會刪除對話。

通道和 Alpha 到 Beta 的流程見[發布通道](docs/release-channels.md)。

## 已知問題

- Poki 操作的是真實手機。你讓它發送消息或付款，它就會執行。螢幕內容會發送給你設定的模型服務。
- 0.4.0 在手機上首次登入 Apple 帳號可能提示需要 Mac，因為 Apple 不再接受 Poki 使用的舊 Mac 登入身份。已登入使用者可照常在手機上更新；其他使用者請通過電腦上的 Poki Setup 續簽和更新。
- 真機支援目前僅在中文介面、竪屏 iPhone 上驗證，不支援橫屏。
- 未在低於 iOS 27 的真機或 iPad 上測試。較舊或較小的 iPhone 上，三維小熊和首頁動畫可能更熱或更慢。低電量模式和「減弱動態效果」會改用靜態小熊圖片。
- 免費 Apple 帳號簽章有效期為 7 天。請讓電腦上的 Poki Setup 能連線手機，或在到期前手動續簽。
- GitHub 發布列表可能返回 403 或 429，通常與多人共用網路有關。換網路或代理伺服器節點後重試，或等一小時。

更多限制和測試結果見[驗證記錄](docs/verification.md)。

## 試跑一個任務

開啟 Poki，在輸入框寫「查一下明天的天氣，告訴我要不要帶傘」，或點首頁的應用開始任務。Poki 在螢幕上的應用程式裡操作，在靈動島和鎖屏顯示步驟，並在敏感操作前停下詢問。

也可以不先開啟 Poki，長按操作按鈕與它對話，或通過快捷指令和 Siri 使用 Talk to Poki、Send Task to Poki。這類任務會通過通知回復。

> **注意：** Poki 控制的是真實 iPhone。你讓它發消息或付款，它就會執行。

## 路線圖

這裡只列方向，不承諾日期。

**已完成，至 0.4.0 Beta**

- iPhone 上的 Poki App，安裝後無需 Mac，支援鎖屏和靈動島批准操作。
- 代理或 Mac、Windows 版 Poki Setup 一步安裝，無需 Xcode，免費 Apple 帳號可用。
- iOS 27 及以上的原生控制。
- Poki MCP、Poki Agent、iMessage 和 Telegram 渠道，以及任務路線的學習與重放。Poki MCP 保留現狀，不再更新。
- 局域網和 Tailscale 遠程連線。
- 0.4.0 介面，包括三維小熊首頁、語音對話、操作按鈕、封存和深色模式。

**下一步**

- 更新改用 Poki 自己的下載源，GitHub 作為備用。
- 多個更新通道合為一個。
- 語音只負責聽、說和看，手機操作交給當前執行任務的文字模型。
- 更多介面語言。

**以後**

- 在更多 iPhone、iOS 版本和螢幕語言上做真機驗證。
- 支援更多模型服務。

## 文件

| 主題 | 文件 |
| --- | --- |
| 各版本更新內容 | [CHANGELOG.md](CHANGELOG.md) |
| 用代理安裝 iPhone App | [install-poki 技能](skills/install-poki/SKILL.md) |
| Mac 和 Windows 安裝器 | [Poki Setup](desktop/README.md) |
| 發布通道和組建晉級 | [發布通道](docs/release-channels.md) |
| Poki MCP 安裝、其他客戶端和排錯（不再更新） | [安裝指南](docs/install.md) |
| Poki Agent、模型、iMessage 和 Telegram | [執行 Poki Agent](agent/README.md) |
| MCP 工具說明 | [工具說明](docs/tools.md) |
| 環境變量和會話 | [設定說明](docs/configuration.md) |
| USB 配對、開發者模式和 Wi-Fi | [真機設定](docs/physical-iphone.md) |
| 測試結果、限制與免責聲明 | [驗證記錄](docs/verification.md) |
| 橋接架構 | [原生橋接](native/NATIVE.md)和[模擬器適配](native/simulator.md) |
| 路線圖 | [路線圖](#路線圖) |

## Star History

<a href="https://www.star-history.com/?repos=JosssphZhou%2Fpoki&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&theme=dark&legend=top-left">
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
    <img alt="Star History chart" src="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
  </picture>
</a>

## 核心貢獻者

<!-- CORE-CONTRIBUTORS:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=240" width="120" height="120" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a><br />提交了 Poki 的第一個問題 <a href="https://github.com/JosssphZhou/poki/issues/1">#1</a>：在 iOS 18.6.2 上截圖正常，輔助功能和觸控不可用，哪些能用哪些不能寫得很清楚。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=240" width="120" height="120" alt="ZhehanZhang"/><br /><sub><b>ZhehanZhang</b></sub></a><br />Poki 偉大的共同創造者。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=240" width="120" height="120" alt="edge369"/><br /><sub><b>edge369</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/14">#14</a> 讓 Poki 能在路由器上執行，Mac 關機時也能透過 Telegram 操作 iPhone；<a href="https://github.com/JosssphZhou/poki/pull/15">#15</a>、<a href="https://github.com/JosssphZhou/poki/pull/17">#17</a> 和 <a href="https://github.com/JosssphZhou/poki/issues/19">#19</a> 隨後跟進。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=240" width="120" height="120" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/6">#6</a> 中回報 macOS 27.2 上 usbmuxd 列不出任何 iPhone；Poki 現在會直接說明這一點，以及輔助程式為何提前停止（<a href="https://github.com/JosssphZhou/poki/issues/59">#59</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=240" width="120" height="120" alt="igc110"/><br /><sub><b>igc110</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/10">#10</a> 查明實體 iPhone 點按慢的原因，隨後的修正讓點按快了約三分之一。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=240" width="120" height="120" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/16">#16</a> 把 Poki 移植到 Linux，並在實體 iPhone 上透過 USB、區域網路和 Tailscale 驗證；README 現已指向該移植版。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=240" width="120" height="120" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/18">#18</a> 把實體 iPhone 觸控失敗追查到缺少 display service；現在 Poki 會說明沒有送出任何輸入，並指向 prepare-device。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=240" width="120" height="120" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a><br />修正了損壞的路由快取中斷無關 Agent 任務的問題（<a href="https://github.com/JosssphZhou/poki/issues/21">#21</a>、<a href="https://github.com/JosssphZhou/poki/pull/22">#22</a>），隨後在 <a href="https://github.com/JosssphZhou/poki/pull/37">#37</a> 讓 Agent 重用操作後已讀到的畫面。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=240" width="120" height="120" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/25">#25</a> 回報 iMessage 任務不會被自然語言的停止請求打斷；現在 Poki 會回覆任務途中的訊息，並提示使用 /stop。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=240" width="120" height="120" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/27">#27</a> 和 <a href="https://github.com/JosssphZhou/poki/issues/28">#28</a> 中重現了兩個 Agent 缺陷，隨後合併了七項修正和測試修整，從已取消的輸入鎖（<a href="https://github.com/JosssphZhou/poki/pull/102">#102</a>）到無效的觸控座標（<a href="https://github.com/JosssphZhou/poki/pull/136">#136</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=240" width="120" height="120" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/34">#34</a> 修正了 iPhone 區域網路位址變更後 RemotePairing 連線失效的問題（<a href="https://github.com/JosssphZhou/poki/issues/30">#30</a>）；實體 iPhone 重新連線只花了 768 毫秒。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=240" width="120" height="120" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/35">#35</a> 和 <a href="https://github.com/JosssphZhou/poki/issues/40">#40</a> 中實地測試了 iPhone 應用，涵蓋行動網路和 Windows，促成了首次設定需要 Wi-Fi 的說明（<a href="https://github.com/JosssphZhou/poki/issues/138">#138</a>）；還回報了 <a href="https://github.com/JosssphZhou/poki/issues/162">#162</a>。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=240" width="120" height="120" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/39">#39</a> 修正了 Windows 主機經 RemotePairing 連線時每次點按都失敗的問題；修正後 5 次點按全部成功。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=240" width="120" height="120" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/42">#42</a> 透過 Tailscale 在實體 iPhone 上做了一次保險條款核對；這份報告推動了更清楚的 USB 錯誤訊息，以及依工作階段切換連線方式。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=240" width="120" height="120" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a><br />錄製了 Poki 操作實體 iPhone 的示範影片，讓新訪客在安裝之前就能看到它能做什麼。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=240" width="120" height="120" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/68">#68</a> 中把 OpenCode Go 加為 iPhone 應用的模型帳號，附獨立的鑰匙圈憑證和獨立的模型選擇。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=240" width="120" height="120" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/69">#69</a> 中提供了 Runner 閒置約 25 分鐘後配對失敗的完整時間線；設定頁現在會指向回環和配對檢查（<a href="https://github.com/JosssphZhou/poki/issues/70">#70</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=240" width="120" height="120" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a><br />讓批次呼叫在裝置不明確時給出提示而不是當機（<a href="https://github.com/JosssphZhou/poki/pull/74">#74</a>），並新增 POKI_MCP_DEVICE（<a href="https://github.com/JosssphZhou/poki/pull/75">#75</a>）和可選的逐任務核准（<a href="https://github.com/JosssphZhou/poki/pull/77">#77</a>）。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=240" width="120" height="120" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a><br />修正配對設定把人帶到錯誤設定頁面的問題，開發者模式和 UI 自動化步驟現在會開啟正確的頁面（<a href="https://github.com/JosssphZhou/poki/pull/137">#137</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=240" width="120" height="120" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/139">#139</a> 中修正讀取畫面超過呼叫期限的問題，並為持續變慢的 Runner 回應補上回歸測試。</td>
    </tr>
  </tbody>
</table>
<!-- CORE-CONTRIBUTORS:END -->

## 特別貢獻者

<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=240" width="120" height="120" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a><br />提交了一整套 0.4.0 改版設計，涵蓋對話、即時動態、設定和首次執行（<a href="https://github.com/JosssphZhou/poki/pull/250">#250</a>、<a href="https://github.com/JosssphZhou/poki/pull/256">#256</a> 至 <a href="https://github.com/JosssphZhou/poki/pull/268">#268</a>），這些設計塑造了新介面的方向。</td>
    </tr>
  </tbody>
</table>


## 感謝牆

感謝每一位提交過 Issue 或 Pull Request 的朋友，你們的回報與修正讓 Poki 變得更好。

<!-- THANKS-WALL:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=160" width="80" height="80" alt="ZhehanZhang"/><br /><sub><b>ZhehanZhang</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=160" width="80" height="80" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=160" width="80" height="80" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=160" width="80" height="80" alt="edge369"/><br /><sub><b>edge369</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=160" width="80" height="80" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=160" width="80" height="80" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=160" width="80" height="80" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=160" width="80" height="80" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/htx996"><img src="https://avatars.githubusercontent.com/u/95217139?v=4&size=160" width="80" height="80" alt="htx996"/><br /><sub><b>htx996</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=160" width="80" height="80" alt="igc110"/><br /><sub><b>igc110</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/iTry"><img src="https://avatars.githubusercontent.com/u/1381960?v=4&size=160" width="80" height="80" alt="iTry"/><br /><sub><b>iTry</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=160" width="80" height="80" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/kilingzhang"><img src="https://avatars.githubusercontent.com/u/17439300?v=4&size=160" width="80" height="80" alt="kilingzhang"/><br /><sub><b>kilingzhang</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=160" width="80" height="80" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/lunar-me"><img src="https://avatars.githubusercontent.com/u/275556969?v=4&size=160" width="80" height="80" alt="lunar-me"/><br /><sub><b>lunar-me</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=160" width="80" height="80" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=160" width="80" height="80" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/oasis979559-alt"><img src="https://avatars.githubusercontent.com/u/295108220?v=4&size=160" width="80" height="80" alt="oasis979559-alt"/><br /><sub><b>oasis979559-alt</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=160" width="80" height="80" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=160" width="80" height="80" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=160" width="80" height="80" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=160" width="80" height="80" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=160" width="80" height="80" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/wanghao-SunSky"><img src="https://avatars.githubusercontent.com/u/73684879?v=4&size=160" width="80" height="80" alt="wanghao-SunSky"/><br /><sub><b>wanghao-SunSky</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/windywendyday"><img src="https://avatars.githubusercontent.com/u/65647922?v=4&size=160" width="80" height="80" alt="windywendyday"/><br /><sub><b>windywendyday</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=160" width="80" height="80" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=160" width="80" height="80" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/zcyoung2000"><img src="https://avatars.githubusercontent.com/u/62181891?v=4&size=160" width="80" height="80" alt="zcyoung2000"/><br /><sub><b>zcyoung2000</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=160" width="80" height="80" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/zqy5608"><img src="https://avatars.githubusercontent.com/u/14949471?v=4&size=160" width="80" height="80" alt="zqy5608"/><br /><sub><b>zqy5608</b></sub></a></td>
    </tr>
  </tbody>
</table>
<!-- THANKS-WALL:END -->

<a id="poki-mcp"></a>

## Poki MCP (早期電腦連線方式，不再更新)

Poki MCP 是早期的電腦端連線方式，現已停止更新。Mac 上的 Claude Code 或 Codex 等代理可透過它控制 iPhone 或 iOS 模擬器，Poki Agent 則提供終端機、iMessage 和 Telegram 管道。這裡保留給既有使用者和繼續開發的人；要使用持續維護的版本，請[安裝 iPhone App](#在-iphone-上安裝-poki)。

**讓 agent 幫你安裝。** 把這段貼給你的 agent：

```text
依照 https://github.com/JosssphZhou/poki 根目錄的 AGENTS.md 安裝，包含 MCP 技能，需要我操作時就停下來。
```

**Poki MCP。** 已經在用 Claude Code、Codex 或其他 MCP 用戶端？接上 Poki MCP，用你自己的訂閱就好，不需要另外的模型帳號。

啟動伺服器並讓它持續執行：

```sh
git clone https://github.com/JosssphZhou/poki.git
cd poki
./bin/setup
npm start
```

Poki MCP 從原始碼建置，因此需要 macOS 15 以上、完整版 Xcode、Rust、Node.js 24+、Python 3 和 ffmpeg。Poki App 不需要 Xcode。`./bin/setup` 會檢查缺少的相依套件，首次建置需要幾分鐘。

Poki 以 macOS 為目標平台。Linux 使用者請見社群移植版 [poki-for-linux](https://github.com/carrotciallo/poki-for-linux)（[#16](https://github.com/JosssphZhou/poki/issues/16)），它在本儲存庫之外維護。

Poki MCP on Windows：社群移植版 [scy7796/poki-for-windows](https://github.com/scy7796/poki-for-windows)（由其作者維護，我們未測試）。

Poki MCP 的發布標籤為 `vX.Y.Z`，iPhone App 的 `app-` 發布不包含這個套件。

### 預先編譯的 macOS arm64 套件

從 Release 頁面下載 [`poki-v0.1.1-macos-arm64.tar.gz`](https://github.com/JosssphZhou/poki/releases/tag/v0.1.1)，然後執行：

```sh
tar -xzf poki-v0.1.1-macos-arm64.tar.gz
cd poki-v0.1.1
npm ci --no-audit --no-fund
npm start
```

套件內含原生橋接和 idevice 工具，不需要 Rust 或 `./bin/setup`。仍然需要 Apple Silicon 的 macOS、完整版 Xcode、Node.js 24+、Python 3 和 ffmpeg。MCP 用戶端的註冊和選用的 Agent 安裝，請參考下文。

在同一個目錄開另一個終端機，註冊 MCP 伺服器：

```sh
claude mcp add --scope user poki-mcp -- node "$PWD/src/stdio.mjs"   # Claude Code
codex mcp add poki-mcp -- node "$PWD/src/stdio.mjs"                 # Codex
```

**Poki Agent。** 想用 Poki 獨立的終端機 agent 或訊息管道的話，讓 `npm start` 繼續執行，在同一個目錄再開一個終端機。安裝 agent，把它的指令加進這個終端機的 PATH，然後登入：

```sh
npm ci --prefix agent
export PATH="$PWD/bin:$PATH"
poki login
poki status
```

Poki Agent 預設使用 GPT-6.1 Terra（`gpt-6.1-terra`），推理強度為 low。建議保留這項設定，它是我們在手機任務中測試過的最快設定。可透過 `POKI_AGENT_MODEL` 更換模型，詳見[執行 Poki Agent](agent/README.md)。

實體 iPhone 請先透過 USB 和 Mac 配對。詳見[實體 iPhone 設定](docs/physical-iphone.md)。

`./bin/poki update` 仍會拉取最新 main 並重新建置。重新啟動步驟和可選的更新檢查見 [Update](AGENTS.md#update)。

### 使用 Poki Agent 試跑任務

使用 Poki Agent 時，如果只連接一支 iPhone，會自動選取。連接多台裝置時，加上 `--device '<device UUID>'`。

```sh
node bin/call.mjs list_devices   # 查詢裝置 UUID
poki "Search esp32 in Chrome and summarize the top result"
```

> **注意：** Poki 操作的是你真實的 iPhone。如果你要它發訊息或付款，它就會照做。螢幕內容會傳送到你設定的模型服務。

越用越快：Poki Agent 會記住做過的任務，重複執行時速度更快。

**訊息管道：** 設定好已授權的管道後，用 `poki imessage` 或 [`poki telegram`](agent/README.md#telegram) 啟動。設定方式請見 [Poki Agent](agent/README.md)。

**MCP 用戶端：** Claude Code、Codex，以及任何支援 `mcpServers` JSON 的用戶端。

實體 iPhone 的支援目前只在使用中文介面的 iPhone 上驗證過。實體裝置只支援直向。無法匯出 App 容器，也無法直接連到「設定」的子頁面。請見[驗證紀錄與已知限制](docs/verification.md)。

## 免責聲明

Poki 是獨立的開源專案，與 Apple、OpenAI 以及它所操作的任何 App 或網站的開發者都沒有關聯，也未獲得其背書。iPhone 是 Apple Inc. 的商標。

自動化操作第三方 App 和網站可能違反其服務條款。是否在特定服務上使用 Poki，請自行判斷。Poki 在你的裝置和帳號上做的事由你負責，包括它發送的訊息、做出的變更，以及因此造成的任何帳號限制。

Poki 依「現狀」提供，不附帶任何擔保，詳見 AGPL-3.0 授權條款。

如有歧義，以英文版為準。

## 授權條款

Poki 的程式碼以 [AGPL-3.0-only 授權條款](LICENSE)開源。

Poki 小熊、App 圖示和 Poki 的其他美術作品不在此授權範圍內。你可以用截圖介紹 Poki；分支版本需要使用自己的名稱和美術。詳見 [BRAND.md](BRAND.md)。

Copyright (c) 2026 Joseph Zhou (周瑟夫) and contributors. 開源相依套件和第三方素材保留各自的授權條款，詳見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。想參與貢獻，請見 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 致謝

<p align="center">
  <img src="docs/images/acknowledgments.png" width="860" alt="建構於開源專案之上：pi、idevice、idb、BlueBubbles、Hermes Agent、MCP SDK、sharp 與 FFmpeg"><br>
  <sub>開源致謝：<a href="https://github.com/earendil-works/pi">pi</a> | <a href="https://github.com/jkcoxson/idevice">idevice</a> | <a href="https://github.com/facebook/idb">idb</a> | <a href="https://github.com/BlueBubblesApp/bluebubbles-server">BlueBubbles</a> | <a href="https://github.com/NousResearch/hermes-agent">Hermes Agent</a> | <a href="https://github.com/modelcontextprotocol/typescript-sdk">MCP SDK</a> | <a href="https://github.com/lovell/sharp">sharp</a> | <a href="https://github.com/FFmpeg/FFmpeg">FFmpeg</a></sub>
</p>
