import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:path/path.dart' as p;

// Host lifecycle fixtures are intentionally not production-approved packages.
// Production trust enforcement is tested separately, including the real sample.
class FixturePluginTrust extends PluginTrust {
  FixturePluginTrust();

  @override
  Future<void> verify(Directory directory, String id, String version) async {}
}

/// Builds a deterministic plugin zip in memory. Entries are sorted and the
/// timestamp is fixed so tests never depend on file system clocks.
Uint8List buildPluginZip(Map<String, String> files,
    {int level = Deflate.BEST_SPEED}) {
  final archive = Archive();
  final names = files.keys.toList()..sort();
  for (final name in names) {
    final bytes = utf8.encode(files[name]!);
    final entry = ArchiveFile(name, bytes.length, bytes)
      ..lastModTime = DateTime.utc(2020, 1, 1).millisecondsSinceEpoch ~/ 1000;
    archive.addFile(entry);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive, level: level)!);
}

Future<File> writePluginZip(
  Directory directory,
  Map<String, String> files, {
  String? name,
  int level = Deflate.BEST_SPEED,
}) async {
  // Windows temp storage can briefly serve stale bytes for a path that was
  // just overwritten, so every write gets its own file unless a name is given.
  final fileName = name ??
      'plugin-${DateTime.now().microsecondsSinceEpoch}-${_counter++}.moduplugin';
  final file = File(p.join(directory.path, fileName));
  await file.writeAsBytes(buildPluginZip(files, level: level), flush: true);
  return file;
}

int _counter = 0;

String manifestJson({
  String id = 'com.example.prompt-pack',
  String version = '1.0.0',
  Object? name = const {'zh-CN': '示例提示词包', 'en': 'Example prompt pack'},
  Object? description = const {
    'zh-CN': '两个 AI 提示词模板。',
    'en': 'Two AI prompt templates.'
  },
  String license = 'CC0-1.0',
  List<String> capabilities = const ['ai:prompt-pack'],
  List<Map<String, Object?>>? contributes,
  String? minAppVersion,
  Object? settings,
  int schemaVersion = 1,
  int hostApi = 1,
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': schemaVersion,
    'id': id,
    'version': version,
    'name': name,
    'description': description,
    'author': {'name': 'Example', 'url': 'https://example.com'},
    'license': license,
    if (minAppVersion != null) 'minAppVersion': minAppVersion,
    'capabilities': capabilities,
    'contributes': contributes ??
        [
          aiSkill(id: 'deep-summary'),
          aiSkill(id: 'socratic-questions'),
        ],
    if (settings != null) 'settings': settings,
    'hostApi': hostApi,
  });
}

Map<String, Object?> aiSkill({
  String id = 'deep-summary',
  Object? name,
  String prompt = '阅读当前内容，按“核心结论 / 论证链 / 证据 / 隐含假设”输出。',
  bool enabled = true,
}) {
  return {
    'kind': 'aiSkill',
    'schema': 1,
    'id': id,
    'name': name ??
        {
          'zh-CN': id,
          'en': id,
        },
    'prompt': prompt,
    'enabled': enabled,
  };
}

Map<String, Object?> selectionAction({
  String id = 'explain-selection',
  Object? name,
  String icon = 'lightbulb',
  String prompt = '解释 {selection} 的含义，简明直接，不编造。',
  String scope = 'context',
  bool enabled = true,
}) {
  return {
    'kind': 'selectionAction',
    'schema': 1,
    'id': id,
    'name': name ??
        {
          'zh-CN': id,
          'en': id,
        },
    'icon': icon,
    'prompt': prompt,
    'scope': scope,
    'enabled': enabled,
  };
}

Map<String, String> samplePackageFiles({String? manifest}) => {
      'manifest.json': manifest ?? manifestJson(),
      'README.md': '# Example prompt pack\n',
      'LICENSE': 'CC0 1.0 Universal\n',
    };
