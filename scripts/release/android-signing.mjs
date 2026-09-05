// Run locally with --generate, or in CI with --from-env. Never prints secrets.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
if (process.argv.includes('--generate')) {
  const folder = path.join(root, '.release-secrets');
  fs.mkdirSync(folder, { recursive: true, mode: 0o700 });
  const key = path.join(folder, 'modu-release.jks');
  const credentials = path.join(folder, 'android-signing.json');
  if (fs.existsSync(key) || fs.existsSync(credentials)) throw Error('Signing identity already exists; refusing to replace it.');
  const password = crypto.randomBytes(36).toString('base64url');
  // Retain recovery credentials even if keytool fails; never regenerate silently.
  fs.writeFileSync(credentials, JSON.stringify({ alias: 'modu', password }), { mode: 0o600, flag: 'wx' });
  execFileSync('keytool', ['-genkeypair', '-v', '-keystore', key, '-storetype', 'JKS', '-alias', 'modu', '-keyalg', 'RSA', '-keysize', '4096', '-validity', '10000', '-dname', 'CN=Modu, OU=Open Source, O=Modu', '-storepass:env', 'MODU_KEY_PASSWORD', '-keypass:env', 'MODU_KEY_PASSWORD'], { env: { ...process.env, MODU_KEY_PASSWORD: password }, stdio: ['ignore', 'ignore', 'pipe'] });
  fs.chmodSync(key, 0o600);
  console.log('Dedicated Android signing identity created in ignored .release-secrets/. Back up this directory securely.');
} else if (process.argv.includes('--from-env')) {
  const { ANDROID_KEYSTORE_BASE64: base64, ANDROID_KEYSTORE_PASSWORD: password, ANDROID_KEY_ALIAS: alias } = process.env;
  if (!base64 || !password || !alias) throw Error('All three dedicated Android signing Secrets are required.');
  if (!/^[A-Za-z0-9_-]+$/.test(alias) || !/^[A-Za-z0-9_-]+$/.test(password)) throw Error('Unexpected signing properties format');
  fs.writeFileSync(path.join(root, 'android/app/modu-release.jks'), Buffer.from(base64, 'base64'), { mode: 0o600, flag: 'wx' });
  fs.writeFileSync(path.join(root, 'android/key.properties'), `storeFile=modu-release.jks\nstorePassword=${password}\nkeyAlias=${alias}\nkeyPassword=${password}\n`, { mode: 0o600, flag: 'wx' });
} else {
  throw Error('Choose --generate or --from-env');
}
