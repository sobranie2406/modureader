import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart' hide ZLibDecoder;
import 'package:dict_reader/dict_reader.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

const _entryLimit = 2 * 1024 * 1024;
const _indexLimit = 64 * 1024 * 1024;
const _dataLimit = 2 * 1024 * 1024 * 1024;

class DictionaryFailure implements Exception {
  const DictionaryFailure(this.code);
  final String code;
  @override
  String toString() => 'DictionaryFailure($code)';
}

class LocalDictionary {
  const LocalDictionary(
      this.id, this.name, this.format, this.count, this.enabled);
  final String id, name, format;
  final int count;
  final bool enabled;
}

class DictionaryEntry {
  const DictionaryEntry(this.dictionary, this.word, this.definition);
  final String dictionary, word, definition;
}

/// Independent local storage: deliberately outside book DB, prefs and WebDAV
/// backup manifests. Dictionary content never participates in synchronization.
class LocalDictionaryStore {
  LocalDictionaryStore(this.root);
  final String root;
  Future<void> _tail = Future.value();

  // Serialize reads/deletes/imports for each UI store. SQLite protects separate
  // instances; published dictionaries are complete, immutable entry databases.
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<List<LocalDictionary>> list() => _serial(() => _listAsync(root));

  Future<void> importFiles(List<String> paths, String name,
          {void Function(int count)? onProgress}) =>
      _serial(() async {
        _checkName(name);
        final directory = root;
        final files = List<String>.of(paths);
        final port = ReceivePort();
        final subscription = port.listen((count) {
          if (count is int) onProgress?.call(count);
        });
        final send = port.sendPort;
        try {
          await _importAsync(directory, files, name.trim(), send);
        } finally {
          await subscription.cancel();
          port.close();
        }
      });

  Future<void> rename(String id, String name) => _update(id, name: name);
  Future<void> enable(String id, bool enabled) => _update(id, enabled: enabled);
  Future<void> _update(String id, {String? name, bool? enabled}) =>
      _serial(() async {
        if (name != null) _checkName(name);
        final path = _dictionaryPath(root, id);
        await _updateAsync(path, name, enabled);
      });

  Future<void> delete(String id) => _serial(() async {
        // Only remove the imported copy. Never delete the user's source files.
        final file = File(_dictionaryPath(root, id));
        if (await file.exists()) await file.delete();
      });

  Future<List<DictionaryEntry>> lookup(String word) => _serial(() {
        final query = word.trim();
        if (query.isEmpty || query.length > 256) {
          return Future.value(<DictionaryEntry>[]);
        }
        return _lookupAsync(root, query);
      });
}

// Separate top-level scopes prevent Isolate.run from capturing a store's
// pending Future, Flutter widgets or the progress callback along with its data.
Future<List<LocalDictionary>> _listAsync(String directory) =>
    Isolate.run(() => _list(directory));
Future<void> _importAsync(
        String directory, List<String> files, String name, SendPort send) =>
    Isolate.run(() => _import(directory, files, name, send));
Future<void> _updateAsync(String path, String? name, bool? enabled) =>
    Isolate.run(() {
      final db = sqlite3.open(path, mode: OpenMode.readWrite);
      try {
        if (name != null) db.execute('UPDATE info SET name=?', [name.trim()]);
        if (enabled != null) {
          db.execute('UPDATE info SET enabled=?', [enabled ? 1 : 0]);
        }
      } finally {
        db.dispose();
      }
    });
Future<List<DictionaryEntry>> _lookupAsync(String directory, String query) =>
    Isolate.run(() {
      final result = <DictionaryEntry>[];
      for (final dictionary in _list(directory).where((d) => d.enabled)) {
        final db = sqlite3.open(_dictionaryPath(directory, dictionary.id),
            mode: OpenMode.readOnly);
        try {
          result.addAll(_lookup(db, query, <String>{})
              .map((row) => DictionaryEntry(dictionary.name, row.$1, row.$2)));
        } finally {
          db.dispose();
        }
      }
      return result;
    });

void _checkName(String name) {
  if (name.trim().isEmpty || name.trim().length > 80) {
    throw const DictionaryFailure('name');
  }
}

String _dictionaryPath(String root, String id) {
  if (!RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(id)) {
    throw const DictionaryFailure('id');
  }
  return p.join(root, '$id.sqlite');
}

List<LocalDictionary> _list(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return [];
  final result = <LocalDictionary>[];
  for (final file in dir.listSync(followLinks: false).whereType<File>()) {
    if (!file.path.endsWith('.sqlite')) continue;
    final id = p.basenameWithoutExtension(file.path);
    _dictionaryPath(root, id);
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      final row = db.select('SELECT * FROM info').single;
      result.add(LocalDictionary(id, row['name'] as String,
          row['format'] as String, row['count'] as int, row['enabled'] == 1));
    } finally {
      db.dispose();
    }
  }
  result.sort((a, b) => a.name.compareTo(b.name));
  return result;
}

List<(String, String)> _lookup(Database db, String word, Set<String> visited) {
  final key = word.trim().toLowerCase();
  if (visited.length >= 8 || !visited.add(key)) return [];
  final rows =
      db.select('SELECT word,body FROM entries WHERE lookup=? LIMIT 20', [key]);
  final result = <(String, String)>[];
  for (final row in rows) {
    if (result.length >= 20) break;
    final body = row['body'] as String;
    if (body.startsWith('@@@LINK=')) {
      result.addAll(_lookup(db, body.substring(8).trim(), visited)
          .take(20 - result.length));
    } else {
      result.add((row['word'] as String, body));
    }
  }
  return result;
}

/// Convert untrusted dictionary markup to text, retaining paragraph boundaries.
/// No web view, scripts, CSS, external images, URLs or resource loads are used.
String dictionaryPlainText(String source) {
  final document = html.parseFragment(source);
  document
      .querySelectorAll('script,style,iframe,object,embed,svg,head')
      .forEach((element) => element.remove());
  final out = StringBuffer();
  const blocks = {'p', 'div', 'br', 'li', 'tr', 'h1', 'h2', 'h3', 'h4', 'hr'};
  void visit(dom.Node node) {
    if (node is dom.Text) out.write(node.text);
    if (node is dom.Element && blocks.contains(node.localName)) out.writeln();
    for (final child in node.nodes) {
      visit(child);
    }
    if (node is dom.Element && blocks.contains(node.localName)) out.writeln();
  }

  visit(document);
  return out
      .toString()
      .replaceAll('\u0000', '')
      .replaceAll(RegExp(r'\n[ \t]*\n(?:[ \t]*\n)+'), '\n\n')
      .trim();
}

Future<void> _import(
    String root, List<String> paths, String name, SendPort progress) async {
  Directory(root).createSync(recursive: true);
  final stage = Directory(root).createTempSync('.import-');
  Database? db;
  try {
    if (paths.isEmpty || paths.length > 16) {
      throw const DictionaryFailure('files');
    }
    if (paths.length == 1 && paths.single.toLowerCase().endsWith('.zip')) {
      paths = await _unzip(paths.single, stage.path);
    }
    final mdx = paths.where((f) => f.toLowerCase().endsWith('.mdx')).toList();
    final ifo = paths.where((f) => f.toLowerCase().endsWith('.ifo')).toList();
    if (mdx.length + ifo.length != 1) throw const DictionaryFailure('files');
    final output = p.join(stage.path, 'dictionary.db');
    db = sqlite3.open(output);
    db.execute('PRAGMA cache_size=-4096');
    db.execute(
        'CREATE TABLE entries(id INTEGER PRIMARY KEY, word TEXT NOT NULL, lookup TEXT NOT NULL, body TEXT NOT NULL)');
    db.execute(
        'CREATE TABLE info(name TEXT, format TEXT, count INTEGER, enabled INTEGER)');
    var count = 0;
    var totalBytes = 0;
    final insert =
        db.prepare('INSERT INTO entries(word,lookup,body) VALUES(?,?,?)');
    void add(String word, String body) {
      word = word.replaceAll('\u0000', '').trim();
      if (word.isEmpty || word.length > 4096 || body.length > _entryLimit) {
        throw const DictionaryFailure('entry');
      }
      totalBytes += utf8.encode(body).length;
      if (totalBytes > _dataLimit || count >= 2000000) {
        throw const DictionaryFailure('size');
      }
      insert.execute([word, word.toLowerCase(), body]);
      count++;
      if (count % 1000 == 0) progress.send(count);
    }

    db.execute('BEGIN');
    try {
      if (mdx.isNotEmpty) {
        if (File(mdx.single).lengthSync() > 256 * 1024 * 1024) {
          throw const DictionaryFailure('mdxSize');
        }
        final reader = DictReader(mdx.single);
        try {
          final headerFile = File(mdx.single).openSync();
          try {
            final bytes = headerFile.readSync(4);
            if (bytes.length != 4) throw const DictionaryFailure('format');
            final headerSize = ByteData.sublistView(bytes).getUint32(0);
            if (headerSize < 2 ||
                headerSize > 1024 * 1024 ||
                headerSize + 8 > headerFile.lengthSync()) {
              throw const DictionaryFailure('format');
            }
          } finally {
            headerFile.closeSync();
          }
          await reader.initDict(readKeys: false, readRecordBlockInfo: false);
          final version = double.tryParse(
                  reader.header['GeneratedByEngineVersion'] ?? '') ??
              0;
          final encrypted = reader.header['Encrypted'] ?? 'No';
          if (version < 1 ||
              version >= 3 ||
              encrypted == 'Yes' ||
              ((int.tryParse(encrypted) ?? 0) & 1) != 0) {
            throw const DictionaryFailure('format');
          }
          await reader.initDict();
          await for (final entry in reader.readWithMdxData()) {
            if (entry.data.length > _entryLimit) {
              throw const DictionaryFailure('entry');
            }
            add(entry.keyText, dictionaryPlainText(entry.data));
          }
          if (count != reader.numEntries) {
            throw const DictionaryFailure('count');
          }
        } finally {
          await reader.close();
        }
      } else {
        await _readStarDict(ifo.single, paths, stage.path, db, add);
      }
      if (count == 0) throw const DictionaryFailure('empty');
      db.execute('CREATE INDEX word_lookup ON entries(lookup)');
      db.execute('INSERT INTO info VALUES(?,?,?,1)',
          [name, mdx.isEmpty ? 'StarDict' : 'MDX', count]);
      db.execute('COMMIT');
    } finally {
      insert.dispose();
    }
    db.dispose();
    db = null;
    File(output).renameSync(_dictionaryPath(root, const Uuid().v4()));
    progress.send(count);
  } on DictionaryFailure {
    rethrow;
  } on FileSystemException {
    throw const DictionaryFailure('io');
  } catch (_) {
    // Parser errors may contain paths or dictionary text. Do not log/display them.
    throw const DictionaryFailure('format');
  } finally {
    db?.dispose();
    if (stage.existsSync()) stage.deleteSync(recursive: true);
  }
}

Future<List<String>> _unzip(String path, String target) async {
  if (File(path).lengthSync() > 512 * 1024 * 1024) {
    throw const DictionaryFailure('size');
  }
  final input = InputFileStream(path);
  try {
    // Read headers only. ZipDecoder(verify:true) eagerly inflates every file,
    // including unrelated attachments, before sizes can be checked.
    final archive = ZipDirectory.read(input);
    final result = <String>[];
    final names = <String>{};
    var total = 0;
    if (archive.fileHeaders.length > 1000) {
      throw const DictionaryFailure('size');
    }
    for (final header in archive.fileHeaders) {
      final entry = header.file!;
      final name = header.filename.replaceAll('\\', '/');
      final mode = (header.externalFileAttributes ?? 0) >> 16;
      if (name.startsWith('/') ||
          name.split('/').contains('..') ||
          name.contains(':') ||
          mode & 0xf000 == 0xa000) {
        throw const DictionaryFailure('archive');
      }
      if (name.endsWith('/')) continue;
      final base = p.posix.basename(name);
      if (!RegExp(r'\.(mdx|ifo|idx|idx\.gz|dict|dict\.dz|syn)$',
              caseSensitive: false)
          .hasMatch(base)) {
        continue;
      }
      final size = header.uncompressedSize ?? -1;
      total += size;
      if (size < 0 || size > _dataLimit || total > _dataLimit) {
        throw const DictionaryFailure('size');
      }
      if (!names.add(base.toLowerCase())) {
        throw const DictionaryFailure('files');
      }
      if (entry.flags & 1 != 0 || !{0, 8}.contains(entry.compressionMethod)) {
        throw const DictionaryFailure('archive');
      }
      final raw = entry.rawContent!;
      Stream<List<int>> compressed() async* {
        while (!raw.isEOS) {
          yield raw.readBytes(raw.length.clamp(0, 16384)).toUint8List();
        }
      }

      final stream = entry.compressionMethod == 8
          ? compressed().transform(ZLibDecoder(raw: true))
          : compressed();
      var written = 0, crc = 0;
      final file = File(p.join(target, base));
      final sink = file.openWrite();
      try {
        await sink.addStream(stream.map((bytes) {
          written += bytes.length;
          if (written > size) throw const DictionaryFailure('archive');
          crc = getCrc32(bytes, crc);
          return bytes;
        }));
      } finally {
        await sink.close();
      }
      if (written != size || crc != header.crc32) {
        throw const DictionaryFailure('archive');
      }
      result.add(file.path);
    }
    return result;
  } finally {
    await input.close();
  }
}

Future<String> _inflateFile(String source, String output, int limit) async {
  final sink = File(output).openWrite();
  var count = 0;
  try {
    final stream = File(source).openRead().transform(gzip.decoder).map((bytes) {
      count += bytes.length;
      if (count > limit) throw const DictionaryFailure('size');
      return bytes;
    });
    await sink.addStream(stream);
  } finally {
    await sink.close();
  }
  return output;
}

Future<void> _readStarDict(String ifo, List<String> files, String stage,
    Database db, void Function(String, String) add) async {
  if (File(ifo).lengthSync() > 1024 * 1024) {
    throw const DictionaryFailure('size');
  }
  final lines = File(ifo).readAsLinesSync();
  if (lines.isEmpty || lines.first != "StarDict's dict ifo file") {
    throw const DictionaryFailure('format');
  }
  final info = <String, String>{};
  for (final line in lines.skip(1)) {
    final at = line.indexOf('=');
    if (at > 0) {
      info[line.substring(0, at).trim()] = line.substring(at + 1).trim();
    }
  }
  if (!{'2.4.2', '3.0.0'}.contains(info['version']) ||
      !{'32', '64'}.contains(info['idxoffsetbits'] ?? '32')) {
    throw const DictionaryFailure('format');
  }
  final stem = p.basenameWithoutExtension(ifo).toLowerCase();
  String? companion(List<String> extensions) {
    final matches = files
        .where((f) =>
            extensions.any((ext) => p.basename(f).toLowerCase() == '$stem$ext'))
        .toList();
    if (matches.length > 1) throw const DictionaryFailure('files');
    return matches.firstOrNull;
  }

  var idxPath = companion(['.idx', '.idx.gz']);
  var dataPath = companion(['.dict', '.dict.dz']);
  if (idxPath == null || dataPath == null) {
    throw const DictionaryFailure('companions');
  }
  if (idxPath.toLowerCase().endsWith('.gz')) {
    idxPath =
        await _inflateFile(idxPath, p.join(stage, 'index.raw'), _indexLimit);
  }
  if (dataPath.toLowerCase().endsWith('.dz')) {
    dataPath =
        await _inflateFile(dataPath, p.join(stage, 'data.raw'), _dataLimit);
  }
  if (File(idxPath).lengthSync() > _indexLimit ||
      File(dataPath).lengthSync() > _dataLimit) {
    throw const DictionaryFailure('size');
  }
  final idx = File(idxPath).readAsBytesSync();
  if (idx.length != int.tryParse(info['idxfilesize'] ?? '')) {
    throw const DictionaryFailure('count');
  }
  final numbers = ByteData.sublistView(idx);
  final width = info['idxoffsetbits'] == '64' ? 8 : 4;
  final data = File(dataPath).openSync();
  var at = 0, words = 0;
  try {
    while (at < idx.length) {
      final end = idx.indexOf(0, at);
      if (end < at || end - at > 4096 || end + 1 + width + 4 > idx.length) {
        throw const DictionaryFailure('format');
      }
      final word = utf8.decode(idx.sublist(at, end));
      at = end + 1;
      final offset = width == 8 ? numbers.getUint64(at) : numbers.getUint32(at);
      final size = numbers.getUint32(at + width);
      at += width + 4;
      if (size > _entryLimit ||
          offset < 0 ||
          offset + size > data.lengthSync()) {
        throw const DictionaryFailure('entry');
      }
      data.setPositionSync(offset);
      add(word,
          starDictDefinition(data.readSync(size), info['sametypesequence']));
      words++;
    }
  } finally {
    data.closeSync();
  }
  if (words != int.tryParse(info['wordcount'] ?? '')) {
    throw const DictionaryFailure('count');
  }
  final synonyms = companion(['.syn']);
  if (synonyms != null) {
    if (File(synonyms).lengthSync() > _indexLimit) {
      throw const DictionaryFailure('size');
    }
    final bytes = File(synonyms).readAsBytesSync();
    final view = ByteData.sublistView(bytes);
    at = 0;
    var count = 0;
    while (at < bytes.length) {
      final end = bytes.indexOf(0, at);
      if (end < at || end + 5 > bytes.length) {
        throw const DictionaryFailure('format');
      }
      final word = utf8.decode(bytes.sublist(at, end));
      final original = view.getUint32(end + 1);
      if (original >= words) throw const DictionaryFailure('entry');
      final row = db
          .select('SELECT body FROM entries WHERE id=?', [original + 1]).single;
      add(word, row['body'] as String);
      at = end + 5;
      count++;
    }
    if (count != int.tryParse(info['synwordcount'] ?? '')) {
      throw const DictionaryFailure('count');
    }
  } else if ((int.tryParse(info['synwordcount'] ?? '0') ?? 0) != 0) {
    throw const DictionaryFailure('companions');
  }
}

String starDictDefinition(Uint8List bytes, String? sequence) {
  var at = 0;
  final parts = <String>[];
  var field = 0;
  while (at < bytes.length) {
    final type = sequence == null
        ? String.fromCharCode(bytes[at++])
        : (field < sequence.length ? sequence[field] : '');
    if (!RegExp(r'^[a-zA-Z]$').hasMatch(type)) {
      throw const DictionaryFailure('format');
    }
    final binary = type == type.toUpperCase();
    final last = sequence != null && field == sequence.length - 1;
    int end;
    if (last) {
      end = bytes.length;
    } else if (binary) {
      if (at + 4 > bytes.length) throw const DictionaryFailure('format');
      final length = ByteData.sublistView(bytes).getUint32(at);
      at += 4;
      end = at + length;
    } else {
      end = bytes.indexOf(0, at);
    }
    if (end < at || end > bytes.length) throw const DictionaryFailure('format');
    if (!binary) {
      if (!{'m', 't', 'y', 'h', 'g', 'x', 'k', 'w', 'n', 'r'}.contains(type)) {
        throw const DictionaryFailure('type');
      }
      final text = utf8.decode(bytes.sublist(at, end));
      if (type != 'r') {
        parts.add({'h', 'g', 'x', 'k'}.contains(type)
            ? dictionaryPlainText(text)
            : text);
      }
    }
    at = end + (!last && !binary ? 1 : 0);
    field++;
  }
  if (sequence != null && field != sequence.length) {
    throw const DictionaryFailure('format');
  }
  return parts.join('\n').replaceAll('\u0000', '').trim();
}
