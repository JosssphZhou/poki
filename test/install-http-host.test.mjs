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
const validatorScript = join(root, 'native/ios-app/scripts/validate-http-endpoint-host.py');
const fakeBridge = join(root, 'src/install/fake-bridge.mjs');
const fastEnv = { POKI_INSTALL_WAIT_MS: '20000', POKI_INSTALL_POLL_MS: '20', POKI_INSTALL_RETRY_MS: '20', POKI_FAKE_DELAY_MS: '30', POKI_INSTALL_DIALOGS: '0' };

const GOOD_HOSTS = [
    'gateway.example.com',
    '203.0.113.9',
    '2001:db8:12::34',
    '::ffff:203.0.113.9',
    'my-mac.local',
    'xn--bcher-kva.example',
    'devbox',
];

const BAD_HOSTS = [
    '', '.', 'http://gateway.example.com', 'gateway.example.com:3425', 'gateway.example.com:', 'gateway.example.com:abc',
    'gateway.example.com:80:80', '[2001:db8:12::34]', '[2001:db8:12::34]:3425', 'fe80::1%en0', ':::',
    '192.168.1.0/24', '2001:db8:12::/48', '999.999.999.999', '127.1', '01.2.3.4', '3405803785', '203.0.113.9.',
    '.example.com', 'example..com', 'example.com..', '-bad.example.com', 'bad-.example.com', '*.example.com',
    '203.0.113.9,evil.com', '${POKI_HTTP_ENDPOINT_HOST}', 'Gateway.Example.COM',
    'gateway.example.com/v1', 'user@gateway.example.com', 'gateway.example.com?x=1', 'gateway.example.com#f',
    'gateway.example.com/v1/v2', 'has space',
];

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
    for (const good of GOOD_HOSTS) {
        assert.equal(isHttpHost(good), true, `accept ${good}`);
    }
    for (const bad of BAD_HOSTS) {
        assert.equal(isHttpHost(bad), false, `reject ${bad}`);
    }
    assert.deepEqual(normalizeHttpHosts([' 203.0.113.9 ']), ['203.0.113.9']);
    assert.deepEqual(normalizeHttpHosts(['Gateway.Example.COM.']), ['gateway.example.com']);
    assert.deepEqual(normalizeHttpHosts(['2001:0DB8:0012:0:0:0:0:0034']), ['2001:db8:12::34']);
    assert.deepEqual(normalizeHttpHosts(['::ffff:cb00:7109']), ['::ffff:203.0.113.9']);
    assert.deepEqual(normalizeHttpHosts(['Gateway.Example.COM.', 'gateway.example.com']), ['gateway.example.com']);
    assert.deepEqual(normalizeHttpHosts(['2001:0DB8:0012:0:0:0:0:0034', '2001:db8:12::34']), ['2001:db8:12::34']);
    assert.throws(
        () => normalizeHttpHosts(['203.0.113.9', 'gateway.example.com']),
        /at most one distinct host/,
    );
    assert.throws(
        () => normalizeHttpHosts(['203.0.113.9', 'http://evil.example.com']),
        /takes a DNS name or IP literal/,
    );
});

test('XcodeGen opt-in host validator enforces the same single-host contract', async () => {
    const nonCanonical = [
        [' 203.0.113.9 ', '203.0.113.9'],
        ['Gateway.Example.COM.', 'gateway.example.com'],
        ['2001:0DB8:0012:0:0:0:0:0034', '2001:db8:12::34'],
        ['::ffff:cb00:7109', '::ffff:203.0.113.9'],
    ];
    const pyCheck = `
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("v", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
data = json.loads(sys.argv[2])
for h in data["good"]:
    assert mod.is_valid_exception_host(h), f"expected valid: {h!r}"
    assert mod.validate_host(h) == h
for h in data["bad"]:
    assert not mod.is_valid_exception_host(h), f"expected invalid: {h!r}"
    try:
        mod.validate_host(h)
        raise AssertionError(f"should reject {h!r}")
    except ValueError:
        pass
for raw, canon in data["nonCanonical"]:
    assert mod.normalize_exception_host(raw) == canon
    try:
        mod.validate_host(raw)
        raise AssertionError(f"should reject non-canonical {raw!r}")
    except ValueError as err:
        assert canon in str(err), str(err)
`;
    const pyEnv = { ...process.env, PYTHONDONTWRITEBYTECODE: '1' };
    await exec('python3', ['-c', pyCheck, validatorScript, JSON.stringify({ good: GOOD_HOSTS, bad: BAD_HOSTS, nonCanonical })], { env: pyEnv });

    const runCli = extraEnv => new Promise(resolve => {
        const env = { ...pyEnv };
        delete env.POKI_HTTP_ENDPOINT_HOST;
        Object.assign(env, extraEnv);
        const child = spawn('python3', [validatorScript], { env, stdio: ['ignore', 'pipe', 'pipe'] });
        let stdout = '';
        let stderr = '';
        child.stdout.on('data', chunk => { stdout += chunk; });
        child.stderr.on('data', chunk => { stderr += chunk; });
        child.on('close', code => resolve({ code, stdout, stderr }));
    });

    const okRes = await runCli({ POKI_HTTP_ENDPOINT_HOST: '203.0.113.9' });
    assert.equal(okRes.code, 0, okRes.stderr);

    const unsetRes = await runCli({});
    assert.equal(unsetRes.code, 1);
    assert.match(unsetRes.stderr, /must be set/);

    const badRes = await runCli({ POKI_HTTP_ENDPOINT_HOST: '203.0.113.9,evil.com' });
    assert.equal(badRes.code, 1);
    assert.match(badRes.stderr, /Invalid POKI_HTTP_ENDPOINT_HOST/);

    const nonCanonRes = await runCli({ POKI_HTTP_ENDPOINT_HOST: 'Gateway.Example.COM.' });
    assert.equal(nonCanonRes.code, 1);
    assert.match(nonCanonRes.stderr, /Non-canonical POKI_HTTP_ENDPOINT_HOST/);
    assert.match(nonCanonRes.stderr, /gateway\.example\.com/);
});

test('a malformed --allow-http-host is refused before the bridge starts', async t => {
    const state = await stateDir(t);
    const result = await installer(state, ['--allow-http-host', '[2001:db8:12::34]:3425']);
    assert.equal(result.code, 2, result.stderr);
    assert.match(result.stderr, /--allow-http-host takes a DNS name/);
    assert.equal(result.events.length, 0, 'no install events');

    const updateBad = await installer(state, ['--update-only', '--allow-http-host', 'http://gateway.example.com']);
    assert.equal(updateBad.code, 2, updateBad.stderr);
    assert.equal(updateBad.events.length, 1);
    assert.equal(updateBad.events[0].event, 'update_result');
    assert.equal(updateBad.events[0].ok, false);
    assert.equal(updateBad.events[0].code, 'update_options_conflict');
});

test('multiple distinct --allow-http-host flags are refused before the bridge starts', async t => {
    const state = await stateDir(t);
    const result = await installer(state, ['--allow-http-host', '203.0.113.9', '--allow-http-host', 'gateway.example.com']);
    assert.equal(result.code, 2, result.stderr);
    assert.match(result.stderr, /--allow-http-host accepts at most one distinct host/);
    assert.equal(result.events.length, 0, 'no install events');

    const updateMulti = await installer(state, ['--update-only', '--allow-http-host', '203.0.113.9', '--allow-http-host', 'gateway.example.com']);
    assert.equal(updateMulti.code, 2, updateMulti.stderr);
    assert.equal(updateMulti.events.length, 1);
    assert.equal(updateMulti.events[0].event, 'update_result');
    assert.equal(updateMulti.events[0].ok, false);
    assert.equal(updateMulti.events[0].code, 'update_options_conflict');
    assert.match(updateMulti.events[0].reason, /at most one distinct host/);
});

test('--update-only keeps the opt-in, because a renewal re-signs a fresh IPA', async t => {
    const state = await stateDir(t);
    const envLog = join(state, 'bridge-env.json');
    const result = await installer(state, ['--update-only', '--allow-http-host', '203.0.113.9'], { POKI_FAKE_ENV_LOG: envLog });
    assert.equal(result.code, 0, result.stderr);
    assert.deepEqual(JSON.parse(await readFile(envLog, 'utf8')), { http_host: '203.0.113.9' });
});

test('the named host reaches the signing bridge, and no opt-in clears any ambient env var', async t => {
    for (const [label, args, extraEnv, expected] of [
        ['single normalized host', ['--allow-http-host', 'Gateway.Example.COM.'], {}, 'gateway.example.com'],
        ['repeated equivalent hosts deduplicate to one', ['--allow-http-host', '2001:0DB8:0012:0:0:0:0:0034', '--allow-http-host', '2001:db8:12::34'], {}, '2001:db8:12::34'],
        ['no flag clears ambient env', [], { POKI_HTTP_ENDPOINT_HOST: 'stale.example.com' }, null],
    ]) {
        await t.test(label, async () => {
            const state = await stateDir(t);
            const envLog = join(state, 'bridge-env.json');
            const result = await installer(state, args, { POKI_FAKE_ENV_LOG: envLog, ...extraEnv });
            assert.equal(result.code, 0, result.stderr);
            assert.deepEqual(JSON.parse(await readFile(envLog, 'utf8')), { http_host: expected });
        });
    }
});
