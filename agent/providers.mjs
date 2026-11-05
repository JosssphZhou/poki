// 供应商注册表：把 pi 内置的 provider 映射到凭据环境变量与登录方式。
// pi 自己会读这些环境变量；这里只为提示、显式注入和 CLI 展示服务。
// 未列出的 provider 也能用：直接传 pi 的 provider id，凭据由 pi 自己解析。
import { readSecretsSync } from './config-file.mjs';

export const CREDENTIAL_ENV = {
  openai: 'OPENAI_API_KEY',
  'openai-codex': 'OPENAI_API_KEY',
  anthropic: 'ANTHROPIC_API_KEY',
  google: 'GEMINI_API_KEY',
  'google-vertex': 'GOOGLE_CLOUD_API_KEY',
  deepseek: 'DEEPSEEK_API_KEY',
  xai: 'XAI_API_KEY',
  groq: 'GROQ_API_KEY',
  mistral: 'MISTRAL_API_KEY',
  cerebras: 'CEREBRAS_API_KEY',
  openrouter: 'OPENROUTER_API_KEY',
  nvidia: 'NVIDIA_API_KEY',
  fireworks: 'FIREWORKS_API_KEY',
  together: 'TOGETHER_API_KEY',
  baseten: 'BASETEN_API_KEY',
  huggingface: 'HF_TOKEN',
  moonshotai: 'MOONSHOT_API_KEY',
  'moonshotai-cn': 'MOONSHOT_API_KEY',
  minimax: 'MINIMAX_API_KEY',
  'minimax-cn': 'MINIMAX_CN_API_KEY',
  zai: 'ZAI_API_KEY',
  'zai-coding-cn': 'ZAI_CODING_CN_API_KEY',
  'kimi-coding': 'KIMI_API_KEY',
  meta: 'META_API_KEY',
  opencode: 'OPENCODE_API_KEY',
  'opencode-go': 'OPENCODE_API_KEY',
  'github-copilot': 'COPILOT_GITHUB_TOKEN',
  'vercel-ai-gateway': 'AI_GATEWAY_API_KEY',
  'cloudflare-ai-gateway': 'CLOUDFLARE_API_KEY',
  'cloudflare-workers-ai': 'CLOUDFLARE_API_KEY',
  radius: 'RADIUS_API_KEY',
  typesafe: 'TYPESAFE_API_KEY',
  'qwen-token-plan': 'QWEN_TOKEN_PLAN_API_KEY',
  'qwen-token-plan-individual': 'QWEN_TOKEN_PLAN_API_KEY',
  'qwen-token-plan-cn': 'QWEN_TOKEN_PLAN_CN_API_KEY',
  xiaomi: 'XIAOMI_API_KEY',
};

// 支持浏览器 OAuth 登录的 provider。其余走 API key。
export const OAUTH_CAPABLE = new Set([
  'openai', 'openai-codex', 'anthropic', 'github-copilot', 'google-vertex', 'amazon-bedrock',
]);

// 服务层级（service_tier）只对 OpenAI 系有效。
export const TIER_PROVIDERS = new Set(['openai', 'openai-codex']);

export function credentialEnv(providerId) {
  return CREDENTIAL_ENV[providerId];
}

export function isOAuthCapable(providerId) {
  return OAUTH_CAPABLE.has(providerId);
}

export function supportsServiceTier(providerId) {
  return TIER_PROVIDERS.has(providerId);
}

/** 实际生效的凭据值：环境变量优先，其次 GUI 写入的私有文件。 */
export function credentialValue(providerId) {
  const name = credentialEnv(providerId);
  if (!name) return undefined;
  return process.env[name]?.trim() || readSecretsSync()[name];
}

/** 凭据来源标签，用于 CLI / GUI 展示。 */
export function credentialOrigin(providerId) {
  const name = credentialEnv(providerId);
  if (!name) return null;
  if (process.env[name]?.trim()) return 'environment';
  if (readSecretsSync()[name]) return 'local file';
  return null;
}

/** 看某个 provider 的凭据是否已就绪（只看本地，不碰网络）。 */
export function envCredentialPresent(providerId) {
  return Boolean(credentialValue(providerId));
}

/** 规范化 --auth 取值，兼容旧写法 chatgpt。 */
export function normalizeAuth(value) {
  if (value === undefined || value === null || value === '') return undefined;
  const text = String(value).toLowerCase();
  if (text === 'chatgpt') return 'oauth';
  if (text === 'key') return 'api-key';
  if (text === 'oauth' || text === 'api-key') return text;
  return text;
}
