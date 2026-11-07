import { randomInt } from 'node:crypto';
import { pause } from './work.mjs';

// Coordinates may move only within the middle half of an observed target.
// Coordinate-only input has no known target bounds, so only its timing varies.
export async function variedInput(ctx, request, enabled, bounds, varyDuration = true, sample = () => randomInt(1_000_000) / 1_000_000) {
  if (!enabled) return ctx.input(request);
  const command = { ...request };
  if (bounds && request.op === 'tap') {
    const { x, y, width, height } = bounds;
    if ([x, y, width, height].every(Number.isFinite) && width > 0 && height > 0) {
      command.x = x + width / 2 + (sample() * 2 - 1) * Math.min(3, width / 4);
      command.y = y + height / 2 + (sample() * 2 - 1) * Math.min(3, height / 4);
    }
  }
  if (varyDuration && command.duration_ms > 0) command.duration_ms = Math.max(1, Math.round(command.duration_ms * (.85 + sample() * .3)));
  await pause(40 + Math.floor(sample() * 81));
  return ctx.input(command);
}
