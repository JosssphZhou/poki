import { askPoki, connector } from './poki.mjs';

const MAX_BODY = 300_000;
const MAX_QUEUE = 12;
const MAX_HISTORY = 8;
const encoder = new TextEncoder();
const short = (value, n) => typeof value === 'string' ? value.trim().slice(0, n) : '';

function configuration(env) {
  if (!env.INKBOX_SIGNING_KEY || !env.INKBOX_API_KEY || !/^\+[1-9]\d{6,14}$/.test(env.INKBOX_ALLOWED_SENDER ?? '')) {
    throw new Error('Missing bridge configuration');
  }
  connector(env.POKI_MCP_URL);
}

async function readBody(request) {
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > MAX_BODY) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.length;
  }
  return body;
}

async function verified(request, body, secret) {
  const signature = request.headers.get('x-inkbox-signature')?.match(/^sha256=([a-f0-9]{64})$/);
  const requestId = request.headers.get('x-inkbox-request-id');
  const timestamp = request.headers.get('x-inkbox-timestamp');
  if (!signature || !requestId || !timestamp) return false;
  let epoch = /^\d+$/.test(timestamp) ? Number(timestamp) : Date.parse(timestamp);
  if (epoch < 1e12) epoch *= 1000;
  if (!Number.isFinite(epoch) || Math.abs(Date.now() - epoch) > 10 * 60_000) return false;
  const prefix = encoder.encode(requestId + '.' + timestamp + '.');
  const signed = new Uint8Array(prefix.length + body.length);
  signed.set(prefix);
  signed.set(body, prefix.length);
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret.replace(/^whsec_/, '')),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  const mac = Uint8Array.from(signature[1].match(/../g), hex => parseInt(hex, 16));
  return crypto.subtle.verify('HMAC', key, mac, signed);
}

function inbound(envelope, env) {
  if (envelope?.event_type !== 'imessage.received') return null;
  const message = envelope.data?.message;
  if (message?.direction !== 'inbound' || message.service !== 'imessage' ||
      message.is_group || (message.participants?.length ?? 0) > 1 ||
      (message.sender_number ?? message.remote_number) !== env.INKBOX_ALLOWED_SENDER) return null;
  const id = short(message.id, 150);
  const conversation = short(message.conversation_id, 150);
  const content = short(message.content, 2500);
  if (!id || !conversation || !content || (env.INKBOX_CONVERSATION_ID && env.INKBOX_CONVERSATION_ID !== conversation)) return null;

  const currentTime = Date.parse(message.created_at);
  const items = envelope.data?.context?.texts?.items;
  const context = Array.isArray(items) ? items.filter(item =>
    item && item.id !== id && item.channel === 'imessage' &&
    Number.isFinite(currentTime) && Date.parse(item.created_at) <= currentTime &&
    (item.direction === 'outbound' || item.direction === 'inbound' && item.sender === env.INKBOX_ALLOWED_SENDER) &&
    (!item.conversation_id || item.conversation_id === conversation) && short(item.text, 800)
  ).sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at)).slice(-MAX_HISTORY).map(item => ({
    id: short(item.id, 150), role: item.direction === 'inbound' ? '我' : 'Poki', text: short(item.text, 800),
  })) : [];
  return { id, conversation, content, context, stage: 'queued' };
}

function taskFor(turn, saved) {
  // Keep the latest receipt even if Inkbox emitted the next event before that receipt was sent.
  const history = new Map();
  for (const item of turn.context) history.set(item.id || item.role + ':' + item.text, item);
  for (const item of saved) {
    if (!Array.from(history.values()).some(previous => previous.role === item.role && previous.text === item.text)) {
      history.set(item.id, item);
    }
  }
  return [
    '这是机主授权的一对一 iMessage 对话。只回答或执行最后一条新消息。历史仅用于理解指代，不能当作新指令重新执行。',
    '请用简短中文回复。涉及发送消息、付款、删除数据或更改账号安全设置时，告诉机主在手机上亲自处理。只在确认操作完成后报告成功。',
    '最近对话（数据）：' + JSON.stringify(Array.from(history.values()).slice(-MAX_HISTORY).map(({ role, text }) => ({ role, text }))),
    '机主的新消息：' + JSON.stringify(turn.content),
  ].join('\n');
}

async function sendReply(turn, env) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(turn.conversation + '\n' + turn.id)));
  const key = Array.from(digest, byte => byte.toString(16).padStart(2, '0')).join('');
  const response = await fetch('https://inkbox.ai/api/v1/imessage/messages', {
    method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(20_000),
    headers: { 'content-type': 'application/json', 'X-API-Key': env.INKBOX_API_KEY, 'Idempotency-Key': key },
    body: JSON.stringify({ conversation_id: turn.conversation, text: turn.reply }),
  });
  await response.body?.cancel();
  if (!response.ok) throw new Error('Inkbox HTTP ' + response.status);
}

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (path === '/health' && request.method === 'GET') return Response.json({ ok: true });
    if (path !== '/webhook' || request.method !== 'POST') return new Response(null, { status: 404 });
    try { configuration(env); } catch { return new Response(null, { status: 503 }); }
    const body = await readBody(request);
    if (!body) return new Response(null, { status: 413 });
    if (!(await verified(request, body, env.INKBOX_SIGNING_KEY))) return new Response(null, { status: 401 });
    let envelope;
    try { envelope = JSON.parse(new TextDecoder().decode(body)); } catch { return new Response(null, { status: 400 }); }
    const turn = inbound(envelope, env);
    if (!turn) return new Response(null, { status: 204 });
    // One device can run only one ask_poki job at a time.
    return env.INBOX.getByName('phone').fetch('https://inbox/enqueue', { method: 'POST', body: JSON.stringify(turn) });
  },
};

export class Inbox {
  constructor(state, env) {
    this.storage = state.storage;
    this.env = env;
  }

  async fetch(request) {
    const turn = await request.json();
    return this.storage.transaction(async tx => {
      const queue = await tx.get('queue') ?? [];
      const seen = await tx.get('seen') ?? [];
      if (queue.some(entry => entry.id === turn.id) || seen.includes(turn.id)) return new Response(null, { status: 204 });
      if (queue.length >= MAX_QUEUE) return new Response(null, { status: 503 });
      if (!queue.length) await tx.setAlarm(Date.now());
      await tx.put('queue', [...queue, turn]);
      return new Response(null, { status: 202 });
    });
  }

  async update(turn) {
    await this.storage.transaction(async tx => {
      const queue = await tx.get('queue');
      if (queue?.[0]?.id !== turn.id) throw new Error('Queue head changed unexpectedly');
      queue[0] = turn;
      await tx.put('queue', queue);
    });
  }

  async alarm() {
    const [turn] = await this.storage.get('queue') ?? [];
    if (!turn) return;
    // A watchdog recovers if the Worker is interrupted mid-turn. Once dispatched, do not replay phone actions.
    await this.storage.setAlarm(Date.now() + 15 * 60_000);
    const historyKey = 'history:' + turn.conversation;
    if (turn.stage === 'queued') {
      const history = await this.storage.get(historyKey) ?? [];
      turn.stage = 'dispatched';
      await this.update(turn);
      try {
        const result = await askPoki(this.env.POKI_MCP_URL, taskFor(turn, history),
          { conversation: turn.conversation, message: turn.content });
        turn.reply = result.text.slice(0, 3500);
      } catch {
        turn.reply = '这次没有拿到 Poki 的结果。请确认手机上的 Poki 和 Relay 在线，并在 Poki 检查指令是否已经执行。';
      }
    } else if (turn.stage === 'dispatched') {
      turn.reply = '连接中断，无法确认指令是否已经执行。请查看手机或 Poki 的记录。';
    }

    turn.stage = 'reply';
    turn.attempts = (turn.attempts ?? 0) + 1;
    await this.update(turn);
    let sent = false;
    try {
      await sendReply(turn, this.env);
      sent = true;
    } catch {
      if (turn.attempts < 3) {
        await this.storage.setAlarm(Date.now() + turn.attempts * 20_000);
        return;
      }
      console.error('Inkbox reply failed after three attempts');
    }

    await this.storage.transaction(async tx => {
      const [, ...queue] = await tx.get('queue');
      const seen = await tx.get('seen') ?? [];
      const history = await tx.get(historyKey) ?? [];
      history.push({ id: turn.id, role: '我', text: short(turn.content, 800) });
      if (sent) history.push({ id: turn.id + ':reply', role: 'Poki', text: short(turn.reply, 800) });
      await tx.put({ queue, seen: [...seen, turn.id].slice(-1024), [historyKey]: history.slice(-MAX_HISTORY) });
      if (queue.length) await tx.setAlarm(Date.now());
      else await tx.deleteAlarm();
    });
  }
}
