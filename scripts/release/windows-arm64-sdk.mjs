// Flutter 3.47.2 distributes only an x64 Windows SDK. Its host detection uses
// Dart's process ABI, so under x64 emulation it incorrectly targets x64 on an
// ARM64 runner. Apply a narrowly scoped host-detection fix to this CI SDK only.
// The packaged app and every critical PE binary are independently verified.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
if (process.platform !== 'win32' || !/arm64/i.test(os.machine()) || process.env.RUNNER_ARCH !== 'ARM64') {
  throw Error('This compatibility patch is only for a real Windows ARM64 CI runner');
}
const root = process.env.FLUTTER_ROOT;
if (!root || !process.env.CI) throw Error('Missing CI Flutter SDK');
const source = path.join(root, 'packages/flutter_tools/lib/src/base/os.dart');
const before = fs.readFileSync(source, 'utf8');
const anchor = 'HostPlatform get hostPlatform {';
if (before.split(anchor).length !== 2) throw Error('Flutter source changed; review compatibility patch');
const marker = '// Modu: detect the native ARM64 Windows host under x64 Dart emulation.';
if (!before.includes(marker)) {
  fs.writeFileSync(source, before.replace(anchor, `${anchor}\n    ${marker}\n    if (_platform.isWindows && _platform.environment['MODU_NATIVE_WINDOWS_ARM64'] == '1') {\n      return HostPlatform.windows_arm64;\n    }`));
  // Regenerable tool snapshot in this job's SDK, not user code or credentials.
  const snapshot = path.join(root, 'bin/cache/flutter_tools.snapshot');
  if (fs.existsSync(snapshot)) fs.unlinkSync(snapshot);
}
fs.appendFileSync(process.env.GITHUB_ENV, '\nMODU_NATIVE_WINDOWS_ARM64=1\n');
console.log('CI SDK host detection patched for native Windows ARM64; package verification remains mandatory.');
