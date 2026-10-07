import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

const directory = new URL('./', import.meta.url);
const qq = (await readFile(new URL('qq-bot.mjs', directory), 'utf8')).replace(/^export /gm, '');
const worker = (await readFile(new URL('worker.mjs', directory), 'utf8'))
  .replace(/^import \{qqRoutes, qqSchedule\} from '\.\/qq-bot\.mjs';\s*/, '');
await mkdir(new URL('dist/', directory), {recursive: true});
const output = new URL('dist/worker.mjs', directory);
await writeFile(output, qq + '\n\n' + worker);
console.log('Built ' + fileURLToPath(output));
