import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'document_text_reflow.dart';

/// Not an EPUB CFI: never pass these positions to the original PDF renderer.
class DocumentReflowAnchor {
  const DocumentReflowAnchor(
      this.page, this.ocr, this.revision, this.start, this.end);
  static const prefix = 'modu-reflow:';
  final int page, start, end;
  final bool ocr;
  final String revision;
  String encode() => '${prefix}v1:$page:${ocr ? 1 : 0}:$revision:$start:$end';
  static DocumentReflowAnchor? parse(String value) {
    final match =
        RegExp(r'^modu-reflow:v1:(\d+):([01]):([a-f0-9]{64}):(\d+):(\d+)$')
            .firstMatch(value);
    if (match == null) return null;
    final page = int.tryParse(match[1]!),
        start = int.tryParse(match[4]!),
        end = int.tryParse(match[5]!);
    if (page == null ||
        start == null ||
        end == null ||
        page > 1000000 ||
        start < 0 ||
        end <= start ||
        end > 1000000) {
      return null;
    }
    return DocumentReflowAnchor(page, match[2] == '1', match[3]!, start, end);
  }

  bool matches(DocumentReflowPage value) =>
      page == value.page &&
      revision == value.revision &&
      end <= value.text.length;
}

class DocumentReflowPage {
  DocumentReflowPage(
      {required this.page, required this.ocr, required this.rawText})
      : text = reflowDocumentText(rawText),
        revision =
            sha256.convert(utf8.encode(reflowDocumentText(rawText))).toString();
  final int page;
  final bool ocr;
  final String rawText, text, revision;
  Map<String, Object> toJson() => {
        'version': 1,
        'page': page,
        'ocr': ocr,
        'rawText': rawText,
        'text': text,
        'revision': revision
      };
  static DocumentReflowPage? decode(dynamic data) {
    if (data is! Map ||
        data['version'] != 1 ||
        data['page'] is! int ||
        data['ocr'] is! bool ||
        data['rawText'] is! String) {
      return null;
    }
    final raw = data['rawText'] as String;
    if (raw.length > 1000000 || (data['page'] as int) < 0) return null;
    final value =
        DocumentReflowPage(page: data['page'], ocr: data['ocr'], rawText: raw);
    return value.revision == data['revision'] && value.text == data['text']
        ? value
        : null;
  }
}

/// Page text, not preferences. Book identity and OCR model revision are part of
/// the cache key. Immutable text revisions keep older notes anchored safely.
class DocumentReflowStore {
  DocumentReflowStore(this.bookKey, {this.directory});
  final String bookKey;
  final Directory? directory;
  Future<Directory> _root() async => Directory(
      '${(directory ?? await getApplicationSupportDirectory()).path}/document-reflow-v1/${sha256.convert(utf8.encode(bookKey))}');
  String _index(int page, String profile) =>
      '$page-${sha256.convert(utf8.encode(profile))}.json';
  Future<DocumentReflowPage?> _read(String name) async {
    try {
      final file = File('${(await _root()).path}/$name');
      if (!await file.exists() || await file.length() > 12000000) return null;
      return DocumentReflowPage.decode(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<DocumentReflowPage?> read(int page, String profile) async {
    final result = await _read(_index(page, profile));
    return result?.page == page ? result : null;
  }

  Future<DocumentReflowPage?> readAnchor(DocumentReflowAnchor anchor) async {
    final result = await _read('${anchor.page}-${anchor.revision}.json');
    return result != null && anchor.matches(result) ? result : null;
  }

  Future<void> save(DocumentReflowPage value, String profile) async {
    if (bookKey.isEmpty ||
        value.text.isEmpty ||
        value.rawText.length > 1000000) {
      throw const FormatException('Invalid reflow page');
    }
    final root = await _root();
    await root.create(recursive: true);
    for (final name in [
      '${value.page}-${value.revision}.json',
      _index(value.page, profile)
    ]) {
      final file = File('${root.path}/$name');
      // Flush then rename; an interrupted OCR/cache write must not replace a
      // valid text revision with a partial JSON document.
      final temporary =
          File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.part');
      try {
        await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
  }
}
