// Platform facts in one place, so every other module asks here instead of testing the OS itself.
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

export const isWin = process.platform === 'win32';
export const isMac = process.platform === 'darwin';

// A helper's file name on disk. Windows carries the extension; POSIX does not.
export const exe = name => isWin ? `${name}.exe` : name;

// The interpreter that runs the small Python helpers. Windows installs `python`.
export const python = process.env.POKI_PYTHON ?? (isWin ? 'python' : 'python3');

// Node's spawn options for a child whose lifetime is owned by a tool call.
export function owned(extra = {}) {
  return { detached: !isWin, windowsHide: true, ...extra };
}

// Ends the process and everything it started. A POSIX process group has a leader with a
// negative pid; Windows has no process groups, so it walks the tree with taskkill instead.
// Windows also has no SIGTERM: a console process cannot be asked to stop, and taskkill
// without /F is refused for one, so ending it here is always forceful. A child that has
// to finish its own output is given that by closing its stdin, never by a signal.
export function killTree(child, signal = 'SIGTERM') {
  const pid = child?.pid;
  if (!pid) return false;
  if (isWin) {
    const result = spawnSync('taskkill', ['/PID', String(pid), '/T', '/F'], { stdio: 'ignore', windowsHide: true, timeout: 15000 });
    if (result.status === 0) return true;
    try { child.kill('SIGKILL'); } catch { /* already gone */ }
    return false;
  }
  try {
    process.kill(-pid, signal);
    return true;
  } catch (error) {
    if (error.code === 'ESRCH') return false;
    try { child.kill(signal); return true; } catch { return false; }
  }
}

// The user-visible folder an app would call Pictures, Movies or Desktop.
export function mediaDirectory(kind) {
  if (isWin) {
    const home = homedir();
    const names = { Movies: 'Videos', Pictures: 'Pictures' };
    return join(home, names[kind] ?? kind);
  }
  return join(homedir(), kind);
}

// Where state that must outlive the checkout goes.
export function applicationData(name) {
  if (isWin) return join(process.env.LOCALAPPDATA ?? join(homedir(), 'AppData', 'Local'), name);
  if (isMac) return join(homedir(), 'Library/Application Support', name);
  return join(process.env.XDG_STATE_HOME ?? join(homedir(), '.local', 'state'), name);
}
