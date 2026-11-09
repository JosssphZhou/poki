import { execFile } from 'node:child_process';
import { randomInt } from 'node:crypto';
import { existsSync } from 'node:fs';
import { appendFile, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { Bridge } from './bridge.mjs';
import { knownValues, redactText, setupKnownValues } from './redact.mjs';
import { findSetupBridge, SetupError } from './setup-app.mjs';

const exec = promisify(execFile);
const cliPath = fileURLToPath(new URL('../../bin/install-iphone.mjs', import.meta.url));
export const LAUNCH_AGENT_LABEL = 'nz.zheha.poki.renew';
const defaultStateDir = () => join(homedir(), 'Library/Application Support/PokiInstall');
const pad = n => String(n).padStart(2, '0');
const xmlEscape = text => String(text).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');

export function launchAgentPath(home = homedir()) {
  return join(home, 'Library/LaunchAgents', `${LAUNCH_AGENT_LABEL}.plist`);
}

export function dailyTime(offsetMinutes = randomInt(0, 24 * 60)) {
  return { hour: Math.floor(offsetMinutes / 60), minute: offsetMinutes % 60, offsetMinutes };
}

export function renderLaunchAgentPlist({ state, setupHome, appDir, bridge, hour, minute }) {
  const resolvedState = resolve(state);
  const args = [process.execPath, cliPath, 'renew'];
  if (resolvedState !== defaultStateDir()) args.push('--state', resolvedState);
  if (setupHome) args.push('--setup-home', resolve(setupHome));
  if (appDir) args.push('--app-dir', resolve(appDir));
  if (bridge) args.push('--bridge', resolve(bridge));
  const logFile = join(resolvedState, 'renew.log');
  const pathEnv = process.env.PATH || '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin';
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    '<dict>',
    '  <key>Label</key>',
    `  <string>${xmlEscape(LAUNCH_AGENT_LABEL)}</string>`,
    '  <key>ProgramArguments</key>',
    '  <array>',
    ...args.map(arg => `    <string>${xmlEscape(arg)}</string>`),
    '  </array>',
    '  <key>EnvironmentVariables</key>',
    '  <dict>',
    '    <key>POKI_INSTALL_DIALOGS</key>',
    '    <string>0</string>',
    '    <key>POKI_RENEW_LAUNCHD</key>',
    '    <string>1</string>',
    '    <key>PATH</key>',
    `    <string>${xmlEscape(pathEnv)}</string>`,
    '  </dict>',
    '  <key>ProcessType</key>',
    '  <string>Background</string>',
    '  <key>StartCalendarInterval</key>',
    '  <dict>',
    '    <key>Hour</key>',
    `    <integer>${hour}</integer>`,
    '    <key>Minute</key>',
    `    <integer>${minute}</integer>`,
    '  </dict>',
    '  <key>StandardOutPath</key>',
    `  <string>${xmlEscape(logFile)}</string>`,
    '  <key>StandardErrorPath</key>',
    `  <string>${xmlEscape(logFile)}</string>`,
    '</dict>',
    '</plist>',
    '',
  ].join('\n');
}

export async function installSchedule({ state, setupHome, appDir, bridge, dryRun = false }) {
  const { hour, minute, offsetMinutes } = dailyTime();
  const xml = renderLaunchAgentPlist({ state, setupHome, appDir, bridge, hour, minute });
  const plist = dryRun ? join(resolve(state), 'LaunchAgents', `${LAUNCH_AGENT_LABEL}.plist`) : launchAgentPath();
  await mkdir(dirname(plist), { recursive: true });
  await writeFile(plist, xml);
  if (!dryRun) {
    const domain = `gui/${process.getuid()}`;
    await exec('launchctl', ['bootout', domain, plist]).catch(() => {});
    await exec('launchctl', ['bootstrap', domain, plist]);
  }
  return { plist, hour, minute, offsetMinutes, time: `${pad(hour)}:${pad(minute)}`, dryRun };
}

export async function uninstallSchedule({ json = false } = {}) {
  const plist = launchAgentPath();
  const domain = `gui/${process.getuid()}`;
  await exec('launchctl', ['bootout', domain, plist]).catch(() => {});
  await rm(plist, { force: true });
  const at = new Date().toISOString();
  const summary = `Removed the daily Poki renewal schedule (${LAUNCH_AGENT_LABEL}).`;
  process.stdout.write(`${json ? JSON.stringify({ event: 'result', ok: true, status: 'uninstalled', label: LAUNCH_AGENT_LABEL, summary, at }) : summary}\n`);
  return 0;
}

export async function readRenew(state) {
  try { return JSON.parse(await readFile(join(state, 'renew.json'), 'utf8')); } catch { return null; }
}

export async function clearRenew(state) {
  await rm(join(state, 'renew.json'), { force: true });
}

const FAILURE_RULES = [
  {
    code: 'phone_locked',
    status: 'deferred',
    needs_person: false,
    match: /unlock|locked|passcode|PasswordProtected|Prohibited/i,
    summary: () => 'Poki renewal skipped: the iPhone is locked. Will try again on the next run.',
  },
  {
    code: 'phone_unreachable',
    status: 'deferred',
    needs_person: false,
    match: /not connected|No iPhone found|unreachable|usbmuxd|timed out|connection|offline|Host is down|No route to host/i,
    summary: () => 'Poki renewal skipped: the iPhone is not connected or not reachable. Will try again on the next run.',
  },
  {
    code: 'apple_account',
    status: 'needs_person',
    needs_person: true,
    match: /Sign in with your Apple ID|verification code|\bpassword\b|-22406|-21669|not on team|apple_id|session/i,
    summary: () => 'Poki renewal skipped: your Apple Account needs to sign in again on this Mac (run: node bin/install-iphone.mjs run). Will try again on the next run.',
  },
  {
    code: 'trust_not_answered',
    status: 'needs_person',
    needs_person: true,
    match: /no longer trusts|tap Trust|Pair with the iPhone/i,
    summary: () => 'Poki renewal skipped: the iPhone needs to trust this Mac again (plug it in and tap Trust, or run: node bin/install-iphone.mjs run). Will try again on the next run.',
  },
];

export function classifyRenewOutcome({ results, records, known = [] }) {
  if (results.length === 0 && records.length === 0) {
    return { ok: true, status: 'no_phones', code: 'no_phones', needs_person: false, summary: 'Poki renewal: no iPhone is set up on this Mac yet.' };
  }
  if (results.length === 0) {
    const daysLeft = Math.min(...records.map(r => Math.max(0, Math.round((r.profile_expires_at - Date.now() / 1000) / 86400))));
    return { ok: true, status: 'not_due', code: 'not_due', days_left: daysLeft, needs_person: false, summary: `Poki renewal: not due yet (${daysLeft} days of signing left).` };
  }
  if (results.every(r => r.ok)) {
    const rec = records.find(r => results.some(d => d.udid === r.udid)) ?? records[0];
    const daysLeft = rec ? Math.max(0, Math.round((rec.profile_expires_at - Date.now() / 1000) / 86400)) : 7;
    const poki = rec ? `${rec.version} (${rec.build})` : null;
    return { ok: true, status: 'renewed', code: 'renewed', poki, days_left: daysLeft, needs_person: false, summary: `Renewed Poki${poki ? ` ${poki}` : ''} on the iPhone; signed for ${daysLeft} days.` };
  }
  const failed = results.find(r => !r.ok);
  const text = String(failed?.error ?? 'unknown error');
  const rule = FAILURE_RULES.find(entry => entry.match.test(text));
  if (rule) return { ok: false, status: rule.status, code: rule.code, needs_person: rule.needs_person, summary: rule.summary() };
  return { ok: false, status: 'needs_person', code: 'renew_failed', needs_person: true, summary: `Poki renewal skipped (${redactText(text, known)}). Will try again on the next run.` };
}

async function readLastRun(state) {
  try { return JSON.parse(await readFile(join(state, 'run.json'), 'utf8')); } catch { return null; }
}

async function writeRenewResult(state, outcome, { json = false } = {}) {
  await mkdir(state, { recursive: true });
  const at = new Date().toISOString();
  const record = { at, ...outcome };
  await writeFile(join(state, 'renew.json'), `${JSON.stringify(record, null, 2)}\n`);
  const logLine = `${at}  [${outcome.code}] ${outcome.summary}\n`;
  if (process.env.POKI_RENEW_LAUNCHD !== '1') await appendFile(join(state, 'renew.log'), logLine);
  if (json) process.stdout.write(`${JSON.stringify({ event: 'result', ...record })}\n`);
  else process.stdout.write(process.env.POKI_RENEW_LAUNCHD === '1' ? logLine : `${outcome.summary}\n`);
}

export async function renew({ state, setupHome, bridge: bridgeOpt, appDir, json = false, uninstallSchedule: remove = false }) {
  if (remove) return uninstallSchedule({ json });
  process.env.POKI_INSTALL_DIALOGS = '0';
  const lastRun = await readLastRun(state);
  const effectiveSetupHome = setupHome ?? lastRun?.setup_home;
  const homes = [effectiveSetupHome, join(state, 'setup-home'), join(homedir(), 'Library/Application Support/nz.Poki.Poki-Setup')].filter(Boolean);
  let bridgePath;
  try {
    if (bridgeOpt) {
      if (!existsSync(resolve(bridgeOpt))) throw new SetupError('setup_app_missing', `${resolve(bridgeOpt)} does not exist`);
      bridgePath = resolve(bridgeOpt);
    } else {
      bridgePath = findSetupBridge({ recorded: lastRun?.setup_bridge, into: appDir });
    }
  } catch (error) {
    const known = [...knownValues(lastRun), ...await setupKnownValues(homes)];
    const summary = redactText(`${error.code ?? 'error'}: ${error.message}`, known);
    await writeRenewResult(state, { ok: false, status: 'failed', code: error.code ?? 'setup_app_missing', needs_person: true, summary }, { json });
    return 2;
  }
  let bridge;
  try {
    ({ bridge } = await Bridge.start(bridgePath, { env: effectiveSetupHome ? { POKI_SETUP_HOME: effectiveSetupHome } : {} }));
  } catch (error) {
    const known = [...knownValues(lastRun), ...await setupKnownValues(homes)];
    const summary = redactText(`${error.kind ?? 'bridge_start_failed'}: ${error.message}`, known);
    await writeRenewResult(state, { ok: false, status: 'failed', code: 'bridge_start_failed', needs_person: true, summary }, { json });
    return 2;
  }
  try {
    if (lastRun?.channel) await bridge.request('set_channel', { channel: lastRun.channel }).catch(() => {});
    const beforeRecords = await bridge.request('records').catch(() => []);
    const account = await bridge.request('account').catch(() => null);
    const results = await bridge.request('renew_due').catch(error => [{ udid: '', ok: false, error: error.message }]);
    const afterRecords = await bridge.request('records').catch(() => beforeRecords);
    const known = [...knownValues([beforeRecords, afterRecords, account, lastRun]), ...await setupKnownValues(homes)];
    const outcome = classifyRenewOutcome({ results, records: afterRecords, known });
    outcome.summary = redactText(outcome.summary, known);
    await writeRenewResult(state, outcome, { json });
    return 0;
  } finally {
    bridge.close();
  }
}
