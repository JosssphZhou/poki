import { credentialEnv, envCredentialPresent, isOAuthCapable, normalizeAuth, supportsServiceTier } from './providers.mjs';
import { readConfigSync } from './config-file.mjs';

const TIERS = ['default', 'auto', 'fast', 'priority', 'flex', 'ultrafast'];
const DEFAULT_PROVIDER = 'openai';
const DEFAULT_MODEL = { openai: 'gpt-6.1-terra' };

function pickAuth(provider, explicit) {
  if (explicit) return normalizeAuth(explicit);
  if (envCredentialPresent(provider)) return 'api-key';
  if (provider === DEFAULT_PROVIDER) return 'oauth';
  return isOAuthCapable(provider) ? 'oauth' : 'api-key';
}

/**
 * 解析模型与供应商配置。
 * 优先级：options（命令行）> 环境变量 > ~/.config/poki-agent/config.json > 内置默认。
 */
export function modelConfig(options = {}) {
  const saved = readConfigSync();
  const provider = options.provider ?? process.env.POKI_AGENT_PROVIDER ?? saved.provider ?? DEFAULT_PROVIDER;
  if (typeof provider !== 'string' || !/^[a-z0-9][a-z0-9-]{0,48}$/.test(provider)) {
    throw new Error('Invalid provider id. Run poki providers to list supported ids.');
  }

  const auth = pickAuth(provider, options.auth ?? process.env.POKI_AGENT_AUTH ?? saved.auth);
  if (!['api-key', 'oauth'].includes(auth)) {
    throw new Error('Set POKI_AGENT_AUTH to api-key or oauth (chatgpt is accepted as an alias for oauth).');
  }

  // 不指定模型时留空，由 PiSession 从该供应商的目录里取第一个对话模型。
  const model = options.model ?? process.env.POKI_AGENT_MODEL ?? saved.model ?? DEFAULT_MODEL[provider] ?? null;

  const requestedTier = options.serviceTier ?? process.env.POKI_AGENT_SERVICE_TIER ?? saved.serviceTier;
  let serviceTier;
  if (supportsServiceTier(provider)) {
    serviceTier = requestedTier ?? 'priority';
    if (!TIERS.includes(serviceTier)) {
      throw new Error('Invalid service tier. Set POKI_AGENT_SERVICE_TIER=default for the standard tier.');
    }
  } else {
    // 其他供应商没有 service_tier 概念，传了只会被拒。
    serviceTier = undefined;
  }

  const baseUrl = options.baseUrl ?? process.env.POKI_AGENT_BASE_URL ?? process.env.OPENAI_BASE_URL ?? saved.baseUrl;
  if (baseUrl) {
    let url;
    try { url = new URL(baseUrl); } catch { throw new Error('Base URL must be a valid absolute URL.'); }
    if (auth !== 'api-key') throw new Error('A custom base URL requires api-key mode.');
    if (url.username || url.password || url.search || url.hash || !['http:', 'https:'].includes(url.protocol)) {
      throw new Error('Base URL must not carry credentials, a query string or a fragment.');
    }
  }

  return { provider, auth, model, serviceTier, baseUrl };
}

/** 给用户看的凭据提示，不含任何密钥。 */
export function credentialHint(provider) {
  const name = credentialEnv(provider);
  return name ? `Set ${name} in your environment.` : `Configure credentials for ${provider} through its own provider login or environment variables.`;
}

export function safeModelError(error) {
  const message = String(error?.message ?? error ?? 'Model request failed');
  const secrets = [process.env.OPENAI_API_KEY, process.env.POKI_IPHONE_PASSCODE,
    ...Object.keys(process.env).filter(key => /_API_KEY$|_TOKEN$/.test(key)).map(key => process.env[key])].filter(Boolean);
  return secrets.reduce((text, secret) => text.replaceAll(secret, '[redacted]'), message);
}
