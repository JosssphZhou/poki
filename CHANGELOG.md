# Changelog

Poki and Poki Runner ship together under one version. Each entry says what changed for the person
using the phone, then what changed underneath. The working notes per round stay in
native/ios-app/CHANGELOG-round.md; this file is what goes into a release and the AltStore source.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).
Build numbers are the GitHub Actions run number of the release workflow.

## [Unreleased]

### Added
- A first run: Poki says what it is, you pick its light, and it walks you through this iPhone, a model and the microphone. Each step can wait.
- Pictures in a message: the plus on the message field takes up to four from Photos or Files.
- Settings › Appearance: Poki’s light (five to choose from) and Light or Dark.
- During a talk with Poki, the Live Activity shows the open microphone and a button that ends the talk.

### Changed
- A new look for the whole app: a New chat page with Poki in its window, a Chats page one swipe away, and Settings behind the gear. The tab bar is gone; Setup is now Settings › Connection, and Accounts is Settings › Model.
- Every page is flat on paper with black for what you press; Poki’s light is the only colour. The Dynamic Island and the Lock Screen card are black, with Poki’s pose for what it is doing.
- While Poki uses the phone the chat stays as it is; afterwards one “Used your iPhone” card lists what it did.
- One button on the message field opens Dictate and Talk with Poki.
- A new app icon.

### Fixed
- 

### Device checks
- docs/device-test-checklist.md: passed / not passed, with the date and iOS version.

## [0.1.0] - unreleased

First prototype: Poki pairs with the phone it runs on, keeps the runner up over the loopback, answers
MCP (look, do, status) through the person's own relay (no default; `deploy/cf-relay/deploy.sh`), and asks the owner on the Lock Screen
before sensitive actions.
