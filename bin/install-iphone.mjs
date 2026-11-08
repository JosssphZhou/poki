#!/usr/bin/env node
// Installs Poki on an iPhone through Poki Setup without its window. Read INSTALL-IPHONE.md first.
import { mkdir, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { Bridge } from '../src/install/bridge.mjs';
import { diagnose, issueDraft } from '../src/install/report.mjs';
import { manifest, run } from '../src/install/run.mjs';

const usage = `Usage: node bin/install-iphone.mjs <command> [options]

Commands:
  run                 Install Poki on the iPhone, stopping only where a person has to act.
  code <digits>       Hand the running install the Apple two-factor code the person read out.
  done <step>         Tell the running install that the person finished a step it cannot see (open_poki).
  phones              List the iPhones Poki Setup can reach (to choose one with --udid).
  diagnose            Print a diagnostics bundle with identifiers and secrets removed.
  issue               Draft an English issue from the last run. It prints the draft and the gh command;
                      it never submits. Show the draft to the person first.
  steps               Print the steps, who does each one, and the error codes.

Options:
  --channel <name>    stable, beta, alpha (default) or pre-alpha.
  --udid <udid>       The iPhone to use when several are plugged in.
  --dry-run           Download and check the real Poki Setup, start its real helper, then simulate the
                      iPhone and the Apple Account. Nothing touches a device or Apple.
  --json              One JSON event per line (for agents).
  --state <dir>       Where the run keeps its record (default ~/Library/Application Support/PokiInstall).
  --setup-home <dir>  Poki Setup's data directory (default: Poki Setup's own, shared with the app).
  --bridge <path>     Use this poki-setup-bridge instead of the one in Poki Setup.app.
  --app-dir <dir>     Where to put Poki Setup.app when it is not installed (default ~/Applications).
  --reinstall         Sign and install again even when the last run installed Poki.
  --no-device         diagnose only: do not ask usbmuxd, devicectl or Bonjour about devices.

Exit codes: 0 done, 1 bad usage, 2 a step failed (see the code), 3 a person step is still open (run again).`;

const { values: opts, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    channel: { type: 'string', default: 'alpha' },
    udid: { type: 'string' },
    'dry-run': { type: 'boolean', default: false },
    json: { type: 'boolean', default: false },
    state: { type: 'string' },
    'setup-home': { type: 'string' },
    bridge: { type: 'string' },
    'app-dir': { type: 'string' },
    reinstall: { type: 'boolean', default: false },
    'no-device': { type: 'boolean', default: false },
    help: { type: 'boolean', short: 'h', default: false },
  },
});
const [command, arg] = positionals;
const dryRun = opts['dry-run'];
const state = resolve(opts.state ?? join(homedir(), 'Library/Application Support/PokiInstall', dryRun ? 'dry-run' : ''));
const setupHome = opts['setup-home'] ? resolve(opts['setup-home']) : dryRun ? join(state, 'setup-home') : undefined;
await mkdir(join(state, 'inbox'), { recursive: true });

async function inbox(name, value) {
  const file = join(state, 'inbox', name);
  await writeFile(file, value, { mode: 0o600 });
}

switch (opts.help ? 'help' : command) {
  case 'run':
    process.exitCode = await run({ state, setupHome, channel: opts.channel, udid: opts.udid, dryRun, json: opts.json, bridge: opts.bridge && resolve(opts.bridge), appDir: opts['app-dir'] && resolve(opts['app-dir']), reinstall: opts.reinstall });
    break;
  case 'code':
    if (!/^\d{6}$/.test(arg ?? '')) { console.error('The Apple code has 6 digits: node bin/install-iphone.mjs code 123456'); process.exitCode = 1; break; }
    await inbox('apple-code', arg);
    console.log('Handed the code to the running install.');
    break;
  case 'done':
    if (arg !== 'open_poki') { console.error('Only open_poki is confirmed by hand: node bin/install-iphone.mjs done open_poki'); process.exitCode = 1; break; }
    await inbox(arg, 'done');
    console.log(`Told the running install that ${arg} is done.`);
    break;
  case 'phones': {
    const path = opts.bridge ?? '/Applications/Poki Setup.app/Contents/MacOS/poki-setup-bridge';
    const { bridge } = await Bridge.start(path, { env: setupHome ? { POKI_SETUP_HOME: setupHome } : {} });
    for (const r of await bridge.request('phones')) console.log(`${r.phone.udid}  ${r.facts?.product_type ?? '?'}  iOS ${r.facts?.ios ?? '?'}  ${r.phone.link?.kind ?? ''}`);
    bridge.close();
    break;
  }
  case 'diagnose':
    process.stdout.write((await diagnose({ state, noDevice: opts['no-device'], bridge: opts.bridge, setupHome })).text);
    break;
  case 'issue': {
    const draft = await issueDraft({ state });
    console.log(`Title: ${draft.title}\n\n${draft.body}`);
    console.log(`Saved to ${draft.draftFile}.\n\nShow this draft to the person and submit it only after they say yes. Then run:\n  ${draft.command}`);
    break;
  }
  case 'steps':
    console.log(JSON.stringify(manifest, null, 2));
    break;
  default:
    console.log(usage);
    process.exitCode = command && !opts.help ? 1 : 0;
}
