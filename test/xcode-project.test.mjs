import test from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { execFile, spawnSync } from 'node:child_process';
import { promisify } from 'node:util';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const exec = promisify(execFile);
const root = fileURLToPath(new URL('../', import.meta.url));
const available = process.platform === 'darwin' && spawnSync('xcodegen', ['--version']).status === 0;

test('generated iOS projects have single-parent groups and include shared keyboard sources in both targets', {
  skip: available ? false : 'requires macOS and XcodeGen', timeout: 60000,
}, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'poki-project-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  // XcodeGen writes Info.plists as well as the project. Keep all generation in a disposable copy.
  const excluded = new Set(['.build', '.swiftpm', 'build', 'target']);
  for (const path of ['native/ios-app', 'native/ios/PokiCore', 'native/ios/PokiLoopback', 'native/ios-gym/check']) {
    await cp(join(root, path), join(directory, path), {
      recursive: true,
      filter: path => !excluded.has(basename(path)) && !path.endsWith('.xcodeproj'),
    });
  }
  for (const [spec, project] of [['project.yml', 'Poki'], ['project-external.yml', 'PokiExternal']]) {
    await t.test(project, async () => {
      const output = join(directory, 'generated', project);
      await mkdir(output, { recursive: true });
      await exec('xcodegen', ['generate', '--spec', join(directory, 'native/ios-app', spec), '--project', output]);
      const { stdout } = await exec('plutil', ['-convert', 'json', '-o', '-', join(output, `${project}.xcodeproj/project.pbxproj`)]);
      const { objects } = JSON.parse(stdout);
      const parents = new Map();
      const duplicates = [];
      for (const [id, object] of Object.entries(objects)) {
        if (!['PBXGroup', 'PBXVariantGroup'].includes(object.isa)) continue;
        for (const child of object.children ?? []) {
          if (!['PBXGroup', 'PBXVariantGroup'].includes(objects[child]?.isa)) continue;
          if (parents.has(child)) duplicates.push({ group: objects[child].path ?? objects[child].name, parents: [parents.get(child), id] });
          else parents.set(child, id);
        }
      }
      assert.deepEqual(duplicates, [], 'Xcode rejects groups that belong to more than one parent');
      for (const name of ['Poki', 'PokiKeyboard']) {
        const target = Object.values(objects).find(o => o.isa === 'PBXNativeTarget' && o.name === name);
        assert.ok(target, `${name} target exists`);
        const sources = target.buildPhases.map(id => objects[id]).filter(o => o.isa === 'PBXSourcesBuildPhase');
        const paths = sources.flatMap(phase => phase.files.map(id => objects[objects[id].fileRef]?.path));
        for (const file of ['KeyboardLink.swift', 'KeyboardTyper.swift']) {
          assert.ok(paths.includes(file), `${name} still compiles ${file}`);
        }
      }
    });
  }
});
