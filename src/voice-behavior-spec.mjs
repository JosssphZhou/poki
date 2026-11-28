import { readFileSync } from 'node:fs';

const specURL = new URL('./data/voice-behavior-spec.json', import.meta.url);
const voiceBehaviorSpec = JSON.parse(readFileSync(specURL, 'utf8'));
export const VOICE_SPEC_VERSION = voiceBehaviorSpec.version;

const SCREEN_IMAGE_TOOLS = ['look', 'do', 'open_app'];
const NUMBERED_TOOLS = ['look', 'do'];
const CONTROL_ONLY_TOOLS = new Set(['cancel_current_task']);

function formatList(items, conjunction) {
  if (items.length <= 1) return items.join('');
  if (items.length === 2) return `${items[0]} ${conjunction} ${items[1]}`;
  return `${items.slice(0, -1).join(', ')}, ${conjunction} ${items.at(-1)}`;
}

function resolveVoiceLanguageName(code) {
  if (typeof code === 'string' && Object.hasOwn(voiceBehaviorSpec.language_names, code)) {
    return voiceBehaviorSpec.language_names[code];
  }
  try {
    if (/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(code ?? '')) {
      return new Intl.DisplayNames(['en'], { type: 'language' }).of(code) || 'English';
    }
  } catch {}
  return 'English';
}

function roleMode(role) {
  if (role === 'realtime') return 'realtime';
  if (role === 'codex_voice' || role === 'codex_executor') return 'codex';
  return 'live';
}

function matchesClause(clause, { role, host, toolSet, hasWorkTools }) {
  if (!clause.roles.includes(role)) return false;
  if (clause.hosts && !clause.hosts.includes(host)) return false;
  if (clause.requires_work_tools && !hasWorkTools) return false;
  if (clause.forbids_work_tools && hasWorkTools) return false;
  if (clause.requires_all_tools && !clause.requires_all_tools.every(name => toolSet.has(name))) return false;
  if (clause.requires_any_tools && !clause.requires_any_tools.some(name => toolSet.has(name))) return false;
  if (clause.forbids_tools && clause.forbids_tools.some(name => toolSet.has(name))) return false;
  return true;
}

export function buildVoicePrompt({ role, language, tools = [], host = 'phone' }) {
  const orderedTools = [...new Set(tools.filter(name => typeof name === 'string' && name.length > 0))];
  const toolSet = new Set(orderedTools);
  const hasWorkTools = orderedTools.some(name => !CONTROL_ONLY_TOOLS.has(name));
  const languageName = resolveVoiceLanguageName(language);
  const screenTools = formatList(SCREEN_IMAGE_TOOLS.filter(name => toolSet.has(name)), 'or');
  const numberedTools = formatList(NUMBERED_TOOLS.filter(name => toolSet.has(name)), 'or');
  const values = {
    language: languageName,
    lock_check: voiceBehaviorSpec.lock_check,
    screen_tools: screenTools,
    numbered_tools: numberedTools,
    cancel_tool: 'cancel_current_task',
  };

  const sections = [];
  const clauseIds = [];
  for (const section of voiceBehaviorSpec.sections) {
    const selected = [];
    for (const clause of voiceBehaviorSpec.clauses) {
      if (clause.section !== section.id) continue;
      if (!matchesClause(clause, { role, host, toolSet, hasWorkTools })) continue;
      const text = clause.text.replace(/\{([a-z_]+)\}/g, (_, key) => values[key] ?? '');
      selected.push({ id: clause.id, text });
      clauseIds.push(clause.id);
    }
    if (selected.length > 0) {
      sections.push({ id: section.id, title: section.title, clauses: selected });
    }
  }

  const text = sections
    .map(section => `# ${section.title}\n${section.clauses.map(clause => clause.text).join('\n')}`)
    .join('\n\n');

  return {
    templateVersion: voiceBehaviorSpec.version,
    role,
    mode: roleMode(role),
    host,
    language: language ?? '',
    languageName,
    tools: orderedTools,
    sectionIds: sections.map(section => section.id),
    clauseIds,
    sections,
    text,
  };
}
