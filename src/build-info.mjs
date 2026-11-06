import { readFileSync } from 'node:fs';
import { readdir, stat } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { join, sep } from 'node:path';
import { root, nativeBin } from './config.mjs';

export const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
const execute = promisify(execFile);
const bridge = nativeBin;

async function codeMarker() {
  const files = (await readdir(join(root, 'src'), { recursive: true }))
    .filter(file => file.endsWith('.mjs')).map(file => join('src', file));
  // The helper is named per platform, so the recorded marker carries the name it actually has.
  files.push('package.json', bridge.slice(root.length + 1).split(sep).join('/'));
  return JSON.stringify(await Promise.all(files.sort().map(async file => {
    const info = await stat(join(root, file)).catch(error => {
      if (error.code === 'ENOENT') return null;
      throw error;
    });
    return [file, info && [info.mtimeMs, info.ctimeMs, info.size, info.ino]];
  })));
}

const startupCode = await codeMarker();

export async function requireCurrentCode() {
  if (await codeMarker() !== startupCode) {
    throw new Error('The service is running old code. Stop the running service and restart it with npm start.');
  }
}

export async function buildInfo() {
  const [commit, native] = await Promise.all([
    execute('git', ['rev-parse', '--short', 'HEAD'], { cwd: root, timeout: 1000 }).then(result => result.stdout.trim(), () => 'unknown'),
    stat(bridge).catch(() => null),
  ]);
  return { commit, native_build: native?.mtime.toISOString() ?? 'unknown' };
}

export async function warnIfNativeStale() {
  const native = await stat(bridge).catch(() => null);
  if (!native) return;
  const directory = join(root, 'native/bridge');
  const files = await readdir(directory, { recursive: true }).catch(() => []);
  for (const file of files.filter(file => /(?:\.rs|Cargo\.toml|Cargo\.lock)$/.test(file) && !file.split(/[\\/]/).includes('target'))) {
    const source = await stat(join(directory, file)).catch(() => null);
    if (source?.mtimeMs > native.mtimeMs) {
      console.error(`Warning: ${bridge} is older than its source; rebuild it with bin/build-native when the device is available. Continuing with the existing bridge.`);
      return;
    }
  }
}
