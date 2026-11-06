import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';

const bundledFontFilename = 'SourceHanSerifSC-Regular.otf';
final _removedFonts = StreamController<String>.broadcast(sync: true);
Stream<String> get removedFonts => _removedFonts.stream;

bool isLocalFontFilename(String name) =>
    !name.contains('/') &&
    !name.contains('\\') &&
    !name.contains('\x00') &&
    RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(name);

List<File> installedFontFiles(Directory directory) {
  if (!directory.existsSync()) return [];
  return directory.listSync(followLinks: false).whereType<File>().where((file) {
    return isLocalFontFilename(file.uri.pathSegments.last);
  }).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Remove only an app-owned regular font file. Persist fallbacks before deleting
/// it, restoring preferences if either persistence or deletion fails.
Future<Set<String>> removeInstalledFont(String filename,
    {required Directory directory}) async {
  if (!isLocalFontFilename(filename) ||
      filename.toLowerCase() == bundledFontFilename.toLowerCase()) {
    throw ArgumentError('This font cannot be removed');
  }
  final file = File('${directory.path}/$filename');
  if (await FileSystemEntity.type(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FileSystemException('Font file unavailable');
  }
  final prefs = Prefs().prefs;
  final previous = <String, String>{};
  final updates = <String, String?>{};
  for (final key in [
    'font',
    'englishFont',
    'excerptShareFont',
    'languageTranslationTextStyle',
    'classicalTranslationTextStyle',
    'documentTextStyles',
    'readingInfo',
  ]) {
    final raw = prefs.getString(key);
    if (raw == null) continue;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) continue;
    if (key == 'documentTextStyles' || key == 'readingInfo') {
      var changed = false;
      for (final style in decoded.values.whereType<Map>()) {
        if (style['font'] == filename) {
          style['font'] = '';
          changed = true;
        }
      }
      if (changed) updates[key] = jsonEncode(decoded);
    } else if (key.endsWith('TranslationTextStyle')) {
      if (decoded['font'] == filename) {
        updates[key] = jsonEncode({...decoded, 'font': ''});
      }
    } else {
      final path = decoded['path'];
      final leaf = path is String && path.startsWith(RegExp(r'https?://'))
          ? Uri.parse(path).pathSegments.lastOrNull
          : path;
      if (leaf == filename) updates[key] = null;
    }
    if (updates.containsKey(key)) previous[key] = raw;
  }
  try {
    for (final entry in updates.entries) {
      final saved = entry.value == null
          ? await prefs.remove(entry.key)
          : await prefs.setString(entry.key, entry.value!);
      if (!saved) throw StateError('Could not save font fallback');
    }
    await file.delete();
  } catch (_) {
    for (final entry in previous.entries) {
      await prefs.setString(entry.key, entry.value);
    }
    rethrow;
  }
  _removedFonts.add(filename);
  Prefs().notifyExternalChange();
  return updates.keys.toSet();
}
