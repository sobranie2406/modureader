// Mirrors PluginScriptRuntime._call's method -> capability map, so an example
// script that calls a method its manifest does not declare fails here instead
// of on a user's machine.
const fs = require('fs');
const path = require('path');

const CAPABILITY = {
  'http.get': 'net:http',
  'library.list': 'library:read',
  'library.tags': 'library:read',
  'library.groups': 'library:read',
  'library.tag': 'library:write',
  'library.move': 'library:write',
  'books.content': 'book:content',
  'books.chapter': 'book:content',
  'notes.list': 'note:read',
  'notes.save': 'note:write',
  'reading.stats': 'reading:read',
  'reading.history': 'reading:read',
  'search.library': 'search:library',
  'knowledge.search': 'knowledge:query',
  'ai.complete': 'ai:invoke',
  'translate.text': 'translate:invoke',
  'tts.speak': 'tts:invoke',
  'dictionary.lookup': 'dictionary:lookup',
  'clipboard.read': 'clipboard:read',
  'clipboard.write': 'clipboard:write',
  'share.text': 'share:text',
  'ui.confirm': 'ui:dialog',
  'ui.prompt': 'ui:dialog',
  'ui.select': 'ui:dialog',
  'ui.progress': 'ui:progress',
  'open.url': 'url:open',
  'storage.list': 'storage:plugin',
  'storage.read': 'storage:plugin',
  'storage.write': 'storage:plugin',
  'storage.remove': 'storage:plugin',
  'permissions.request': 'script:run',
  'permissions.status': 'script:run',
  'articles.capture': 'article:capture',
  'privateLibrary.open': 'library:private',
  'privateLibrary.lock': 'library:private',
  'privateLibrary.state': 'library:private-control',
  'privateLibrary.updateOptions': 'library:private-control',
  'privateLibrary.selectBooks': 'library:private-control',
  'privateLibrary.setPrivate': 'library:private-control',
};

// Observations recorded by the stubs, so a script can run without a real host.
function makeHost(manifest, notes) {
  const declared = new Set(manifest.capabilities);
  const files = new Map();
  const call = (method, args) => {
    const capability = CAPABILITY[method];
    if (!capability) throw new Error('unknown method ' + method);
    if (!declared.has(capability)) {
      const error = new Error('Plugin request failed');
      error.code = 'permission';
      error.missing = capability;
      throw error;
    }
    notes.push(method);
    switch (method) {
      case 'storage.read':
        return { text: files.has(args.name) ? files.get(args.name) : null };
      case 'storage.write':
        files.set(args.name, args.text);
        return { bytes: args.text.length };
      case 'storage.list':
        return [...files.keys()].map((name) => ({ name, bytes: files.get(name).length }));
      case 'storage.remove':
        files.delete(args.name);
        return { removed: true };
      case 'dictionary.lookup':
        return [{ word: args.word, definition: 'a definition', dictionary: 'test' }];
      case 'translate.text':
        return { text: 'translated' };
      case 'search.library':
        return { books: [], notes: [] };
      case 'notes.list':
        return [];
      case 'library.list':
        return [];
      case 'reading.stats':
        return { days: 30, totalSeconds: 0, books: [] };
      case 'reading.history':
        return [];
      case 'ui.confirm':
        return { confirmed: true };
      case 'ui.select':
        return { selected: args.options[0] };
      case 'ui.prompt':
        return { text: 'typed' };
      case 'ui.progress':
        return { shown: true };
      case 'clipboard.write':
        return { written: true };
      case 'share.text':
        return { shared: true };
      default:
        return {};
    }
  };
  return call;
}

function buildModu(call) {
  const ns = (name, methods) => {
    const out = {};
    for (const [key, method] of Object.entries(methods)) {
      out[key] = (args) => Promise.resolve().then(() => call(method, args || {}));
    }
    return Object.freeze(out);
  };
  return Object.freeze({
    http: ns('http', { get: 'http.get' }),
    library: ns('library', {
      list: 'library.list', tags: 'library.tags', groups: 'library.groups',
      tag: 'library.tag', move: 'library.move',
    }),
    books: ns('books', { content: 'books.content', chapter: 'books.chapter' }),
    notes: ns('notes', { list: 'notes.list', save: 'notes.save' }),
    reading: ns('reading', { stats: 'reading.stats', history: 'reading.history' }),
    search: ns('search', { library: 'search.library' }),
    knowledge: ns('knowledge', { search: 'knowledge.search' }),
    dictionary: ns('dictionary', { lookup: 'dictionary.lookup' }),
    ai: ns('ai', { complete: 'ai.complete' }),
    translate: ns('translate', { text: 'translate.text' }),
    tts: ns('tts', { speak: 'tts.speak' }),
    clipboard: ns('clipboard', { read: 'clipboard.read', write: 'clipboard.write' }),
    share: ns('share', { text: 'share.text' }),
    ui: ns('ui', {
      confirm: 'ui.confirm', prompt: 'ui.prompt', select: 'ui.select',
      progress: 'ui.progress',
    }),
    open: ns('open', { url: 'open.url' }),
    storage: ns('storage', {
      list: 'storage.list', read: 'storage.read',
      write: 'storage.write', remove: 'storage.remove',
    }),
    articles: ns('articles', { capture: 'articles.capture' }),
    permissions: ns('permissions', {
      request: 'permissions.request', status: 'permissions.status',
    }),
    privateLibrary: ns('privateLibrary', {
      open: 'privateLibrary.open', lock: 'privateLibrary.lock',
      state: 'privateLibrary.state',
      updateOptions: 'privateLibrary.updateOptions',
      selectBooks: 'privateLibrary.selectBooks',
      setPrivate: 'privateLibrary.setPrivate',
    }),
  });
}

const root = 'docs/examples/plugins';
const results = [];
for (const entry of fs.readdirSync(root)) {
  const dir = path.join(root, entry);
  const manifestPath = path.join(dir, 'manifest.json');
  if (!fs.existsSync(manifestPath)) continue;
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const settings = {};
  for (const spec of manifest.settings || []) settings[spec.key] = spec.defaultValue;
  for (const contribution of manifest.contributes || []) {
    if (contribution.kind !== 'scriptAction') continue;
    const source = fs.readFileSync(path.join(dir, contribution.entry), 'utf8');
    const notes = [];
    const call = makeHost(manifest, notes);
    const input = {
      selection: 'ephemeral',
      context: 'some surrounding context',
      settings,
      actionId: contribution.id,
      book: { id: 1, title: 'Book', author: 'A', format: 'epub' },
    };
    let outcome;
    try {
      // Same shape the runtime uses: an async arrow taking (input, modu).
      const body = new Function('input', 'modu',
        'return (async (input, modu) => {' + source + '\n})(input, modu);');
      const value = body(input, buildModu(call));
      outcome = Promise.resolve(value).then((result) => ({ ok: true, result }),
        (error) => ({ ok: false, error, notes }));
      // eslint-disable-next-line no-await-in-loop
      results.push({ entry, id: contribution.id, surface: contribution.surface,
        promise: outcome });
    } catch (error) {
      results.push({ entry, id: contribution.id, surface: contribution.surface,
        promise: Promise.resolve({ ok: false, error, notes }) });
    }
  }
}

(async () => {
  let failures = 0;
  for (const item of results) {
    const outcome = await item.promise;
    if (outcome.ok) {
      const keys = Object.keys(outcome.result || {});
      const shaped = keys.every((k) => ['title', 'text', 'candidates', 'private', 'markdown'].includes(k));
      if (!shaped) {
        failures++;
        console.log('SHAPE  ' + item.entry + '/' + item.id + ' -> ' + JSON.stringify(keys));
      } else {
        console.log('ok     ' + item.entry + '/' + item.id);
      }
    } else {
      failures++;
      const error = outcome.error || {};
      console.log('FAIL   ' + item.entry + '/' + item.id +
          ' [' + item.surface + '] ' + (error.message || String(error)) +
          (error.missing ? ' missing=' + error.missing : ''));
      console.log('       called: ' + (outcome.notes || []).join(', '));
    }
  }
  console.log(failures === 0 ? 'ALL OK' : failures + ' failure(s)');
  process.exit(failures === 0 ? 0 : 1);
})();
