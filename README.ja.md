<p align="center">
  <img src="docs/images/poki-icon.png" width="72" height="72" alt="Poki icon">
</p>

<h1 align="center">Poki は、あなたと同じように iPhone を使う</h1>

<p align="center">
  <img src="docs/images/poki-home.gif" width="720" alt="Poki 公式サイトのトップページのアニメーション">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | <a href="README.zh-TW.md">繁體中文</a> | 日本語 | <a href="README.ko.md">한국어</a> | <a href="README.es.md">Español</a><br>
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

Poki は、人と同じように iPhone を操作するエージェントです。画面を読み取り、実際のアプリでタップ、入力、スクロールを行い、慎重な扱いが必要な操作の前に確認します。

**Poki アプリ**は iPhone 自体で動きます。チャットで依頼すると、ほかのアプリで作業します。最初に Mac または Windows PC からインストールすれば、タスクの実行にパソコンは必要ありません。

Mac のエージェントから iPhone を操作する従来の Poki MCP は、更新を終了しました。既存ユーザー向けに、ページ後半の [Poki MCP](#poki-mcp) に説明を残しています。

各バージョンの変更内容は [CHANGELOG.md](CHANGELOG.md) をご覧ください。

## iPhone に Poki をインストール

初回のインストールには Mac または Windows PC が必要です。

- **Mac** では、エージェントに依頼するか、macOS 版 Poki Setup をダウンロードして画面に従ってください。
- **Windows** では、Windows 版 Poki Setup を使ってください。USB 接続の iPhone を認識できるよう、先に Apple Devices または iTunes をインストールします。エージェントは Poki Setup 内蔵のコマンドラインツールも使えます。
- **インストール後**は iPhone だけでタスクを実行できます。無料 Apple Account の署名は 7 日間有効です。パソコンで Poki Setup を開いておくと更新できます。[よくある質問](#よくある質問)をご覧ください。

### エージェントに依頼（推奨）

Claude Code や Codex などに次のように伝えてください。

```text
https://github.com/JosssphZhou/poki から私の iPhone に Poki をインストールしてください。
```

エージェントは [install-poki スキル](skills/install-poki/SKILL.md)に従い、`bin/install-iphone.mjs` で自動化できる手順を進めます。本人の操作が必要な部分だけ行ってください。Mac の Poki Setup で Apple Account を入力し、iPhone で「信頼」、デベロッパモード、開発元の信頼を設定して Poki を開きます。初回は Automation Mode の確認で Continue をタップし、iPhone のパスコードを入力します。キャンセルした場合は Poki を開き直すと再度確認できます。エージェントは必要な操作をその都度一文で案内します。無料 Apple Account も使えます。

既定のインストール先は Alpha チャンネルです。Beta などを希望する場合はエージェントに指定してください。ビルドはまず Alpha に入り、追加のテスト後に同じビルドが Beta に進みます。

Node.js 24 がない場合や Windows の場合は、先に Poki Setup をインストールしてください。同じ依頼で内蔵のコマンドラインツールを使えます。依頼文は Mac の Poki > Copy Prompt for Your Agent、Windows の Settings > Use an agent からもコピーできます。

GitHub のリリース一覧取得で 403 または 429 が出る場合、同じネットワークで共有する匿名リクエストの時間枠を使い切っていることがあります。別のネットワークやプロキシ接続先で再試行するか、1 時間待ってください。

### Poki Setup を使う

自分で操作する場合は、[Alpha リリース](https://github.com/JosssphZhou/poki/releases/tag/app-alpha-latest)から macOS 用 `.dmg` または Windows 用 `.exe` をダウンロードしてください。Windows 版は [ZhehanZhang](https://github.com/ZhehanZhang) による貢献です。Beta にも同じインストーラがあります。設定でチャンネルを選ぶまでは最新の Stable を、Stable がなければ Beta をインストールします。詳しい手順は [Poki Setup](desktop/README.md) をご覧ください。

### 必要なもの

| 項目 | 要件 |
| --- | --- |
| iPhone | iOS 18 以降、iPhone XS、XR、SE（第 2 世代）以降。実機テストは iOS 27 で実施しています。 |
| パソコン | macOS 14 以降の Mac、または Apple Devices か iTunes を入れた x64 Windows PC。Mac のエージェントによるインストールには Node.js 24 以降も必要です。Xcode は不要です。 |
| ケーブルとアカウント | USB データケーブルと Apple Account。無料アカウントの署名は 7 日間有効で、Poki Setup が更新できます。 |
| 接続 | 10.7.0.1 を iPhone 自身に戻す VPN アプリ。App Store の無料 LocalDevVPN、または Poki の案内に従って設定した Karing や Shadowrocket を使えます。 |
| モデルアカウント | 自分のアカウントが必要です。ChatGPT Plus または Pro でのログインが簡単です。Anthropic、OpenAI、Gemini、DeepSeek、OpenRouter の API キーや、OpenAI 互換サーバーも使えます。Claude のサブスクリプションではログインできないため、Anthropic API キーを使ってください。 |

iOS 27 以降ではネイティブサービスで操作します。iOS 18 から 26 では XCTest セッションを使うため、開発者設定の UI Automation を有効にする必要があります。iPadOS 18 以降の iPad にもインストールできます。

### よくある質問

**Windows からインストールできますか？** はい。Mac 版と同様にインストール、ペアリング、再署名ができます。先に Apple Devices または iTunes を入れてください。[Poki Setup](desktop/README.md)を参照してください。

**インストール後もパソコンは必要ですか？** タスクは iPhone 単体で動きます。無料 Apple Account の署名を毎週更新するにはパソコンの Poki Setup を開いておくか、iPhone の Poki で Apple Account にログインして自動更新を使います。0.4.0 では初回ログインが失敗する場合があります。[既知の問題](#既知の問題)と[起動しておくもの](skills/install-poki/SKILL.md#what-to-keep-running)を参照してください。

**無料アカウントと 7 日の制限は？** 無料アカウントも使えますが、署名は 7 日間で失効します。パソコンがスリープせず、iPhone に接続でき、Poki Setup が開いていれば、6 時間ごとに確認し、残り 2 日以内になると更新します。更新しなければアプリを開けなくなります。Poki は最後の 2 日間に警告します。[無料アカウントの説明](skills/install-poki/SKILL.md#no-paid-developer-account)をご覧ください。

**どの iPhone と iOS が必要ですか？** iOS 18 以降の iPhone XS、XR、SE（第 2 世代）以降、または iPadOS 18 以降の iPad です。実機検証は iOS 27 のみです。iOS 18 から 26 の別の操作経路は実機未検証です。[検証記録](docs/verification.md)をご覧ください。

**モデルのアカウントは必要ですか？** はい。ChatGPT Plus/Pro、各社の API キー、または自分の OpenAI 互換サーバーを使います。音声会話には音声モデルのキーも必要です。[必要なもの](#必要なもの)をご覧ください。

**中国本土などのネットワークで更新が見つかりません。** 更新元は GitHub です。接続できない場合や 403、429 制限では、ネットワークやプロキシ接続先を変えるか、パソコンの Poki Setup で Renew を使ってください。[Poki を更新](#poki-を更新)を参照してください。

**端末の内容を変更しますか？確認はありますか？** 実際のアプリで、メッセージ送信も含めて依頼を実行します。画面の内容は設定したモデルサービスに送られます。支払い、削除、Wallet の操作には常に確認が必要です。送信やパスワード入力などは Settings > Approvals で確認方法や確認の有無を選べます。[既知の問題](#既知の問題)をご覧ください。

## Poki を更新

- **iPhone** では、0.4.0 の Settings > Connection > Signing & Updates、または 0.3.1 の設定内の Signing を開きます。新しいビルドがあればダウンロードとインストールが表示されます。ログインを求められたら、パソコンでのインストール時に使った Apple Account でログインするか、パソコンから更新してください。
- **パソコン** の Poki Setup で Renew を選ぶと、そのチャンネルの最新ビルドを上書きインストールします。Mac ではエージェントにも更新を頼めます。install-poki スキルはバージョンと署名の識別情報を先に確認します。
- 「Finishing the update」で止まったら、App スイッチャーで Poki を終了し、開き直してバージョンを確認します。変わらなければパソコンの Poki Setup で更新してください。更新のために Poki を削除しないでください。会話も消えます。

チャンネルと Alpha から Beta への移行は[リリースチャンネル](docs/release-channels.md)をご覧ください。

## 既知の問題

- 実際の iPhone を操作します。送信や支払いを依頼すると実行します。画面の内容は設定したモデルサービスに送られます。
- 0.4.0 の iPhone 初回 Apple Account ログインは、古い Mac の識別情報を Apple が受け付けなくなったため、Mac が必要と表示される場合があります。ログイン済みなら通常どおり更新できます。それ以外はパソコンの Poki Setup で再署名と更新を行ってください。
- 実機は中国語表示、縦向きの iPhone でのみ検証済みです。横向きは非対応です。
- iOS 27 未満の実機と iPad は未検証です。古い小型端末では三次元のクマやホームのアニメーションで発熱や動作の遅さが増す可能性があります。低電力モードや「視差効果を減らす」では静止画を使います。
- 無料アカウントの署名は 7 日間です。パソコンの Poki Setup が iPhone に接続できるようにするか、期限前に手動更新してください。
- GitHub 取得時の 403、429 は共有ネットワークで起きることがあります。ネットワークやプロキシ接続先を変えるか、1 時間待ってください。

詳しくは[検証記録と制限](docs/verification.md)をご覧ください。

## タスクを試す

Poki を開いて「明日の天気を調べて、傘が必要か教えて」と入力するか、ホームのアプリをタップしてください。画面のアプリで作業し、Dynamic Island とロック画面に手順を表示して、慎重な扱いが必要な操作の前に確認します。

アクションボタンの長押しで話しかけたり、ショートカットや Siri の Talk to Poki、Send Task to Poki から呼び出したりすることもできます。その場合は通知で結果を返します。

> **注意：** Poki は実際の iPhone を操作します。送信や支払いを依頼すると実行します。

## ロードマップ

方向性のみを示し、日程は約束しません。

**0.4.0 Beta までに実装済み**

- 設定後は Mac 不要の iPhone アプリ、ロック画面と Dynamic Island での承認。
- Mac と Windows の Poki Setup またはエージェントによるインストール。Xcode 不要で無料アカウントも利用可能。
- iOS 27 以降のネイティブ操作。
- Poki MCP、Poki Agent、iMessage、Telegram、学習した操作経路の再実行。Poki MCP は現状を維持し、更新を終了。
- LAN と Tailscale のリモート接続。
- 三次元のクマのホーム、音声会話、アクションボタン、アーカイブ、ダークモードを含む 0.4.0 の画面。

**次の予定**

- Poki 独自のダウンロード元を使い、GitHub を予備にする。
- 更新チャンネルを一つにする。
- 音声は聞く、話す、見ることを担当し、端末操作は現在のテキストモデルに任せる。
- 表示言語を増やす。

**その後**

- より多くの iPhone、iOS、表示言語で実機検証。
- モデルプロバイダーの追加。

## ドキュメント

| 内容 | 文書 |
| --- | --- |
| 各バージョンの変更 | [CHANGELOG.md](CHANGELOG.md) |
| エージェントによるアプリのインストール | [install-poki](skills/install-poki/SKILL.md) |
| Mac と Windows のインストーラ | [Poki Setup](desktop/README.md) |
| チャンネルと昇格 | [リリースチャンネル](docs/release-channels.md) |
| Poki MCP のインストールとトラブル対応（更新終了） | [インストールガイド](docs/install.md) |
| Poki Agent、モデル、iMessage、Telegram | [Poki Agent](agent/README.md) |
| MCP ツール | [ツールの説明](docs/tools.md) |
| 環境変数とセッション | [設定](docs/configuration.md) |
| USB、開発者モード、Wi-Fi | [実機の設定](docs/physical-iphone.md) |
| 検証、制限、免責 | [検証記録](docs/verification.md) |
| ブリッジの構成 | [ネイティブ](native/NATIVE.md)と[シミュレータ](native/simulator.md) |
| ロードマップ | [ロードマップ](#ロードマップ) |

## Star History

<a href="https://www.star-history.com/?repos=JosssphZhou%2Fpoki&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&theme=dark&legend=top-left">
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
    <img alt="Star History chart" src="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
  </picture>
</a>

## コアコントリビューター

<!-- CORE-CONTRIBUTORS:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=240" width="120" height="120" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a><br />Poki 最初の issue <a href="https://github.com/JosssphZhou/poki/issues/1">#1</a> を報告。iOS 18.6.2 でスクリーンショットは動き、アクセシビリティとタッチは動かないことを、切り分けてわかりやすく書いてくれました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=240" width="120" height="120" alt="ZhehanZhang"/><br /><sub><b>ZhehanZhang</b></sub></a><br />Poki の偉大な共同創造者。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=240" width="120" height="120" alt="edge369"/><br /><sub><b>edge369</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/14">#14</a> で Poki をルーター上で動かせるようにし、Mac の電源がオフでも Telegram から iPhone を操作できます。<a href="https://github.com/JosssphZhou/poki/pull/15">#15</a>、<a href="https://github.com/JosssphZhou/poki/pull/17">#17</a>、<a href="https://github.com/JosssphZhou/poki/issues/19">#19</a> が続きました。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=240" width="120" height="120" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/6">#6</a> で macOS 27.2 の usbmuxd が iPhone を一覧に出さないことを報告。Poki はそれを明確に伝え、ヘルパーが早く止まる理由も示すようになりました（<a href="https://github.com/JosssphZhou/poki/issues/59">#59</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=240" width="120" height="120" alt="igc110"/><br /><sub><b>igc110</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/10">#10</a> で実機 iPhone のタップが遅い原因を突き止め、その後の修正でタップが約 3 分の 1 速くなりました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=240" width="120" height="120" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/16">#16</a> で Poki を Linux に移植し、実機 iPhone で USB、LAN、Tailscale 経由の動作を確認しました。README はこの移植版を案内しています。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=240" width="120" height="120" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/18">#18</a> で実機 iPhone のタッチ失敗の原因が display service の欠如にあると突き止めました。Poki は何も送信されなかったことを伝え、prepare-device を案内します。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=240" width="120" height="120" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a><br />壊れたキャッシュ済みルートが無関係な Agent タスクを中断させる問題を修正し（<a href="https://github.com/JosssphZhou/poki/issues/21">#21</a>、<a href="https://github.com/JosssphZhou/poki/pull/22">#22</a>）、続く <a href="https://github.com/JosssphZhou/poki/pull/37">#37</a> で操作後に読み取った画面を Agent が再利用できるようにしました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=240" width="120" height="120" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/25">#25</a> で、自然言語の停止リクエストでは iMessage のタスクが止まらないことを報告しました。Poki はタスク中のメッセージに返信し、/stop を案内するようになりました。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=240" width="120" height="120" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/27">#27</a> と <a href="https://github.com/JosssphZhou/poki/issues/28">#28</a> で Agent の 2 つの不具合を再現し、その後、キャンセル済みの入力ロック（<a href="https://github.com/JosssphZhou/poki/pull/102">#102</a>）から無効なタッチ座標（<a href="https://github.com/JosssphZhou/poki/pull/136">#136</a>）まで、7 件の修正とテスト修整をマージしました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=240" width="120" height="120" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a><br />iPhone の LAN アドレスが変わると RemotePairing 接続が切れる問題（<a href="https://github.com/JosssphZhou/poki/issues/30">#30</a>）を <a href="https://github.com/JosssphZhou/poki/pull/34">#34</a> で修正しました。実機では 768 ミリ秒で再接続できました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=240" width="120" height="120" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/35">#35</a> と <a href="https://github.com/JosssphZhou/poki/issues/40">#40</a> でモバイル通信と Windows から iPhone アプリを実機テストし、初回セットアップに Wi-Fi が必要という説明（<a href="https://github.com/JosssphZhou/poki/issues/138">#138</a>）につながりました。<a href="https://github.com/JosssphZhou/poki/issues/162">#162</a> も報告。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=240" width="120" height="120" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a><br />Windows ホストから RemotePairing 接続でタップが毎回失敗する問題を <a href="https://github.com/JosssphZhou/poki/pull/39">#39</a> で修正しました。修正後は 5 回中 5 回のタップが成功しました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=240" width="120" height="120" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/42">#42</a> で Tailscale 経由の実機 iPhone を使い、保険約款の確認を行いました。この報告が、USB のより分かりやすいエラーと、セッションごとの接続方式の切り替えにつながっています。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=240" width="120" height="120" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a><br />Poki が実機 iPhone を操作するデモ動画を制作し、新しい訪問者がインストール前に何ができるかを確認できるようにしました。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=240" width="120" height="120" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/68">#68</a> で OpenCode Go を iPhone アプリのモデルアカウントとして追加。専用の Keychain 認証情報と独立したモデル選択を備えています。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=240" width="120" height="120" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/69">#69</a> で Runner が約 25 分の待機後にペアリングに失敗する経過を詳しく記録。Setup は Loopback と Pairing の確認を案内するようになりました（<a href="https://github.com/JosssphZhou/poki/issues/70">#70</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=240" width="120" height="120" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a><br />バッチ呼び出しがデバイス不明時にクラッシュせず知らせるようにし（<a href="https://github.com/JosssphZhou/poki/pull/74">#74</a>）、POKI_MCP_DEVICE（<a href="https://github.com/JosssphZhou/poki/pull/75">#75</a>）とタスクごとの任意の承認ゲート（<a href="https://github.com/JosssphZhou/poki/pull/77">#77</a>）を追加しました。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=240" width="120" height="120" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a><br />ペアリング設定が誤った設定ページへ誘導する問題を修正し、開発者モードと UI オートメーションの手順が正しいページを開くようになりました（<a href="https://github.com/JosssphZhou/poki/pull/137">#137</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=240" width="120" height="120" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/139">#139</a> で画面読み取りが呼び出しの期限を超える問題を修正し、常に遅い Runner 応答に対する回帰テストも追加しました。</td>
    </tr>
  </tbody>
</table>
<!-- CORE-CONTRIBUTORS:END -->

## 特別貢献者

<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=240" width="120" height="120" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a><br />0.4.0 の再設計に向け、チャット、Live Activity、設定、初回起動の画面一式を提供しました（<a href="https://github.com/JosssphZhou/poki/pull/250">#250</a>、<a href="https://github.com/JosssphZhou/poki/pull/256">#256</a> から <a href="https://github.com/JosssphZhou/poki/pull/268">#268</a>）。新しい画面の方向性を形作ったデザインです。</td>
    </tr>
  </tbody>
</table>


## スペシャルサンクス

Issue や Pull Request を寄せてくださった皆さまに感謝いたします。皆さまのご報告と修正が Poki をより良くしています。

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

## Poki MCP (従来のパソコン接続方式、更新終了)

Poki MCP は更新を終了した従来の接続方式です。Mac の Claude Code や Codex から iPhone や iOS Simulator を操作し、Poki Agent はターミナル、iMessage、Telegram を提供します。既存ユーザーや開発を続ける人のために残しています。継続して更新される版は [iPhone アプリ](#iphone-に-poki-をインストール)です。

**エージェントにインストールを任せる。** 次の内容をエージェントに渡してください：

```text
https://github.com/JosssphZhou/poki を、ルートの AGENTS.md に従ってインストールしてください。MCP スキルも含めます。私の操作が必要なときは、その都度止まってください。
```

**Poki MCP。** Claude Code、Codex などの MCP クライアントをすでに使っていますか？ Poki MCP を接続すれば、ご自身のサブスクリプションをそのまま使えます。追加のモデルアカウントは不要です。

サーバーを起動し、動かしたままにします：

```sh
git clone https://github.com/JosssphZhou/poki.git
cd poki
./bin/setup
npm start
```

Poki MCP はソースからビルドするため、macOS 15 以降、完全版 Xcode、Rust、Node.js 24+、Python 3、ffmpeg が必要です。Poki アプリに Xcode は不要です。`./bin/setup` が不足する依存関係を確認します。初回ビルドには数分かかります。

Poki は macOS 向けです。Linux では、コミュニティによる移植版 [poki-for-linux](https://github.com/carrotciallo/poki-for-linux)（[#16](https://github.com/JosssphZhou/poki/issues/16)）を参照してください。このリポジトリとは別に管理されています。

Poki MCP on Windows: コミュニティによる移植版 [scy7796/poki-for-windows](https://github.com/scy7796/poki-for-windows)（作者が管理しており、当方ではテストしていません）。

Poki MCP のタグは `vX.Y.Z` です。iPhone アプリの `app-` リリースにはこのパッケージはありません。

### ビルド済み macOS arm64 パッケージ

リリースから [`poki-v0.1.1-macos-arm64.tar.gz`](https://github.com/JosssphZhou/poki/releases/tag/v0.1.1) をダウンロードして、次を実行します：

```sh
tar -xzf poki-v0.1.1-macos-arm64.tar.gz
cd poki-v0.1.1
npm ci --no-audit --no-fund
npm start
```

パッケージにはネイティブブリッジと idevice ツールが含まれています。Rust や `./bin/setup` は不要です。ただし、Apple Silicon の macOS、完全版の Xcode、Node.js 24+、Python 3、ffmpeg は必要です。MCP クライアントの登録と、オプションの Agent のインストールは下記のとおりです。

別のターミナルを同じディレクトリで開き、MCP サーバーを登録します：

```sh
claude mcp add --scope user poki-mcp -- node "$PWD/src/stdio.mjs"   # Claude Code
codex mcp add poki-mcp -- node "$PWD/src/stdio.mjs"                 # Codex
```

**Poki Agent。** Poki 単体のターミナルエージェントやメッセージングチャネルを使う場合は、`npm start` を動かしたまま、同じディレクトリで別のターミナルを開きます。エージェントをインストールし、そのコマンドをこのターミナルの PATH に追加して、サインインします：

```sh
npm ci --prefix agent
export PATH="$PWD/bin:$PATH"
poki login
poki status
```

Poki Agent は、デフォルトで GPT-6.1 Terra（`gpt-6.1-terra`）を推論強度 low で使用します。スマートフォンのタスクで私たちがテストした中で最も速い設定なので、そのまま使うことをおすすめします。モデルは `POKI_AGENT_MODEL` で変更できます。[Poki Agent の実行](agent/README.md)を参照してください。

実機の iPhone を使う場合は、先に USB で Mac とペアリングしてください。[実機 iPhone のセットアップ](docs/physical-iphone.md)を参照してください。

`./bin/poki update` は今後も最新 main を取得して再ビルドします。再起動と任意の更新確認は [Update](AGENTS.md#update) を参照してください。

### Poki Agent でタスクを試す

Poki Agent では、接続中の iPhone が 1 台なら自動で選択されます。複数台ある場合は `--device '<device UUID>'` を追加します。

```sh
node bin/call.mjs list_devices   # デバイスの UUID を確認
poki "Search esp32 in Chrome and summarize the top result"
```

> **注意：** Poki はあなたの実機 iPhone を操作します。メッセージの送信や支払いを頼めば、そのとおりに実行します。画面の内容は、設定したモデルサービスに送信されます。

使うほど速くなる：Poki Agent は過去のタスクを記憶し、繰り返し実行するときはより速く動きます。

**チャネル：** 許可済みのチャネルを設定したら、`poki imessage` または [`poki telegram`](agent/README.md#telegram) で起動します。設定方法は [Poki Agent](agent/README.md) を参照してください。

**MCP クライアント：** Claude Code、Codex、および `mcpServers` JSON に対応したクライアント。

実機 iPhone のサポートは、中国語インターフェースの iPhone でのみ検証済みです。実機は縦向きのみ対応です。App コンテナのエクスポートと、設定アプリのサブページへの直接リンクは使えません。[検証結果と既知の制限](docs/verification.md)を参照してください。

## 免責事項

Poki は独立したオープンソースプロジェクトです。Apple、OpenAI、および Poki が操作するアプリやウェブサイトの開発元とは提携関係になく、それらの承認も受けていません。iPhone は Apple Inc. の商標です。

サードパーティのアプリやウェブサイトの自動操作は、それらの利用規約に違反する可能性があります。特定のサービスで Poki を使うかどうかは、ご自身で判断してください。お使いのデバイスとアカウント上で Poki が行うこと（送信したメッセージ、加えた変更、その結果生じたアカウントの制限を含む）については、ご自身の責任となります。

Poki は AGPL-3.0 ライセンスの定めるとおり、無保証かつ「現状のまま」提供されます。

解釈に相違がある場合は、英語版が優先されます。

## ライセンス

Poki のコードは [AGPL-3.0-only ライセンス](LICENSE)のもとでオープンソースとして公開されています。

Poki のクマ、アプリアイコン、その他の Poki のアートワークはこのライセンスの対象外です。Poki を紹介するためにスクリーンショットを使うことはできます。フォークには独自の名前とアートワークが必要です。詳しくは [BRAND.md](BRAND.md) をご覧ください。

Copyright (c) 2026 Joseph Zhou (周瑟夫) and contributors. オープンソースの依存関係とサードパーティの素材には、それぞれのライセンスが適用されます。[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) を参照してください。コントリビュートについては [CONTRIBUTING.md](CONTRIBUTING.md) をご覧ください。

## 謝辞

<p align="center">
  <img src="docs/images/acknowledgments.png" width="860" alt="オープンソースで構築：pi、idevice、idb、BlueBubbles、Hermes Agent、MCP SDK、sharp、FFmpeg"><br>
  <sub>オープンソースへの謝辞：<a href="https://github.com/earendil-works/pi">pi</a> | <a href="https://github.com/jkcoxson/idevice">idevice</a> | <a href="https://github.com/facebook/idb">idb</a> | <a href="https://github.com/BlueBubblesApp/bluebubbles-server">BlueBubbles</a> | <a href="https://github.com/NousResearch/hermes-agent">Hermes Agent</a> | <a href="https://github.com/modelcontextprotocol/typescript-sdk">MCP SDK</a> | <a href="https://github.com/lovell/sharp">sharp</a> | <a href="https://github.com/FFmpeg/FFmpeg">FFmpeg</a></sub>
</p>
