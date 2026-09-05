import 'package:anx_reader/service/ai/reading_skill_execution.dart';
import 'package:langchain_core/chat_models.dart';

/// The actual source and tool policy sent for the last reader request.
/// No provider credentials are stored here.
class ReadingRequestSnapshot {
  const ReadingRequestSnapshot(
      {required this.request, this.skillId, this.bookId, this.chapterHref});

  final ReadingSkillRequest request;
  final String? skillId;
  final int? bookId;
  final String? chapterHref;

  ReadingSkillRequest replay({int? currentBookId, String? currentChapterHref}) {
    // Skills already contain bounded source text and only safe drawing tools.
    // Generic agents can access the live reader, so require the original context.
    if (skillId == null &&
        (bookId != currentBookId || chapterHref != currentChapterHref)) {
      throw StateError('这条对话使用了原书籍的阅读工具，请回到原书原章节后重试，或新建对话。');
    }
    return request;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'skillId': skillId,
        'bookId': bookId,
        'chapterHref': chapterHref,
        'messages': request.messages.map((m) => m.toMap()).toList(),
        'useAgent': request.useAgent,
        'allowedToolIds': request.allowedToolIds?.toList(),
      };

  factory ReadingRequestSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1)
      throw const FormatException('Unknown reading snapshot');
    final messages = (json['messages'] as List)
        .map((m) => ChatMessage.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList(growable: false);
    if (messages.isEmpty || messages.last is! HumanChatMessage) {
      throw const FormatException('Missing original reading request');
    }
    return ReadingRequestSnapshot(
      skillId: json['skillId'] as String?,
      bookId: json['bookId'] as int?,
      chapterHref: json['chapterHref'] as String?,
      request: ReadingSkillRequest(
          messages: messages,
          useAgent: json['useAgent'] == true,
          allowedToolIds:
              (json['allowedToolIds'] as List?)?.cast<String>().toSet()),
    );
  }
}
