import http from 'node:http';
import { EventEmitter, once } from 'node:events';
import { Server } from 'socket.io';

const id = (kind, number) => `pho_${kind}_${String(number).padStart(26, '0')}`;

export async function makePhoton() {
  const fixture = new EventEmitter();
  const project = id('prj', 1);
  const user = (number, handle, kind) => ({ id: id('usr', number), projectId: project, platform: 'imessage', handle, kind, details: {}, metadata: {} });
  const agent = user(1, '+14155550188', 'agent');
  const people = { 1: user(2, 'allowed@example.test', 'human'), 2: user(3, 'other@example.test', 'human') };
  const space = (number, kind) => ({ id: id('spc', number), projectId: project, platform: 'imessage', kind, participantIds: [agent.id], details: {}, metadata: {} });
  const subscribers = new Set();
  let seq = 0;
  Object.assign(fixture, { project, agent, space: space(1, 'direct'), key: 'pho_sk_local-photon-test-secret',
    events: [], sent: [], ids: [], requests: [], subscriptions: [], assignments: [] });

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const send = (status, data) => res.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify(data));
    const problem = ({ status, code }) => res.writeHead(status, { 'content-type': 'application/problem+json' })
      .end(JSON.stringify({ type: `https://photon.codes/docs/problems/${code.toLowerCase().replaceAll('_', '-')}`, title: code, status, code }));
    if (req.headers.authorization !== `Bearer ${fixture.key}`) { problem({ status: 401, code: 'NOT_AUTHENTICATED' }); return; }
    let raw = ''; for await (const chunk of req) raw += chunk;
    const body = raw ? JSON.parse(raw) : null;
    fixture.requests.push({ method: req.method, path: url.pathname, key: req.headers['idempotency-key'], body });
    const now = new Date().toISOString();
    if (url.pathname === `/v1/projects/${project}/messages` && req.method === 'POST') {
      if (fixture.sendError) {
        const error = fixture.sendError;
        if (error.once) fixture.sendError = null;
        problem(error);
        return;
      }
      const message = { id: id('msg', 1000 + fixture.sent.length), projectId: project, platform: 'imessage', space: fixture.space, sentBy: agent,
        content: body.content, metadata: {}, createdAt: now, updatedAt: now, status: 'dispatched', timestamps: { dispatchedAt: now } };
      fixture.sent.push(body);
      fixture.ids.push(message.id);
      send(202, message);
      fixture.emit('reply', body.content.text);
      return;
    }
    if (url.pathname === `/v1/projects/${project}/platforms/imessage/assignments`) {
      if (fixture.assignError) { problem(fixture.assignError); return; }
      if (req.method === 'GET') { send(200, { assignments: fixture.assignments }); return; }
      if (fixture.assignments.some(assignment => assignment.handle === body.handle)) { problem({ status: 409, code: 'ASSIGNMENT_EXISTS' }); return; }
      const assignment = { assignmentId: `assignment-${fixture.assignments.length + 1}`, projectId: project, platform: 'imessage', handle: body.handle,
        assignedPhoneNumber: agent.handle, optIn: { state: 'pending' }, createdAt: now, updatedAt: now };
      fixture.assignments.push(assignment);
      send(201, assignment);
      return;
    }
    problem({ status: 404, code: 'NOT_FOUND' });
  });
  const events = new Server(server, { path: `/v1/projects/${project}/events/ws`, addTrailingSlash: false, transports: ['websocket'],
    allowRequest: (req, allow) => allow(null, req.headers.authorization === `Bearer ${fixture.key}`) });
  events.on('connection', socket => {
    socket.on('disconnect', () => subscribers.delete(socket));
    socket.on('subscribe', ({ startSeq, apiVersion }, acknowledge) => {
      fixture.subscriptions.push(startSeq);
      acknowledge({ ok: true, projectId: project, apiVersion, connectionId: socket.id, startSeq, limits: { maxFrameBytes: 1048576, maxReplyBodyBytes: 65536 } });
      if (startSeq > 0) for (const item of fixture.events) if (item.seq > startSeq) fixture.deliver(item.seq, [socket]);
      subscribers.add(socket);
    });
  });

  fixture.deliver = (cursor, sockets = subscribers) => {
    const item = fixture.events.find(item => item.seq === cursor);
    for (const socket of sockets) socket.emit('delivery', item.event, { seq: item.seq, replyExpected: false });
  };
  fixture.event = (type, object) => {
    seq += 2;
    const now = new Date().toISOString();
    fixture.events.push({ seq, event: { id: id('evt', seq), type, apiVersion: '2026-07-01', source: 'imessage.photon', timestamp: now,
      data: { projectId: project, object: { id: id('msg', seq), projectId: project, platform: 'imessage', metadata: {}, createdAt: now, updatedAt: now, ...object } } } });
    fixture.deliver(seq);
    return seq;
  };
  fixture.add = (text, { sender = 1, group = false, content = { type: 'text', format: 'plain', text } } = {}) => fixture.event('message.received', {
    space: group ? space(3, 'group') : sender === 1 ? fixture.space : space(2, 'direct'), sentBy: people[sender], receivedBy: agent,
    content, status: 'received', timestamps: { receivedAt: new Date().toISOString() } });
  fixture.fail = index => fixture.event('message.failed', { id: fixture.ids[index], space: fixture.space, sentBy: agent, content: fixture.sent[index].content,
    status: 'failed', failure: { code: 'recipient_unreachable', message: 'The recipient could not be reached.' }, timestamps: {} });
  fixture.drop = () => { for (const socket of subscribers) socket.conn.close(); };
  fixture.kick = () => { for (const socket of subscribers) socket.disconnect(); };

  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  fixture.url = `http://127.0.0.1:${server.address().port}`;
  fixture.close = async () => { server.closeAllConnections(); await events.close(); };
  return fixture;
}
