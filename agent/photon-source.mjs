import { randomUUID } from 'node:crypto';
import { io } from 'socket.io-client';
import { Photon, ApiError } from '@photon-ai/api';
import { ChannelCursor, channelURL } from './channel-state.mjs';

const apiVersion = '2026-07-01';
const typingRefresh = 20000;

function connection() {
  const project = process.env.PHOTON_PROJECT_ID;
  if (!/^pho_prj_[0-9a-z]{26}$/.test(project ?? '')) throw new Error('Set PHOTON_PROJECT_ID to the Photon project ID (pho_prj_...).');
  const key = process.env.PHOTON_API_KEY;
  if (!key) throw new Error('Set PHOTON_API_KEY in the environment.');
  const url = channelURL(process.env.PHOTON_API_URL ?? 'https://api.photon.codes', 'PHOTON_API_URL');
  if (url.origin !== 'https://api.photon.codes' && url.protocol !== 'http:') {
    throw new Error('PHOTON_API_URL must be the Photon API or a loopback HTTP development server.');
  }
  return { project, key, url, photon: new Photon({ baseUrl: url.origin, headers: { Authorization: `Bearer ${key}` } }) };
}

function rejection(error) {
  return `HTTP ${error.status}${typeof error.body?.code === 'string' ? `, ${error.body.code}` : ''}`;
}

export async function assignSharedLine(sender) {
  const { project, photon } = connection();
  const assignments = photon.projects.platforms.imessage.assignments;
  try {
    const assignment = await assignments.create({ path: { id: project }, headers: { 'idempotency-key': randomUUID() }, body: { handle: sender } });
    return assignment.assignedPhoneNumber;
  } catch (error) {
    if (!(error instanceof ApiError)) throw new Error('Photon request failed. Check the network and the project in the Photon dashboard before retrying.');
    if (error.body?.code === 'ASSIGNMENT_EXISTS') {
      let pageToken;
      do {
        const page = await assignments.list({ path: { id: project }, query: pageToken ? { pageToken } : {} }).catch(() => ({ assignments: [] }));
        const existing = page.assignments.find(assignment => assignment.handle === sender);
        if (existing) return existing.assignedPhoneNumber;
        pageToken = page.nextPageToken;
      } while (pageToken);
      throw new Error('This sender already has a shared line. Find its number in the Photon dashboard under iMessage.');
    }
    if (error.status === 403) throw new Error('This API key cannot assign shared lines; that needs platforms:write. Assign the sender in the Photon dashboard under iMessage instead.');
    throw new Error(`Photon rejected the assignment (${rejection(error)}). Check the plan's shared iMessage capacity.`);
  }
}

export class PhotonSource {
  constructor({ sender, stateDirectory }) {
    if (typeof sender !== 'string' || !sender.trim()) throw new Error('Configure exactly one iMessage sender.');
    this.sender = sender.trim();
    Object.assign(this, connection());
    this.progressStyle = 'opening';
    this.state = new ChannelCursor(stateDirectory, 'photon', `${this.url.origin}/${this.project}/${this.sender}`);
    this.queue = [];
    this.sent = new Set();
    this.lastQueued = 0;
    this.skipped = 0;
    this.presence = Promise.resolve();
    this.unavailable = new Set();
  }

  listen(signal) {
    return new Promise((resolve, reject) => {
      const socket = this.socket = io(this.url.origin, {
        path: `/v1/projects/${this.project}/events/ws`, addTrailingSlash: false, transports: ['websocket'],
        extraHeaders: { Authorization: `Bearer ${this.key}` }, autoConnect: false,
      });
      let ready = false, streamError;
      const stop = message => {
        socket.disconnect();
        if (ready) this.failure = new Error(message); else reject(new Error(message));
      };
      signal?.addEventListener('abort', () => { socket.disconnect(); reject(signal.reason); }, { once: true });
      socket.on('connect', () => {
        socket.timeout(10000).emit('subscribe', { startSeq: this.lastQueued, apiVersion }, (error, result) => {
          if (result?.ok) {
            if (ready) console.log('photon: event stream resumed.');
            ready = true;
            resolve();
            return;
          }
          if (ready && (error || result?.error?.retryable)) { socket.io.engine.close(); return; }
          stop(`Photon did not accept the event subscription${result?.error?.code ? ` (${result.error.code})` : ''}.`);
        });
      });
      socket.on('connect_error', () => {
        if (!ready || !socket.active) stop('Photon refused the event connection. Check PHOTON_PROJECT_ID, PHOTON_API_KEY and its project:read permission.');
      });
      socket.on('delivery_error', error => { streamError = error?.code; });
      socket.on('disconnect', reason => {
        if (reason === 'io server disconnect') stop(`Photon closed the event stream${streamError ? ` (${streamError})` : ''}. Fix the cause before restarting.`);
        else if (socket.active) console.error(`photon: event stream disconnected (${reason}); reconnecting.`);
      });
      socket.on('delivery', (event, metadata) => {
        const seq = metadata?.seq;
        if (!Number.isSafeInteger(seq) || seq < 0) { stop('Photon returned an invalid event cursor.'); return; }
        if (seq <= this.lastQueued) return;
        this.lastQueued = seq;
        const message = this.message(event);
        if (message) this.queue.push({ seq, id: event.data.object.id, message });
        else this.skipped = seq;
      });
      socket.connect();
    });
  }

  check(signal) { return this.listen(signal); }

  async open(signal) {
    await this.state.open();
    this.lastQueued = this.state.cursor ?? 0;
    await this.listen(signal);
  }

  message(event) {
    const message = event?.data?.object;
    if (event?.type === 'message.failed' && this.sent.delete(message?.id)) {
      console.error(`photon: a reply was not delivered (${message.failure?.code ?? 'no reason given'}). Check the conversation.`);
    }
    if (event?.type !== 'message.received' || message?.platform !== 'imessage' || message.space?.kind !== 'direct' ||
        message.sentBy?.kind !== 'human' || message.sentBy.handle !== this.sender || message.receivedBy?.kind !== 'agent' ||
        !['text', 'attachment', 'voice', 'group'].includes(message.content?.type)) return null;
    this.target = { spaceId: message.space.id, senderId: message.receivedBy.id };
    return { text: message.content.type === 'text' && message.content.format === 'plain' ? message.content.text : null };
  }

  async *read() {
    if (this.failure) throw this.failure;
    let yielded = 0;
    while (this.queue.length) {
      const { seq, id, message } = this.queue.shift();
      this.signal('read receipts', () => this.photon.projects.markMessageRead({
        path: { id: this.project, messageId: id }, headers: { 'idempotency-key': randomUUID() },
      }));
      yielded = seq;
      yield { id: seq, ...message };
    }
    const cursor = this.state.cursor ?? 0;
    if (this.skipped > cursor && cursor >= yielded) await this.state.save(this.skipped);
  }

  acknowledge(id) { return this.state.save(id); }
  replyTo() { return this; }

  signal(feature, request) {
    this.presence = this.presence.then(() => this.unavailable.has(feature) ? undefined : request()).catch(error => {
      if (!(error instanceof ApiError) || error.status >= 500) return;
      this.unavailable.add(feature);
      console.error(`photon: ${feature} are unavailable (${rejection(error)}); continuing without them.`);
    });
  }

  setTyping(typing) {
    const { spaceId, senderId } = this.target;
    this.signal('typing indicators', () => this.photon.projects.setSpaceTyping({ path: { id: this.project, spaceId }, body: { senderId, typing } }));
  }

  async send(text, metadata) {
    if (!text.trim()) return;
    if (!this.target) throw new Error('No Photon conversation to reply in yet.');
    const final = metadata?.kind === 'final', typing = this.typing;
    if (final) { clearInterval(typing); this.typing = null; }
    let message;
    try {
      message = await this.photon.projects.sendMessage({
        path: { id: this.project }, headers: { 'idempotency-key': randomUUID() },
        body: { ...this.target, content: { type: 'text', format: 'plain', text } },
      });
    } catch (error) {
      if (error instanceof ApiError) throw new Error(`Photon request rejected (${rejection(error)}). Check the API key's project:write permission and the sender's shared-line assignment.`);
      throw new Error('Photon request failed. Delivery may be uncertain; check the conversation before restarting.');
    }
    this.sent.add(message.id);
    if (this.sent.size > 100) this.sent.delete(this.sent.values().next().value);
    if (final) {
      if (typing) this.setTyping(false);
    } else if (metadata?.kind || typing) {
      this.setTyping(true);
      this.typing ??= setInterval(() => this.setTyping(true), typingRefresh);
    }
  }

  close() {
    clearInterval(this.typing);
    this.socket?.disconnect();
  }
}
