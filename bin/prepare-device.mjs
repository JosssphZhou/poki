#!/usr/bin/env node
// Prepares a physical iPhone for Poki: developer mode, then Apple's developer disk image.
//
// On macOS the image comes from Xcode. Elsewhere it has to be obtained another way,
// so this helper accepts a POKI_DDI_DIR holding an unpacked DDI Restore directory,
// installs it with cryptexd, and falls back to pymobiledevice3's own downloader.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { access, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { root, idevice } from '../src/config.mjs';
import { isWin, python } from '../src/os.mjs';

const execute = promisify(execFile);
const { stdout } = await execute(python, [join(root, 'native/devices.py')], { timeout: 8000 });
const ids = [...new Set(JSON.parse(stdout).map(d => d.id).filter(Boolean))];
const selected = process.argv[2] ?? (ids.length === 1 ? ids[0] : undefined);
if (!selected || !ids.includes(selected)) throw new Error('Connect one unlocked, trusted iPhone, or pass a connected device id.');
const call = async (args, options = {}) => execute(idevice, ['--udid', selected, ...args], { timeout: 180000, maxBuffer: 8 * 1024 * 1024, ...options });
const services = async () => (await call(['remotexpc'])).stdout;

async function identity() {
  const read = async key => JSON.parse((await call(['lockdown', 'get', key])).stdout);
  return { name: await read('DeviceName'), model: await read('ProductType'), ios: await read('ProductVersion') };
}

async function developerMode(device) {
  const status = (await call(['amfi', 'status'])).stdout.trim();
  if (/true/i.test(status)) return 'enabled';
  // The toggle has to be visible before a person can turn it on, and enabling it over
  // this API is refused while the phone has a passcode. Both paths are offered.
  await call(['amfi', 'show']).catch(() => {});
  const attempt = await call(['amfi', 'enable']).then(() => '', error => String(error.stderr ?? error.message));
  if (/passcode/i.test(attempt)) {
    return `needs a person: open Settings > Privacy & Security > Developer Mode on ${device.name}, turn it on, and restart the phone. (Enabling it remotely is refused while a passcode is set.)`;
  }
  if (attempt) return `needs a person: turn on Developer Mode in Settings > Privacy & Security and restart the phone. ${attempt.split('\n').at(-1)}`;
  return 'enabled remotely; restart the phone if the setting asks for it';
}

async function removableDirectory() {
  const configured = process.env.POKI_DDI_DIR;
  if (!configured) return undefined;
  const candidate = join(configured, 'BuildManifest.plist');
  const present = await access(candidate).then(() => true, () => false);
  return present ? configured : undefined;
}

async function diskImage() {
  if ((await services().catch(() => '')).includes('com.apple.coredevice.displayservice')) return 'display service is already available';
  const restore = await removableDirectory();
  if (restore) {
    const result = await call(['cryptexd', 'install-ddi', restore]);
    if (!/installed com\.apple\.MobileAsset\.DDI|is already installed/.test(result.stdout)) throw new Error(`The device did not confirm installation: ${result.stdout.slice(-1500)}`);
  } else {
    // pymobiledevice3 downloads the personalized image Apple signs for this phone.
    const result = await execute(python, ['-m', 'pymobiledevice3', 'mounter', 'auto-mount'], { timeout: 900000, maxBuffer: 8 * 1024 * 1024 }).then(outcome => outcome, error => ({ stdout: String(error.stdout ?? ''), stderr: String(error.stderr ?? error.message) }));
    if (!/mounted|already/i.test(result.stdout + result.stderr)) throw new Error(`Mounting the developer disk image failed. Set POKI_DDI_DIR to an unpacked DDI Restore directory, or install pymobiledevice3 and let it download one. ${(result.stderr || result.stdout).slice(-1500)}`);
  }
  if (!(await services()).includes('com.apple.coredevice.displayservice')) {
    throw new Error('The image is installed, but displayservice is still unavailable. Check image compatibility, and that Developer Mode and UI Automation are on in Developer settings.');
  }
  return 'developer disk image installed; the device now exposes displayservice';
}

const device = await identity();
console.log(JSON.stringify({ device }, null, 2));
console.log(`Developer mode: ${await developerMode(device)}`);
if (isWin) console.log('If the developer image below fails, obtain it from a Mac whose Xcode matches this iOS version and set POKI_DDI_DIR to its iOS_DDI/Restore directory.');
console.log(`Developer disk image: ${await diskImage()}`);
