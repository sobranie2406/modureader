import 'dart:async';
import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/dao/book_note.dart';
import 'package:modu_reader/dao/database.dart';
import 'package:modu_reader/dao/reading_time.dart';
import 'package:modu_reader/dao/search_repository.dart';
import 'package:modu_reader/dao/tag.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/book_note.dart';
import 'package:modu_reader/models/tag.dart';
import 'package:modu_reader/service/ai/index.dart';
import 'package:modu_reader/service/dictionary/local_dictionary.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_retriever.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/service/tts/online_tts.dart';
import 'package:modu_reader/service/tts/system_tts.dart';
import 'package:modu_reader/service/tts/system_tts_support.dart';
import 'package:modu_reader/service/tts/tts_factory.dart';
import 'package:modu_reader/service/tts/tts_service.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:path/path.dart' as p;

/// Text the reading view exposes to one plugin invocation.
///
/// Kept as a narrow value object so the reader page can supply content without
/// giving the plugin a route into the reader itself.
class PluginReaderSnapshot {
  const PluginReaderSnapshot({
    required this.book,
    required this.chapter,
    this.currentChapter,
    this.chapterByHref,
  });

  final Book book;
  final String chapter;
  final Future<String> Function()? currentChapter;
  final Future<String> Function(String href)? chapterByHref;
}

/// Extra native surfaces a host call needs.
///
/// Optional on purpose: a headless test or a settings-page invocation simply
/// passes fewer handlers and the corresponding method fails as `permission`.
class PluginHostServices {
  const PluginHostServices({
    this.reader,
    this.showProgress,
    this.askConfirm,
    this.askPrompt,
    this.askSelect,
    this.copyToClipboard,
    this.readClipboard,
    this.shareText,
    this.openUrl,
  });

  final PluginReaderSnapshot? reader;
  final Future<void> Function(String label, double fraction)? showProgress;
  final Future<bool> Function(String title, String message)? askConfirm;
  final Future<String?> Function(String title, String message, String? initial)?
      askPrompt;
  final Future<String?> Function(String title, List<String> options)?
      askSelect;
  final Future<void> Function(String text)? copyToClipboard;
  final Future<String?> Function()? readClipboard;
  final Future<void> Function(String text, String? subject)? shareText;
  final Future<bool> Function(Uri uri)? openUrl;
}

/// Executes the non-network host API methods for one plugin.
///
/// Everything here is deliberately narrow: ids are validated, every list is
/// bounded, every write goes through the same DAO the app uses, and private
/// books are filtered by [PrivateLibrary.canRead] rather than by a copy of the
/// rule. Nothing returns a file path, a credential or another plugin's data.
class PluginHostApi {
  PluginHostApi({
    required this.pluginId,
    required this.services,
    this.maxResults = 50,
  });

  final String pluginId;
  final PluginHostServices services;
  final int maxResults;

  /// Dispatches one method. Throws [PluginScriptFailure] with a stable code.
  Future<Object?> call(String method, Map<String, dynamic> args) async {
    switch (method) {
      case 'library.list':
        return _libraryList(args);
      case 'library.tags':
        return _libraryTags(args);
      case 'library.groups':
        return _libraryGroups(args);
      case 'library.tag':
        return _libraryTag(args);
      case 'library.move':
        return _libraryMove(args);
      case 'books.content':
        return _bookContent(args);
      case 'books.chapter':
        return _bookChapter(args);
      case 'notes.list':
        return _notesList(args);
      case 'reading.stats':
        return _readingStats(args);
      case 'reading.history':
        return _readingHistory(args);
      case 'search.library':
        return _searchLibrary(args);
      case 'knowledge.search':
        return _knowledgeSearch(args);
      case 'dictionary.lookup':
        return _dictionaryLookup(args);
      case 'ai.complete':
        return _aiComplete(args);
      case 'translate.text':
        return _translate(args);
      case 'tts.speak':
        return _ttsSpeak(args);
      case 'clipboard.write':
        return _clipboardWrite(args);
      case 'clipboard.read':
        return _clipboardRead(args);
      case 'share.text':
        return _shareText(args);
      case 'ui.confirm':
        return _uiConfirm(args);
      case 'ui.prompt':
        return _uiPrompt(args);
      case 'ui.select':
        return _uiSelect(args);
      case 'ui.progress':
        return _uiProgress(args);
      case 'open.url':
        return _openUrl(args);
      case 'storage.list':
        return _storageList(args);
      case 'storage.read':
        return _storageRead(args);
      case 'storage.write':
        return _storageWrite(args);
      case 'storage.remove':
        return _storageRemove(args);
      default:
        throw const PluginScriptFailure('permission');
    }
  }

  // ---- argument helpers ----------------------------------------------------

  static const int _maxText = 8000;
  static const int _maxChapterChars = 12000;
  static const int _maxId = 1 << 31;

  void _only(Map<String, dynamic> args, Set<String> allowed) {
    if (args.keys.any((key) => !allowed.contains(key))) {
      throw const PluginScriptFailure('permission');
    }
  }

  int _int(Map<String, dynamic> args, String key,
      {required int min, required int max, int? fallback}) {
    final value = args[key] ?? fallback;
    if (value is! int || value < min || value > max) {
      throw const PluginScriptFailure('permission');
    }
    return value;
  }

  String _text(Map<String, dynamic> args, String key,
      {int maxLength = _maxText, bool allowEmpty = false}) {
    final value = args[key];
    if (value is! String || value.length > maxLength) {
      throw const PluginScriptFailure('permission');
    }
    if (!allowEmpty && value.trim().isEmpty) {
      throw const PluginScriptFailure('permission');
    }
    return value;
  }

  Future<Book> _readableBook(int id) async {
    final book = await bookDao.selectBookById(id);
    if (book.id != id || book.isDeleted) {
      throw const PluginScriptFailure('permission');
    }
    if (!PrivateLibrary.instance.canRead(book)) {
      throw const PluginScriptFailure('permission');
    }
    return book;
  }

  Map<String, Object?> _bookSummary(Book book) => {
        'id': book.id,
        'title': book.title,
        'author': book.author,
        'groupId': book.groupId,
        'percentage': book.readingPercentage,
        'lastReadAt': book.lastReadTime.toIso8601String(),
        'private': PrivateLibrary.instance.isPrivate(book),
      };

  // ---- library -------------------------------------------------------------

  Future<Object?> _libraryList(Map<String, dynamic> args) async {
    _only(args, const {'offset', 'limit'});
    final offset = _int(args, 'offset', min: 0, max: 10000, fallback: 0);
    final limit = _int(args, 'limit', min: 1, max: maxResults, fallback: 20);
    final books = await bookDao.selectBooks(includeDeleted: false);
    return books
        .where(PrivateLibrary.instance.canRead)
        .skip(offset)
        .take(limit)
        .map(_bookSummary)
        .toList();
  }

  Future<Object?> _libraryTags(Map<String, dynamic> args) async {
    _only(args, const {'bookId'});
    final bookId = _int(args, 'bookId', min: 1, max: _maxId);
    await _readableBook(bookId);
    final tags = await bookTagDao.fetchTagsForBook(bookId);
    return [
      for (final tag in tags)
        {'id': tag.id, 'name': tag.name, 'color': _colorValue(tag)},
    ];
  }

  Future<Object?> _libraryGroups(Map<String, dynamic> args) async {
    _only(args, const {});
    final db = await DBHelper().database;
    final rows = await db.rawQuery(
        'SELECT id, name, parent_id FROM tb_groups WHERE COALESCE(is_deleted, 0) = 0 ORDER BY id');
    return [
      for (final row in rows.take(500))
        {
          'id': row['id'],
          'name': row['name'],
          'parentId': row['parent_id'],
        }
    ];
  }

  Future<Object?> _libraryTag(Map<String, dynamic> args) async {
    _only(args, const {'bookIds', 'name', 'remove'});
    final ids = args['bookIds'];
    if (ids is! List || ids.isEmpty || ids.length > 100) {
      throw const PluginScriptFailure('permission');
    }
    final bookIds = <int>[];
    for (final id in ids) {
      if (id is! int || id < 1) throw const PluginScriptFailure('permission');
      bookIds.add(id);
    }
    final name = _text(args, 'name', maxLength: 60).trim();
    final remove = args['remove'];
    if (remove != null && remove is! bool) {
      throw const PluginScriptFailure('permission');
    }
    if (remove == true) {
      final tag = await tagDao.getTagByName(name);
      if (tag == null) return {'applied': 0};
      var applied = 0;
      for (final bookId in bookIds) {
        await _readableBook(bookId);
        await bookTagDao.removeRelation(bookId: bookId, tagId: tag.id);
        applied++;
      }
      return {'applied': applied};
    }
    final tag = await _ensureTag(name);
    for (final bookId in bookIds) {
      await _readableBook(bookId);
      await bookTagDao.addRelation(bookId: bookId, tagId: tag.id);
    }
    return {'applied': bookIds.length, 'tagId': tag.id};
  }

  Future<Tag> _ensureTag(String name) async {
    final existing = await tagDao.getTagByName(name);
    if (existing != null) return existing;
    final id = await tagDao.insertTag(name, color: 0x00888888);
    return (await tagDao.getTagById(id)) ?? Tag(id: id, name: name);
  }

  String? _colorValue(Tag tag) =>
      tag.color?.toARGB32().toRadixString(16).padLeft(8, '0');

  Future<Object?> _libraryMove(Map<String, dynamic> args) async {
    _only(args, const {'bookIds', 'groupId'});
    final ids = args['bookIds'];
    if (ids is! List || ids.isEmpty || ids.length > 100) {
      throw const PluginScriptFailure('permission');
    }
    final groupId = _int(args, 'groupId', min: 0, max: _maxId);
    final bookIds = <int>[];
    for (final id in ids) {
      if (id is! int || id < 1) throw const PluginScriptFailure('permission');
      await _readableBook(id);
      bookIds.add(id);
    }
    await bookDao.moveBooksToFolder(bookIds, groupId: groupId);
    return {'moved': bookIds.length};
  }

  // ---- book content --------------------------------------------------------

  Future<Object?> _bookContent(Map<String, dynamic> args) async {
    _only(args, const {'maxCharacters'});
    final reader = services.reader;
    final fetch = reader?.currentChapter;
    if (reader == null || fetch == null) {
      throw const PluginScriptFailure('permission');
    }
    if (!PrivateLibrary.instance.canRead(reader.book)) {
      throw const PluginScriptFailure('permission');
    }
    final limit = _int(args, 'maxCharacters',
        min: 1, max: _maxChapterChars, fallback: _maxChapterChars);
    final text = await fetch();
    return {
      'bookId': reader.book.id,
      'title': reader.book.title,
      'chapter': reader.chapter,
      'text': text.length > limit ? text.substring(0, limit) : text,
    };
  }

  Future<Object?> _bookChapter(Map<String, dynamic> args) async {
    _only(args, const {'href', 'maxCharacters'});
    final reader = services.reader;
    final fetch = reader?.chapterByHref;
    if (reader == null || fetch == null) {
      throw const PluginScriptFailure('permission');
    }
    if (!PrivateLibrary.instance.canRead(reader.book)) {
      throw const PluginScriptFailure('permission');
    }
    final href = _text(args, 'href', maxLength: 512).trim();
    final limit = _int(args, 'maxCharacters',
        min: 1, max: _maxChapterChars, fallback: _maxChapterChars);
    final text = await fetch(href);
    return {
      'bookId': reader.book.id,
      'href': href,
      'text': text.length > limit ? text.substring(0, limit) : text,
    };
  }

  // ---- notes ---------------------------------------------------------------

  Future<Object?> _notesList(Map<String, dynamic> args) async {
    _only(args, const {'bookId', 'keyword', 'limit'});
    final limit = _int(args, 'limit', min: 1, max: maxResults, fallback: 20);
    final bookId = args.containsKey('bookId')
        ? _int(args, 'bookId', min: 1, max: _maxId)
        : null;
    if (bookId != null) await _readableBook(bookId);
    final keyword = args.containsKey('keyword')
        ? _text(args, 'keyword', maxLength: 200)
        : null;
    final notes = await bookNoteDao.searchBookNotesAdvanced(
      keyword: keyword,
      bookId: bookId,
      limit: limit * 2,
    );
    final books = await bookDao
        .selectBooksByIds(notes.map((note) => note.bookId).toSet().toList());
    final byId = {for (final book in books) book.id: book};
    final result = <Map<String, Object?>>[];
    for (final note in notes) {
      final book = byId[note.bookId];
      if (book == null || !PrivateLibrary.instance.canRead(book)) continue;
      result.add(_noteSummary(note, book));
      if (result.length >= limit) break;
    }
    return result;
  }

  Map<String, Object?> _noteSummary(BookNote note, Book book) => {
        'id': note.id,
        'bookId': note.bookId,
        'bookTitle': book.title,
        'chapter': note.chapter,
        'type': note.type,
        'text': _excerpt(note.content, 4000),
        if (note.readerNote != null && note.readerNote!.trim().isNotEmpty)
          'note': _excerpt(note.readerNote!, 2000),
      };

  // ---- reading statistics --------------------------------------------------

  Future<Object?> _readingStats(Map<String, dynamic> args) async {
    _only(args, const {'days'});
    final days = _int(args, 'days', min: 1, max: 365, fallback: 30);
    final from = DateTime.now().subtract(Duration(days: days));
    final entries = await readingTimeDao.queryReadingHistory(from: from);
    var total = 0;
    final perBook = <int, int>{};
    for (final entry in entries) {
      total += entry.readingTime;
      perBook[entry.bookId] = (perBook[entry.bookId] ?? 0) + entry.readingTime;
    }
    final books =
        await bookDao.selectBooksByIds(perBook.keys.toList(growable: false));
    final byId = {for (final book in books) book.id: book};
    final ranked = perBook.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final result = <Map<String, Object?>>[];
    for (final entry in ranked) {
      final book = byId[entry.key];
      if (book == null || !PrivateLibrary.instance.canRead(book)) continue;
      result.add({
        'bookId': entry.key,
        'title': book.title,
        'seconds': entry.value,
      });
      if (result.length >= 20) break;
    }
    return {'days': days, 'totalSeconds': total, 'books': result};
  }

  Future<Object?> _readingHistory(Map<String, dynamic> args) async {
    _only(args, const {'bookId', 'limit'});
    final limit = _int(args, 'limit', min: 1, max: maxResults, fallback: 20);
    final bookId = args.containsKey('bookId')
        ? _int(args, 'bookId', min: 1, max: _maxId)
        : null;
    if (bookId != null) await _readableBook(bookId);
    final entries =
        await readingTimeDao.queryReadingHistory(bookId: bookId, limit: limit);
    final books = await bookDao
        .selectBooksByIds(entries.map((entry) => entry.bookId).toSet().toList());
    final byId = {for (final book in books) book.id: book};
    final result = <Map<String, Object?>>[];
    for (final entry in entries) {
      final book = byId[entry.bookId];
      if (book == null || !PrivateLibrary.instance.canRead(book)) continue;
      result.add({
        'bookId': entry.bookId,
        'title': book.title,
        'date': entry.date,
        'seconds': entry.readingTime,
      });
      if (result.length >= limit) break;
    }
    return result;
  }

  // ---- search --------------------------------------------------------------

  Future<Object?> _searchLibrary(Map<String, dynamic> args) async {
    _only(args, const {'query', 'limit', 'includeNotes'});
    final query = _text(args, 'query', maxLength: 200).trim();
    final limit = _int(args, 'limit', min: 1, max: maxResults, fallback: 20);
    final includeNotes = args['includeNotes'];
    if (includeNotes != null && includeNotes is! bool) {
      throw const PluginScriptFailure('permission');
    }
    final data = await const SearchRepository()
        .search(query, limit: limit, includeNotes: includeNotes != false);
    return {
      'books': [
        for (final book in data.books.take(limit))
          if (PrivateLibrary.instance.canRead(book)) _bookSummary(book)
      ],
      'notes': [
        for (final group in data.noteGroups)
          if (PrivateLibrary.instance.canRead(group.book))
            for (final note in group.notes.take(limit))
              _noteSummary(note, group.book)
      ],
    };
  }

  Future<Object?> _knowledgeSearch(Map<String, dynamic> args) async {
    _only(args, const {'query', 'limit'});
    final query = _text(args, 'query', maxLength: 500).trim();
    final limit = _int(args, 'limit', min: 1, max: 20, fallback: 5);
    final reader = services.reader;
    final book = reader?.book ??
        (await bookDao.selectBooks(includeDeleted: false))
            .where(PrivateLibrary.instance.canRead)
            .firstOrNull;
    if (book == null || !PrivateLibrary.instance.canRead(book)) {
      throw const PluginScriptFailure('permission');
    }
    final results = await BookKnowledgeRetriever().search(book, query,
        limit: limit, timeBudget: const Duration(seconds: 5));
    return {
      'bookId': book.id,
      'results': [
        for (final result in results)
          {'score': result.score, 'text': _excerpt(result.chunk.text, 1200)}
      ],
    };
  }

  static String _excerpt(String value, int max) =>
      value.length > max ? value.substring(0, max) : value;

  // ---- dictionary ----------------------------------------------------------

  Future<Object?> _dictionaryLookup(Map<String, dynamic> args) async {
    _only(args, const {'word', 'limit'});
    final word = _text(args, 'word', maxLength: 256).trim();
    final limit = _int(args, 'limit', min: 1, max: 20, fallback: 5);
    final entries =
        await LocalDictionaryStore(getBasePath('dictionaries')).lookup(word);
    return [
      for (final entry in entries.take(limit))
        {
          'word': entry.word,
          'definition': _excerpt(entry.definition, 4000),
          // The source dictionary name is the closest thing to a part of
          // speech the local format carries; the plugin may render it.
          'dictionary': entry.dictionary,
          if (entry.attribution != null) 'attribution': entry.attribution,
        }
    ];
  }

  // ---- AI / translate ------------------------------------------------------

  Future<Object?> _aiComplete(Map<String, dynamic> args) async {
    _only(args, const {'prompt', 'system'});
    final prompt = _text(args, 'prompt', maxLength: 16000).trim();
    final system = args.containsKey('system')
        ? _text(args, 'system', maxLength: 8000).trim()
        : null;
    final messages = <ChatMessage>[
      if (system != null) SystemChatMessage(content: system),
      HumanChatMessage(
          content: ChatMessageContent.text(prompt)),
    ];
    final buffer = StringBuffer();
    await for (final chunk in aiGenerateStream(messages)) {
      buffer.write(chunk);
      // The runtime deadline still applies; this only stops a runaway answer
      // from eating the whole budget.
      if (buffer.length > 32000) break;
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw const PluginScriptFailure('result');
    return {'text': text};
  }

  Future<Object?> _translate(Map<String, dynamic> args) async {
    _only(args, const {'text'});
    final text = _text(args, 'text', maxLength: 8000).trim();
    final translated = await translateTextOnly(text);
    return {'text': _excerpt(translated, _maxText * 2)};
  }

  Future<Object?> _ttsSpeak(Map<String, dynamic> args) async {
    _only(args, const {'text'});
    final text = _text(args, 'text', maxLength: 4000).trim();
    if (!supportsSystemTts() && Prefs().ttsService == 'system') {
      throw const PluginScriptFailure('permission');
    }
    final tts = TtsFactory().current;
    await tts.stop();
    // The plugin speaks through the user's own voice settings; it never gets a
    // raw audio pipeline, so it cannot exfiltrate the synthesised bytes.
    if (tts is OnlineTts) {
      final voice =
          getTtsService(Prefs().ttsService).provider.getSelectedVoice();
      if (voice.isNotEmpty) {
        await tts.speakWithVoice(text, voice, rate: 1.0);
      } else {
        await tts.speak(content: text);
      }
    } else if (tts is SystemTts) {
      final voice =
          getTtsService(Prefs().ttsService).provider.getSelectedVoice();
      if (voice.isNotEmpty) {
        await tts.speakWithVoice(text, voice, rate: 1.0);
      } else {
        await tts.speak(content: text);
      }
    } else {
      throw const PluginScriptFailure('permission');
    }
    return {'spoken': true};
  }

  // ---- system surfaces -----------------------------------------------------

  Future<Object?> _clipboardWrite(Map<String, dynamic> args) async {
    _only(args, const {'text'});
    final text = _text(args, 'text', maxLength: _maxText);
    final write = services.copyToClipboard;
    if (write == null) throw const PluginScriptFailure('permission');
    await write(text);
    return {'written': true};
  }

  Future<Object?> _clipboardRead(Map<String, dynamic> args) async {
    _only(args, const {});
    final read = services.readClipboard;
    if (read == null) throw const PluginScriptFailure('permission');
    final text = await read();
    return {'text': text == null ? '' : _excerpt(text, _maxText)};
  }

  Future<Object?> _shareText(Map<String, dynamic> args) async {
    _only(args, const {'text', 'subject'});
    final text = _text(args, 'text', maxLength: _maxText);
    final subject = args.containsKey('subject')
        ? _text(args, 'subject', maxLength: 120)
        : null;
    final share = services.shareText;
    if (share == null) throw const PluginScriptFailure('permission');
    await share(text, subject);
    return {'shared': true};
  }

  Future<Object?> _uiConfirm(Map<String, dynamic> args) async {
    _only(args, const {'title', 'message'});
    final title = _text(args, 'title', maxLength: 120);
    final message = _text(args, 'message', maxLength: 2000);
    final ask = services.askConfirm;
    if (ask == null) throw const PluginScriptFailure('permission');
    return {'confirmed': await ask(title, message)};
  }

  Future<Object?> _uiPrompt(Map<String, dynamic> args) async {
    _only(args, const {'title', 'message', 'initial'});
    final title = _text(args, 'title', maxLength: 120);
    final message = _text(args, 'message', maxLength: 2000, allowEmpty: true);
    final initial = args.containsKey('initial')
        ? _text(args, 'initial', maxLength: 500, allowEmpty: true)
        : null;
    final ask = services.askPrompt;
    if (ask == null) throw const PluginScriptFailure('permission');
    return {'text': await ask(title, message, initial)};
  }

  Future<Object?> _uiSelect(Map<String, dynamic> args) async {
    _only(args, const {'title', 'options'});
    final title = _text(args, 'title', maxLength: 120);
    final raw = args['options'];
    if (raw is! List || raw.isEmpty || raw.length > 30) {
      throw const PluginScriptFailure('permission');
    }
    final options = <String>[];
    for (final option in raw) {
      if (option is! String || option.isEmpty || option.length > 200) {
        throw const PluginScriptFailure('permission');
      }
      options.add(option);
    }
    final ask = services.askSelect;
    if (ask == null) throw const PluginScriptFailure('permission');
    return {'selected': await ask(title, options)};
  }

  Future<Object?> _uiProgress(Map<String, dynamic> args) async {
    _only(args, const {'label', 'fraction'});
    final label = _text(args, 'label', maxLength: 120, allowEmpty: true);
    final raw = args['fraction'];
    if (raw is! num || raw.isNaN || raw < 0 || raw > 1) {
      throw const PluginScriptFailure('permission');
    }
    final show = services.showProgress;
    if (show == null) throw const PluginScriptFailure('permission');
    await show(label, raw.toDouble());
    return {'shown': true};
  }

  // ---- plugin storage ------------------------------------------------------

  /// Files live outside the verified package, so writing cannot make the
  /// installed plugin look tampered with on the next start.
  static const int _maxStorageFiles = 200;
  static const int _maxStorageFileBytes = 256 * 1024;
  static const int _maxStorageTotalBytes = 4 * 1024 * 1024;

  Directory get _storageRoot => pluginOwnedDirectory(pluginId);

  /// Rejects anything that is not a flat, safe file name.
  ///
  /// Names are compared after normalisation as well as by pattern: the pattern
  /// catches intent, the containment check catches a missed rule.
  String _storageName(Object? raw) {
    if (raw is! String || raw.isEmpty || raw.length > 64) {
      throw const PluginScriptFailure('permission');
    }
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*\.json$').hasMatch(raw)) {
      throw const PluginScriptFailure('permission');
    }
    final resolved = p.normalize(p.join(_storageRoot.path, raw));
    if (p.dirname(resolved) != p.normalize(_storageRoot.path)) {
      throw const PluginScriptFailure('permission');
    }
    return raw;
  }

  Future<List<File>> _storageFiles() async {
    final root = _storageRoot;
    if (!await root.exists()) return const [];
    final files = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.json')) {
        files.add(entity);
        if (files.length > _maxStorageFiles) {
          throw const PluginScriptFailure('quota');
        }
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<Object?> _storageList(Map<String, dynamic> args) async {
    _only(args, const {});
    final files = await _storageFiles();
    return [
      for (final file in files)
        {
          'name': p.basename(file.path),
          'bytes': await file.length(),
        }
    ];
  }

  Future<Object?> _storageRead(Map<String, dynamic> args) async {
    _only(args, const {'name'});
    final file = File(p.join(_storageRoot.path, _storageName(args['name'])));
    if (!await file.exists()) return {'text': null};
    if (await file.length() > _maxStorageFileBytes) {
      throw const PluginScriptFailure('size');
    }
    return {'text': await file.readAsString()};
  }

  Future<Object?> _storageWrite(Map<String, dynamic> args) async {
    _only(args, const {'name', 'text'});
    final name = _storageName(args['name']);
    final text = _text(args, 'text', maxLength: _maxStorageFileBytes);
    final root = _storageRoot;
    if (!await root.exists()) await root.create(recursive: true);
    var total = 0;
    final existing = await _storageFiles();
    for (final file in existing) {
      total += await file.length();
    }
    if (existing.length >= _maxStorageFiles) {
      throw const PluginScriptFailure('quota');
    }
    final target = File(p.join(root.path, name));
    final previous = await target.exists() ? await target.length() : 0;
    if (total - previous + text.length > _maxStorageTotalBytes) {
      throw const PluginScriptFailure('quota');
    }
    await target.writeAsString(text, flush: true);
    return {'bytes': text.length};
  }

  Future<Object?> _storageRemove(Map<String, dynamic> args) async {
    _only(args, const {'name'});
    final file = File(p.join(_storageRoot.path, _storageName(args['name'])));
    if (!await file.exists()) return {'removed': false};
    await file.delete();
    return {'removed': true};
  }

  Future<Object?> _openUrl(Map<String, dynamic> args) async {
    _only(args, const {'url'});
    final raw = _text(args, 'url', maxLength: 2048).trim();
    final uri = Uri.tryParse(raw);
    // Only ordinary web links: a plugin must not hand the platform a
    // `file:`, `javascript:` or `intent:` URL another app would act on.
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const PluginScriptFailure('permission');
    }
    final open = services.openUrl;
    if (open == null) throw const PluginScriptFailure('permission');
    return {'opened': await open(uri)};
  }
}

/// The plugin's own data directory, resolved through the same root as packages.
Directory pluginOwnedDirectory(String id) =>
    Directory(p.join(getBasePath('plugins'), '.data', id));
