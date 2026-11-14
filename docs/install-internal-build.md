# Install an internal Poki build

You need an iPhone, a USB cable, and [Poki Setup](https://github.com/JosssphZhou/poki/releases/tag/app-alpha-latest)
on your Mac or Windows PC. Use the test package shared by the maintainer. You do not need a GitHub
account when the maintainer sends you the files directly.

1. Download and unzip the test package on your computer. Keep `Poki-signing.zip` beside
   `Poki-internal-<version>-<build>.ipa`.
2. Connect your iPhone over USB and unlock it. Accept **Trust This Computer** if asked.
3. Open Poki Setup. Complete its Apple Account sign-in and device preparation steps, including
   Developer Mode if prompted. Enter your password and verification code only in Poki Setup.
4. Select the local IPA. On Mac, open **More install options** in the Poki section and choose
   **Install from an IPA File…**. On Windows, choose **Use an IPA file…**.
5. Click **Install Poki**. Follow any device prompts, then open Poki on the iPhone.
   Confirm the version and build match the package the maintainer sent you.

Internal builds use numbers from 9001 to 9999. A normal channel build of the same version may
have a lower number, so Poki may not offer it as an update. To leave the test, select the release
instead of the local IPA in Poki Setup and install it. Keep the app installed to preserve its data.
If installation fails, send the maintainer the error text and the test build number. Remove account
details and private screen contents. Do not uninstall Poki as a troubleshooting step.
