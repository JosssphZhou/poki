import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createInterface } from 'node:readline';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { root } from '../src/config.mjs';
import { isHttpHost, normalizeHttpHosts } from '../src/install/http-endpoint.mjs';

const cli = join(root, 'bin/install-iphone.mjs');
const fakeBridge = join(root, 'src/install/fake-bridge.mjs');
const fastEnv = { POKI_INSTALL_WAIT_MS: '20000', POKI_INSTALL_POLL_MS: '20', POKI_INSTALL_RETRY_MS: '20', POKI_FAKE_DELAY_MS: '30', POKI_INSTALL_DIALOGS: '0' };

const exec = promisify(execFile);
const sub = (state, ...args) => exec(process.execPath, [cli, ...args, '--state', state]);

function typeCode(state, input) {
    const child = spawn(process.execPath, [cli, 'code', '--state', state], { stdio: ['pipe', 'pipe', 'pipe'] });
    child.stdout.resume();
    child.stderr.resume();
    child.stdin.end(input);
    return new Promise(resolve => child.on('close', code => resolve(code)));
}

async function stateDir(t) {
    const dir = await mkdtemp(join(tmpdir(), 'poki-http-host-'));
    t.after(() => rm(dir, { recursive: true, force: true }));
    return dir;
}

function installer(state, args, env = {}) {
    const child = spawn(process.execPath, [cli, 'run', '--json', '--bridge', fakeBridge, '--state', state, ...args], {
        env: { ...process.env, ...fastEnv, POKI_FAKE_SCENARIO: 'happy', POKI_APPLE_ID: 'tester@example.com', POKI_SETUP_PASSWORD: 'correct horse', ...env },
    });
    const events = [];
    let stderr = '';
    child.stderr.on('data', chunk => { stderr += chunk; });
    createInterface({ input: child.stdout }).on('line', async line => {
        const event = JSON.parse(line);
        events.push(event);
        if (event.event === 'wait' && event.wait === 'apple_code') await typeCode(state, '123456\n');
        if (event.event === 'wait' && ['open_poki', 'open_poki_tell'].includes(event.wait)) await sub(state, 'done', 'open_poki');
    });
    return new Promise(resolve => child.on('close', code => resolve({ code, events, stderr })));
}

test('host validation matches the signer', () => {
    for (const good of ['gateway.example.com', '203.0.113.9', '192.168.1.0/24', '2001:db8:12::34', '2001:db8:12::/48', 'my-mac.local']) {
        assert.equal(isHttpHost(good), true, `accept ${good}`);
    }
    for (const bad of ['', 'http://gateway.example.com', 'gateway.example.com:3425', 'gateway.example.com/v1',
        'user@gateway.example.com', 'gateway.example.com?x=1', 'gateway.example.com#f', 'gateway.example.com/v1/v2', 'has space']) {
        assert.equal(isHttpHost(bad), false, `reject ${bad}`);
    }
    assert.deepEqual(normalizeHttpHosts([' 203.0.113.9 ', 'Gateway.Example.COM.']), ['203.0.113.9', 'gateway.example.com']);
});

test('a malformed --allow-http-host is refused before the bridge starts', async t => {
    const state = await stateDir(t);
    const result = await installer(state, ['--allow-http-host', 'http://gateway.example.com']);
    assert.equal(result.code, 2, result.stderr);
    assert.match(result.stderr, /--allow-http-host takes a DNS name/);
    assert.equal(result.events.length, 0, 'no install events');
});

test('--update-only keeps the opt-in, because a renewal re-signs a fresh IPA', async t => {
    const state = await stateDir(t);
    const envLog = join(state, 'bridge-env.json');
    const result = await installer(state, ['--update-only', '--allow-http-host', '203.0.113.9'], { POKI_FAKE_ENV_LOG: envLog });
    assert.equal(result.code, 0, result.stderr);
    assert.deepEqual(JSON.parse(await readFile(envLog, 'utf8')), { http_host: '203.0.113.9' });
});

test('the named host reaches the signing bridge, and no opt-in leaves it unset', async t => {
    for (const [args, expected] of [
        [['--allow-http-host', '203.0.113.9', '--allow-http-host', 'Gateway.Example.COM.'], '203.0.113.9,gateway.example.com'],
        [[], null],
    ]) {
        await t.test(expected === null ? 'no flag' : 'two hosts', async t => {
            const state = await stateDir(t);
            const envLog = join(state, 'bridge-env.json');
            const result = await installer(state, args, { POKI_FAKE_ENV_LOG: envLog });
            assert.equal(result.code, 0, result.stderr);
            assert.deepEqual(JSON.parse(await readFile(envLog, 'utf8')), { http_host: expected });
        });
    }
});
