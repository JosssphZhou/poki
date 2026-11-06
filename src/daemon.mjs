import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdir, writeFile, readFile, unlink, rename, chmod } from 'node:fs/promises';
import { once } from 'node:events';
import { NodeStreamableHTTPServerTransport, localhostHostValidation, localhostOriginValidation, hostHeaderValidation } from '@modelcontextprotocol/node';
import { createServer, definitions } from './tools.mjs';
import { Coordination } from './coordination.mjs';
import { Devices } from './device.mjs';
import { stateDir, endpointFile } from './config.mjs';
import { startUpdateChecks } from './update-check.mjs';
import { warnIfNativeStale } from './build-info.mjs';

const portIndex = process.argv.indexOf('--port');
const port = portIndex < 0 ? 47825 : Number(process.argv[portIndex + 1]);
if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('Invalid port');
await warnIfNativeStale();
const sessions = new Map();
const coordinator = new Coordination();
const token = process.env.POKI_MCP_TOKEN?.trim() || randomBytes(32).toString('hex');
// A short token is the only thing standing between the network and the device, and it is cheap
// to type in a shell by mistake.
if (token.length < 32) throw new Error('POKI_MCP_TOKEN must be at least 32 characters long.');
const expected = Buffer.from(`Bearer ${token}`);
const requestedBind = process.env.POKI_BIND_HOST?.trim() ?? '';
if (process.env.POKI_BIND_HOST !== undefined && !requestedBind) throw new Error('POKI_BIND_HOST is empty. Unset it to listen on 127.0.0.1.');
const loopback = new Set(['127.0.0.1', 'localhost', '::1']);
const wildcard = new Set(['0.0.0.0', '::']);
const requested = (requestedBind || '127.0.0.1').split(',').map(part => part.trim()).filter(Boolean);
if (!requested.length) throw new Error('POKI_BIND_HOST must name at least one address.');
if (requested.some(host => wildcard.has(host)) && requested.length > 1) throw new Error('POKI_BIND_HOST: a wildcard address already covers every interface, so it cannot be combined with another one.');
// `src/stdio.mjs` accepts a 127.0.0.1 endpoint only, and every local client (the agent, bin/call.mjs)
// reads that endpoint from mcp.json. Serving loopback as well is what keeps them working once the
// daemon also listens on a LAN address.
const bindHosts = [...new Set(requested.some(host => wildcard.has(host) || loopback.has(host)) ? requested : [...requested, '127.0.0.1'])];
const serveLoopback = bindHosts.some(host => loopback.has(host) || wildcard.has(host));
const hostAllow = (process.env.POKI_HOST_ALLOW ?? '').split(',').map(part => part.trim()).filter(Boolean);
// Binding beyond loopback without an allowlist answers 403 to every client, which reads as
// "the daemon is broken" rather than "you forgot a variable".
if (bindHosts.some(host => !loopback.has(host))) {
  if (!hostAllow.length) throw new Error(`POKI_BIND_HOST=${bindHosts.join(',')} serves beyond loopback, so POKI_HOST_ALLOW must list the Host headers your clients send.`);
  for (const host of bindHosts) if (!wildcard.has(host) && !hostAllow.includes(host)) throw new Error(`POKI_BIND_HOST=${host} is not in POKI_HOST_ALLOW (${hostAllow.join(',')}); every request to it would be rejected.`);
}
// Local clients send `Host: 127.0.0.1:PORT`, so an allowlist that omits loopback locks out the
// very clients the loopback listener exists for.
if (serveLoopback && hostAllow.length && !hostAllow.some(host => loopback.has(host))) throw new Error(`POKI_HOST_ALLOW (${hostAllow.join(',')}) must include 127.0.0.1 or localhost, because local clients connect through the loopback endpoint.`);
const validHost = hostAllow.length ? hostHeaderValidation(hostAllow) : localhostHostValidation();
const validOrigin = localhostOriginValidation();
const active = new Set();

async function handle(req, res) {
  if (!validHost(req, res) || !validOrigin(req, res)) return;
  const received = Buffer.from(req.headers.authorization ?? '');
  if (received.length !== expected.length || !timingSafeEqual(received, expected)) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Authorization required' }));
    return;
  }
  if (!['/mcp', '/session/close', '/request/cancel'].includes(req.url)) { res.writeHead(404); res.end(); return; }
  const session = req.headers['x-poki-mcp-session'];
  if (typeof session !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(session)) { res.writeHead(400); res.end('Invalid session'); return; }
  if (!sessions.has(session)) sessions.set(session, new Devices(coordinator));
  const devices = sessions.get(session);
  devices.peers = () => sessions.values();
  if (req.url === '/session/close') {
    if (req.method !== 'POST') { res.writeHead(405); res.end(); return; }
    await devices.close(); sessions.delete(session); res.end('{}'); return;
  }
  if (req.url === '/request/cancel') {
    if (req.method !== 'POST') { res.writeHead(405); res.end(); return; }
    const id = req.headers['x-poki-request'];
    if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(id)) { res.writeHead(400); res.end(); return; }
    devices.cancelledRequests ??= new Set();
    devices.cancelledRequests.add(id);
    const expiration = setTimeout(() => devices.cancelledRequests.delete(id), 60000); expiration.unref();
    for (const operation of coordinator.operations) if (operation.owner === devices && operation.requestId === id) operation.controller.abort(new DOMException('Request cancelled', 'AbortError'));
    res.end('{}'); return;
  }
  const server = createServer((name, args, extra) => {
    if (devices.cancelledRequests?.delete(extra?.requestId)) throw new DOMException('Request cancelled', 'AbortError');
    return devices.call(name, args, extra?.signal, extra?.requestId);
  });
  const transport = new NodeStreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
  active.add(server);
  res.once('close', () => { active.delete(server); void server.close(); });
  try {
    await server.connect(transport);
    await transport.handleRequest(req, res);
  } catch (error) {
    if (!res.headersSent) res.writeHead(500, { 'Content-Type': 'application/json' });
    if (!res.writableEnded) res.end(JSON.stringify({ error: error.message }));
  }
}

await mkdir(stateDir, { recursive: true, mode: 0o700 });
const servers = bindHosts.map(() => http.createServer(handle));
servers[0].listen(port, bindHosts[0]);
await once(servers[0], 'listening');
const actualPort = servers[0].address().port;
for (const [index, server] of servers.entries()) if (index > 0) server.listen(actualPort, bindHosts[index]);
await Promise.all(servers.slice(1).map(server => once(server, 'listening')));
const entry = { url: `http://127.0.0.1:${actualPort}/mcp`, port: actualPort, token, enabled: true, pid: process.pid };
const temporary = `${endpointFile}.${process.pid}.tmp`;
await writeFile(temporary, JSON.stringify(entry, null, 2), { mode: 0o600, flag: 'wx' });
await rename(temporary, endpointFile);
await chmod(endpointFile, 0o600);
console.log(JSON.stringify({ event: 'ready', url: entry.url, endpointFile, tools: definitions.length }));

const stopUpdateChecks = startUpdateChecks();

let stopping = false;
async function stop() {
  if (stopping) return;
  stopping = true;
  stopUpdateChecks();
  const closed = Promise.all(servers.map(server => new Promise(resolve => server.close(resolve))));
  for (const server of servers) server.closeAllConnections();
  await Promise.allSettled([...sessions.values()].map(devices => devices.close()));
  await Promise.allSettled([...active].map(server => server.close()));
  await closed;
  const entry = await readFile(endpointFile, 'utf8').then(JSON.parse).catch(() => null);
  if (entry?.pid === process.pid) await unlink(endpointFile);
}
process.on('SIGINT', () => void stop());
process.on('SIGTERM', () => void stop());

const supervisedBy = Number(process.env.POKI_PARENT_PID ?? '');
if (Number.isInteger(supervisedBy) && supervisedBy > 0) {
  const watchdog = setInterval(() => {
    try { process.kill(supervisedBy, 0); } catch {
      console.error(JSON.stringify({ event: 'parent-gone', pid: supervisedBy }));
      void stop();
      return;
    }
    if (process.ppid !== supervisedBy) {
      console.error(JSON.stringify({ event: 'parent-changed', expected: supervisedBy, actual: process.ppid }));
      void stop();
    }
  }, 1500);
  watchdog.unref();
  process.on('exit', () => clearInterval(watchdog));
}
