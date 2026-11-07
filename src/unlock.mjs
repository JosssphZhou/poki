import { checkWork, pause } from './work.mjs';

// Shared across MCP sessions. An uncertain attempt is never automatically retried.
const attempts = new Set();
export function validateKeypad(points, width, height) {
  if (width >= height || points.length !== 10) throw new Error('A portrait ten-key numeric keypad is required.');
  for (const p of points) if (!Number.isFinite(p.x) || !Number.isFinite(p.y) || p.x < 0 || p.x >= width || p.y < height * .2 || p.y >= height) throw new Error('Keypad points must be inside the observed screen.');
  const tolerance = Math.min(width, height) * .025;
  const close = (a, b) => Math.abs(a - b) <= tolerance;
  for (const row of [[1, 2, 3], [4, 5, 6], [7, 8, 9]]) {
    const [a, b, c] = row.map(i => points[i]);
    if (!close(a.y, b.y) || !close(b.y, c.y) || b.x - a.x < width * .1 || c.x - b.x < width * .1) throw new Error('Keypad rows do not match the standard numeric layout.');
  }
  for (const col of [[1, 4, 7], [2, 5, 8, 0], [3, 6, 9]]) {
    for (let i = 1; i < col.length; i++) {
      const a = points[col[i - 1]], b = points[col[i]];
      if (!close(a.x, b.x) || b.y - a.y < height * .05) throw new Error('Keypad columns do not match the standard numeric layout.');
    }
  }
}

export async function unlockDevice(ctx, args, env = process.env, attempted = attempts) {
  const target = await ctx.target();
  if (target.kind !== 'physical' || env.POKI_UNLOCK_DEVICE !== target.id) throw new Error('Unlock is disabled for this device. Configure POKI_UNLOCK_DEVICE locally.');
  let pin = env.POKI_IPHONE_PASSCODE;
  if (!/^[0-9]{6}$/.test(pin ?? '')) throw new Error('Configure a six-digit POKI_IPHONE_PASSCODE in the private local launcher. Never send it in chat.');
  if (args.empty_keypad_confirmed !== true) throw new Error('Observe an empty six-digit lock-screen keypad first.');
  const frame = ctx.frame;
  if (!frame || frame.id !== args.observation_id || frame.device !== target.id || Date.now() - frame.at > 30000 || frame.revision !== ctx.coordinator.revision(target.id)) throw new Error('Use a fresh screenshot from this session; the keypad observation has expired.');
  validateKeypad(args.digits, frame.width, frame.height);
  if (attempted.has(target.id)) throw new Error('An unlock attempt needs human review. Inspect the phone and restart the service before another attempt.');
  // Fresh server-side confirmation rejects an app keypad or a dismissed lock screen.
  const tree = await ctx.bridge({ op: 'ax' });
  const elements = tree.elements ?? [];
  const labels = elements.flatMap(e => [e.label, e.text]).filter(t => typeof t === 'string');
  const foregroundProcess = await ctx.bridge({ op: 'process_info', pid: tree.foreground?.pid ?? 0 });
  if (!/\/SpringBoard\.app\/SpringBoard$/.test(foregroundProcess.executable ?? '') || !labels.some(t => /^(Enter Passcode|输入密码|輸入密碼)$/i.test(t.trim()))) throw new Error('Cannot confirm the system passcode screen. Unlock manually; nothing was sent.');
  const empty = elements.some(e => /TextField$/.test(e.role ?? e.type ?? '') && /^(共6位数，已输入0位|共6位數，已輸入0位|0 of 6 values entered|6 digits, 0 entered)$/i.test(e.value ?? ''));
  if (!empty) throw new Error('Cannot confirm an empty six-digit passcode field. Nothing was sent.');
  for (let digit = 0; digit < 10; digit++) {
    const keys = elements.filter(e => (e.role ?? e.type) === 'Key' && e.label === String(digit));
    const box = keys[0]?.frame;
    if (keys.length !== 1 || !box || Math.abs(args.digits[digit].x - (box.x + box.width / 2)) > 3 || Math.abs(args.digits[digit].y - (box.y + box.height / 2)) > 3) throw new Error('Keypad coordinates do not match the fresh system keys. Nothing was sent.');
  }
  checkWork();
  attempted.add(target.id);
  try {
    for (const digit of pin) {
      checkWork();
      const result = await ctx.input({ op: 'tap', ...args.digits[Number(digit)], duration_ms: 100 });
      if (result.isError || result.sent !== true) throw new Error('Input not confirmed');
    }
    await ctx.settle();
    const after = await ctx.bridge({ op: 'ax' });
    const stillKeypad = (after.elements ?? []).some(e => /^(Enter Passcode|输入密码|輸入密碼)$/i.test(e.label ?? ''));
    let verified = false;
    if (!stillKeypad) {
      // AX often omits bundle IDs. A launched app's PID must actually become
      // foreground; a successful launch response alone does not prove unlock.
      const app = await ctx.bridge({ op: 'launch_app', bundle_id: 'com.apple.Preferences' });
      if (!app.isError && Number.isSafeInteger(app.pid) && app.pid > 0) for (let i = 0; i < 3; i++) {
        const shown = await ctx.bridge({ op: 'ax' });
        verified = shown.foreground?.pid === app.pid && Boolean(shown.elements?.length);
        if (verified) break;
        await pause(400);
      }
    }
    if (verified) attempted.delete(target.id);
    return { input_sent: true, unlock_verified: verified, ...(!verified ? { isError: true, outcome: 'unknown', stop_reason: 'unknown' } : {}), instruction: verified ? 'Unlock verified by a readable foreground app.' : 'Inspect a fresh screenshot. Do not retry. Human review and a service restart are required before the next unlock attempt.' };
  } catch {
    // Never expose bridge errors, tap coordinates, or partial PIN progress.
    return { isError: true, outcome: 'unknown', stop_reason: 'unknown', unlock_verified: false, instruction: 'Unlock input may have been sent. Inspect the phone; no automatic retry. Human review and a service restart are required.' };
  } finally { pin = undefined; }
}
