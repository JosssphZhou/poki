# Install Poki on your iPhone

## Install with Poki Setup

1. Download [Poki Setup](https://github.com/JosssphZhou/poki/releases) for macOS or Windows and open it. On Windows, follow the driver prompt if it appears.
2. Connect an unlocked iPhone with a USB data cable. Tap **Trust** and enter the iPhone passcode. If Developer Mode is off, the wizard shows where to turn it on. After iOS restarts, unlock the iPhone and confirm Developer Mode.
3. Sign in with an Apple Account in Poki Setup, enter the verification code if Apple asks, and click **Install Poki**. Keep the phone unlocked until Poki Setup finishes installing the app and mounting the developer disk image.
4. If iOS shows an untrusted developer alert, open **Settings › General › VPN & Device Management** on the iPhone, select the developer and follow iOS's trust prompts.
5. Open Poki. In **Settings › Developer**, turn on **Enable UI Automation**. Return to Poki, start automation and enter the iPhone passcode on the iOS screen when asked. Unplug the cable when Poki Setup shows **Poki is ready**.

The first install uses USB and the computer's internet connection for signing. Model sign-in takes place in Poki. If the phone restarts, reconnect it to Poki Setup to restore the mounted image over USB, or use your existing local connection on the phone.

## Install or update with an agent

Use the agent skill [skills/install-poki/SKILL.md](skills/install-poki/SKILL.md). Read it and choose its first-install or update branch before running a command. First installation uses `node bin/install-iphone.mjs run --json`. Updating an existing app first checks its version, channel and signing identity. It is the backup when the iPhone cannot download an in-app update from GitHub.

Keep the existing app and its data. Poki Setup cannot preserve every custom signing or extension setup; the skill names the cases that must stop. Finish by reading the version and build on the iPhone and explaining signing renewal. A successful installer exit alone is not completion.

To keep it for later sessions, copy the whole `skills/install-poki` folder into your client's skill folder:

- Claude Code: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/install-poki`
- Codex: `${CODEX_HOME:-$HOME/.codex}/skills/install-poki`

The skill runs the installer from a Poki checkout; it clones one when there is none.
