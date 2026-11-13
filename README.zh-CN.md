<p align="center">
  <img src="docs/images/poki-icon.png" width="72" height="72" alt="Poki icon">
</p>

<h1 align="center">Poki 像你一样使用你的 iPhone</h1>

<p align="center">
  <img src="docs/images/poki-home.gif" width="720" alt="Poki 官网首页动画">
</p>

<p align="center">
  <a href="README.md">English</a> | 简体中文 | <a href="README.zh-TW.md">繁體中文</a> | <a href="README.ja.md">日本語</a> | <a href="README.ko.md">한국어</a> | <a href="README.es.md">Español</a><br>
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

Poki 是一个像人一样操作 iPhone 的智能体。它读取屏幕，在真实应用里点按、输入和滚动，并在敏感操作前询问你。

**Poki App** 直接在 iPhone 上运行。你在对话里交代任务，它就在其他应用里完成。首次安装需要 Mac 或 Windows 电脑，之后执行任务不需要电脑。

Poki MCP 是早期通过 Mac 上的智能体控制 iPhone 的方式，现已停止更新。已有用户仍可使用，说明保留在页面后部的 [Poki MCP](#poki-mcp)。

各版本的更新内容见 [CHANGELOG.md](CHANGELOG.md)。

## 在 iPhone 上安装 Poki

首次安装需要一台 Mac 或 Windows 电脑。

- **Mac**：让智能体安装 Poki，或下载 macOS 版 Poki Setup，按窗口操作。
- **Windows**：下载 Windows 版 Poki Setup，按窗口操作。先安装 Apple Devices 或 iTunes，让电脑能通过 USB 识别 iPhone。智能体也可以使用 Poki Setup 自带的命令行工具。
- **安装之后**：Poki 在 iPhone 上独立执行任务。免费 Apple 账户的签名有效期是 7 天，电脑上的 Poki Setup 保持运行时可以续签，见[常见问题](#常见问题)。

### 让智能体安装（推荐）

把下面这句话发给 Claude Code 或 Codex 等智能体：

```text
从 https://github.com/JosssphZhou/poki 把 Poki 安装到我的 iPhone。
```

智能体按 [install-poki 技能](skills/install-poki/SKILL.md)运行 `bin/install-iphone.mjs`，自动完成可以代做的步骤。你只需完成系统要求本人操作的部分：在 Mac 的 Poki Setup 窗口输入 Apple 账户，在手机上点「信任」、开启开发者模式、信任开发者并打开 Poki。首次打开时，Poki 会请求开启自动化模式，请点「继续」并输入锁屏密码。取消后重新打开 Poki，即可再次请求。智能体会在每一步用一句话告诉你要做什么。免费 Apple 账户也可以使用。

安装器默认选择 Alpha 通道，也可以让智能体选择 Beta 等其他通道。构建先进入 Alpha，经过更多测试后，同一构建再进入 Beta。

没有 Node.js 24，或使用 Windows？先安装 Poki Setup，同一句提示词仍然可用，智能体会使用安装器内的命令行工具。Poki Setup 也能复制给智能体的提示词，Mac 上在 Poki > Copy Prompt for Your Agent，Windows 上在 Settings > Use an agent。

安装器读取 GitHub 发布列表时若出现 403 或 429，通常是同一网络共享的匿名请求额度已用完。换一个网络或代理节点后重试，或等一小时。

### 使用 Poki Setup

想自己点选安装？从 [Alpha 发布页](https://github.com/JosssphZhou/poki/releases/tag/app-alpha-latest)下载 macOS 版 `.dmg` 或 Windows 版 `.exe`，按窗口操作。Windows 版由 [ZhehanZhang](https://github.com/ZhehanZhang) 贡献。Beta 发布页带有相同的 Poki Setup 安装文件。在设置中选择通道之前，Poki Setup 默认安装最新 Stable；尚无 Stable 时安装 Beta。步骤见 [Poki Setup](desktop/README.md)。

### 需要准备什么

| 项目 | 要求 |
| --- | --- |
| iPhone | iOS 18 或更高版本，即 iPhone XS、XR、SE（第 2 代）或更新机型。真机测试目前使用 iOS 27。 |
| 电脑 | macOS 14 或更高版本的 Mac，或已安装 Apple Devices 或 iTunes 的 x64 Windows 电脑。Mac 上用智能体安装还需要 Node.js 24 或更高版本，不需要 Xcode。 |
| 数据线与账户 | USB 数据线和 Apple 账户。免费账户的签名有效期为 7 天，Poki Setup 可以续签。 |
| 连接 | iPhone 上需要能把 10.7.0.1 连回手机本机的 VPN 应用。App Store 上免费的 LocalDevVPN 可以使用，也可以按 Poki 的说明配置 Karing 或 Shadowrocket。 |
| 模型账户 | 需要自己准备。使用 ChatGPT Plus 或 Pro 登录最方便。也可填写 Anthropic、OpenAI、Gemini、DeepSeek 或 OpenRouter 的 API 密钥，或使用自己的 OpenAI 兼容服务。Claude 订阅不能直接登录，请使用 Anthropic API 密钥。 |

iOS 27 及以上通过原生服务控制手机。iOS 18 至 26 使用 XCTest 会话，需要在手机的开发者设置中开启 UI Automation。应用也能安装到 iPadOS 18 及以上的 iPad。

### 常见问题

**Windows 能安装吗？** 可以。Windows 版 Poki Setup 和 Mac 版一样能安装、配对和续签。请先安装 Apple Devices 或 iTunes，让电脑能识别 iPhone。见 [Poki Setup](desktop/README.md)。

**装好以后还需要电脑吗？** 执行任务不需要，Poki 在手机上独立运行。使用免费 Apple 账户时，保持电脑上的 Poki Setup 运行以便每周续签；也可以在手机的 Poki 中登录 Apple 账户，让手机自行续签。0.4.0 的首次手机登录可能失败，见[已知问题](#已知问题)和[需要保持运行的内容](skills/install-poki/SKILL.md#what-to-keep-running)。

**免费 Apple 账户可以用吗？7 天限制是什么？** 可以，但签名只有 7 天有效。电脑保持唤醒、手机可连接且 Poki Setup 开着时，安装器每 6 小时检查一次，剩余 2 天或更少时续签。不续签就会到期无法打开，Poki 会在最后 2 天提醒。见[没有付费开发者账户](skills/install-poki/SKILL.md#no-paid-developer-account)。

**需要什么 iPhone 和系统？** iOS 18 及以上，即 iPhone XS、XR、SE（第 2 代）或更新机型；也支持安装到 iPadOS 18 及以上。真机测试目前只在 iOS 27 上完成，iOS 18 至 26 使用的另一条控制路径尚未在真机验证。见[验证记录](docs/verification.md)。

**需要自己的模型账户吗？** 需要。可用 ChatGPT Plus 或 Pro 登录，或使用 Anthropic、OpenAI、Gemini、DeepSeek、OpenRouter 的 API 密钥或自己的 OpenAI 兼容服务。语音对话还需要语音模型密钥。见[需要准备什么](#需要准备什么)。

**看不到更新，例如在中国大陆的网络上，怎么办？** Poki 从 GitHub 查更新，部分网络无法访问或会遇到 403、429 限制。换网络或代理节点，或在电脑上的 Poki Setup 点 Renew 更新。见[更新 Poki](#更新-poki)。

**会改动手机里的内容吗？操作前会问吗？** Poki 在真实应用里执行你交代的任务，包括发消息。屏幕内容会发送给你配置的模型服务。付款、删除和钱包操作始终需要确认。发消息、输入密码等其他敏感步骤，可以在 Settings > Approvals 选择询问方式或不询问。见[已知问题](#已知问题)。

## 更新 Poki

- **手机上**：0.4.0 打开 Settings > Connection > Signing & Updates，0.3.1 打开设置中的 Signing 页面。有新构建时，页面提供下载并安装。若要求先登录，说明应用由电脑安装，手机还没有 Apple 账户，请使用安装时的账户登录，或改由电脑更新。
- **电脑上**：Poki Setup 的 Renew 会把所选通道的最新构建覆盖安装到现有应用。Mac 上也可以让智能体「更新我 iPhone 上的 Poki」，install-poki 技能的更新流程会先检查版本和签名身份。
- 卡在「Finishing the update」时，从多任务界面划掉 Poki，再打开并核对设置中的版本。版本未变则用电脑上的 Poki Setup 更新。不要为修复更新而删除 Poki，删除应用也会删除对话。

通道和 Alpha 到 Beta 的流程见[发布通道](docs/release-channels.md)。

## 已知问题

- Poki 操作的是真实手机。你让它发送消息或付款，它就会执行。屏幕内容会发送给你配置的模型服务。
- 0.4.0 在手机上首次登录 Apple 账户可能提示需要 Mac，因为 Apple 不再接受 Poki 使用的旧 Mac 登录身份。已登录用户可照常在手机上更新；其他用户请通过电脑上的 Poki Setup 续签和更新。
- 真机支持目前仅在中文界面、竖屏 iPhone 上验证，不支持横屏。
- 未在低于 iOS 27 的真机或 iPad 上测试。较旧或较小的 iPhone 上，三维小熊和首页动画可能更热或更慢。低电量模式和「减弱动态效果」会改用静态小熊图片。
- 免费 Apple 账户签名有效期为 7 天。请让电脑上的 Poki Setup 能连接手机，或在到期前手动续签。
- GitHub 发布列表可能返回 403 或 429，通常与多人共用网络有关。换网络或代理节点后重试，或等一小时。

更多限制和测试结果见[验证记录](docs/verification.md)。

## 试跑一个任务

打开 Poki，在输入框写「查一下明天的天气，告诉我要不要带伞」，或点首页的应用开始任务。Poki 在屏幕上的应用里操作，在灵动岛和锁屏显示步骤，并在敏感操作前停下询问。

也可以不先打开 Poki，长按操作按钮与它对话，或通过快捷指令和 Siri 使用 Talk to Poki、Send Task to Poki。这类任务会通过通知回复。

> **注意：** Poki 控制的是真实 iPhone。你让它发消息或付款，它就会执行。

## 路线图

这里只列方向，不承诺日期。

**已完成，至 0.4.0 Beta**

- iPhone 上的 Poki App，安装后无需 Mac，支持锁屏和灵动岛批准操作。
- 智能体或 Mac、Windows 版 Poki Setup 一步安装，无需 Xcode，免费 Apple 账户可用。
- iOS 27 及以上的原生控制。
- Poki MCP、Poki Agent、iMessage 和 Telegram 渠道，以及任务路线的学习与重放。Poki MCP 保留现状，不再更新。
- 局域网和 Tailscale 远程连接。
- 0.4.0 界面，包括三维小熊首页、语音对话、操作按钮、归档和深色模式。

**下一步**

- 更新改用 Poki 自己的下载源，GitHub 作为备用。
- 多个更新通道合为一个。
- 语音只负责听、说和看，手机操作交给当前执行任务的文字模型。
- 更多界面语言。

**以后**

- 在更多 iPhone、iOS 版本和屏幕语言上做真机验证。
- 支持更多模型服务。

## 文档

| 主题 | 文档 |
| --- | --- |
| 各版本更新内容 | [CHANGELOG.md](CHANGELOG.md) |
| 用智能体安装 iPhone App | [install-poki 技能](skills/install-poki/SKILL.md) |
| Mac 和 Windows 安装器 | [Poki Setup](desktop/README.md) |
| 发布通道和构建晋级 | [发布通道](docs/release-channels.md) |
| Poki MCP 安装、其他客户端和排错（不再更新） | [安装指南](docs/install.md) |
| Poki Agent、模型、iMessage 和 Telegram | [运行 Poki Agent](agent/README.md) |
| MCP 工具说明 | [工具说明](docs/tools.md) |
| 环境变量和会话 | [配置说明](docs/configuration.md) |
| USB 配对、开发者模式和 Wi-Fi | [真机配置](docs/physical-iphone.md) |
| 测试结果、限制与免责声明 | [验证记录](docs/verification.md) |
| 桥接架构 | [原生桥接](native/NATIVE.md)和[模拟器适配](native/simulator.md) |
| 路线图 | [路线图](#路线图) |

## Star History

<a href="https://www.star-history.com/?repos=JosssphZhou%2Fpoki&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&theme=dark&legend=top-left">
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
    <img alt="Star History chart" src="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
  </picture>
</a>

## 核心贡献者

<!-- CORE-CONTRIBUTORS:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=240" width="120" height="120" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a><br />提交了 Poki 的第一个问题 <a href="https://github.com/JosssphZhou/poki/issues/1">#1</a>：在 iOS 18.6.2 上截图正常，辅助功能和触控不可用，哪些能用哪些不能写得很清楚。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=240" width="120" height="120" alt="ZhehanZhang"/><br /><sub><b>ZhehanZhang</b></sub></a><br />Poki 伟大的共同创造者。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=240" width="120" height="120" alt="edge369"/><br /><sub><b>edge369</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/14">#14</a> 中让 Poki 能在路由器上运行，Mac 关机时也能通过 Telegram 操作 iPhone；<a href="https://github.com/JosssphZhou/poki/pull/15">#15</a>、<a href="https://github.com/JosssphZhou/poki/pull/17">#17</a> 和 <a href="https://github.com/JosssphZhou/poki/issues/19">#19</a> 随后跟进。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=240" width="120" height="120" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/6">#6</a> 中报告 macOS 27.2 上 usbmuxd 列不出任何 iPhone；Poki 现在会直接说明这一点，以及辅助程序为何提前停止（<a href="https://github.com/JosssphZhou/poki/issues/59">#59</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=240" width="120" height="120" alt="igc110"/><br /><sub><b>igc110</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/10">#10</a> 中查明真机点按慢的原因，随后的修复让点按快了约三分之一。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=240" width="120" height="120" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/16">#16</a> 中把 Poki 移植到 Linux，并在 iPhone 真机上通过 USB、局域网和 Tailscale 验证；README 现已指向该移植版。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=240" width="120" height="120" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/18">#18</a> 中把 iPhone 真机触控失败追查到缺少 display service；现在 Poki 会说明没有发送任何输入，并指向 prepare-device。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=240" width="120" height="120" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a><br />修复了损坏的路由缓存中断无关 Agent 任务的问题（<a href="https://github.com/JosssphZhou/poki/issues/21">#21</a>、<a href="https://github.com/JosssphZhou/poki/pull/22">#22</a>），随后在 <a href="https://github.com/JosssphZhou/poki/pull/37">#37</a> 中让 Agent 复用操作后已读取的屏幕。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=240" width="120" height="120" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/25">#25</a> 中报告了 iMessage 任务不会被自然语言的停止请求打断；现在 Poki 会回复任务中途的消息，并提示使用 /stop。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=240" width="120" height="120" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/27">#27</a> 和 <a href="https://github.com/JosssphZhou/poki/issues/28">#28</a> 中复现了两个 Agent 缺陷，随后合并了七项修复和测试修整，从已取消的输入锁（<a href="https://github.com/JosssphZhou/poki/pull/102">#102</a>）到无效的触控坐标（<a href="https://github.com/JosssphZhou/poki/pull/136">#136</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=240" width="120" height="120" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/34">#34</a> 中修复了 iPhone 局域网地址变化后 RemotePairing 连接失效的问题（<a href="https://github.com/JosssphZhou/poki/issues/30">#30</a>）；真机重连只用了 768 毫秒。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=240" width="120" height="120" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/35">#35</a> 和 <a href="https://github.com/JosssphZhou/poki/issues/40">#40</a> 中实地测试了 iPhone 应用，覆盖蜂窝网络和 Windows，促成了首次设置需要 Wi-Fi 的说明（<a href="https://github.com/JosssphZhou/poki/issues/138">#138</a>）；还报告了 <a href="https://github.com/JosssphZhou/poki/issues/162">#162</a>。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=240" width="120" height="120" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/39">#39</a> 中修复了 Windows 主机经 RemotePairing 连接时每次点按都失败的问题；修复后 5 次点按全部成功。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=240" width="120" height="120" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/42">#42</a> 中通过 Tailscale 在真机上做了一次保险条款核对；这份报告推动了更清晰的 USB 报错，以及按会话切换连接方式。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=240" width="120" height="120" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a><br />录制了 Poki 操作 iPhone 真机的演示视频，让新访客在安装之前就能看到它能做什么。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=240" width="120" height="120" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/68">#68</a> 中把 OpenCode Go 加为 iPhone 应用的模型账号，带独立的钥匙串凭据和独立的模型选择。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=240" width="120" height="120" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/69">#69</a> 中给出了 Runner 空闲约 25 分钟后配对失败的完整时间线；设置页现在会指向回环和配对检查（<a href="https://github.com/JosssphZhou/poki/issues/70">#70</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=240" width="120" height="120" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a><br />让批量调用在设备不明确时给出提示而不是崩溃（<a href="https://github.com/JosssphZhou/poki/pull/74">#74</a>），并新增 POKI_MCP_DEVICE（<a href="https://github.com/JosssphZhou/poki/pull/75">#75</a>）和可选的按任务审批（<a href="https://github.com/JosssphZhou/poki/pull/77">#77</a>）。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=240" width="120" height="120" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a><br />修复配对设置把人带到错误设置页面的问题，开发者模式和 UI 自动化步骤现在会打开正确的页面（<a href="https://github.com/JosssphZhou/poki/pull/137">#137</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=240" width="120" height="120" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/139">#139</a> 中修复读屏超过调用期限的问题，并为持续变慢的 Runner 响应补了回归测试。</td>
    </tr>
  </tbody>
</table>
<!-- CORE-CONTRIBUTORS:END -->

## 特别贡献者

<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=240" width="120" height="120" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a><br />提交了一整套 0.4.0 改版设计，涵盖对话、实时活动、设置和首次运行（<a href="https://github.com/JosssphZhou/poki/pull/250">#250</a>、<a href="https://github.com/JosssphZhou/poki/pull/256">#256</a> 至 <a href="https://github.com/JosssphZhou/poki/pull/268">#268</a>），这些设计塑造了新界面的方向。</td>
    </tr>
  </tbody>
</table>


## 感谢墙

感谢每一位提交过 Issue 或 Pull Request 的朋友，你们的反馈与修复让 Poki 变得更好。

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

## Poki MCP (早期电脑连接方式，不再更新)

Poki MCP 是早期的电脑端连接方式，现已停止更新。Mac 上的 Claude Code 或 Codex 等智能体可通过它控制 iPhone 或 iOS 模拟器，Poki Agent 则提供终端、iMessage 和 Telegram 渠道。这里保留给已有用户和继续开发的人；要使用持续维护的版本，请[安装 iPhone App](#在-iphone-上安装-poki)。

**让 agent 帮你安装。** 把这段发给你的 agent：

```text
安装 https://github.com/JosssphZhou/poki，按根目录 AGENTS.md 配好 MCP 和使用技能，遇到必须由我操作的步骤就停下来告诉我。
```

**Poki MCP。** 已经在用 Claude Code、Codex 或其他 MCP 客户端？接入 Poki MCP，直接用你自己的订阅，不需要另外登录模型账号。

启动服务并保持运行：

```sh
git clone https://github.com/JosssphZhou/poki.git
cd poki
./bin/setup
npm start
```

Poki MCP 从源码构建，因此需要 macOS 15 及以上、完整版 Xcode、Rust、Node.js 24+、Python 3 和 ffmpeg。Poki App 不需要 Xcode。`./bin/setup` 检查缺失依赖，首次构建需要几分钟。

Poki 面向 macOS。Linux 用户详见社区移植版 [poki-for-linux](https://github.com/carrotciallo/poki-for-linux)（[#16](https://github.com/JosssphZhou/poki/issues/16)），它在本仓库之外维护。

Poki MCP on Windows：社区移植版 [scy7796/poki-for-windows](https://github.com/scy7796/poki-for-windows)（由其作者维护，我们未测试）。

Poki MCP 的发布标签为 `vX.Y.Z`，iPhone App 的 `app-` 发布不包含这个安装包。

### macOS arm64 预编译安装包

从版本发布页下载 [`poki-v0.1.1-macos-arm64.tar.gz`](https://github.com/JosssphZhou/poki/releases/tag/v0.1.1)，然后运行：

```sh
tar -xzf poki-v0.1.1-macos-arm64.tar.gz
cd poki-v0.1.1
npm ci --no-audit --no-fund
npm start
```

安装包包含原生桥接和 idevice 工具，无需安装 Rust 或运行 `./bin/setup`。仍需 Apple Silicon Mac、完整版 Xcode、Node.js 24+、Python 3 和 ffmpeg。MCP 客户端注册和可选 Agent 安装按下文操作。

在同一目录下打开另一个终端，注册 MCP 服务：

```sh
claude mcp add --scope user poki-mcp -- node "$PWD/src/stdio.mjs"   # Claude Code
codex mcp add poki-mcp -- node "$PWD/src/stdio.mjs"                 # Codex
```

**Poki Agent。** 如果要使用 Poki 独立终端智能体或消息渠道，保持 `npm start` 运行，在同一目录下打开另一个终端。安装智能体，将命令加入当前终端的路径，再登录模型账号：

```sh
npm ci --prefix agent
export PATH="$PWD/bin:$PATH"
poki login
poki status
```

Poki Agent 默认使用 GPT-6.1 Terra（`gpt-6.1-terra`），推理强度为 low。建议保留这一配置，它是我们在手机任务中测试过的最快配置。可通过 `POKI_AGENT_MODEL` 更换模型，详见[运行 Poki Agent](agent/README.md)。

如果连接 iPhone 真机，请先通过 USB 与 Mac 配对。详见[真机配置指南](docs/physical-iphone.md)。

`./bin/poki update` 仍会拉取最新 main 并重新构建。重启步骤和可选更新检查见 [Update](AGENTS.md#update)。

### 使用 Poki Agent 试跑任务

Poki Agent 会自动选择唯一连接的 iPhone。连接多台设备时，加上 `--device '<device UUID>'` 指定设备。

```sh
node bin/call.mjs list_devices   # 查设备 UUID
poki "Search esp32 in Chrome and summarize the top result"
```

> **注意：** Poki 操作的是真实手机，如果你让它发消息或付款，它会直接执行；屏幕内容也会发送给你配置的模型服务。

越用越快：Poki Agent 会记住跑过的任务，再次执行同款任务时速度更快。

**消息渠道：** 配置获授权的渠道后，运行 `poki imessage` 或 [`poki telegram`](agent/README.md#telegram)。详见[运行 Poki Agent](agent/README.md)。

**MCP 客户端：** Claude Code、Codex，以及任何支持 `mcpServers` JSON 配置的客户端。

目前仅在中文界面的 iPhone 上验证过真机支持。真机仅支持竖屏，不支持 App 容器导出和直接打开设置子页面。详见[验证记录与已知限制](docs/verification.md)。

## 免责声明

Poki 是独立的开源项目，与 Apple、OpenAI 以及它所操作的任何应用或网站的开发者均无关联，也未获得其认可。iPhone 是 Apple Inc. 的商标。

自动操作第三方应用和网站可能违反其服务条款，请自行判断是否在相应服务上使用 Poki。Poki 在你的设备和账号上执行的操作由你负责，包括它发送的消息、作出的更改，以及由此导致的账号限制。

Poki 按「原样」提供，不附带任何担保，具体以 AGPL-3.0 许可证为准。

如有歧义，以英文版为准。

## 开源许可

Poki 的代码基于 [AGPL-3.0-only 许可证](LICENSE)开源。

Poki 小熊、应用图标和 Poki 的其他美术作品不在这一许可证范围内。你可以用截图介绍 Poki；分叉版本需要使用自己的名称和美术。详见 [BRAND.md](BRAND.md)。

Copyright (c) 2026 Joseph Zhou (周瑟夫) and contributors。开源依赖项和第三方素材保留各自的许可证，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。如需参与贡献，请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 致谢

<p align="center">
  <img src="docs/images/acknowledgments.png" width="860" alt="开源致谢：pi、idevice、idb、BlueBubbles、Hermes Agent、MCP SDK、sharp 与 FFmpeg"><br>
  <sub>开源致谢：<a href="https://github.com/earendil-works/pi">pi</a> | <a href="https://github.com/jkcoxson/idevice">idevice</a> | <a href="https://github.com/facebook/idb">idb</a> | <a href="https://github.com/BlueBubblesApp/bluebubbles-server">BlueBubbles</a> | <a href="https://github.com/NousResearch/hermes-agent">Hermes Agent</a> | <a href="https://github.com/modelcontextprotocol/typescript-sdk">MCP SDK</a> | <a href="https://github.com/lovell/sharp">sharp</a> | <a href="https://github.com/FFmpeg/FFmpeg">FFmpeg</a></sub>
</p>
