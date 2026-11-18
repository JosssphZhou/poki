#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { readFile, stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';
import { chooseProvider } from '../agent/imessage-provider.mjs';

const routes = {
  bluebubbles: { name: 'imessage', variables: { BLUEBUBBLES_URL: 'url', BLUEBUBBLES_PASSWORD: 'password' }, secret: 'password' },
  photon: { name: 'photon', variables: { PHOTON_PROJECT_ID: 'projectId', PHOTON_API_KEY: 'apiKey' }, secret: 'apiKey' },
};
const stop = error => { console.error(error.message); process.exit(1); };

let run;
try {
  const { values } = parseArgs({ options: {
    provider: { type: 'string' }, 'config-dir': { type: 'string' },
    check: { type: 'boolean' }, assign: { type: 'boolean' }, help: { type: 'boolean', short: 'h' },
  } });
  if (values.help) {
    console.log('Usage: node bin/poki-imessage.mjs [--provider bluebubbles|photon] [--config-dir <private directory>] [--check | --assign]\nWithout --provider, the provider that is set up starts. When both are, the command asks in a terminal and otherwise starts BlueBubbles.\n--check authenticates and reads only; no task or reply is sent.\n--assign maps the configured sender to a shared Photon iMessage line and prints its number.');
  } else {
    const directories = {}, configured = [];
    for (const [candidate, { name }] of Object.entries(routes)) {
      directories[candidate] = resolve(values['config-dir'] ?? join(homedir(), '.config/poki-agent', name));
      if (await stat(join(directories[candidate], `${name}.json`)).catch(() => null)) configured.push(candidate);
    }
    const provider = await chooseProvider(values.assign ? values.provider ?? 'photon' : values.provider, configured).catch(stop);
    if (values.assign && provider !== 'photon') stop(new Error('--assign maps a sender to a Photon line. Use it with --provider photon.'));
    if (provider === 'photon' && Number(process.versions.node.split('.')[0]) < 24) {
      stop(new Error(`Poki Agent needs Node.js 24 or later; this is ${process.version}. Install it, then run npm ci --prefix agent from the repository root.`));
    }
    const { name, variables, secret } = routes[provider];
    const directory = directories[provider];
    const path = join(directory, 'connection.json');
    if ((await stat(path)).mode & 0o077) throw new Error('Private connection file must have mode 600.');
    const connection = JSON.parse(await readFile(path, 'utf8'));
    if (Object.values(variables).some(field => typeof connection[field] !== 'string') || !connection[secret]) {
      throw new Error('Invalid connection configuration.');
    }
    for (const [variable, field] of Object.entries(variables)) process.env[variable] = connection[field];
    const config = join(directory, `${name}.json`);
    if (values.assign) {
      const { sender } = JSON.parse(await readFile(config, 'utf8'));
      run = async () => {
        const { assignSharedLine } = await import('../agent/photon-source.mjs');
        try { console.log(`Shared line assigned. From ${sender}, send an iMessage to ${await assignSharedLine(sender)} to start.`); }
        catch (error) {
          console.error(error.message.replaceAll(connection[secret], '[redacted]'));
          process.exitCode = 1;
        }
      };
    } else {
      process.argv = [process.execPath, `agent/${name}.mjs`, '--config', config,
        '--state', join(directory, 'state'), ...(values.check ? ['--check'] : [])];
      run = () => import(`../agent/${name}.mjs`);
    }
  }
} catch {
  console.error('Cannot load private iMessage settings. Check the configuration directory, JSON fields and file permissions.');
  process.exitCode = 1;
}
try {
  await run?.();
} catch (error) {
  if (error?.code !== 'ERR_MODULE_NOT_FOUND') throw error;
  console.error(`Poki Agent's packages are not installed (${error.message.split(' imported from ')[0]}). Run npm ci --prefix agent from the repository root first.`);
  process.exitCode = 1;
}
