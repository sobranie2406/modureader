import 'package:anx_reader/models/book.dart';

/// A versioned, data-only reference. Never includes credentials or file paths.
class ReadingLink {
  const ReadingLink(
      {required this.title,
      required this.author,
      required this.created,
      required this.cfi,
      this.md5});

  final String title;
  final String author;
  final DateTime created;
  final String cfi;
  final String? md5;

  static final _hash = RegExp(r'^[a-fA-F0-9]{32}$');
  static final _controls = RegExp(r'[\x00-\x1f\x7f]');
  static bool validCfi(String value) =>
      value.length <= 8192 &&
      value.startsWith('epubcfi(') &&
      value.endsWith(')') &&
      !_controls.hasMatch(value);

  static String? forBook(Book book, String cfi) {
    if (!validCfi(cfi) ||
        book.title.length > 1000 ||
        book.author.length > 1000) {
      return null;
    }
    final raw = ReadingLink(
            title: book.title,
            author: book.author,
            created: book.createTime,
            cfi: cfi,
            md5:
                _hash.hasMatch(book.md5 ?? '') ? book.md5!.toLowerCase() : null)
        .uri
        .toString();
    return raw.length <= 40000 ? raw : null;
  }

  Uri get uri => Uri(scheme: 'modu', host: 'read', queryParameters: {
        'v': '1',
        'title': title,
        'author': author,
        'created': created.toUtc().toIso8601String(),
        if (md5 != null) 'md5': md5!,
        'cfi': cfi,
      });

  factory ReadingLink.parse(String raw) {
    if (raw.length > 40000) {
      throw const FormatException('Reading link too long');
    }
    final uri = Uri.parse(raw);
    if (uri.scheme != 'modu' ||
        uri.host != 'read' ||
        uri.path.isNotEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((v) => v.length != 1)) {
      throw const FormatException('Invalid reading link');
    }
    final q = uri.queryParameters;
    final created = DateTime.tryParse(q['created'] ?? '');
    if (q['v'] != '1' ||
        created == null ||
        !q.containsKey('title') ||
        !q.containsKey('author') ||
        q['title']!.length > 1000 ||
        q['author']!.length > 1000 ||
        !validCfi(q['cfi'] ?? '') ||
        (q.containsKey('md5') && !_hash.hasMatch(q['md5']!))) {
      throw const FormatException('Invalid reading reference');
    }
    return ReadingLink(
        title: q['title']!,
        author: q['author']!,
        created: created,
        cfi: q['cfi']!,
        md5: q['md5']?.toLowerCase());
  }

  List<Book> matches(Iterable<Book> books) => books.where((book) {
        if (book.isDeleted) return false;
        if (md5 != null) return book.md5?.toLowerCase() == md5;
        // Legacy records without a hash need all three fields. A local numeric ID
        // alone is never portable, and a title alone can select a different edition.
        return book.title == title &&
            book.author == author &&
            book.createTime.isAtSameMomentAs(created);
      }).toList();
}

/// Buffer a cold-start link until storage/migration and the home navigator are
/// ready. Serial delivery avoids stacking readers; while busy, newest wins.
class ReadingLinkInbox {
  Future<void> Function(String)? _handler;
  String? _pending;
  String? _active;
  bool _running = false;

  void add(String raw) {
    if (!raw.startsWith('modu://read') ||
        raw.length > 40000 ||
        raw == _active ||
        raw == _pending) {
      return;
    }
    _pending = raw;
    _drain();
  }

  void attach(Future<void> Function(String) handler) {
    _handler = handler;
    _drain();
  }

  void detach() => _handler = null;

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_handler != null && _pending != null) {
        final handler = _handler!;
        _active = _pending;
        _pending = null;
        try {
          await handler(_active!);
        } catch (_) {
          // UI handler reports errors. Never leak a URI into crash/log output
          // or block subsequent user links after one failed navigation.
        }
        _active = null;
      }
    } finally {
      _running = false;
    }
  }
}

final readingLinkInbox = ReadingLinkInbox();
