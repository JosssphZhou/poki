#!/usr/bin/env node
// 配置 Poki 的 BlueBubbles（iMessage）通道。
// 只写本地私有配置并做一次只读连通性检查，不安装 App、不发送任何消息。
import { parseArgs } from 'node:util';
import { readFile, writeFile, mkdir, chmod, rename, stat } from 'node:fs/promises';
import { createInterface } from 'node:readline/promises';
import { Writable } from 'node:stream';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';

const defaultDir = join(homedir(), '.config/poki-agent/imessage');

const help = `Usage: poki imessage-setup [options]
  --url <url>            BlueBubbles 本地服务地址，默认 http://127.0.0.1:1234
  --password <pass>      服务器密码（不推荐：会留在 shell 历史里，优先交互输入）
  --sender <address>     唯一允许的发送者（邮箱或手机号）
  --chat-guid <guid>     精确的直聊 GUID，默认 iMessage;-;<sender>
  --device <name|id>     Poki 目标设备
  --config-dir <dir>     配置目录，默认 ~/.config/poki-agent/imessage
  --no-check             跳过连通性检查
  --force                覆盖已存在的配置
  --help

只写 ~/.config/poki-agent/imessage/{imessage.json,connection.json}（权限 600）。
不会下载或启动 BlueBubbles，也不会发送任何消息。`;

function loopbackURL(text) {
  let url;
  try { url = new URL(text); } catch { throw new Error('服务器地址必须是合法的 HTTP URL。'); }
  if (url.protocol !== 'http:') throw new Error('只支持 http:// 的本地地址（BlueBubbles 默认不启用 TLS）。');
  if (!['127.0.0.1', 'localhost', '[::1]', '::1'].includes(url.hostname)) {
    throw new Error('只接受本机地址（127.0.0.1 / localhost）。Poki 不需要把 BlueBubbles 暴露到公网。');
  }
  if (url.username || url.password || url.search || url.hash || !['', '/'].includes(url.pathname)) {
    throw new Error('地址里不能带账号、密码、路径、查询串或片段。');
  }
  return url.origin;
}

async function ping(url, password) {
  const target = new URL('/api/v1/ping', url);
  target.searchParams.set('password', password);
  let response;
  try {
    response = await fetch(target, { method: 'GET', redirect: 'error', signal: AbortSignal.timeout(8000) });
  } catch (error) {
    throw new Error(`连不上 ${url}：${error?.cause?.code ?? error?.message ?? 'unknown'}。确认 BlueBubbles 正在运行、端口一致。`);
  }
  if (response.status === 401 || response.status === 403) throw new Error('认证被拒（401/403）。密码和 BlueBubbles Connection 里设置的不一致。');
  if (!response.ok) throw new Error(`BlueBubbles 返回 HTTP ${response.status}。`);
  const body = await response.json().catch(() => null);
  if (!body || body.status !== 200) throw new Error('BlueBubbles 没有确认 ping（返回体异常）。');
  return true;
}

async function askHidden(question) {
  const input = createInterface({
    input: process.stdin,
    output: new Writable({ write(chunk, encoding, callback) { callback(); } }),
    terminal: true,
  });
  try {
    console.log(question);
    return (await input.question('> ')).trim();
  } finally { input.close(); }
}

async function ask(question) {
  const input = createInterface({ input: process.stdin, output: process.stdout });
  try { return (await input.question(question)).trim(); } finally { input.close(); }
}

async function main() {
  const { values } = parseArgs({ options: {
    url: { type: 'string' }, password: { type: 'string' }, sender: { type: 'string' },
    'chat-guid': { type: 'string' }, device: { type: 'string' },
    'config-dir': { type: 'string' }, 'no-check': { type: 'boolean' },
    force: { type: 'boolean' }, help: { type: 'boolean', short: 'h' },
  } });
  if (values.help) { console.log(help); return; }

  const directory = resolve(values['config-dir'] ?? defaultDir);
  const connectionPath = join(directory, 'connection.json');
  const configPath = join(directory, 'imessage.json');

  const exists = await stat(connectionPath).then(() => true, () => false);
  if (exists && !values.force) {
    throw new Error(`已经存在配置：${directory}\n要覆盖请加 --force。检查现有连接用：poki imessage --check`);
  }

  const interactive = process.stdin.isTTY && (!values.sender || !values.device || !values.password);
  let url = values.url, password = values.password, sender = values.sender;
  let chatGuid = values['chat-guid'], device = values.device;

  if (!url) {
    url = interactive ? (await ask('BlueBubbles 本地服务地址 [http://127.0.0.1:1234]: ')) || 'http://127.0.0.1:1234' : 'http://127.0.0.1:1234';
  }
  url = loopbackURL(url);

  if (!password) {
    if (!process.stdin.isTTY) throw new Error('非交互环境请用 --password 传入，或在终端里运行让密码隐藏输入。');
    password = await askHidden('BlueBubbles 服务器密码（输入不回显）:');
    if (!password) throw new Error('密码不能为空。');
  }

  if (!sender) {
    if (!interactive) throw new Error('缺少 --sender：唯一允许的 iMessage 发送者。');
    sender = await ask('允许的发送者（邮箱或手机号）: ');
  }
  if (!sender || sender.includes(';')) throw new Error('sender 必须是一个地址，且不能包含分号。');

  if (!chatGuid) {
    const fallback = `iMessage;-;${sender}`;
    chatGuid = interactive ? (await ask(`直聊 GUID [${fallback}]: `)) || fallback : fallback;
  }
  if (![`iMessage;-;${sender}`, `any;-;${sender}`].includes(chatGuid)) {
    throw new Error(`GUID 必须是 iMessage;-;${sender} 或 any;-;${sender}。`);
  }

  if (!device) {
    if (!interactive) throw new Error('缺少 --device：Poki 要操作的设备名或 UUID。');
    device = await ask('Poki 设备名或 UUID: ');
  }
  if (!device) throw new Error('device 不能为空。');

  if (!values['no-check']) {
    process.stdout.write('检查 BlueBubbles 连通性… ');
    await ping(url, password);
    console.log('通过');
  }

  await mkdir(directory, { recursive: true, mode: 0o700 });
  await chmod(directory, 0o700);
  const write = async (path, value) => {
    const temporary = `${path}.${process.pid}.tmp`;
    await writeFile(temporary, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
    await rename(temporary, path);
    await chmod(path, 0o600);
  };
  await write(configPath, { sender, chatGuid, device, auth: 'oauth' });
  await write(connectionPath, { url, password });

  console.log(`\n配置已写入 ${directory}`);
  console.log(`  imessage.json   sender=${sender}  device=${device}`);
  console.log(`  connection.json ${url}`);
  console.log(`
下一步：
  1. 确认 BlueBubbles 已经在 Messages 里登录 Apple 账号，并授予「完全磁盘访问权限」。
  2. 检查通道（只读，不发消息）：  poki imessage --check
  3. 正式启动通道：                poki imessage
通道只处理启动之后的新消息。`);
}

main().catch(error => { console.error(error?.message ?? error); process.exitCode = 1; });
