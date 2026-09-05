import fs from 'node:fs';

export const desktops = [
  {os: 'ubuntu-24.04', platform: 'linux', arch: 'x64', container: 'debian:trixie'},
  {os: 'ubuntu-24.04-arm', platform: 'linux', arch: 'arm64', container: 'debian:trixie'},
  {os: 'windows-2025', platform: 'windows', arch: 'x64', sdk_arch: 'x64'},
  {os: 'windows-11-arm', platform: 'windows', arch: 'arm64', sdk_arch: 'x64'},
  {os: 'macos-15-intel', platform: 'macos', arch: 'x64', xcode_arch: 'x86_64'},
  {os: 'macos-15', platform: 'macos', arch: 'arm64', xcode_arch: 'arm64'},
];

export function selectTargets(value) {
  const names = [...desktops.map(t => `${t.platform}-${t.arch}`), 'android', 'ios'];
  const requested = value === 'all' ? names : value.split(',').map(s => s.trim());
  if (!requested.length || requested.some(t => !names.includes(t))) throw Error('Invalid release targets');
  const desktop = desktops.filter(t => requested.includes(`${t.platform}-${t.arch}`));
  return {desktop, has_desktop: desktop.length > 0, android: requested.includes('android'), ios: requested.includes('ios')};
}

if (process.env.GITHUB_OUTPUT) {
  for (const [key, value] of Object.entries(selectTargets(process.env.MODU_BUILD_TARGETS || 'all'))) {
    fs.appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${JSON.stringify(value)}\n`);
  }
}
