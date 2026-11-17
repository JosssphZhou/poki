#!/usr/bin/env node
import { parseArgs } from 'node:util';
import { readFile, stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';

let run;
try {
  const { values } = parseArgs({ options: {
    'config-dir': { type: 'string', default: join(homedir(), '.config/poki-agent/photon') },
    check: { type: 'boolean' }, assign: { type: 'boolean' }, help: { type: 'boolean', short: 'h' },
  } });
  if (values.help) {
    console.log('Usage: node bin/poki-photon.mjs [--config-dir <private directory>] [--check | --assign]\n--check authenticates and connects only; no task or reply is sent.\n--assign maps the configured sender to a shared Photon iMessage line and prints its number.');
  } else {
    const directory = resolve(values['config-dir']);
    const path = join(directory, 'connection.json');
    if ((await stat(path)).mode & 0o077) throw new Error('Private connection file must have mode 600.');
    const connection = JSON.parse(await readFile(path, 'utf8'));
    if (typeof connection.projectId !== 'string' || typeof connection.apiKey !== 'string' || !connection.apiKey) {
      throw new Error('Invalid connection configuration.');
    }
    process.env.PHOTON_PROJECT_ID = connection.projectId;
    process.env.PHOTON_API_KEY = connection.apiKey;
    const config = join(directory, 'photon.json');
    if (values.assign) {
      const { sender } = JSON.parse(await readFile(config, 'utf8'));
      run = async () => {
        const { assignSharedLine } = await import('../agent/photon-source.mjs');
        try { console.log(`Shared line assigned. From ${sender}, send an iMessage to ${await assignSharedLine(sender)} to start.`); }
        catch (error) {
          console.error(error.message.replaceAll(connection.apiKey, '[redacted]'));
          process.exitCode = 1;
        }
      };
    } else {
      process.argv = [process.execPath, 'agent/photon.mjs', '--config', config,
        '--state', join(directory, 'state'), ...(values.check ? ['--check'] : [])];
      run = () => import('../agent/photon.mjs');
    }
  }
} catch {
  console.error('Cannot load private Photon settings. Check the configuration directory, JSON fields and file permissions.');
  process.exitCode = 1;
}
await run?.();
