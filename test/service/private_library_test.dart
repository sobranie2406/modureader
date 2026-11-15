import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/private_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late SharedPreferences prefs;
  late PrivateLibrary library;
  final ordinary =
      Book.mock().copyWith(id: 1, md5: 'public', filePath: 'public.epub');
  final secret =
      Book.mock().copyWith(id: 2, md5: 'private', filePath: 'private.epub');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    library = PrivateLibrary(preferences: prefs);
  });
  tearDown(() => library.dispose());

  test('sync exclusions outlive UI sessions and follow local file replacement',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setBooksPrivate([secret], true);
    final replacement =
        secret.copyWith(md5: 'replacement', filePath: 'new.epub');
    expect(library.canSyncBook(replacement), false);
    expect(library.isPrivate(replacement), true);
    await library.setBooksPrivate([replacement], true);
    await library.setEnabled(false);
    library.setPluginActive(false);
    expect(library.canRead(replacement), true);
    expect(library.canSyncBook(replacement), false);
    final restarted = PrivateLibrary(preferences: prefs);
    addTearDown(restarted.dispose);
    expect(restarted.canSyncBook(replacement), false);
    expect(restarted.bookPredicate(), '1'); // Protection UI was explicitly off.
    restarted.setPluginActive(true);
    await restarted.unlock();
    await restarted.setBooksPrivate([replacement], false);
    expect(restarted.canSyncBook(replacement), true);
    expect(restarted.hasSyncExclusions, false);
  });

  test('path marks survive later MD5 discovery; shared history stays local',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    final noHash = secret.copyWith(md5: '');
    await library.setBooksPrivate([noHash], true);
    await library.protectHistory('private-history');
    expect(library.canSyncBook(secret), false);
    expect(library.canSyncHistory('private-history'), false);
    expect(library.canSyncHistory('legacy', unscoped: true), false);
    expect(library.canSyncHistory('public'), true);
    await library.clearProtection();
    expect(library.canSyncBook(secret), true);
    expect(library.canSyncHistory('private-history'), true);
    expect(library.hasSyncExclusions, false);
  });

  test(
      'protected conversations still require sanitization after book unmarking',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setBooksPrivate([secret], true);
    await library.protectHistory('private-conversation');
    await library.setBooksPrivate([secret], false);
    expect(library.canSyncBook(secret), true);
    expect(library.hasSyncExclusions, true);
    expect(library.canSyncHistory('private-conversation'), false);
    await library.clearProtection();
    expect(library.hasSyncExclusions, false);
  });

  test('no plugin adds no entrance or filtering; activation starts locked',
      () async {
    expect(library.showEntry, false);
    expect(library.bookPredicate(), '1');
    expect(library.canRead(secret), true);
    library.setPluginActive(true);
    expect(library.showEntry, true);
    expect(library.enabled, true);
    expect(library.unlocked, false);
    expect(prefs.containsKey(PrivateLibrary.storageKey), false);
  });

  test('bulk marks preserve books and locked/all/private-only views agree',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setBooksPrivate([secret], true);
    library.lock();
    expect(library.canRead(secret), false);
    expect(library.isVisible(ordinary), true);
    await library.unlock();
    expect(library.isVisible(secret), true);
    expect(library.isVisible(ordinary), true);
    await library.setOptions(privateOnly: true);
    expect(library.isVisible(ordinary), false);
    expect(library.canRead(ordinary), true);
    expect(library.isVisible(secret), true);
    await library.setBooksPrivate([secret], false);
    expect(library.isPrivate(secret), false);
    expect(secret.filePath, 'private.epub');
    expect(secret.readingPercentage, .78);
  });

  test('missing plugin and a fresh process stay closed until explicit recovery',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setBooksPrivate([secret], true);
    library.setPluginActive(false);
    expect(library.showEntry, false);
    expect(library.canRead(secret), false);
    final restarted = PrivateLibrary(preferences: prefs);
    addTearDown(restarted.dispose);
    expect(restarted.unlocked, false);
    expect(restarted.canRead(secret), false);
    restarted.setPluginActive(true);
    await restarted.unlock();
    expect(restarted.canRead(secret), true);
    await restarted.clearProtection();
    restarted.setPluginActive(false);
    expect(restarted.canRead(secret), true);
    expect(restarted.hasPrivateBooks, false);
  });

  test(
      'PIN uses independent salt and derived hash; background invalidates unlock',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setBooksPrivate([secret], true);
    await library.setPin('123456');
    final first =
        jsonDecode(prefs.getString(PrivateLibrary.storageKey)!) as Map;
    expect(base64Decode(first['salt'] as String), hasLength(16));
    expect(base64Decode(first['hash'] as String), hasLength(32));
    expect(
        prefs.getString(PrivateLibrary.storageKey), isNot(contains('123456')));
    library.lock();
    expect(await library.unlock('000000'), false);
    expect(await library.unlock('123456'), true);
    await library.setPin('123456');
    final second =
        jsonDecode(prefs.getString(PrivateLibrary.storageKey)!) as Map;
    expect(second['salt'], isNot(first['salt']));
    final pending = library.unlock('123456');
    library.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(await pending, false);
    expect(library.canRead(secret), false);
  });

  test('queued removal, settings and credential writes cannot outlive locking',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setBooksPrivate([secret], true);
    final removal = library.setBooksPrivate([secret], false);
    final settings = library.setOptions(autoImport: true);
    final credential = library.setPin('123456');
    final results = [
      expectLater(removal, throwsStateError),
      expectLater(settings, throwsStateError),
      expectLater(credential, throwsStateError),
    ];
    library.lock();
    await Future.wait(results);
    expect(library.isPrivate(secret), true);
    expect(library.autoImport, false);
    expect(library.hasPin, false);
  });

  test('worker derivation accepts the existing PBKDF2-SHA256 PIN format',
      () async {
    await prefs.setString(
        PrivateLibrary.storageKey,
        jsonEncode({
          'books': ['m:private'], 'salt': 'AAECAwQFBgcICQoLDA0ODw==',
          // Independent PBKDF2-HMAC-SHA256 vector: 210000 rounds, 32-byte output.
          'hash': '986qxnMbMmzuHyS3MK9F7gz4EXIuhMjAubUlwLFpHTo='
        }));
    library.setPluginActive(true);
    expect(await library.unlock('654321'), false);
    expect(await library.unlock('123456'), true);
    expect(library.canRead(secret), true);
  });

  test('cancelling verification or PIN creation rejects late worker results',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setPin('123456');
    library.lock();
    final checking = library.unlock('123456');
    library.cancelPendingAuthentication();
    expect(await checking, false);
    expect(library.unlocked, false);
    await library.unlock('123456');
    final before = prefs.getString(PrivateLibrary.storageKey);
    final saving = library.setPin('654321');
    final rejected = expectLater(saving, throwsStateError);
    library.cancelPendingAuthentication();
    await rejected;
    expect(prefs.getString(PrivateLibrary.storageKey), before);
    expect(library.unlocked, true);
    library.lock();
    expect(await library.unlock('123456'), true);
  });

  test('disposed authentication cannot unlock or notify a dead service',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setPin('123456');
    final discarded = PrivateLibrary(preferences: prefs)..setPluginActive(true);
    final checking = discarded.unlock('123456');
    discarded.dispose();
    expect(await checking, false);
  });

  test('reauthentication does not refresh unchanged library visibility',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setPin('123456');
    var notifications = 0;
    library.addListener(() => notifications++);
    expect(await library.unlock('123456'), true);
    expect(notifications, 0);
  });

  test('automatic privacy applies only to new imports and works while locked',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setOptions(autoImport: true);
    library.lock();
    await library.onImported(secret, isNew: false);
    expect(library.isPrivate(secret), false);
    await library.onImported(secret, isNew: true);
    expect(library.isPrivate(secret), true);
    expect(library.canRead(secret), false);
    library.setPluginActive(false);
    await library.onImported(ordinary, isNew: true);
    expect(library.isPrivate(ordinary), false);
  });

  test('explicit protection switch preserves marks and locks when re-enabled',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.setBooksPrivate([secret], true);
    await library.setEnabled(false);
    expect(library.unlocked, false);
    expect(library.canRead(secret), true);
    expect(library.isPrivate(secret), true);
    await library.unlock();
    await library.setEnabled(true);
    expect(library.canRead(secret), false);
  });

  test(
      'SQL policy agrees with memory for NULL hashes, aliases and quoted paths',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
        'CREATE TABLE tb_books(id INTEGER PRIMARY KEY,file_md5 TEXT,file_path TEXT)');
    await db.insert('tb_books',
        {'id': 1, 'file_md5': 'public', 'file_path': 'public.epub'});
    await db.insert('tb_books',
        {'id': 2, 'file_md5': 'private', 'file_path': 'private.epub'});
    final quoted =
        secret.copyWith(id: 3, md5: '', filePath: "reader's book.epub");
    await db.insert('tb_books', {'id': 3, 'file_path': quoted.filePath});
    library.setPluginActive(true);
    await library.unlock();
    await library.setBooksPrivate([secret, quoted], true);
    library.lock();
    Future<List<int>> ids() async => (await db.rawQuery(
            'SELECT b.id FROM tb_books b WHERE ${library.bookPredicate('b')} ORDER BY id'))
        .map((r) => r['id'] as int)
        .toList();
    expect(await ids(), [1]);
    await library.unlock();
    await library.setOptions(privateOnly: true);
    expect(await ids(), [2, 3]);
    expect(
        await db.rawQuery(
            'SELECT id AS book_id FROM tb_books WHERE ${library.bookIdPredicate('id')}'),
        hasLength(2));
  });

  test('damaged privacy data cannot silently expose books', () async {
    await prefs.setString(PrivateLibrary.storageKey, '{');
    expect(library.corrupt, true);
    expect(library.canRead(secret), false);
    expect(library.bookPredicate(), '0');
    expect(await library.unlock(), false);
  });

  test(
      'protected history IDs are local, persistent and released by verified cleanup',
      () async {
    library.setPluginActive(true);
    await library.unlock();
    await library.protectHistory('existing-conversation');
    expect(library.canReadHistory('existing-conversation'), true);
    library.lock();
    expect(library.canReadHistory('existing-conversation'), false);
    final fresh = PrivateLibrary(preferences: prefs);
    addTearDown(fresh.dispose);
    expect(fresh.canReadHistory('existing-conversation'), false);
    expect(fresh.canReadHistory('ordinary-conversation'), true);
    await library.unlock();
    await library.clearProtection();
    library.lock();
    expect(library.canReadHistory('existing-conversation'), true);
  });
}
