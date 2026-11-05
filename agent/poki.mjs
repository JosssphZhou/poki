#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { createInterface } from 'node:readline/promises';
import { Writable } from 'node:stream';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { ModelRuntime, SettingsManager } from '@earendil-works/pi-coding-agent';
import { PokiClient } from './poki-client.mjs';
import { modelConfig, safeModelError } from './model-config.mjs';
import { credentialEnv, credentialOrigin, envCredentialPresent, isOAuthCapable, normalizeAuth, supportsServiceTier } from './providers.mjs';
import { configPath, readConfig, writeConfig, unsetConfig } from './config-file.mjs';

const entries = { task: 'cli.mjs', imessage: 'imessage.mjs', telegram: 'telegram.mjs' };
const taskOptions = {
  device: { type: 'string' }, state: { type: 'string' }, model: { type: 'string' },
  provider: { type: 'string' }, 'base-url': { type: 'string' },
  auth: { type: 'string' }, 'service-tier': { type: 'string' }, context: { type: 'string' },
  'step-timeout': { type: 'string' }, help: { type: 'boolean', short: 'h' },
};
const help = `Usage: poki "task" [--device <UUID>] [--state <directory>] [--provider <id>] [--model <model>]
            [--auth api-key|oauth] [--service-tier <tier>] [--base-url <url>] [--context <text>]
            [--step-timeout <seconds>]
       poki login [--provider <id>] [--auth api-key|oauth]
       poki status
       poki providers            List providers and whether credentials are present
       poki models [--provider <id>] [--limit <n>]
       poki config               Show the saved configuration
       poki config set <provider|model|auth|serviceTier|baseUrl> <value>
       poki config unset <key>
       poki imessage [--check]   BlueBubbles iMessage channel (configure with poki imessage-setup)
       poki imessage-setup       Write the private BlueBubbles connection settings
       poki telegram --config <private JSON file> [--check]
With one connected physical phone, --device is optional. Use --device for a simulator.
Tasks accept /stop and corrections on stdin. Step timeout defaults to 60 seconds.
API keys belong only in the provider's environment variable, never in command arguments.`;

function parse(args, options, allowPositionals = false) {
  try { return parseArgs({ args, options, allowPositionals }); }
  catch { throw new Error('Invalid arguments. Use poki --help. Do not pass credentials on the command line.'); }
}

function runtime() {
  return ModelRuntime.create({ modelsPath: null, allowModelNetwork: false, authPath: process.env.POKI_AGENT_AUTH_FILE });
}

async function signedInProvider(modelRuntime, providerId) {
  const credentials = await modelRuntime.listCredentials();
  return credentials.some(item => item.providerId === providerId && item.type === 'oauth');
}

function credentialSource(providerId, credentials) {
  const origin = credentialOrigin(providerId);
  if (origin === 'environment') return credentialEnv(providerId);
  if (origin === 'local file') return `${credentialEnv(providerId)} (local file)`;
  if (credentials.some(c => c.providerId === providerId && c.type === 'oauth')) return 'OAuth';
  if (credentials.some(c => c.providerId === providerId)) return 'stored';
  return null;
}

async function withMCP(action) {
  const client = new PokiClient();
  try {
    await client.open(`poki-cli-${randomUUID()}`);
    return await action(async name => {
      const result = await client.call(name);
      if (result.isError) throw new Error('Poki MCP could not report device status. Check the local service and phone connection.');
      return JSON.parse(result.content.find(item => item.type === 'text').text);
    });
  } finally { await client.close(); }
}

async function login(args) {
  const { values } = parse(args, { provider: { type: 'string' }, auth: { type: 'string' }, help: { type: 'boolean', short: 'h' } });
  if (values.help) {
    console.log('Usage: poki login [--provider <id>] [--auth api-key|oauth]\nOAuth opens a browser sign-in. API access reads the provider environment variable; Poki never stores or prints keys.');
    return;
  }
  const saved = await readConfig();
  const provider = values.provider ?? saved.provider ?? 'openai';
  const abort = new AbortController();
  let input;
  const stop = () => abort.abort();
  const ask = async prompt => {
    if (!process.stdin.isTTY) throw new Error('Interactive login needs a terminal. Run poki login in a terminal.');
    if (!input) {
      input = createInterface({ input: process.stdin, output: new Writable({ write(chunk, encoding, callback) { callback(); } }), terminal: true });
      input.on('SIGINT', stop);
    }
    console.log(prompt.message);
    if (prompt.type === 'select') for (const option of prompt.options) console.log(`  ${option.id}: ${option.label}`);
    const answer = await input.question('> ', { signal: prompt.signal ? AbortSignal.any([prompt.signal, abort.signal]) : abort.signal });
    return answer.trim();
  };
  process.once('SIGINT', stop);
  try {
    const auth = normalizeAuth(values.auth) ?? await ask({ type: 'select', message: `Choose ${provider} access (type oauth or api-key):`, options: [
      { id: 'oauth', label: 'Browser sign-in (OAuth)' }, { id: 'api-key', label: 'API key from the environment' },
    ] });
    if (!['api-key', 'oauth'].includes(auth)) throw new Error('Choose oauth or api-key. Run poki login --help.');

    if (auth === 'api-key') {
      const env = credentialEnv(provider);
      if (!env) throw new Error(`${provider} has no known API key variable. Use its OAuth login, or check poki providers.`);
      console.log(`Set ${env} and POKI_AGENT_PROVIDER=${provider} in your environment. Poki does not accept or store API keys.`);
      if (!envCredentialPresent(provider)) { process.exitCode = 1; return; }
      console.log(`${env} is present in the environment (not sent or validated).`);
      await writeConfig({ provider, auth: 'api-key' });
      console.log(`Saved provider=${provider} auth=api-key to ${configPath}.`);
      return;
    }

    if (!isOAuthCapable(provider)) throw new Error(`${provider} does not offer a known OAuth flow here. Use api-key mode with ${credentialEnv(provider) ?? 'its credentials'}.`);
    const modelRuntime = await runtime();
    if (await signedInProvider(modelRuntime, provider)) {
      console.log(`${provider}: using the existing sign-in.`);
      await writeConfig({ provider, auth: 'oauth' });
      return;
    }
    const options = { agentName: 'Poki', getDeviceId: () => SettingsManager.create(process.cwd()).getOrCreateDeviceId() };
    await modelRuntime.login(provider, 'oauth', {
      signal: abort.signal,
      prompt: ask,
      notify(event) {
        if (event.type === 'auth_url') console.log(`Open this URL to sign in to ${provider}:\n${event.url}\n${event.instructions ?? ''}`);
        else if (event.type === 'device_code') console.log(`Open ${event.verificationUri} and enter the displayed code: ${event.userCode}`);
        else console.log(event.message);
      },
    }, options);
    if (!await signedInProvider(modelRuntime, provider)) throw new Error('Sign-in was not saved.');
    await writeConfig({ provider, auth: 'oauth' });
    console.log(`${provider} sign-in saved. Set as the default provider in ${configPath}.`);
  } catch (error) {
    throw new Error(`Poki login did not complete (${error?.message ?? 'unknown error'}). Check your selection or browser sign-in and retry poki login.`);
  } finally { input?.close(); process.removeListener('SIGINT', stop); }
}

async function showProviders(args) {
  const { values } = parse(args, { all: { type: 'boolean' }, json: { type: 'boolean' }, help: { type: 'boolean', short: 'h' } });
  if (values.help) { console.log('Usage: poki providers [--all] [--json]\nList providers from the built-in catalog with credential state. --all includes providers without credentials. --json prints machine-readable output for the menu bar app.'); return; }
  const saved = await readConfig();
  const current = saved.provider ?? 'openai';
  const modelRuntime = await runtime();
  const credentials = await modelRuntime.listCredentials();
  const rows = [];
  for (const provider of modelRuntime.getProviders()) {
    const models = modelRuntime.getModels(provider.id).filter(model => !['image', 'classifier'].includes(model.type));
    const source = credentialSource(provider.id, credentials);
    const includeAll = values.all || values.json;
    if (!includeAll && !source && provider.id !== current) continue;
    rows.push({ id: provider.id, name: provider.name ?? provider.id, models: models.length, source, configured: Boolean(source), current: provider.id === current, env: credentialEnv(provider.id) ?? null, oauth: isOAuthCapable(provider.id) });
  }
  rows.sort((a, b) => Number(b.current) - Number(a.current) || a.id.localeCompare(b.id));
  if (values.json) {
    console.log(JSON.stringify({ current, providers: rows }, null, 2));
    return;
  }
  const width = Math.max(8, ...rows.map(row => row.id.length));
  console.log(`${'provider'.padEnd(width)}  models  credentials`);
  for (const row of rows) {
    console.log(`${(row.current ? '* ' : '  ') + row.id.padEnd(width - 2)}  ${String(row.models).padStart(6)}  ${row.source ?? 'not configured'}`);
  }
  console.log(`\n* = current provider. Set one with: poki config set provider <id>`);
  console.log(`Providers without credentials are hidden; add --all to list every id.`);
}

async function showModels(args) {
  const { values } = parse(args, { provider: { type: 'string' }, limit: { type: 'string' }, json: { type: 'boolean' }, help: { type: 'boolean', short: 'h' } });
  if (values.help) { console.log('Usage: poki models [--provider <id>] [--limit <n>] [--json]\nList chat models available for a provider. Use the id with poki config set model <id>.'); return; }
  const saved = await readConfig();
  const provider = values.provider ?? saved.provider ?? 'openai';
  const limit = Number(values.limit ?? 40);
  if (!Number.isInteger(limit) || limit < 1) throw new Error('--limit must be a positive integer.');
  const modelRuntime = await runtime();
  if (!modelRuntime.getProvider(provider)) throw new Error(`Unknown provider "${provider}". Run poki providers --all.`);
  const models = modelRuntime.getModels(provider).filter(model => !['image', 'classifier'].includes(model.type));
  if (values.json) {
    console.log(JSON.stringify({ provider, models: models.map(model => model.id) }, null, 2));
    return;
  }
  console.log(`${provider}: ${models.length} chat models`);
  for (const model of models.slice(0, limit)) console.log(`  ${model.id}`);
  if (models.length > limit) console.log(`  ... ${models.length - limit} more (raise --limit)`);
  console.log(`\nSet one with: poki config set model <id>`);
}

async function showConfig(args) {
  const wantJSON = args.includes('--json');
  args = args.filter(argument => argument !== '--json');
  const sub = args[0];
  if (!sub || sub === 'path' || sub === 'show') {
    const saved = await readConfig();
    const effective = modelConfig();
    if (wantJSON) {
      console.log(JSON.stringify({ file: configPath, saved, effective }, null, 2));
      return;
    }
    console.log(`File: ${configPath}`);
    console.log(`Provider: ${effective.provider}${saved.provider ? '' : ' (default)'}`);
    console.log(`Model: ${effective.model ?? '(auto: first chat model of the provider)'}`);
    console.log(`Auth: ${effective.auth}${saved.auth ? '' : ' (inferred)'}`);
    if (effective.serviceTier) console.log(`Service tier: ${effective.serviceTier}`);
    if (effective.baseUrl) console.log(`Base URL: ${effective.baseUrl}`);
    const keys = Object.keys(saved);
    console.log(keys.length ? `\nSaved keys: ${keys.join(', ')}` : '\nNothing saved yet. Use poki config set <key> <value>.');
    return;
  }
  if (sub === 'set') {
    const [key, ...rest] = args.slice(1);
    const value = rest.join(' ').trim();
    if (!key || !value) throw new Error('Usage: poki config set <provider|model|auth|serviceTier|baseUrl> <value>');
    if (key === 'provider' && !/^[a-z0-9][a-z0-9-]{0,48}$/.test(value)) throw new Error('Invalid provider id. Run poki providers --all.');
    if (key === 'auth') {
      const normalized = normalizeAuth(value);
      if (!['api-key', 'oauth'].includes(normalized)) throw new Error('auth must be api-key or oauth.');
      await writeConfig({ auth: normalized });
    } else if (key === 'serviceTier') {
      if (!['default', 'auto', 'fast', 'priority', 'flex', 'ultrafast'].includes(value)) throw new Error('Invalid service tier.');
      await writeConfig({ serviceTier: value });
    } else {
      await writeConfig({ [key]: value });
    }
    console.log(`Saved ${key}=${value} to ${configPath}`);
    if (key === 'provider') {
      const runtimeNow = await runtime();
      const effective = modelConfig();
      if (!supportsServiceTier(effective.provider) && modelConfig().serviceTier) console.log('Note: service tier only applies to OpenAI providers and is ignored elsewhere.');
      if (!runtimeNow.getProvider(value)) console.log(`Warning: "${value}" is not in the built-in catalog. Run poki providers --all to check the id.`);
    }
    return;
  }
  if (sub === 'unset') {
    const keys = args.slice(1);
    if (!keys.length) throw new Error('Usage: poki config unset <key> [<key> ...]');
    await unsetConfig(keys);
    console.log(`Removed ${keys.join(', ')} from ${configPath}`);
    return;
  }
  throw new Error('Usage: poki config [path|set <key> <value>|unset <key>]');
}

async function status(args) {
  const { values } = parse(args, { json: { type: 'boolean' }, help: { type: 'boolean', short: 'h' } });
  if (values.help) { console.log('Usage: poki status [--json]\nShow provider, access method, model, service tier, MCP service and connected devices. No credentials are printed.'); return; }
  const config = modelConfig();
  const modelRuntime = await runtime();
  const credentials = await modelRuntime.listCredentials();
  const source = credentialSource(config.provider, credentials);
  const ready = config.auth === 'api-key'
    ? envCredentialPresent(config.provider)
    : (await signedInProvider(modelRuntime, config.provider)) || (config.provider === 'openai' && await signedInProvider(modelRuntime, 'openai-codex'));

  let devices = [];
  let connected = false;
  try {
    await withMCP(async call => {
      await call('poki_mcp_status');
      devices = (await call('list_devices')).devices;
      connected = true;
    });
  } catch { connected = false; }

  if (values.json) {
    console.log(JSON.stringify({
      provider: config.provider, auth: config.auth, ready, source,
      model: config.model, serviceTier: config.serviceTier ?? null, baseUrl: config.baseUrl ?? null,
      mcp: { connected, devices },
    }, null, 2));
    if (!connected) process.exitCode = 1;
    return;
  }

  console.log(`Provider: ${config.provider}`);
  console.log(`Access: ${config.auth} (${ready ? `configured via ${source ?? 'sign-in'}` : 'not configured; run poki login'})`);
  console.log(`Model: ${config.model ?? '(auto: first chat model of the provider)'}`);
  if (config.serviceTier) console.log(`Service tier: ${config.serviceTier}`);
  if (config.baseUrl) console.log(`Base URL: ${config.baseUrl}`);
  if (connected) {
    console.log('Poki MCP: connected');
    console.log(`Devices: ${devices.length}`);
    for (const device of devices) console.log(`  ${device.id}  ${device.name}  ${device.kind}${device.blocked ? ' (not ready)' : ''}`);
  } else {
    console.log('Poki MCP: unavailable. Start the local service with node src/daemon.mjs --port 0, using the same POKI_MCP_STATE_DIR.');
    process.exitCode = 1;
  }
}

async function main() {
  const args = process.argv.slice(2);
  if (!args.length || args[0] === '--help' || args[0] === '-h') { console.log(help); return; }
  const command = args[0];
  if (command === 'login') return login(args.slice(1));
  if (command === 'status') return status(args.slice(1));
  if (command === 'providers') return showProviders(args.slice(1));
  if (command === 'models') return showModels(args.slice(1));
  if (command === 'config') return showConfig(args.slice(1));
  if (command === 'imessage-setup') {
    const entry = new URL('imessage-setup.mjs', import.meta.url);
    process.argv = [process.execPath, fileURLToPath(entry), ...args.slice(1)];
    return import(entry.href);
  }
  if (command === 'imessage') {
    const rest = args.slice(1);
    if (rest.includes('--help') || rest.includes('-h')) {
      console.log('Usage: poki imessage [--config-dir <dir>] [--check]\n--check 只做认证与只读拉取，不发消息、不跑设备任务。\n未指定 --config-dir 时使用 ~/.config/poki-agent/imessage。首次配置用 poki imessage-setup。');
      return;
    }
    const entry = new URL('../bin/poki-imessage.mjs', import.meta.url);
    process.argv = [process.execPath, fileURLToPath(entry), ...rest];
    return import(entry.href);
  }
  let target = 'task', forwarded = args;
  if (command === 'telegram') {
    target = command; forwarded = args.slice(1);
    if (forwarded.includes('--help') || forwarded.includes('-h')) {
      console.log(`Usage: poki telegram --config <private JSON file> [--state <directory>] [--step-timeout <seconds>] [--once] [--check]\n--check authenticates and reads only; no task or reply is sent.`);
      return;
    }
  } else {
    const { values, positionals } = parse(args, taskOptions, true);
    if (values.help) { console.log(help); return; }
    if (!positionals.join(' ').trim()) throw new Error('A task is required. Use poki --help.');
    if (!values.device) {
      const phones = await withMCP(async call => (await call('list_devices')).devices.filter(device => device.kind === 'physical'));
      if (phones.length !== 1) {
        console.error(phones.length ? 'Multiple phones connected. Specify --device <UUID>:' : 'No physical phone connected. Connect a phone, or specify --device for a simulator.');
        for (const phone of phones) console.error(`  ${phone.id}  ${phone.name}`);
        process.exitCode = 2; return;
      }
      forwarded = ['--device', phones[0].id, ...args];
    }
  }
  const entry = new URL(entries[target], import.meta.url);
  process.argv = [process.execPath, fileURLToPath(entry), ...forwarded];
  await import(entry.href);
}
main().catch(error => { console.error(safeModelError(error)); process.exitCode = 1; });
