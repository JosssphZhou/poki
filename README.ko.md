<p align="center">
  <img src="docs/images/poki-icon.png" width="72" height="72" alt="Poki icon">
</p>

<h1 align="center">Poki는 당신의 iPhone을 당신처럼 씁니다</h1>

<p align="center">
  <img src="docs/images/poki-home.gif" width="720" alt="Poki 공식 웹사이트 홈페이지 애니메이션">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | <a href="README.zh-TW.md">繁體中文</a> | <a href="README.ja.md">日本語</a> | 한국어 | <a href="README.es.md">Español</a><br>
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

Poki는 사람이 하듯 iPhone을 조작하는 에이전트입니다. 화면을 읽고 실제 앱에서 탭, 입력, 스크롤을 수행하며 민감한 작업 전에 확인을 요청합니다.

**Poki 앱**은 iPhone 자체에서 실행됩니다. 채팅으로 작업을 요청하면 다른 앱에서 수행합니다. Mac 또는 Windows PC로 한 번 설치한 뒤에는 컴퓨터 없이 작업을 실행할 수 있습니다.

Mac의 에이전트로 iPhone을 조작하던 기존 Poki MCP는 더 이상 업데이트하지 않습니다. 기존 사용자를 위한 설명은 페이지 뒤쪽의 [Poki MCP](#poki-mcp)에 남겨 두었습니다.

버전별 변경 사항은 [CHANGELOG.md](CHANGELOG.md)를 참고하세요.

## iPhone에 Poki 설치하기

처음 설치할 때는 Mac 또는 Windows PC가 필요합니다.

- **Mac**에서는 에이전트에 설치를 요청하거나 macOS용 Poki Setup을 내려받아 화면 안내를 따르세요.
- **Windows**에서는 Windows용 Poki Setup을 사용하세요. USB로 연결한 iPhone을 인식하려면 먼저 Apple Devices 또는 iTunes를 설치해야 합니다. 에이전트는 Poki Setup의 내장 명령줄 도구도 사용할 수 있습니다.
- **설치 후**에는 iPhone만으로 작업을 실행합니다. 무료 Apple 계정의 서명은 7일 동안 유효하며, 컴퓨터에서 Poki Setup을 열어 두면 갱신할 수 있습니다. [자주 묻는 질문](#자주-묻는-질문)을 참고하세요.

### 에이전트로 설치하기（권장）

Claude Code나 Codex 등에 다음과 같이 요청하세요.

```text
https://github.com/JosssphZhou/poki 에서 내 iPhone에 Poki를 설치해 주세요.
```

에이전트는 [install-poki 스킬](skills/install-poki/SKILL.md)에 따라 `bin/install-iphone.mjs`로 자동화 가능한 단계를 진행합니다. 본인만 할 수 있는 단계는 직접 수행하세요. Mac의 Poki Setup 창에서 Apple 계정을 입력하고, iPhone에서 신뢰, 개발자 모드, 개발자 신뢰를 설정한 뒤 Poki를 엽니다. 처음 열면 Automation Mode를 요청하므로 Continue를 누르고 iPhone 암호를 입력하세요. 취소했다면 Poki를 다시 열어 요청할 수 있습니다. 에이전트가 필요한 작업을 그때마다 한 문장으로 안내합니다. 무료 Apple 계정도 사용할 수 있습니다.

설치기는 기본적으로 Alpha 채널을 사용합니다. Beta 등 다른 채널은 에이전트에 지정하세요. 빌드는 Alpha에 먼저 배포되고, 추가 테스트 후 같은 빌드가 Beta로 이동합니다.

Node.js 24가 없거나 Windows를 사용하나요? Poki Setup을 먼저 설치하면 같은 요청으로 내장 명령줄 도구를 사용할 수 있습니다. Mac의 Poki > Copy Prompt for Your Agent 또는 Windows의 Settings > Use an agent에서도 요청 문구를 복사할 수 있습니다.

GitHub 릴리스 목록을 읽을 때 403이나 429가 나오면 같은 네트워크에서 공유하는 익명 요청 한도를 다 쓴 경우가 많습니다. 다른 네트워크나 프록시 노드에서 다시 시도하거나 한 시간 기다리세요.

### Poki Setup으로 설치하기

직접 설치하려면 [Alpha 릴리스](https://github.com/JosssphZhou/poki/releases/tag/app-alpha-latest)에서 macOS용 `.dmg` 또는 Windows용 `.exe`를 내려받아 안내를 따르세요. Windows 버전은 [ZhehanZhang](https://github.com/ZhehanZhang)의 기여로 만들어졌습니다. Beta에도 같은 설치 파일이 있습니다. 설정에서 채널을 선택하기 전에는 최신 Stable을, Stable이 없으면 Beta를 설치합니다. 자세한 과정은 [Poki Setup](desktop/README.md)을 참고하세요.

### 준비할 것

| 항목 | 요구 사항 |
| --- | --- |
| iPhone | iOS 18 이상, iPhone XS, XR, SE 2세대 또는 이후 기종. 실제 기기 테스트는 iOS 27에서 진행했습니다. |
| 컴퓨터 | macOS 14 이상인 Mac 또는 Apple Devices나 iTunes가 설치된 x64 Windows PC. Mac에서 에이전트로 설치하려면 Node.js 24 이상도 필요합니다. Xcode는 필요 없습니다. |
| 케이블과 계정 | USB 데이터 케이블과 Apple 계정. 무료 계정 서명은 7일 동안 유효하며 Poki Setup으로 갱신할 수 있습니다. |
| 연결 | 10.7.0.1을 iPhone 자체로 연결하는 VPN 앱. App Store의 무료 LocalDevVPN이나 Poki 안내에 따라 설정한 Karing, Shadowrocket을 사용할 수 있습니다. |
| 모델 계정 | 본인 계정이 필요합니다. ChatGPT Plus 또는 Pro 로그인이 가장 간단합니다. Anthropic, OpenAI, Gemini, DeepSeek, OpenRouter의 API 키 또는 OpenAI 호환 서버도 사용할 수 있습니다. Claude 구독으로는 로그인할 수 없으므로 Anthropic API 키를 사용하세요. |

iOS 27 이상에서는 네이티브 서비스로 조작합니다. iOS 18부터 26까지는 XCTest 세션을 사용하므로 개발자 설정에서 UI Automation을 켜야 합니다. iPadOS 18 이상인 iPad에도 설치할 수 있습니다.

### 자주 묻는 질문

**Windows에서 설치할 수 있나요?** 네. Mac 버전과 마찬가지로 설치, 페어링, 서명 갱신이 가능합니다. 먼저 Apple Devices 또는 iTunes를 설치하세요. [Poki Setup](desktop/README.md)을 참고하세요.

**설치 후에도 컴퓨터가 필요한가요?** 작업은 iPhone에서 독립적으로 실행됩니다. 무료 계정의 서명을 매주 갱신하려면 컴퓨터에서 Poki Setup을 열어 두거나, iPhone의 Poki에서 Apple 계정에 로그인해 자체 갱신을 사용하세요. 0.4.0에서는 첫 로그인이 실패할 수 있습니다. [알려진 문제](#알려진-문제)와 [계속 실행할 항목](skills/install-poki/SKILL.md#what-to-keep-running)을 참고하세요.

**무료 계정과 7일 제한은 무엇인가요?** 무료 계정도 사용할 수 있지만 서명은 7일 뒤 만료됩니다. 컴퓨터가 깨어 있고 iPhone에 연결할 수 있으며 Poki Setup이 열려 있으면 6시간마다 확인하고, 남은 기간이 2일 이하일 때 갱신합니다. 갱신하지 않으면 앱이 열리지 않습니다. Poki는 마지막 2일 동안 경고합니다. [무료 계정 안내](skills/install-poki/SKILL.md#no-paid-developer-account)를 참고하세요.

**어떤 iPhone과 iOS가 필요한가요?** iOS 18 이상인 iPhone XS, XR, SE 2세대 또는 이후 기종과 iPadOS 18 이상인 iPad입니다. 실제 기기 검증은 iOS 27에서만 진행했습니다. iOS 18부터 26까지의 별도 조작 경로는 실제 iPhone에서 아직 검증하지 않았습니다. [검증 기록](docs/verification.md)을 참고하세요.

**모델 계정이 필요한가요?** 네. ChatGPT Plus 또는 Pro, 위 서비스의 API 키, 본인의 OpenAI 호환 서버를 사용할 수 있습니다. 음성 대화에는 음성 모델 키도 필요합니다. [준비할 것](#준비할-것)을 참고하세요.

**중국 본토 등의 네트워크에서 업데이트가 보이지 않아요.** 업데이트는 GitHub에서 확인합니다. 연결할 수 없거나 403, 429 제한이 발생하면 네트워크나 프록시 노드를 바꾸거나, 컴퓨터의 Poki Setup에서 Renew를 사용하세요. [Poki 업데이트](#poki-업데이트)를 참고하세요.

**휴대폰의 내용을 바꾸나요? 먼저 확인하나요?** 메시지 전송을 포함해 실제 앱에서 요청한 작업을 수행합니다. 화면 내용은 설정한 모델 서비스로 전송됩니다. 결제, 삭제, Wallet 작업에는 항상 확인이 필요합니다. 메시지 전송이나 암호 입력 등은 Settings > Approvals에서 확인 방식이나 확인 여부를 선택할 수 있습니다. [알려진 문제](#알려진-문제)를 참고하세요.

## Poki 업데이트

- **iPhone**에서는 0.4.0의 Settings > Connection > Signing & Updates 또는 0.3.1 설정의 Signing 페이지를 여세요. 새 빌드가 있으면 다운로드 및 설치가 표시됩니다. 로그인을 요구하면 컴퓨터에서 설치할 때 사용한 Apple 계정으로 로그인하거나 컴퓨터에서 업데이트하세요.
- **컴퓨터**의 Poki Setup에서 Renew를 누르면 선택한 채널의 최신 빌드를 기존 앱 위에 설치합니다. Mac에서는 에이전트에 업데이트를 요청할 수도 있습니다. install-poki 스킬의 업데이트 절차는 버전과 서명 정보를 먼저 확인합니다.
- “Finishing the update”에서 멈추면 앱 전환기에서 Poki를 닫고 다시 열어 버전을 확인하세요. 버전이 바뀌지 않았으면 컴퓨터의 Poki Setup으로 업데이트하세요. 업데이트 문제를 해결하려고 Poki를 삭제하지 마세요. 대화도 삭제됩니다.

채널과 Alpha에서 Beta로 옮기는 과정은 [릴리스 채널](docs/release-channels.md)을 참고하세요.

## 알려진 문제

- 실제 iPhone을 조작합니다. 메시지 전송이나 결제를 요청하면 실행하며, 화면 내용은 설정한 모델 서비스로 전송됩니다.
- 0.4.0에서 iPhone의 첫 Apple 계정 로그인 시 Mac이 필요하다는 오류가 날 수 있습니다. Apple이 기존 Mac 로그인 식별 정보를 더 이상 허용하지 않기 때문입니다. 이미 로그인했다면 휴대폰에서 평소처럼 업데이트할 수 있습니다. 그렇지 않으면 컴퓨터의 Poki Setup으로 갱신하고 업데이트하세요.
- 실제 기기는 중국어 인터페이스와 세로 방향에서만 검증했습니다. 가로 방향은 지원하지 않습니다.
- iOS 27 미만인 실제 기기와 iPad는 테스트하지 않았습니다. 오래되거나 작은 iPhone에서는 3D 곰과 홈 애니메이션으로 발열이나 지연이 늘 수 있습니다. 저전력 모드와 동작 줄이기를 켜면 곰의 정지 화면을 사용합니다.
- 무료 계정 서명은 7일 동안 유효합니다. 컴퓨터의 Poki Setup이 iPhone에 연결할 수 있게 하거나 만료 전에 수동 갱신하세요.
- 공유 네트워크에서는 GitHub가 403이나 429를 반환할 수 있습니다. 네트워크나 프록시 노드를 바꾸거나 한 시간 기다리세요.

추가 제한과 테스트 결과는 [검증 기록](docs/verification.md)을 참고하세요.

## 작업 실행해 보기

Poki에서 “내일 날씨를 확인하고 우산이 필요한지 알려 줘”라고 입력하거나 홈의 앱을 눌러 시작하세요. 화면의 앱에서 작업하고 Dynamic Island와 잠금 화면에 단계를 표시하며 민감한 작업 전에 확인합니다.

앱을 먼저 열지 않아도 동작 버튼을 길게 눌러 말하거나, 단축어와 Siri의 Talk to Poki, Send Task to Poki를 사용할 수 있습니다. 이 방식으로 보낸 작업은 알림으로 답합니다.

> **주의:** Poki는 실제 iPhone을 조작합니다. 메시지 전송이나 결제를 요청하면 실행합니다.

## 로드맵

방향만 제시하며 날짜는 약속하지 않습니다.

**0.4.0 Beta까지 완료**

- 설정 후 Mac 없이 실행되는 iPhone 앱, 잠금 화면과 Dynamic Island의 승인.
- Mac 또는 Windows의 Poki Setup이나 에이전트로 설치. Xcode가 필요 없고 무료 Apple 계정도 사용 가능.
- iOS 27 이상의 네이티브 조작.
- Poki MCP, Poki Agent, iMessage, Telegram, 학습한 작업 경로 재실행. Poki MCP는 현재 상태로 유지하며 업데이트하지 않음.
- LAN과 Tailscale 원격 연결.
- 3D 곰 홈 화면, 음성 대화, 동작 버튼, 보관, 다크 모드를 포함한 0.4.0 인터페이스.

**다음 단계**

- 자체 다운로드 서버를 사용하고 GitHub는 예비로 유지.
- 업데이트 채널을 하나로 통합.
- 음성은 듣기, 말하기, 보기만 맡고 휴대폰 조작은 현재 작업용 텍스트 모델에 전달.
- 인터페이스 언어 추가.

**이후**

- 더 많은 iPhone, iOS 버전, 화면 언어에서 실제 기기 검증.
- 모델 제공자 추가.

## 문서

| 주제 | 문서 |
| --- | --- |
| 버전별 변경 | [CHANGELOG.md](CHANGELOG.md) |
| 에이전트로 앱 설치 | [install-poki](skills/install-poki/SKILL.md) |
| Mac 및 Windows 설치기 | [Poki Setup](desktop/README.md) |
| 채널과 빌드 승격 | [릴리스 채널](docs/release-channels.md) |
| Poki MCP 설치, 다른 클라이언트, 문제 해결（업데이트 종료） | [설치 안내](docs/install.md) |
| Poki Agent, 모델, iMessage, Telegram | [Poki Agent](agent/README.md) |
| MCP 도구 | [도구 설명](docs/tools.md) |
| 환경 변수와 세션 | [설정](docs/configuration.md) |
| USB, 개발자 모드, Wi-Fi | [실제 기기 설정](docs/physical-iphone.md) |
| 테스트, 제한, 면책 | [검증](docs/verification.md) |
| 브리지 구조 | [네이티브](native/NATIVE.md) 및 [시뮬레이터](native/simulator.md) |
| 로드맵 | [로드맵](#로드맵) |

## Star History

<a href="https://www.star-history.com/?repos=JosssphZhou%2Fpoki&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&theme=dark&legend=top-left">
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
    <img alt="Star History chart" src="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
  </picture>
</a>

## 핵심 기여자

<!-- CORE-CONTRIBUTORS:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=240" width="120" height="120" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a><br />Poki의 첫 번째 이슈 <a href="https://github.com/JosssphZhou/poki/issues/1">#1</a>을 올렸습니다. iOS 18.6.2에서 스크린샷은 되고 손쉬운 사용과 터치는 안 된다는 점을 명확히 나누어 적어 주었습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=240" width="120" height="120" alt="ZhehanZhang"/><br /><sub><b>ZhehanZhang</b></sub></a><br />Poki의 위대한 공동 창작자.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=240" width="120" height="120" alt="edge369"/><br /><sub><b>edge369</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/14">#14</a>에서 Poki를 라우터에서 실행할 수 있게 만들어 Mac이 꺼져 있어도 Telegram으로 iPhone을 조작할 수 있게 했고, <a href="https://github.com/JosssphZhou/poki/pull/15">#15</a>, <a href="https://github.com/JosssphZhou/poki/pull/17">#17</a>, <a href="https://github.com/JosssphZhou/poki/issues/19">#19</a>가 이어졌습니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=240" width="120" height="120" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/6">#6</a>에서 macOS 27.2의 usbmuxd가 iPhone을 목록에 보이지 않는 문제를 보고했습니다. 이제 Poki는 이를 분명히 알리고 도우미가 일찍 멈춘 이유도 알려 줍니다(<a href="https://github.com/JosssphZhou/poki/issues/59">#59</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=240" width="120" height="120" alt="igc110"/><br /><sub><b>igc110</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/10">#10</a>에서 실제 iPhone의 탭이 느린 원인을 찾아냈고, 이후 수정으로 탭이 약 3분의 1 빨라졌습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=240" width="120" height="120" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/16">#16</a>에서 Poki를 Linux로 포팅해 실제 iPhone에서 USB, LAN, Tailscale 연결을 검증했고, README는 이 포팅 버전을 안내합니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=240" width="120" height="120" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/18">#18</a>에서 실제 iPhone의 터치 실패 원인이 display service 누락임을 밝혀냈고, 이제 Poki는 아무것도 전송되지 않았다고 알리며 prepare-device를 안내합니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=240" width="120" height="120" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a><br />손상된 캐시 경로가 관련 없는 Agent 작업을 중단시키는 문제를 고쳤고(<a href="https://github.com/JosssphZhou/poki/issues/21">#21</a>, <a href="https://github.com/JosssphZhou/poki/pull/22">#22</a>), 이어 <a href="https://github.com/JosssphZhou/poki/pull/37">#37</a>에서 Agent가 동작 후 읽은 화면을 재사용하게 했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=240" width="120" height="120" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/25">#25</a>에서 자연어 중지 요청으로는 iMessage 작업이 멈추지 않는다고 보고했고, 이제 Poki는 작업 도중 받은 메시지에 답하며 /stop을 안내합니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=240" width="120" height="120" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/27">#27</a>과 <a href="https://github.com/JosssphZhou/poki/issues/28">#28</a>에서 Agent 버그 두 건을 재현한 뒤, 취소된 입력 잠금(<a href="https://github.com/JosssphZhou/poki/pull/102">#102</a>)부터 잘못된 터치 좌표(<a href="https://github.com/JosssphZhou/poki/pull/136">#136</a>)까지 수정과 테스트 정비 일곱 건을 병합했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=240" width="120" height="120" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a><br />iPhone의 LAN 주소가 바뀌면 끊기던 RemotePairing 연결(<a href="https://github.com/JosssphZhou/poki/issues/30">#30</a>)을 <a href="https://github.com/JosssphZhou/poki/pull/34">#34</a>에서 고쳤고, 실제 iPhone은 768ms 만에 다시 연결되었습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=240" width="120" height="120" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/35">#35</a>와 <a href="https://github.com/JosssphZhou/poki/issues/40">#40</a>에서 모바일 데이터와 Windows로 iPhone 앱을 실기기 테스트했고, 첫 설정에 Wi-Fi가 필요하다는 안내(<a href="https://github.com/JosssphZhou/poki/issues/138">#138</a>)로 이어졌습니다. <a href="https://github.com/JosssphZhou/poki/issues/162">#162</a>도 보고했습니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=240" width="120" height="120" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a><br />Windows 호스트에서 RemotePairing으로 연결할 때 탭이 매번 실패하던 문제를 <a href="https://github.com/JosssphZhou/poki/pull/39">#39</a>에서 고쳤고, 수정 후 5번 중 5번의 탭이 성공했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=240" width="120" height="120" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/42">#42</a>에서 Tailscale로 연결한 실제 iPhone으로 보험 약관을 확인했고, 이 보고가 더 알기 쉬운 USB 오류와 세션별 연결 방식 전환 작업으로 이어졌습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=240" width="120" height="120" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a><br />Poki가 실제 iPhone을 조작하는 데모 영상을 제작해, 새 방문자가 설치하기 전에 무엇을 할 수 있는지 볼 수 있게 했습니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=240" width="120" height="120" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/68">#68</a>에서 OpenCode Go를 iPhone 앱의 모델 계정으로 추가했습니다. 전용 키체인 자격 증명과 독립된 모델 선택을 갖추고 있습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=240" width="120" height="120" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/69">#69</a>에서 Runner가 약 25분 유휴 후 페어링에 실패하는 과정을 상세히 기록했습니다. 이제 Setup은 Loopback과 Pairing 확인을 안내합니다(<a href="https://github.com/JosssphZhou/poki/issues/70">#70</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=240" width="120" height="120" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a><br />배치 호출이 기기가 모호할 때 충돌하지 않고 알려 주도록 했고(<a href="https://github.com/JosssphZhou/poki/pull/74">#74</a>), POKI_MCP_DEVICE(<a href="https://github.com/JosssphZhou/poki/pull/75">#75</a>)와 작업별 선택적 승인 단계(<a href="https://github.com/JosssphZhou/poki/pull/77">#77</a>)를 추가했습니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=240" width="120" height="120" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a><br />페어링 설정이 잘못된 설정 페이지로 안내하던 문제를 고쳐, 개발자 모드와 UI 자동화 단계가 이제 올바른 페이지를 엽니다(<a href="https://github.com/JosssphZhou/poki/pull/137">#137</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=240" width="120" height="120" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/139">#139</a>에서 화면 읽기가 호출 기한을 넘기던 문제를 고쳤고, 계속 느린 Runner 응답에 대한 회귀 테스트도 추가했습니다.</td>
    </tr>
  </tbody>
</table>
<!-- CORE-CONTRIBUTORS:END -->

## 특별 기여자

<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=240" width="120" height="120" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a><br />0.4.0 개편을 위해 채팅, Live Activity, 설정, 첫 실행 화면의 전체 디자인을 제공했습니다（<a href="https://github.com/JosssphZhou/poki/pull/250">#250</a>, <a href="https://github.com/JosssphZhou/poki/pull/256">#256</a>부터 <a href="https://github.com/JosssphZhou/poki/pull/268">#268</a>）. 새 인터페이스의 방향을 만드는 데 기여했습니다.</td>
    </tr>
  </tbody>
</table>


## 고마운 분들

Issue나 Pull Request를 남겨 주신 모든 분께 감사드리며, 여러분의 제보와 수정 덕분에 Poki가 더 좋아지고 있습니다.

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

## Poki MCP (기존 컴퓨터 연결 방식, 업데이트 종료)

Poki MCP는 더 이상 업데이트하지 않는 기존 컴퓨터 연결 방식입니다. Mac의 Claude Code나 Codex로 iPhone 또는 iOS Simulator를 조작하며 Poki Agent는 터미널, iMessage, Telegram을 제공합니다. 기존 사용자와 개발자를 위해 남겨 둡니다. 계속 유지되는 버전은 [iPhone 앱](#iphone에-poki-설치하기)입니다.

**에이전트에게 설치를 맡기세요.** 아래 내용을 복사해 에이전트에게 전달하세요:

```text
https://github.com/JosssphZhou/poki 를 루트의 AGENTS.md에 따라 MCP 스킬까지 포함해 설치해 줘. 내가 직접 해야 하는 단계가 나오면 그때마다 멈춰 줘.
```

**Poki MCP.** 이미 Claude Code, Codex 또는 다른 MCP 클라이언트를 쓰고 있나요? Poki MCP를 연결하면 사용 중인 구독을 그대로 쓸 수 있습니다. 별도의 모델 계정은 필요 없습니다.

서버를 시작하고 계속 실행해 두세요:

```sh
git clone https://github.com/JosssphZhou/poki.git
cd poki
./bin/setup
npm start
```

Poki MCP는 소스에서 빌드하므로 macOS 15 이상, 전체 Xcode, Rust, Node.js 24+, Python 3, ffmpeg가 필요합니다. Poki 앱에는 Xcode가 필요 없습니다. `./bin/setup`은 누락된 의존성을 확인하며 첫 빌드에는 몇 분이 걸립니다.

Poki는 macOS용입니다. Linux에서는 커뮤니티 포팅 버전인 [poki-for-linux](https://github.com/carrotciallo/poki-for-linux)([#16](https://github.com/JosssphZhou/poki/issues/16))를 참고하세요. 이 저장소와 별도로 관리됩니다.

Poki MCP on Windows: 커뮤니티 포팅 버전 [scy7796/poki-for-windows](https://github.com/scy7796/poki-for-windows)(작성자가 관리하며, 저희는 테스트하지 않았습니다).

Poki MCP 릴리스 태그는 `vX.Y.Z`입니다. iPhone 앱의 `app-` 릴리스에는 이 패키지가 없습니다.

### 사전 빌드된 macOS arm64 패키지

릴리스에서 [`poki-v0.1.1-macos-arm64.tar.gz`](https://github.com/JosssphZhou/poki/releases/tag/v0.1.1)를 내려받아 실행하세요:

```sh
tar -xzf poki-v0.1.1-macos-arm64.tar.gz
cd poki-v0.1.1
npm ci --no-audit --no-fund
npm start
```

패키지에는 네이티브 브리지와 idevice 도구가 포함되어 있습니다. Rust나 `./bin/setup`은 필요 없습니다. 다만 Apple Silicon macOS, 전체 버전 Xcode, Node.js 24+, Python 3, ffmpeg는 여전히 필요합니다. MCP 클라이언트 등록과 선택 사항인 Agent 설치는 아래를 참고하세요.

같은 디렉터리에서 다른 터미널을 열고 MCP 서버를 등록하세요:

```sh
claude mcp add --scope user poki-mcp -- node "$PWD/src/stdio.mjs"   # Claude Code
codex mcp add poki-mcp -- node "$PWD/src/stdio.mjs"                 # Codex
```

**Poki Agent.** Poki의 독립형 터미널 에이전트나 메시징 채널을 쓰려면 `npm start`를 계속 실행한 채 같은 디렉터리에서 다른 터미널을 여세요. 에이전트를 설치하고, 명령어를 이 터미널의 PATH에 추가한 뒤 로그인하세요:

```sh
npm ci --prefix agent
export PATH="$PWD/bin:$PATH"
poki login
poki status
```

Poki Agent는 기본적으로 GPT-6.1 Terra(`gpt-6.1-terra`)를 low 추론 강도로 사용합니다. 휴대폰 작업에서 저희가 테스트한 가장 빠른 설정이므로 그대로 사용하는 것을 권장합니다. `POKI_AGENT_MODEL`로 모델을 변경할 수 있습니다. [Poki Agent 실행](agent/README.md)을 참고하세요.

실제 iPhone을 쓰려면 먼저 USB로 Mac과 페어링하세요. [실제 iPhone 설정](docs/physical-iphone.md)을 참고하세요.

`./bin/poki update`는 여전히 최신 main을 가져와 다시 빌드합니다. 재시작과 선택적 업데이트 확인은 [Update](AGENTS.md#update)를 참고하세요.

### Poki Agent로 작업 실행하기

Poki Agent에서는 연결된 iPhone이 한 대면 자동으로 선택됩니다. 기기가 여러 대면 `--device '<device UUID>'`를 추가하세요.

```sh
node bin/call.mjs list_devices   # 기기 UUID 확인
poki "Search esp32 in Chrome and summarize the top result"
```

> **주의:** Poki는 실제 iPhone을 조작합니다. 메시지를 보내거나 결제하라고 하면 그대로 실행합니다. 화면 내용은 설정한 모델 서비스로 전송됩니다.

쓸수록 빨라집니다: Poki Agent는 지난 작업을 기억해 반복 실행할 때 더 빠르게 처리합니다.

**채널:** 승인된 채널을 설정한 뒤 `poki imessage` 또는 [`poki telegram`](agent/README.md#telegram)으로 시작하세요. 설정 방법은 [Poki Agent](agent/README.md)를 참고하세요.

**MCP 클라이언트:** Claude Code, Codex, 그리고 `mcpServers` JSON을 지원하는 모든 클라이언트.

실제 iPhone 지원은 중국어 인터페이스를 쓰는 iPhone에서만 검증되었습니다. 실제 기기는 세로 방향만 지원합니다. 앱 컨테이너 내보내기와 설정 하위 페이지로 바로 가는 링크는 사용할 수 없습니다. [검증 결과와 알려진 제한](docs/verification.md)을 참고하세요.

## 면책 조항

Poki는 독립적인 오픈소스 프로젝트입니다. Apple, OpenAI 또는 Poki가 조작하는 앱이나 웹사이트의 제작사와 제휴 관계가 없으며, 이들의 보증을 받지 않았습니다. iPhone은 Apple Inc.의 상표입니다.

타사 앱과 웹사이트를 자동으로 조작하면 해당 서비스 약관을 위반할 수 있습니다. 특정 서비스에서 Poki를 쓸지는 직접 판단하세요. 사용자의 기기와 계정에서 Poki가 하는 일(보낸 메시지, 변경한 내용, 그 결과로 생긴 계정 제한 포함)에 대한 책임은 사용자에게 있습니다.

Poki는 AGPL-3.0 라이선스에 명시된 대로 어떠한 보증도 없이 "있는 그대로" 제공됩니다.

해석에 차이가 있는 경우 영어판을 기준으로 합니다.

## 라이선스

Poki의 코드는 [AGPL-3.0-only 라이선스](LICENSE)에 따라 공개된 오픈소스입니다.

Poki 곰, 앱 아이콘과 Poki의 다른 아트워크는 이 라이선스에 포함되지 않습니다. Poki를 소개할 때 스크린샷은 사용할 수 있지만, 포크는 자체 이름과 아트워크를 사용해야 합니다. 자세한 내용은 [BRAND.md](BRAND.md)를 참고하세요.

Copyright (c) 2026 Joseph Zhou (周瑟夫) and contributors. 오픈소스 의존성과 서드파티 에셋은 각자의 라이선스를 따릅니다. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 참고하세요. 기여하려면 [CONTRIBUTING.md](CONTRIBUTING.md)를 읽어 보세요.

## 감사의 말

<p align="center">
  <img src="docs/images/acknowledgments.png" width="860" alt="오픈소스 기반: pi, idevice, idb, BlueBubbles, Hermes Agent, MCP SDK, sharp, FFmpeg"><br>
  <sub>오픈소스 감사의 말: <a href="https://github.com/earendil-works/pi">pi</a> | <a href="https://github.com/jkcoxson/idevice">idevice</a> | <a href="https://github.com/facebook/idb">idb</a> | <a href="https://github.com/BlueBubblesApp/bluebubbles-server">BlueBubbles</a> | <a href="https://github.com/NousResearch/hermes-agent">Hermes Agent</a> | <a href="https://github.com/modelcontextprotocol/typescript-sdk">MCP SDK</a> | <a href="https://github.com/lovell/sharp">sharp</a> | <a href="https://github.com/FFmpeg/FFmpeg">FFmpeg</a></sub>
</p>
