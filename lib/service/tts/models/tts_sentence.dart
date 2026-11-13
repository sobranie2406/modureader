import 'package:modu_reader/models/tts_role_config.dart';

class TtsSentence {
  const TtsSentence({
    required this.text,
    this.cfi,
    this.endsParagraph = true,
    this.voice,
    this.role,
    this.advanceCursor = true,
  });

  final String text;
  final String? cfi;
  final bool endsParagraph;

  /// Voice short name chosen for this run. Null keeps the service default.
  final String? voice;

  /// Narration or quoted dialogue; null for passages the splitter never saw.
  final TtsSpeakerRole? role;

  /// False for runs that continue the same source passage. Only the last run of
  /// a passage may advance the reader cursor.
  final bool advanceCursor;

  factory TtsSentence.fromMap(Map<dynamic, dynamic> data) {
    final text = data['text'];
    final cfi = data['cfi'];
    if (text is! String) {
      throw const FormatException('Missing TTS sentence text');
    }
    final voice = data['voice'];
    final role = data['role'];
    final advance = data['advanceCursor'];
    return TtsSentence(
      text: text,
      cfi: cfi is String && cfi.isNotEmpty ? cfi : null,
      endsParagraph:
          data['endsParagraph'] is bool ? data['endsParagraph'] as bool : true,
      voice: voice is String && voice.isNotEmpty ? voice : null,
      role: _roleFromName(role),
      advanceCursor: advance is bool ? advance : true,
    );
  }

  static TtsSpeakerRole? _roleFromName(Object? value) {
    if (value is! String) return null;
    for (final role in TtsSpeakerRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
        'text': text,
        if (cfi != null) 'cfi': cfi,
        'endsParagraph': endsParagraph,
        if (voice != null && voice!.isNotEmpty) 'voice': voice,
        if (role != null) 'role': role!.name,
        if (!advanceCursor) 'advanceCursor': false,
      };

  @override
  String toString() => 'TtsSentence(text: $text, cfi: $cfi, voice: $voice)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TtsSentence &&
        other.text == text &&
        other.cfi == cfi &&
        other.endsParagraph == endsParagraph &&
        other.voice == voice &&
        other.role == role &&
        other.advanceCursor == advanceCursor;
  }

  @override
  int get hashCode =>
      Object.hash(text, cfi, endsParagraph, voice, role, advanceCursor);
}
