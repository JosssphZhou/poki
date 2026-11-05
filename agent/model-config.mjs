import { homedir } from 'node:os';
import { join } from 'node:path';
import { credentialEnv, envCredentialPresent, isOAuthCapable, normalizeAuth, supportsServiceTier } from './providers.mjs';
import { readConfigSync } from './config-file.mjs';

const TIERS = ['default', 'auto', 'fast', 'priority', 'flex', 'ultrafast'];
const DEFAULT_PROVIDER = 'openai';
const DEFAULT_MODEL = { openai: 'gpt-6.1-terra' };

/** 手填供应商的模型目录：pi 从 models.json 读取自定义 provider 与模型。 */
export const customModelsPath = process.env.POKI_AGENT_MODELS
  ?? join(homedir(), '.config/poki-agent/models.json');

function pickAuth(provider, explicit, baseUrl) {
  // 自带 baseUrl 的供应商只能走 API key，OAuth 只对内置供应商有意义。
  if (baseUrl) return 'api-key';
  if (explicit) return normalizeAuth(explicit);
  if (envCredentialPresent(provider)) return 'api-key';
  if (provider === DEFAULT_PROVIDER) return 'oauth';
  return isOAuthCapable(provider) ? 'oauth' : 'api-key';
}

function checkBaseUrl(baseUrl) {
  if (!baseUrl) return undefined;
  let url;
  try { url = new URL(baseUrl); } catch { throw new Error('API 地址必须是完整 URL，例如 https://api.deepseek.com/v1。'); }
  if (!['http:', 'https:'].includes(url.protocol)) throw new Error('API 地址只支持 http 或 https。');
  if (url.username || url.password || url.search || url.hash) {
    throw new Error('API 地址里不能带账号、密码、查询串或片段。');
  }
  return baseUrl.replace(/\/+$/, '');
}

/**
 * 解析模型与供应商配置。
 * 优先级：options（命令行/GUI）> 环境变量 > ~/.config/poki-agent/config.json > 内置默认。
 */
export function modelConfig(options = {}) {
  const saved = readConfigSync();
  const baseUrl = checkBaseUrl(options.baseUrl ?? process.env.POKI_AGENT_BASE_URL ?? saved.baseUrl);
  const provider = options.provider ?? process.env.POKI_AGENT_PROVIDER ?? saved.provider
    ?? (baseUrl ? 'custom' : DEFAULT_PROVIDER);
  if (typeof provider !== 'string' || !/^[a-z0-9][a-z0-9-]{0,48}$/.test(provider)) {
    throw new Error('供应商 id 只能用小写字母、数字和连字符。');
  }

  const auth = pickAuth(provider, options.auth ?? process.env.POKI_AGENT_AUTH ?? saved.auth, baseUrl);
  if (!['api-key', 'oauth'].includes(auth)) {
    throw new Error('认证方式只能是 api-key 或 oauth（chatgpt 是 oauth 的别名）。');
  }

  // 不指定模型时留空，由 PiSession 从该供应商的目录里取第一个对话模型。
  const model = options.model ?? process.env.POKI_AGENT_MODEL ?? saved.model
    ?? (baseUrl ? null : DEFAULT_MODEL[provider] ?? null);

  const requestedTier = options.serviceTier ?? process.env.POKI_AGENT_SERVICE_TIER ?? saved.serviceTier;
  let serviceTier;
  if (supportsServiceTier(provider) && !baseUrl) {
    serviceTier = requestedTier ?? 'priority';
    if (!TIERS.includes(serviceTier)) {
      throw new Error('service tier 无效。用 POKI_AGENT_SERVICE_TIER=default 表示标准层级。');
    }
  } else {
    // 其他供应商没有 service_tier 概念，传了只会被拒。
    serviceTier = undefined;
  }

  return {
    provider, auth, model, serviceTier, baseUrl,
    modelsPath: baseUrl ? customModelsPath : null,
    custom: Boolean(baseUrl),
  };
}

/** 给用户看的凭据提示，不含任何密钥。 */
export function credentialHint(provider) {
  const name = credentialEnv(provider);
  if (name) return `在环境变量里设置 ${name}，或在 Poki 设置里填 API Key。`;
  return '在 Poki 设置里填 API Key（或设置环境变量 POKI_CUSTOM_API_KEY）。';
}

export function safeModelError(error) {
  const message = String(error?.message ?? error ?? 'Model request failed');
  const secrets = [process.env.OPENAI_API_KEY, process.env.POKI_IPHONE_PASSCODE, process.env.POKI_CUSTOM_API_KEY,
    ...Object.keys(process.env).filter(key => /_API_KEY$|_TOKEN$/.test(key)).map(key => process.env[key])].filter(Boolean);
  return secrets.reduce((text, secret) => text.replaceAll(secret, '[redacted]'), message);
}
