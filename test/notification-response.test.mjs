import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const exec = promisify(execFile);
const fixture = fileURLToPath(new URL('./fixtures/notification-response/', import.meta.url));

test('notification response completion returns to UIKit on the main thread', { skip: process.platform !== 'darwin' }, async () => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-notification-response-'));
  try {
    const contents = join(dir, 'NotificationCheck.app', 'Contents');
    const executable = join(contents, 'MacOS', 'check');
    await mkdir(join(contents, 'MacOS'), { recursive: true });
    await writeFile(join(contents, 'Info.plist'), `<?xml version="1.0"?><plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>check</string>
      <key>CFBundleIdentifier</key><string>test.poki.notification-response</string>
      </dict></plist>`);
    const source = await readFile(new URL('../native/ios-app/Poki/Activity/ApprovalNotice.swift', import.meta.url), 'utf8');
    const begin = source.indexOf('final class ApprovalNoticeDelegate:');
    const end = source.indexOf('\n}\n', begin) + 2;
    await writeFile(join(dir, 'Delegate.swift'), `import Foundation\nimport UserNotifications\n${source.slice(begin, end)}\n`);
    // Keep the daily-notification parser real too; only its queue/state is adapted by the fixture.
    const notice = await readFile(new URL('../native/ios-app/Poki/Entry/DailyTaskNotice.swift', import.meta.url), 'utf8');
    const deliveryBegin = notice.indexOf('    static func delivery(');
    const deliveryEnd = notice.indexOf('\n    }', deliveryBegin) + '\n    }'.length;
    assert.ok(deliveryBegin >= 0 && deliveryEnd > deliveryBegin, 'DailyTaskNotice must declare delivery');
    const reminder = await readFile(new URL('../native/ios-app/Poki/Entry/DailyTaskReminders.swift', import.meta.url), 'utf8');
    const reminderBegin = reminder.indexOf('enum DailyTaskReminder {');
    const reminderEnd = reminder.indexOf('    @MainActor static func request(', reminderBegin);
    assert.ok(reminderBegin >= 0 && reminderEnd > reminderBegin, 'DailyTaskReminder must declare its identifiers');
    await writeFile(join(dir, 'DailyDelivery.swift'), `import Foundation\nimport UserNotifications\n${reminder.slice(reminderBegin, reminderEnd)}\n}\n
enum DailyTaskNotice {
    static let categoryID = DailyTaskReminder.categoryID
    static let runID = DailyTaskReminder.runID
${notice.slice(deliveryBegin, deliveryEnd)}
}\n`);
    await exec('clang', ['-fobjc-arc', '-c', join(fixture, 'Delivery.m'), '-o', join(dir, 'Delivery.o')]);
    await exec('swiftc', ['-import-objc-header', join(fixture, 'Delivery.h'), join(dir, 'Delegate.swift'), join(dir, 'DailyDelivery.swift'),
      join(fixture, 'main.swift'), join(dir, 'Delivery.o'), '-o', executable]);
    const { stdout } = await exec(executable, [], { timeout: 10_000 });
    process.stdout.write(stdout);
    assert.match(stdout, /PASS: notification responses complete on the main thread/);
    assert.match(stdout, /PASS: only the two explicit daily-task actions queue a task/);
  } catch (error) {
    if (error.stdout) process.stdout.write(error.stdout);
    if (error.stderr) process.stderr.write(error.stderr);
    throw error;
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
