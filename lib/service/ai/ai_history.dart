import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_request_snapshot.dart';
import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:path/path.dart' as p;
import 'package:langchain_core/chat_models.dart';

class AiChatHistoryEntry {
  static const Object _unchanged = Object();

  const AiChatHistoryEntry({
    required this.id,
    required this.scope,
    required this.serviceId,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    required this.completed,
    this.homePromptId,
    this.readingRequest,
  });

  final String id;
  final String scope;
  final String serviceId;
  final String model;
  final int createdAt;
  final int updatedAt;
  final List<ChatMessage> messages;
  final bool completed;
  final String? homePromptId;
  final ReadingRequestSnapshot? readingRequest;

  AiChatHistoryEntry copyWith({
    List<ChatMessage>? messages,
    int? updatedAt,
    bool? completed,
    String? scope,
    String? serviceId,
    String? model,
    Object? homePromptId = _unchanged,
    Object? readingRequest = _unchanged,
  }) {
    return AiChatHistoryEntry(
      id: id,
      scope: scope ?? this.scope,
      serviceId: serviceId ?? this.serviceId,
      model: model ?? this.model,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
      completed: completed ?? this.completed,
      homePromptId: identical(homePromptId, _unchanged)
          ? this.homePromptId
          : homePromptId as String?,
      readingRequest: identical(readingRequest, _unchanged)
          ? this.readingRequest
          : readingRequest as ReadingRequestSnapshot?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scope': scope,
      'serviceId': serviceId,
      'model': model,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'completed': completed,
      'messages': messages.map((m) => m.toMap()).toList(growable: false),
      if (homePromptId != null) 'homePromptId': homePromptId,
      if (readingRequest != null) 'readingRequest': readingRequest!.toJson(),
    };
  }

  factory AiChatHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    final messages = <ChatMessage>[];
    if (rawMessages is List) {
      for (final item in rawMessages) {
        if (item is Map<String, dynamic>) {
          messages.add(ChatMessage.fromMap(item));
        } else if (item is Map) {
          messages.add(ChatMessage.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ));
        }
      }
    }

    ReadingRequestSnapshot? readingRequest;
    try {
      if (json['readingRequest'] is Map) {
        readingRequest = ReadingRequestSnapshot.fromJson(
            Map<String, dynamic>.from(json['readingRequest']));
      }
    } catch (_) {
      // Keep readable conversation text, but disallow unsafe legacy replay.
    }
    return AiChatHistoryEntry(
      id: json['id']?.toString() ?? '',
      scope: json['scope']?.toString() ?? _inferLegacyScope(messages),
      serviceId: json['serviceId']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] is int
          ? json['updatedAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      completed: json['completed'] == true,
      messages: messages,
      homePromptId: json['homePromptId']?.toString(),
      readingRequest: readingRequest,
    );
  }
}

String _inferLegacyScope(List<ChatMessage> messages) {
  String firstHumanPrompt = '';
  for (final message in messages) {
    if (message is HumanChatMessage) {
      firstHumanPrompt = message.contentAsString.trim();
      if (firstHumanPrompt.isNotEmpty) break;
    }
  }
  if (firstHumanPrompt.isEmpty) return 'library';

  final matchesCurrentSkill = readAnySkills.any(
    (skill) => skill.defaultPrompt.trim() == firstHumanPrompt,
  );
  if (matchesCurrentSkill) return 'reader';

  // Prompts written by the reader panel before scoped history was added.
  const legacyReaderMarkers = <String>[
    '当前章节',
    '当前阅读内容',
    '当前内容涉及的人物',
    '当前内容中的生词',
    '当前内容中的论证',
    '当前选中的原文',
  ];
  if (legacyReaderMarkers.any(firstHumanPrompt.contains)) return 'reader';

  return 'library';
}

class AiHistoryStore {
  static const String historyFileName = 'ai_history.json';
  static Future<void> _pendingWrite = Future<void>.value();

  // Every read-modify-write operation shares this queue, including deletion.
  static Future<T> _mutate<T>(Future<T> Function(File) action) {
    final operation =
        _pendingWrite.then((_) async => action(await _resolveFile()));
    _pendingWrite =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  static Future<List<AiChatHistoryEntry>> readHistory() => _mutate(_read);

  static Future<List<AiChatHistoryEntry>> _read(File file,
      {bool backupCorrupt = false}) async {
    if (!await file.exists()) {
      return <AiChatHistoryEntry>[];
    }
    final history = <AiChatHistoryEntry>[];
    var damaged = false;
    // I/O failures propagate: an unreadable file must never be overwritten.
    final content = await file.readAsString();
    try {
      final decoded = json.decode(content);
      if (decoded is! List) {
        throw const FormatException('Expected history list');
      }
      for (final raw in decoded) {
        try {
          final entry = AiChatHistoryEntry.fromJson(
              Map<String, dynamic>.from(raw as Map));
          if (entry.id.isEmpty) {
            throw const FormatException('Missing history id');
          }
          history.add(entry);
        } catch (_) {
          damaged = true;
        }
      }
    } catch (_) {
      damaged = true;
    }
    if (damaged && backupCorrupt) {
      // Preserve exact bytes before repairing on the next explicit mutation.
      await file.copy(
          '${file.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}');
    }
    return history;
  }

  static Future<void> _write(
      File file, List<AiChatHistoryEntry> entries) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
        json.encode(entries.map((e) => e.toJson()).toList()),
        flush: true);
    await temporary.rename(file.path);
  }

  static Future<void> upsertEntry(AiChatHistoryEntry entry) =>
      _mutate((file) async {
        final history = await _read(file, backupCorrupt: true);
        final existingIndex =
            history.indexWhere((element) => element.id == entry.id);

        if (existingIndex >= 0) {
          history[existingIndex] = entry;
        } else {
          history.add(entry);
        }

        history.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        await _write(file, history);
      });

  static Future<void> removeEntry(String id) => _mutate((file) async {
        final history = await _read(file, backupCorrupt: true);
        final filtered = history
            .where((element) => element.id != id)
            .toList(growable: false);
        await _write(file, filtered);
      });

  // Keep an empty destination so a legacy copy cannot resurrect cleared chats.
  static Future<void> clear() => _mutate((file) => _write(file, []));

  static Future<void> migrateLegacyHistory() => _mutate((_) async {});

  static Future<void> clearScope(String scope) => _mutate((file) async {
        if (!await file.exists()) return;

        final history = await _read(file, backupCorrupt: true);
        final remaining = history
            .where((entry) => entry.scope != scope)
            .toList(growable: false);
        await _write(file, remaining);
      });

  static Future<File> _resolveFile() async {
    final cacheDir = await getAnxCacheDir();
    final root =
        documentPath.isEmpty ? await getAnxDocumentsPath() : documentPath;
    final directory = Directory(p.join(root, 'ai'));
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, historyFileName));
    if (await cacheDir.exists()) {
      // Preserve the original bytes, including previously recovered corrupt files.
      await for (final entity in cacheDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name != historyFileName &&
            !name.startsWith('$historyFileName.corrupt-')) {
          continue;
        }
        final target = File(p.join(directory.path, name));
        if (await target.exists()) continue;
        final temporary = File(
            '${target.path}.migrate-${DateTime.now().microsecondsSinceEpoch}');
        await temporary.writeAsBytes(await entity.readAsBytes(), flush: true);
        if (await target.exists()) {
          await temporary.delete();
        } else {
          await temporary.rename(target.path);
        }
      }
    }
    return destination;
  }
}
