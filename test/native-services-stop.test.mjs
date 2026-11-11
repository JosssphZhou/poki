import test from 'node:test';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, copyFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const exec = promisify(execFile);

test('native input completion survives cancellation and session recreation', {
  timeout: 180000,
  skip: process.platform !== 'darwin' && 'The native iOS transport contract uses macOS Swift',
}, async t => {
  const dir = await mkdtemp(join(tmpdir(), 'poki-native-stop-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  await mkdir(join(dir, 'Sources/UIKit'), { recursive: true });
  await mkdir(join(dir, 'Tests/NativeStopTests'), { recursive: true });
  await writeFile(join(dir, 'Sources/UIKit/UIKit.swift'), '@_exported import Foundation\n');
  await writeFile(join(dir, 'Package.swift'), `// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "NativeStopContract",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: ${JSON.stringify(resolve('native/ios/PokiCore'))})],
    targets: [
        .target(name: "UIKit"),
        .testTarget(name: "NativeStopTests", dependencies: ["UIKit", .product(name: "PokiCore", package: "PokiCore")]),
    ]
)
`);
  await copyFile('native/ios-app/Poki/Runtime/NativeServicesWDA.swift', join(dir, 'Tests/NativeStopTests/NativeServicesWDA.swift'));
  for (const name of ['DeviceStubs.swift', 'NativeStopTests.swift']) {
    await copyFile(join('test/fixtures/native-services-stop', name), join(dir, 'Tests/NativeStopTests', name));
  }
  try {
    const result = await exec('swift', ['test', '--package-path', dir, '--filter', 'NativeStopTests'], { timeout: 170000, maxBuffer: 4 * 1024 * 1024 });
    t.diagnostic(result.stdout + result.stderr);
  } catch (error) {
    t.diagnostic((error.stdout ?? '') + (error.stderr ?? ''));
    throw error;
  }
});
