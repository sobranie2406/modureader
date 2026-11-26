import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const root = new URL('../', import.meta.url);
const source = readFileSync(new URL(
    'ohos/entry/src/main/ets/plugins/LinkedBookFilesPlugin.ets', root), 'utf8');
const code = stripTypeScriptTypes(source.replace(/^import [\s\S]*?;\n/gm, '')
    .replace('export default class', 'class')) + '\nLinkedBookFilesPlugin;';
const folderUri = 'file://docs/storage/Users/currentUser/Book%20Shelf';
const childUri = relative => folderUri + '/' + relative.split('/').map(encodeURIComponent).join('/');
const plain = value => JSON.parse(JSON.stringify(value));

function harness({uris = [folderUri], children = [], unreadable = [], directories = [], failCopy = false} = {}) {
    const events = [], handles = new Map(), local = new Set(), records = new Map();
    let serial = 0;
    const fs = {
        OpenMode: {READ_ONLY: 0, READ_WRITE: 2, CREATE: 64, TRUNC: 512},
        async listFile(path, options) {
            events.push(['list', path, plain(options)]);
            return children;
        },
        async open(path, mode) {
            events.push(['open', path, mode]);
            if (unreadable.includes(path)) throw Error('private/source/permission denied');
            const file = {fd: ++serial};
            handles.set(file.fd, {path, mode});
            if (path.startsWith('/cache/')) local.add(path);
            return file;
        },
        async stat(value) {
            const path = typeof value === 'number' ? handles.get(value)?.path : value;
            return {isFile: () => !directories.includes(path), isDirectory: () => directories.includes(path)};
        },
        async copyFile(from, to) {
            const origin = handles.get(from)?.path ?? from;
            const destination = handles.get(to)?.path ?? to;
            events.push(['copy', origin, destination]);
            if (failCopy) throw Error('private/source/copy failed');
            local.add(destination);
        },
        async close(file) {
            events.push(['close', file.fd]);
            assert.ok(handles.delete(file.fd), 'a file descriptor must be closed once');
        },
        closeSync(file) {
            events.push(['close', file.fd]);
            assert.ok(handles.delete(file.fd), 'a file descriptor must be closed once');
        },
        async mkdir(path) {events.push(['mkdir', path]);},
        async mkdtemp(path) {
            const directory = path.replace(/X+$/, '') + ++serial;
            events.push(['mkdir', directory]);
            return directory;
        },
        async unlink(path) {events.push(['unlink', path]); local.delete(path);},
        async rmdir(path) {
            events.push(['rmdir', path]);
            for (const item of local) if (item.startsWith(path + '/')) local.delete(item);
        },
        async symlink(from, to) {events.push(['symlink', from, to]); local.add(to);},
    };
    const picker = {
        DocumentSelectMode: {FILE: 0, FOLDER: 1},
        DocumentViewPicker: class {
            async select(options) {
                events.push(['picker', plain(options)]);
                return uris;
            }
        },
    };
    const Plugin = vm.runInNewContext(code, {
        fs, picker, util: {generateRandomUUID: () => `selection-${++serial}`},
        fileUri: {FileUri: class {
            constructor(uri) {
                const parsed = new URL(uri);
                this.path = decodeURIComponent(parsed.pathname);
                this.name = decodeURIComponent(parsed.pathname.split('/').at(-1));
            }
        }},
        fileShare: {
            OperationMode: {READ_MODE: 1},
            async persistPermission(policies) {events.push(['persist', plain(policies)]);},
            async activatePermission(policies) {events.push(['activate', plain(policies)]);},
            async revokePermission(policies) {events.push(['revoke', plain(policies)]);},
        },
        preferences: {async getPreferences() {return {
            async get(key, fallback) {return records.get(key) ?? fallback;},
            async put(key, value) {records.set(key, value);},
            async flush() {},
        };}},
        MethodChannel: class {setMethodCallHandler() {}},
    });
    const plugin = new Plugin();
    plugin.onAttachedToEngine({getBinaryMessenger: () => ({}),
        getApplicationContext: () => ({cacheDir: '/cache'})});
    plugin.onAttachedToAbility({getAbility: () => ({context: {cacheDir: '/ability-cache'}})});
    const invoke = (method, args = {}) => new Promise(resolve => plugin.onMethodCall({
        method, args: new Map(Object.entries(args)),
    }, {
        success: value => resolve({value: value === undefined ? null : plain(value)}),
        error: (error, message) => resolve({error, message}),
        notImplemented: () => resolve({error: 'not_implemented'}),
    }));
    const pick = args => invoke('pick', {files: false, inPlace: false,
        extensions: ['epub', 'pdf'], ...args});
    return {events, handles, local, records, plugin, invoke, pick};
}

test('OHOS folder copy uses scoped URI handles for nested Unicode and encoded filenames', async () => {
    const relative = '子 目录/更深一层/罕见#100%.EPUB';
    const h = harness({children: ['/' + relative, '/另一层/同名.pdf', '/同名.pdf', '/ignore.txt']});
    const picked = await h.pick();
    assert.equal(picked.error, undefined);
    assert.equal(picked.value.length, 3);
    assert.deepEqual(picked.value.map(entry => [entry.name, entry.collectionName ?? null]),
        [['罕见#100%.EPUB', '子 目录'], ['同名.pdf', '另一层'], ['同名.pdf', null]]);
    assert.deepEqual(h.events.find(event => event[0] === 'picker')[1],
        {selectMode: 1, maxSelectNumber: 1});
    assert.deepEqual(h.events.find(event => event[0] === 'list').slice(1),
        ['/storage/Users/currentUser/Book Shelf', {recursion: true}]);
    const staged = await h.invoke('copy', {ids: picked.value.map(entry => entry.id)});
    assert.equal(staged.error, undefined);
    assert.equal(staged.value.length, 3);
    assert.equal(new Set(staged.value).size, 3, 'same-named books cannot overwrite each other');
    assert.ok(staged.value.every(path => path.startsWith('/cache/')));
    const copied = h.events.filter(event => event[0] === 'copy');
    assert.equal(copied.length, 3);
    assert.ok(copied.some(event => event[1] === childUri(relative)));
    assert.ok(copied.every(event => event[1].startsWith(folderUri + '/') && event[2].startsWith('/cache/')));
    assert.ok(h.events.filter(event => event[0] === 'open' && event[1].startsWith('file:'))
        .every(event => event[2] === 0), 'selected originals are opened read-only');
    assert.equal(h.handles.size, 0);
    assert.equal(h.events.some(event => ['persist', 'activate'].includes(event[0])), false,
        'copy import uses picker authorization without persistent access');
    await h.invoke('release');
    assert.equal(h.events.some(event => ['unlink', 'rmdir'].includes(event[0]) && event[1].startsWith('file:')), false);
});

test('OHOS folder picker cancellation does not open files or persist access', async () => {
    const h = harness({uris: []});
    assert.deepEqual(await h.pick(), {value: null});
    assert.deepEqual(h.events.map(event => event[0]), ['picker']);
    assert.equal(h.handles.size, 0);
});

test('folder discovery is lazy and staging rejects unreadable files and directories individually', async () => {
    const h = harness({children: ['/ok.epub', '/locked.pdf', '/directory.pdf', '/../outside.epub', '/.hidden.pdf'],
        unreadable: [childUri('locked.pdf')], directories: [childUri('directory.pdf')]});
    const picked = await h.pick();
    assert.equal(picked.error, undefined);
    assert.deepEqual(picked.value.map(entry => entry.name), ['ok.epub', 'locked.pdf', 'directory.pdf']);
    assert.equal(h.events.some(event => event[0] === 'open'), false,
        'discovery only lists the selected folder');
    assert.equal((await h.invoke('copy', {ids: [picked.value[0].id]})).error, undefined);
    for (const entry of picked.value.slice(1)) {
        const failed = await h.invoke('copy', {ids: [entry.id]});
        assert.ok(failed.error);
        assert.doesNotMatch(JSON.stringify(failed), /private|locked|directory\.pdf/);
        assert.equal(h.handles.size, 0);
    }
    assert.equal(h.events.some(event => event[0] === 'open' && /outside|hidden/.test(event[1])), false);
    assert.ok(h.events.some(event => event[0] === 'rmdir'), 'failed staging removes its isolated cache directory');
    assert.equal(h.handles.size, 0);
});

test('folder child URI encoding preserves the selected provider query suffix', async () => {
    const suffix = '?networkid=device%2F123';
    const h = harness({uris: [folderUri + suffix], children: ['/资料 #100%.epub']});
    const picked = await h.pick();
    assert.equal(picked.error, undefined);
    assert.equal((await h.invoke('copy', {ids: [picked.value[0].id]})).error, undefined);
    assert.deepEqual(h.events.find(event => event[0] === 'copy').slice(1, 2),
        [childUri('资料 #100%.epub') + suffix]);
    assert.equal(h.handles.size, 0);
});

test('copy refuses foreign and released selection IDs before reading any source', async () => {
    const h = harness({children: ['/ok.epub']});
    const picked = await h.pick();
    h.events.length = 0;
    const foreign = await h.invoke('copy', {ids: [picked.value[0].id, 'file://docs/not-selected/private.epub']});
    assert.ok(foreign.error);
    assert.doesNotMatch(JSON.stringify(foreign), /not-selected|private\.epub/);
    assert.equal(h.events.some(event => event[0] === 'open'), false);
    await h.invoke('release');
    h.events.length = 0;
    assert.ok((await h.invoke('copy', {ids: [picked.value[0].id]})).error);
    assert.equal(h.events.some(event => event[0] === 'open'), false);
});

test('copy failure is sanitized, closes handles, and permits a later selection', async () => {
    const h = harness({children: ['/ok.epub'], failCopy: true});
    const picked = await h.pick();
    const failed = await h.invoke('copy', {ids: [picked.value[0].id]});
    assert.ok(failed.error);
    assert.doesNotMatch(JSON.stringify(failed), /private|source\/copy/);
    assert.equal(h.handles.size, 0);
    assert.equal((await h.pick()).error, undefined, 'an I/O failure must release the busy flag');
});

test('a later unreadable book rolls back the entire isolated copy batch', async () => {
    const h = harness({children: ['/ok.epub', '/locked.pdf'], unreadable: [childUri('locked.pdf')]});
    const picked = await h.pick();
    const failed = await h.invoke('copy', {ids: picked.value.map(entry => entry.id)});
    assert.ok(failed.error);
    assert.equal(h.events.filter(event => event[0] === 'copy').length, 1,
        'the first book copied before the second failed');
    assert.equal(h.local.size, 0, 'partial staging is removed instead of reported as a complete import');
    assert.equal(h.handles.size, 0);
    assert.ok(h.events.filter(event => event[0] === 'rmdir')
        .every(event => event[1].startsWith('/cache/book-folder-')));
});

test('in-place picking retains read-only persistence and the existing link lifecycle', async () => {
    const uri = childUri('原位.epub');
    const h = harness({uris: [uri]});
    const picked = await h.pick({files: true, inPlace: true});
    assert.equal(picked.error, undefined);
    assert.equal(picked.value.length, 1);
    assert.deepEqual(h.events.find(event => event[0] === 'persist')[1], [{uri, operationMode: 1}]);
    const linked = await h.invoke('link', {id: picked.value[0].id});
    assert.equal(linked.error, undefined);
    assert.match(linked.value.key, /^file\/linked-[a-zA-Z0-9-]+\.epub$/);
    assert.ok(linked.value.path.startsWith('/cache/linked-book-access/'));
    assert.equal(h.handles.size, 1, 'the original descriptor stays open for linked reading');
    await h.invoke('release');
    assert.equal(h.events.some(event => event[0] === 'revoke'), false,
        'releasing a selection keeps the saved link permission');
    await h.invoke('forgetLink', {key: linked.value.key});
    assert.equal(h.handles.size, 0);
    assert.deepEqual(h.events.find(event => event[0] === 'revoke')[1], [{uri, operationMode: 1}]);
});
