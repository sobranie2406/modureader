import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/dao/database.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/dao/book_note.dart';
import 'package:modu_reader/dao/reading_time.dart';
import 'package:modu_reader/dao/search_repository.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/providers/book_list.dart';
import 'package:modu_reader/providers/ai_history.dart';
import 'package:modu_reader/providers/ai_chat.dart';
import 'package:modu_reader/service/ai/ai_history.dart';
import 'package:modu_reader/service/ai/reading_request_snapshot.dart';
import 'package:modu_reader/service/ai/reading_skill_execution.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/statistic/reading_insights.dart';
import 'package:modu_reader/service/ai/tools/repository/books_repository.dart';
import 'package:modu_reader/service/ai/tools/repository/notes_repository.dart';
import 'package:modu_reader/service/ai/tools/repository/reading_history_repository.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import '../service/sync/row_sync_test.dart' show bookRow;

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final library = PrivateLibrary.instance;
  late Directory root;
  late PathProviderPlatform oldPaths;
  late String oldDocumentPath;
  late Book secret;
  setUp(() async {
    await DBHelper.close();
    root = await Directory.systemTemp.createTemp('modu-private-dao-');
    oldPaths = PathProviderPlatform.instance;
    oldDocumentPath = documentPath;
    PathProviderPlatform.instance = _Paths(root.path);
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await initBasePath();
    final db = await DBHelper().database;
    await db.insert(
        'tb_books', {...bookRow(1, md5: 'public'), 'title': 'Public book'});
    await db.insert(
        'tb_books', {...bookRow(2, md5: 'private'), 'title': 'Private book'});
    for (final id in [1, 2]) {
      await db.insert('tb_notes', {
        'book_id': id,
        'content': 'Matching note $id',
        'cfi': 'epubcfi(/6/2)',
        'chapter': 'Chapter',
        'type': 'highlight',
        'color': 'FFFF00',
        'create_time': '2026-11-01',
        'update_time': '2026-11-0$id'
      });
      await readingTimeDao.insertReadingSession(
          bookId: id, readingTime: id * 60, startedAt: DateTime(2026, 11, id));
    }
    secret = await bookDao.selectBookById(2);
    library.setPluginActive(true);
    await library.unlock();
    await library.setBooksPrivate([secret], true);
    library.lock();
  });
  tearDown(() async {
    library.setPluginActive(false);
    await DBHelper.close();
    PathProviderPlatform.instance = oldPaths;
    documentPath = oldDocumentPath;
    await root.delete(recursive: true);
  });

  test('shelf policy refreshes on unlock while raw sync keeps every book',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
        (await container.read(bookListProvider.future))
            .expand((b) => b)
            .map((b) => b.id),
        [1]);
    expect(await bookDao.selectNotDeleteBooks(), hasLength(2));
    expect(await bookDao.selectBooks(), hasLength(2));
    await library.unlock();
    expect((await container.read(bookListProvider.future)).expand((b) => b),
        hasLength(2));
    await library.setOptions(privateOnly: true);
    expect(
        (await container.read(bookListProvider.future))
            .expand((b) => b)
            .single
            .id,
        2);
    library.lock();
    expect(
        (await container.read(bookListProvider.future))
            .expand((b) => b)
            .single
            .id,
        1);
  });

  test(
      'protected AI history remains on disk and lock clears restored book content',
      () async {
    const id = 'existing-conversation';
    final entry = AiChatHistoryEntry(
        id: id,
        scope: 'knowledge',
        serviceId: 'fake',
        model: 'fake',
        createdAt: 1,
        updatedAt: 1,
        messages: [ChatMessage.ai('PRIVATE ANSWER')],
        completed: true);
    await AiHistoryStore.upsertEntry(entry);
    await AiHistoryStore.upsertEntry(AiChatHistoryEntry(
        id: 'legacy-without-book-id',
        scope: 'library',
        serviceId: 'fake',
        model: 'fake',
        createdAt: 1,
        updatedAt: 1,
        messages: [ChatMessage.ai('UNATTRIBUTED ANSWER')],
        completed: true));
    await AiHistoryStore.upsertEntry(AiChatHistoryEntry(
        id: 'public-conversation',
        scope: 'reader',
        serviceId: 'fake',
        model: 'fake',
        createdAt: 2,
        updatedAt: 2,
        messages: [ChatMessage.ai('PUBLIC ANSWER')],
        completed: true,
        readingRequest: ReadingRequestSnapshot(
            bookId: 1,
            request: ReadingSkillRequest(
                messages: [ChatMessage.humanText('Public question')],
                useAgent: false))));
    await library.unlock();
    await library.protectHistory(id);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiHistoryProvider.notifier).refresh();
    expect(container.read(aiHistoryProvider).value, hasLength(3));
    library.lock();
    await container.read(aiHistoryProvider.notifier).refresh();
    expect(container.read(aiHistoryProvider).value!.single.id,
        'public-conversation');
    expect(await AiHistoryStore.readHistory(), hasLength(3));
    await library.unlock();
    await container.read(aiHistoryProvider.notifier).refresh();
    expect(container.read(aiHistoryProvider).value, hasLength(3));
    await container.read(aiChatProvider(AiChatScope.knowledge).future);
    final chat = container.read(aiChatProvider(AiChatScope.knowledge).notifier);
    chat.loadHistoryEntry(entry);
    library.lock();
    expect(
        container.read(aiChatProvider(AiChatScope.knowledge)).value, isEmpty);
    expect(await AiHistoryStore.readHistory(), hasLength(3));
  });

  test('search, note lists, counts and random selection exclude locked books',
      () async {
    final result = await const SearchRepository().search('book');
    expect(result.books.map((b) => b.id), [1]);
    final notes = await const SearchRepository().search('Matching');
    expect(notes.noteGroups.map((g) => g.book.id), [1]);
    expect(await bookNoteDao.selectBookNotesByBookId(2), isEmpty);
    expect((await bookNoteDao.selectAllBookIdAndNotes()).single['bookId'], 1);
    expect(await bookNoteDao.selectNumberOfNotesAndBooks(),
        {'numberOfNotes': 1, 'numberOfBooks': 1});
    expect((await bookNoteDao.selectRandomNote())!.bookId, 1);
    expect(
        (await bookNoteDao.searchBookNotesAdvanced(
                keyword: 'Matching', limit: 1))
            .single
            .bookId,
        1);
  });

  test('reading history and insights filter before limit and aggregation',
      () async {
    expect(
        (await readingTimeDao.queryReadingHistory(limit: 1)).single.bookId, 1);
    expect((await readingTimeDao.selectLatestReadingRecord())!['book_id'], 1);
    expect(await readingTimeDao.selectTotalReadingTime(), 60);
    expect(
        (await readingTimeDao.selectBookReadingTimeOfAll())
            .single
            .keys
            .single
            .id,
        1);
    final insights = await ReadingInsights.load(await DBHelper().database,
        now: DateTime(2026, 11, 3));
    expect(insights.totalSeconds, 60);
  });

  test('AI book, note and history repositories cannot bypass the same policy',
      () async {
    expect((await const BooksRepository().searchBooks(limit: 1)).single.book.id,
        1);
    expect(await const BooksRepository().fetchByIds([2]), isEmpty);
    expect((await const NotesRepository().searchNotes(limit: 1)).single.book.id,
        1);
    expect(
        (await const ReadingHistoryRepository().fetchHistory(limit: 1))
            .single
            .book
            .id,
        1);
    await library.unlock();
    final cached =
        (await const BooksRepository().searchBooks(keyword: 'Private')).single;
    library.lock();
    expect(cached.toMap, throwsStateError);
  });

  test('privacy does not alter row sync schema or remove synchronized data',
      () async {
    final db = await DBHelper().database;
    final before =
        (await RowSyncStore(db).snapshot()).map((r) => r.toMap()).toList();
    expect(before.where((r) => r['kind'] == 'book'), hasLength(2));
    await bookDao.selectNotDeleteBooks(visibleOnly: true);
    await bookNoteDao.searchBookNotesAdvanced(keyword: 'Matching');
    await readingTimeDao.queryReadingHistory();
    expect((await RowSyncStore(db).snapshot()).map((r) => r.toMap()).toList(),
        before);
    expect(
        (await db.rawQuery('PRAGMA table_info(tb_books)'))
            .map((r) => r['name']),
        isNot(contains('is_private')));
  });
}
