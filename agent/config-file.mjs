// 用户级配置文件：~/.config/poki-agent/config.json（mode 600）
// 优先级：命令行参数 > 环境变量 > 本文件 > 内置默认
import { readFileSync } from 'node:fs';
import { readFile, writeFile, mkdir, chmod, rename } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

export const configPath = process.env.POKI_AGENT_CONFIG
  ?? join(homedir(), '.config/poki-agent/config.json');

const ALLOWED = new Set(['provider', 'model', 'auth', 'serviceTier', 'baseUrl']);

export function readConfigSync() {
  try {
    const parsed = JSON.parse(readFileSync(configPath, 'utf8'));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
    const clean = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (ALLOWED.has(key) && typeof value === 'string' && value.trim()) clean[key] = value.trim();
    }
    return clean;
  } catch { return {}; }
}

export async function readConfig() {
  try {
    const parsed = JSON.parse(await readFile(configPath, 'utf8'));
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch { return {}; }
}

export async function writeConfig(patch) {
  const current = await readConfig();
  const next = { ...current };
  for (const [key, value] of Object.entries(patch)) {
    if (!ALLOWED.has(key)) throw new Error(`Unknown setting "${key}". Allowed: ${[...ALLOWED].join(', ')}.`);
    if (value === null || value === undefined || value === '') delete next[key];
    else next[key] = String(value);
  }
  await mkdir(dirname(configPath), { recursive: true, mode: 0o700 });
  const temporary = `${configPath}.${process.pid}.tmp`;
  await writeFile(temporary, JSON.stringify(next, null, 2) + '\n', { mode: 0o600 });
  await rename(temporary, configPath);
  await chmod(configPath, 0o600);
  return next;
}

export async function unsetConfig(keys) {
  const patch = {};
  for (const key of keys) patch[key] = null;
  return writeConfig(patch);
}

// GUI 写入的密钥存在单独的私有文件里，权限 600，只在没有环境变量时兜底。
export const secretsPath = process.env.POKI_AGENT_SECRETS
  ?? join(homedir(), '.config/poki-agent/env.json');

export function readSecretsSync() {
  try {
    const parsed = JSON.parse(readFileSync(secretsPath, 'utf8'));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
    const clean = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (/^[A-Z0-9_]+$/.test(key) && typeof value === 'string' && value.trim()) clean[key] = value.trim();
    }
    return clean;
  } catch { return {}; }
}

export async function writeSecrets(patch) {
  let current = {};
  try { current = JSON.parse(await readFile(secretsPath, 'utf8')) ?? {}; } catch { current = {}; }
  const next = { ...current };
  for (const [key, value] of Object.entries(patch)) {
    if (!/^[A-Z0-9_]+$/.test(key)) throw new Error(`Invalid secret name "${key}".`);
    if (value === null || value === undefined || value === '') delete next[key];
    else next[key] = String(value);
  }
  await mkdir(dirname(secretsPath), { recursive: true, mode: 0o700 });
  const temporary = `${secretsPath}.${process.pid}.tmp`;
  await writeFile(temporary, JSON.stringify(next, null, 2) + '\n', { mode: 0o600 });
  await rename(temporary, secretsPath);
  await chmod(secretsPath, 0o600);
  return next;
}
