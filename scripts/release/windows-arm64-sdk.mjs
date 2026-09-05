// Flutter 3.47.2 distributes only an x64 Windows SDK. Its host detection uses
// Dart's process ABI, so under x64 emulation it incorrectly targets x64 on an
// ARM64 runner. Apply a narrowly scoped host-detection fix to this CI SDK only.
// The packaged app and every critical PE binary are independently verified.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
const nativeCpu = process.platform === 'win32' ? execFileSync('powershell.exe',
  ['-NoProfile', '-Command', '(Get-CimInstance Win32_Processor | Select-Object -First 1).Architecture'],
  { encoding: 'utf8' }).trim() : '';
console.log(JSON.stringify({ process: process.arch, machine: os.machine(), nativeCpu }));
// Win32_Processor.Architecture = 12 is ARM64. os.machine() can report AMD64
// inside an emulated Node process and must not be used as the hardware test.
if (process.platform !== 'win32' || nativeCpu !== '12') {
  throw Error('This compatibility patch is only for a real Windows ARM64 CI runner');
}
const root = process.env.FLUTTER_ROOT;
if (!root || !process.env.CI) throw Error('Missing CI Flutter SDK');
const source = path.join(root, 'packages/flutter_tools/lib/src/base/os.dart');
const before = fs.readFileSync(source, 'utf8');
const marker = '// Modu: detect the native ARM64 Windows host under x64 Dart emulation.';
if (!before.includes(marker)) {
  // There is also a macOS override. Match only the shared ABI-based getter.
  const anchor = /HostPlatform get hostPlatform \{(?=\r?\n\s+return switch \(_currentAbi\))/g;
  if ([...before.matchAll(anchor)].length !== 1) throw Error('Flutter source changed; review compatibility patch');
  fs.writeFileSync(source, before.replace(anchor, match => `${match}\n    ${marker}\n    if (_platform.isWindows && _platform.environment['MODU_NATIVE_WINDOWS_ARM64'] == '1') {\n      return HostPlatform.windows_arm64;\n    }`));
  // Regenerable tool snapshot in this job's SDK, not user code or credentials.
  const snapshot = path.join(root, 'bin/cache/flutter_tools.snapshot');
  if (fs.existsSync(snapshot)) fs.unlinkSync(snapshot);
}
fs.appendFileSync(process.env.GITHUB_ENV, '\nMODU_NATIVE_WINDOWS_ARM64=1\n');
console.log('CI SDK host detection patched for native Windows ARM64; package verification remains mandatory.');
