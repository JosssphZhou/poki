const version = '2025-06-18';
const callback = 'http://127.0.0.1:9/callback';
const bytes = size => crypto.getRandomValues(new Uint8Array(size));
const b64url = data => btoa(String.fromCharCode(...data)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');

export function connector(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      !/^\/v1\/[a-z2-7]{52}\/[A-Za-z0-9_-]{43}\/mcp$/.test(url.pathname)) {
    throw new Error('需要有效的 Poki Relay Connector URL');
  }
  return url.href;
}

async function http(url, init = {}, timeout = 20_000) {
  try {
    return await fetch(url, { ...init, redirect: 'manual', signal: AbortSignal.timeout(timeout) });
  } catch {
    throw new Error('Relay 未响应');
  }
}

async function json(response, phase) {
  if (!response.ok) throw new Error(`${phase}失败（HTTP ${response.status}）`);
  try {
    return await response.json();
  } catch {
    throw new Error(`${phase}返回了无效数据`);
  }
}

export async function connectPoki(value) {
  const url = connector(value);
  const base = url.slice(0, -4);
  const registration = await json(await http(base + '/register', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ client_name: 'Inkbox iMessage for Poki', redirect_uris: [callback] }),
  }), 'Relay 注册');
  if (!registration.client_id) throw new Error('Relay 未返回客户端 ID');
  const verifier = b64url(bytes(32));
  const state = b64url(bytes(16));
  const challenge = b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
  const params = new URLSearchParams({
    response_type: 'code', client_id: registration.client_id, redirect_uri: callback,
    code_challenge: challenge, code_challenge_method: 'S256', state, resource: url, scope: 'poki',
  });
  const auth = await http(base + '/authorize?' + params);
  const location = auth.headers.get('location');
  if (auth.status !== 302 || !location) throw new Error(`Relay 授权失败（HTTP ${auth.status}）。请确认 Poki 在线`);
  const returned = new URL(location);
  const code = returned.searchParams.get('code');
  if (returned.origin + returned.pathname !== callback || returned.searchParams.get('state') !== state || !code) {
    throw new Error('Relay 授权回执无效');
  }
  const tokens = await json(await http(base + '/token', {
    method: 'POST', body: new URLSearchParams({
      grant_type: 'authorization_code', code, redirect_uri: callback,
      code_verifier: verifier, client_id: registration.client_id,
    }),
  }), 'Relay 登录');
  if (!tokens.access_token) throw new Error('Relay 未返回访问令牌');

  const headers = new Headers({
    'content-type': 'application/json', accept: 'application/json, text/event-stream',
    authorization: 'Bearer ' + tokens.access_token, 'mcp-protocol-version': version,
  });
  let id = 0;
  async function rpc(method, params, notification = false) {
    const request = { jsonrpc: '2.0', method, params };
    if (!notification) request.id = ++id;
    const response = await http(url, { method: 'POST', headers, body: JSON.stringify(request) }, 185_000);
    const session = response.headers.get('mcp-session-id');
    if (method === 'initialize' && session) headers.set('mcp-session-id', session);
    if (notification && response.status === 202) return;
    const result = await json(response, 'Poki ' + method);
    if (result.id !== request.id || result.error || !result.result) {
      throw new Error(`Poki ${method} 未完成`);
    }
    return result.result;
  }
  const init = await rpc('initialize', {
    protocolVersion: version, capabilities: {}, clientInfo: { name: 'Inkbox iMessage for Poki', version: '0.1.0' },
  });
  if (init.protocolVersion !== version || !headers.has('mcp-session-id')) throw new Error('Poki Relay 未建立受支持的会话');
  await rpc('notifications/initialized', undefined, true);
  return {
    list: () => rpc('tools/list', {}),
    call: args => rpc('tools/call', { name: 'ask_poki', arguments: args }),
    async close() {
      await http(url, { method: 'DELETE', headers }, 3000).then(r => r.body?.cancel()).catch(() => {});
    },
  };
}

export async function askPoki(url, task, { conversation, message }) {
  const client = await connectPoki(url);
  try {
    const listing = await client.list();
    const tool = listing.tools?.find(tool => tool.name === 'ask_poki');
    if (!tool) {
      return { text: 'Poki 暂未提供 ask_poki。请检查 Poki → Diagnostics → Testing 和模型登录。', complete: false };
    }
    const fields = tool.inputSchema?.properties;
    const structured = fields?.conversation_id && fields?.message;
    // The same MCP session owns the job. Never resubmit the task after it was sent.
    let result = await client.call(structured ? { task, conversation_id: conversation, message } : { task });
    for (let polls = 0; ; polls++) {
      const text = result.content?.filter(item => item.type === 'text').map(item => item.text).join('\n').trim();
      if (!text) return { text: 'Poki 没有返回文字。请查看手机上的运行记录。', complete: false };
      if (result.isError || !text.startsWith('working:')) {
        // Builds before threaded history returned a status envelope. Keep one readable answer.
        const legacy = !structured && text.match(/^result: (done|not done): ([\s\S]*?)(?:\nPoki said: |\nerror: |$)/);
        return { text: legacy ? legacy[2].trim() : text, complete: !result.isError };
      }
      if (polls === 2) return { text: 'Poki 仍在处理，请到 Poki 查看结果。此指令不会自动重发。', complete: false };
      await new Promise(resolve => setTimeout(resolve, 3000));
      result = await client.call({ check: true });
    }
  } finally {
    await client.close();
  }
}
