import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { clientSecretRequest, phoneRequestFile, phoneTools, sessionConfig } from '../src/voice-session.mjs';

test('the Poki app asks OpenAI for the same voice session the voice bridge asks for by default', async () => {
  const bundled = JSON.parse(await readFile(phoneRequestFile, 'utf8'));
  assert.deepEqual(bundled, clientSecretRequest(sessionConfig()), 'the app bundles an old session: run node src/voice-session.mjs');
  // The app runs every tool of that session on the phone, with no Mac to run the others.
  assert.ok(phoneTools.every(tool => tool.local));
});
