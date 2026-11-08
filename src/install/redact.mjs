// Takes identifiers and secrets out of text before a person or an issue sees it: UDIDs, ECIDs,
// serials, device names, Apple Account emails, tokens and keys, pairing records, relay addresses,
// IP addresses and the macOS user name. Known values go first, then patterns catch the rest.
import { homedir, userInfo } from 'node:os';

const SECRET_KEYS = /^(?:.*(?:token|secret|password|passcode|private|pkcs8|cookie|authorization|api_?key|pairing_record|certificate_der).*)$/i;
const IDENTIFIER_KEYS = /^(?:udid|unique_chip_id|ecid|serial(?:_number)?|mux_id|apple_id|email|wifi_address|address|phone_name|name|team_id|bundle_id|app_group|relay|url)$/i;

const patterns = [
  [/-----BEGIN [A-Z ]+-----[\s\S]*?-----END [A-Z ]+-----/g, '[pem removed]'],
  [/<data>[\s\S]*?<\/data>/g, '<data>[removed]</data>'],
  [/\bpoki:\/\/[^\s"'<>)]+/g, '[poki link removed]'],
  [/\bhttps?:\/\/[^\s"'<>)]*workers\.dev[^\s"'<>)]*/g, '[relay removed]'],
  [/\b(Bearer|Basic)\s+[^\s"',]+/gi, '$1 [removed]'],
  [/\b(sk-(?:ant-|proj-)?[A-Za-z0-9_-]{16,}|AIza[0-9A-Za-z_-]{30,}|gh[pousr]_[A-Za-z0-9]{20,}|xox[abpr]-[A-Za-z0-9-]{10,}|eyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]{8,})/g, '[key removed]'],
  [/\b(token|secret|password|passwd|passcode|api[_-]?key|authorization|cookie)\b(["']?\s*[:=]\s*["']?)[^\s"',}&]+/gi, '$1$2[removed]'],
  [/([?&](?:secret|token|key|sig|code)=)[^&\s"']+/gi, '$1[removed]'],
  [/\b[0-9A-F]{8}-[0-9A-F]{16}\b/gi, '[udid]'],
  [/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, '[uuid]'],
  [/\b[0-9a-f]{40}\b/gi, '[udid]'],
  [/\b[0-9A-F]{20,}\b/gi, '[serial]'],
  [/\b((?:serial(?:\s*number)?|SerialNumber|ecid|unique_chip_id)["']?\s*[:=]?\s*["']?)[A-Z0-9]{6,}\b/gi, '$1[serial]'],
  [/\b[A-Za-z0-9_+-]{40,}={0,2}/g, '[removed]'],
  [/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, '[email]'],
  [/\b(?!127\.0\.0\.1\b)(?!10\.7\.0\.1\b)(?:\d{1,3}\.){3}\d{1,3}\b/g, '[ip]'],
  [/\b[\w-]+(?: [\w-]+)?['’]s (iPhone|iPad)\b/g, '[device name]'],
];

function escape(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

export function redactText(text, known = []) {
  let out = String(text);
  const user = (() => { try { return userInfo().username; } catch { return ''; } })();
  out = out.split(homedir()).join('~');
  if (user && user.length > 2) out = out.replace(new RegExp(`/Users/${escape(user)}\\b`, 'g'), '/Users/[user]');
  for (const value of [...new Set(known)].filter(v => typeof v === 'string' && v.length >= 3).sort((a, b) => b.length - a.length)) {
    out = out.replace(new RegExp(escape(value), 'gi'), '[removed]');
  }
  for (const [pattern, replacement] of patterns) out = out.replace(pattern, replacement);
  return out;
}

// Values worth removing literally wherever they show up, collected from structured data.
export function knownValues(value, found = []) {
  if (Array.isArray(value)) value.forEach(v => knownValues(v, found));
  else if (value && typeof value === 'object') {
    for (const [key, v] of Object.entries(value)) {
      if (typeof v === 'string' && (IDENTIFIER_KEYS.test(key) || SECRET_KEYS.test(key))) found.push(v);
      else knownValues(v, found);
    }
  }
  return found;
}

// Structured data: secret fields are dropped, identifier fields replaced, and every string goes
// through redactText with every identifier the structure itself holds.
export function redactValue(value, known = knownValues(value)) {
  if (Array.isArray(value)) return value.map(v => redactValue(v, known));
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, v]) => {
      if (SECRET_KEYS.test(key)) return [key, v == null ? v : '[removed]'];
      if (IDENTIFIER_KEYS.test(key) && typeof v === 'string') return [key, '[removed]'];
      if (IDENTIFIER_KEYS.test(key) && typeof v === 'number') return [key, '[removed]'];
      return [key, redactValue(v, known)];
    }));
  }
  return typeof value === 'string' ? redactText(value, known) : value;
}
