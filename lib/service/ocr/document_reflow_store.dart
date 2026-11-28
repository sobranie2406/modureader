import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'document_text_reflow.dart';
import 'document_text_geometry.dart';

enum DocumentTextExportFormat {
  txt('txt', 'text/plain'),
  markdown('md', 'text/markdown');

  const DocumentTextExportFormat(this.extension, this.mimeType);
  final String extension, mimeType;
}

/// Not an EPUB CFI: never pass these positions to the original PDF renderer.
class DocumentReflowAnchor {
  const DocumentReflowAnchor(
      this.page, this.ocr, this.revision, this.start, this.end,
      {this.rects = const [], this.original = false});
  static const prefix = 'modu-reflow:';
  final int page, start, end;
  final bool ocr;
  final String revision;
  final List<DocumentImageRect> rects;
  final bool original;
  String encode() {
    final base = '$page:${ocr ? 1 : 0}:$revision:$start:$end';
    return rects.isEmpty
        ? '${prefix}v1:$base'
        : '${prefix}v2:$base:${base64Url.encode(utf8.encode(jsonEncode(rects.map((r) => r.toJson()).toList())))}';
  }

  String get originalReference =>
      '${prefix}source:${encode().substring(prefix.length)}';
  static DocumentReflowAnchor? parse(String value) {
    if (value.length > 1000000) return null;
    final original = value.startsWith('${prefix}source:');
    if (original) value = prefix + value.substring('${prefix}source:'.length);
    final match = RegExp(
            r'^modu-reflow:v([12]):(\d+):([01]):([a-f0-9]{64}):(\d+):(\d+)(?::([A-Za-z0-9_=-]+))?$')
        .firstMatch(value);
    if (match == null) return null;
    final page = int.tryParse(match[2]!),
        start = int.tryParse(match[5]!),
        end = int.tryParse(match[6]!);
    if (page == null ||
        start == null ||
        end == null ||
        page > 1000000 ||
        start < 0 ||
        end <= start ||
        end > 1000000) {
      return null;
    }
    final rects = <DocumentImageRect>[];
    if (match[1] == '1' && match[7] != null) return null;
    if (match[1] == '2') {
      try {
        final raw = jsonDecode(utf8.decode(base64Url.decode(match[7]!)));
        if (raw is! List || raw.isEmpty || raw.length > 4096) return null;
        for (final value in raw) {
          final rect = DocumentImageRect.decode(value);
          if (rect == null) return null;
          rects.add(rect);
        }
      } catch (_) {
        return null;
      }
    }
    return DocumentReflowAnchor(page, match[3] == '1', match[4]!, start, end,
        rects: List.unmodifiable(rects), original: original);
  }

  bool matches(DocumentReflowPage value) =>
      page == value.page &&
      revision == value.revision &&
      end <= value.text.length;
}

class DocumentReflowPage {
  DocumentReflowPage(
      {required this.page,
      required this.ocr,
      required this.rawText,
      this.layoutVersion = 4,
      this.editedText,
      this.ocrProfile = '',
      List<DocumentTextRegion> rawRegions = const []})
      : rawRegions = DocumentTextResult(rawText, rawRegions).regions {
    final mapped = <DocumentTextRegion>[];
    final ordered = [...this.rawRegions]
      ..sort((a, b) => a.start.compareTo(b.start));
    var cursor = 0;
    final originalText = reflowDocumentText(rawText,
        layoutVersion: layoutVersion,
        regions: layoutVersion >= 3 ? this.rawRegions : const [],
        mapLine: (rawStart, rawEnd, start, end) {
      while (cursor < ordered.length && ordered[cursor].end <= rawStart) {
        cursor++;
      }
      for (var i = cursor;
          i < ordered.length && ordered[i].start < rawEnd;
          i++) {
        final region = ordered[i];
        final a = region.start.clamp(rawStart, rawEnd);
        final b = region.end.clamp(rawStart, rawEnd);
        final mappedStart = (start + a - rawStart).clamp(start, end);
        final mappedEnd = (start + b - rawStart).clamp(start, end);
        if (mappedEnd > mappedStart) {
          mapped.add(DocumentTextRegion(mappedStart, mappedEnd, region.rect));
        }
      }
    });
    if (editedText != null) {
      if (editedText!.length > 1000000) {
        throw const FormatException('Edited page is too large');
      }
      // Only unchanged text keeps its image mapping; never guess coordinates for a correction.
      var prefix = 0, suffix = 0;
      while (prefix < originalText.length &&
          prefix < editedText!.length &&
          originalText.codeUnitAt(prefix) == editedText!.codeUnitAt(prefix)) {
        prefix++;
      }
      while (suffix < originalText.length - prefix &&
          suffix < editedText!.length - prefix &&
          originalText.codeUnitAt(originalText.length - suffix - 1) ==
              editedText!.codeUnitAt(editedText!.length - suffix - 1)) {
        suffix++;
      }
      final delta = editedText!.length - originalText.length;
      final unchanged = <DocumentTextRegion>[];
      for (final region in mapped) {
        if (region.end <= prefix) {
          unchanged.add(region);
        } else if (region.start >= originalText.length - suffix) {
          unchanged.add(DocumentTextRegion(
              region.start + delta, region.end + delta, region.rect));
        }
      }
      mapped
        ..clear()
        ..addAll(unchanged);
    }
    text = editedText ?? originalText;
    regions = List.unmodifiable(mapped);
    // Geometry is part of the immutable revision: identical OCR words can move.
    revision = sha256
        .convert(utf8.encode(rawRegions.isEmpty
            ? text
            : jsonEncode([text, rawRegions.map((r) => r.toJson()).toList()])))
        .toString();
  }
  final int page;
  final bool ocr;
  final int layoutVersion;
  final String rawText;
  final String ocrProfile;
  bool acceptsOcrProfile(String profile) =>
      !ocr || editedText != null || ocrProfile == profile;
  final String? editedText;
  late final String text, revision;
  final List<DocumentTextRegion> rawRegions;
  late final List<DocumentTextRegion> regions;
  DocumentReflowAnchor anchor(int start, int end) =>
      DocumentReflowAnchor(page, ocr, revision, start, end,
          rects: List.unmodifiable(regions
              .where((r) => r.start < end && r.end > start)
              .map((r) => r.rect)));
  Map<String, Object> toJson() => {
        'version':
            layoutVersion >= 3 ? layoutVersion : (rawRegions.isEmpty ? 1 : 2),
        'page': page,
        'ocr': ocr,
        'rawText': rawText,
        if (ocrProfile.isNotEmpty) 'ocrProfile': ocrProfile,
        'text': text,
        'revision': revision,
        if (editedText != null) 'editedText': editedText!,
        if (rawRegions.isNotEmpty)
          'regions': rawRegions.map((r) => r.toJson()).toList(),
      };
  static DocumentReflowPage? decode(dynamic data) {
    if (data is! Map ||
        ![1, 2, 3, 4].contains(data['version']) ||
        data['page'] is! int ||
        data['ocr'] is! bool ||
        data['rawText'] is! String) {
      return null;
    }
    final raw = data['rawText'] as String;
    if (raw.length > 1000000 || (data['page'] as int) < 0) return null;
    try {
      if (data['editedText'] != null && data['editedText'] is! String) {
        return null;
      }
      if (data['version'] == 2 && data['regions'] is! List) return null;
      final geometry = data['version'] != 1
          ? DocumentTextResult.decode({'text': raw, 'regions': data['regions']})
              .regions
          : const <DocumentTextRegion>[];
      final value = DocumentReflowPage(
          page: data['page'],
          ocr: data['ocr'],
          rawText: raw,
          layoutVersion: data['version'],
          editedText: data['editedText'],
          ocrProfile: data['ocrProfile'] ?? '',
          rawRegions: geometry);
      return value.revision == data['revision'] && value.text == data['text']
          ? value
          : null;
    } catch (_) {
      return null;
    }
  }
}

/// One durable book file, indexed by original page, including immutable note revisions.
class DocumentReflowStore {
  DocumentReflowStore(this.bookKey, {this.directory});
  final String bookKey;
  final Directory? directory;
  Future<Directory> _root() async => Directory(
      '${(directory ?? await getApplicationSupportDirectory()).path}/document-reflow-v1/${sha256.convert(utf8.encode(bookKey))}');
  static final _pending = <String, Future<void>>{};
  Future<T> _locked<T>(Future<T> Function(Directory) action) async {
    final root = await _root();
    final previous = _pending[root.path] ?? Future<void>.value();
    final done = Completer<void>();
    _pending[root.path] = done.future;
    await previous;
    try {
      return await action(root);
    } finally {
      done.complete();
      if (identical(_pending[root.path], done.future)) {
        _pending.remove(root.path);
      }
    }
  }

  Future<Map<String, dynamic>> _book(Directory root) async {
    final file = File('${root.path}/book.json');
    if (await file.exists()) {
      if (await file.length() > 256 * 1024 * 1024) {
        throw const FormatException('Saved OCR book is too large');
      }
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic> ||
          data['version'] != 1 ||
          data['pages'] is! Map<String, dynamic> ||
          data['revisions'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid saved OCR book');
      }
      return data;
    }
    final data = <String, dynamic>{
      'version': 1,
      'pages': <String, dynamic>{},
      'revisions': <String, dynamic>{}
    };
    if (!await root.exists()) return data;
    // Import legacy profile caches once, retaining their files as recovery copies.
    final files = <(File, DateTime)>[];
    await for (final entry in root.list()) {
      if (entry is File &&
          RegExp(r'[/\\]\d+-[a-f0-9]{64}\.json$').hasMatch(entry.path)) {
        files.add((entry, await entry.lastModified()));
      }
    }
    files.sort((a, b) => a.$2.compareTo(b.$2));
    for (final entry in files) {
      try {
        if (await entry.$1.length() > 12000000) continue;
        final page = DocumentReflowPage.decode(
            jsonDecode(await entry.$1.readAsString()));
        if (page != null) _put(data, page);
      } on FormatException {
        continue;
      }
    }
    if ((data['pages'] as Map).isNotEmpty) await _write(root, data);
    return data;
  }

  void _put(Map<String, dynamic> data, DocumentReflowPage page,
      {bool explicit = false}) {
    final key = '${page.page}-${page.revision}';
    (data['revisions'] as Map)[key] = page.toJson();
    (data['pages'] as Map)['${page.page}'] = key;
    final heads = data.putIfAbsent('heads', () => <String, dynamic>{}) as Map;
    var clock = 0;
    for (final head in heads.values) {
      if ((head['clock'] as int) > clock) clock = head['clock'] as int;
    }
    heads['${page.page}'] = {
      'clock': clock + 1,
      'explicit': explicit ||
          page.editedText != null ||
          heads['${page.page}']?['explicit'] == true,
    };
  }

  DocumentReflowPage? _page(Map<String, dynamic> data, int number) {
    final key = (data['pages'] as Map)['$number'];
    if (key == null) return null;
    final page = DocumentReflowPage.decode((data['revisions'] as Map)[key]);
    if (page == null ||
        page.page != number ||
        key != '$number-${page.revision}') {
      throw const FormatException('Invalid saved OCR page');
    }
    return page;
  }

  Future<void> _write(Directory root, Map<String, dynamic> data) async {
    await root.create(recursive: true);
    final bytes = utf8.encode(jsonEncode(data));
    if (bytes.length > 256 * 1024 * 1024) {
      throw const FormatException('Saved OCR book is too large');
    }
    final file = File('${root.path}/book.json');
    final temporary =
        File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  // Forced OCR skips embedded-text heads; old revisions remain available to notes.
  Future<Set<int>> cachedPages(int start, int count,
          {bool forceOcr = false, String ocrProfile = ''}) =>
      _locked((root) async {
        if (start < 0 || count < 0 || count > 5) {
          throw ArgumentError('Invalid prefetch window');
        }
        final data = await _book(root);
        return {
          for (var page = start; page < start + count; page++)
            if (_page(data, page) case final saved?
                when (!forceOcr || saved.ocr) &&
                    saved.acceptsOcrProfile(ocrProfile))
              page
        };
      });

  Future<DocumentReflowPage?> read(int page, String profile) =>
      _locked((root) async {
        final data = await _book(root);
        final result = _page(data, page);
        if (result != null &&
            result.layoutVersion < 4 &&
            result.editedText == null) {
          final updated = DocumentReflowPage(
              page: page,
              ocr: result.ocr,
              ocrProfile: result.ocrProfile,
              rawText: result.rawText,
              rawRegions: result.rawRegions);
          _put(data, updated);
          await _write(root, data);
          return updated;
        }
        return result;
      });

  Future<DocumentReflowPage?> readAnchor(DocumentReflowAnchor anchor) =>
      _locked((root) async {
        final data = await _book(root);
        final result = DocumentReflowPage.decode(
            (data['revisions'] as Map)['${anchor.page}-${anchor.revision}']);
        return result != null && anchor.matches(result) ? result : null;
      });

  Future<void> save(DocumentReflowPage value, String profile,
          {bool onlyIfAbsent = false, bool replaceEmbeddedText = false}) =>
      _locked((root) async {
        if (bookKey.isEmpty ||
            value.text.trim().isEmpty ||
            value.text.length > 1000000 ||
            value.rawText.length > 1000000 ||
            value.page < 0 ||
            value.page > 1000000) {
          throw const FormatException('Invalid reflow page');
        }
        final data = await _book(root);
        final existing = _page(data, value.page);
        if (onlyIfAbsent &&
            existing != null &&
            existing.acceptsOcrProfile(value.ocrProfile) &&
            !(replaceEmbeddedText && value.ocr && !existing.ocr)) {
          return;
        }
        _put(data, value, explicit: !onlyIfAbsent);
        await _write(root, data);
      });

  Future<DocumentReflowPage> saveEdit(
          DocumentReflowPage original, String text) =>
      _locked((root) async {
        if (text.trim().isEmpty || text.length > 1000000) {
          throw const FormatException('Invalid edited page');
        }
        final data = await _book(root);
        if (_page(data, original.page)?.revision != original.revision) {
          throw StateError('Page changed; reopen before editing');
        }
        final edited = DocumentReflowPage(
            page: original.page,
            ocr: original.ocr,
            ocrProfile: original.ocrProfile,
            rawText: original.rawText,
            rawRegions: original.rawRegions,
            layoutVersion: original.layoutVersion,
            editedText: text);
        _put(data, edited, explicit: true);
        await _write(root, data);
        return edited;
      });

  /// Snapshot under the same lock as OCR/edit writes; local numeric IDs never travel.
  Future<Map<String, dynamic>> syncSnapshot() => _locked(
      (root) async => DocumentReflowSyncData.normalize(await _book(root)));

  Future<void> mergeSynced(Map<String, dynamic> incoming) =>
      _locked((root) async {
        final local = await _book(root);
        final merged = DocumentReflowSyncData.merge(local, incoming);
        if (jsonEncode(local) != jsonEncode(merged)) await _write(root, merged);
      });

  Future<String> exportTxt() => exportText();

  Future<String> exportText({
    DocumentTextExportFormat format = DocumentTextExportFormat.txt,
  }) =>
      _locked((root) async {
        final data = await _book(root);
        final numbers = (data['pages'] as Map)
            .keys
            .map((key) => int.parse(key as String))
            .toList()
          ..sort();
        const separator = '────────────────────';
        if (format == DocumentTextExportFormat.markdown) {
          return numbers
              .map((number) =>
                  '## 第${number + 1}页\n\n${_page(data, number)!.text}\n')
              .join('\n---\n\n');
        }
        return numbers
            .map((number) =>
                '第${number + 1}页\n$separator\n${_page(data, number)!.text}\n$separator')
            .join('\n\n');
      });
}

/// A per-page logical clock makes merges independent of device/server wall time.
/// Explicit edits/re-OCR beat passive prefetch; all immutable note revisions survive.
abstract final class DocumentReflowSyncData {
  static const maxBytes = 256 * 1024 * 1024;

  static Map<String, dynamic> normalize(Map<String, dynamic> data) {
    if (data['version'] != 1 ||
        data['pages'] is! Map ||
        data['revisions'] is! Map ||
        (data['heads'] != null && data['heads'] is! Map)) {
      throw const FormatException('Invalid OCR sync data');
    }
    final pages = data['pages'] as Map;
    final revisions = data['revisions'] as Map;
    final heads = data['heads'] as Map? ?? {};
    if (pages.length > 100000 || revisions.length > 200000) {
      throw const FormatException('OCR sync data exceeds limits');
    }
    final cleanRevisions = <String, dynamic>{};
    for (final key in revisions.keys.toList()..sort()) {
      final page = DocumentReflowPage.decode(revisions[key]);
      if (page == null ||
          page.page > 1000000 ||
          key != '${page.page}-${page.revision}') {
        throw const FormatException('Invalid OCR sync revision');
      }
      cleanRevisions[key as String] = page.toJson();
    }
    final cleanPages = <String, dynamic>{}, cleanHeads = <String, dynamic>{};
    for (final key in pages.keys.toList()..sort()) {
      final number = key is String ? int.tryParse(key) : null;
      final revision = pages[key];
      final page = cleanRevisions[revision];
      if (number == null ||
          '$number' != key ||
          page == null ||
          page['page'] != number) {
        throw const FormatException('Invalid OCR sync page');
      }
      final head =
          heads[key] ?? {'clock': 0, 'explicit': page['editedText'] != null};
      if (head is! Map ||
          head['clock'] is! int ||
          head['clock'] < 0 ||
          head['clock'] > 9007199254740000 ||
          head['explicit'] is! bool) {
        throw const FormatException('Invalid OCR sync clock');
      }
      cleanPages[key as String] = revision;
      cleanHeads[key] = {'clock': head['clock'], 'explicit': head['explicit']};
    }
    return {
      'version': 1,
      'pages': cleanPages,
      'revisions': cleanRevisions,
      'heads': cleanHeads
    };
  }

  static Map<String, dynamic> merge(
      Map<String, dynamic> a, Map<String, dynamic> b) {
    a = normalize(a);
    b = normalize(b);
    final revisions = a['revisions'] as Map<String, dynamic>;
    for (final entry in (b['revisions'] as Map<String, dynamic>).entries) {
      final old = revisions[entry.key];
      // Legacy revisions hash displayed text/geometry, not raw OCR metadata.
      if (old == null ||
          jsonEncode(entry.value).compareTo(jsonEncode(old)) > 0) {
        revisions[entry.key] = entry.value;
      }
    }
    final pages = a['pages'] as Map<String, dynamic>;
    final heads = a['heads'] as Map<String, dynamic>;
    for (final entry in (b['pages'] as Map<String, dynamic>).entries) {
      final old = heads[entry.key];
      final next = b['heads'][entry.key];
      var order = old == null
          ? 1
          : (next['explicit'] == true ? 1 : 0)
              .compareTo(old['explicit'] == true ? 1 : 0);
      if (old != null && order == 0) {
        order = (next['clock'] as int).compareTo(old['clock'] as int);
        if (order == 0) {
          order = (entry.value as String).compareTo(pages[entry.key] as String);
        }
      }
      if (order > 0) {
        pages[entry.key] = entry.value;
        heads[entry.key] = next;
      }
    }
    return normalize(a);
  }
}
