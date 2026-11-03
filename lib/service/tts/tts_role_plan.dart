import 'package:anx_reader/models/tts_role_config.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';

/// One speech run with a single voice: either narration or quoted dialogue.
class TtsRoleRun {
  const TtsRoleRun({required this.text, required this.role});

  final String text;
  final TtsSpeakerRole role;

  @override
  String toString() => 'TtsRoleRun(${role.name}: $text)';
}

/// Splits a collected passage into narration and quoted-dialogue runs.
///
/// Quotes are matched with a stack so nested Chinese quotes stay inside the
/// outer dialogue run. An unterminated quote is treated as dialogue up to the
/// end of the passage: a missing closing mark is far more often a scan/OCR
/// defect than the end of the speech.
class TtsRoleSplitter {
  const TtsRoleSplitter({this.maxCharacters = ttsRoleMaxRunCharacters});

  final int maxCharacters;

  static const _closers = {
    '\u201C': '\u201D', // “ ”
    '\u300C': '\u300D', // 「 」
    '\u300E': '\u300F', // 『 』
    '"': '"',
    '\u2018': '\u2019', // ‘ ’
  };

  static const _clauseMarks = '，,、；;：:。！？!?…—\n';

  List<TtsRoleRun> split(String text) {
    if (text.isEmpty) return const [];
    final runs = <TtsRoleRun>[];
    final buffer = StringBuffer();
    final stack = <String>[];
    var role = TtsSpeakerRole.narration;

    void flush() {
      final value = buffer.toString().trim();
      buffer.clear();
      if (value.isNotEmpty) runs.add(TtsRoleRun(text: value, role: role));
    }

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (stack.isEmpty) {
        final closer = _closers[char];
        if (closer != null) {
          flush();
          role = TtsSpeakerRole.dialogue;
          stack.add(closer);
          buffer.write(char);
        } else {
          buffer.write(char);
        }
        continue;
      }
      buffer.write(char);
      if (char == stack.last) {
        stack.removeLast();
        if (stack.isEmpty) {
          flush();
          role = TtsSpeakerRole.narration;
        }
        continue;
      }
      final nested = _closers[char];
      if (nested != null) stack.add(nested);
    }
    // A dangling open quote keeps the dialogue role on purpose.
    flush();
    return _bounded(_merged(runs));
  }

  /// Adjacent runs of the same speaker would be two requests for one voice.
  List<TtsRoleRun> _merged(List<TtsRoleRun> runs) {
    final merged = <TtsRoleRun>[];
    for (final run in runs) {
      if (merged.isNotEmpty &&
          merged.last.role == run.role &&
          merged.last.text.runes.length + run.text.runes.length <=
              maxCharacters) {
        merged[merged.length - 1] = TtsRoleRun(
          text: '${merged.last.text}${run.text}',
          role: run.role,
        );
      } else {
        merged.add(run);
      }
    }
    return merged;
  }

  /// Keeps every request within the provider limit, preferring clause marks.
  List<TtsRoleRun> _bounded(List<TtsRoleRun> runs) {
    final bounded = <TtsRoleRun>[];
    for (final run in runs) {
      var rest = run.text;
      while (rest.runes.length > maxCharacters) {
        final runes = rest.runes.toList(growable: false);
        var cut = maxCharacters;
        for (var index = maxCharacters - 1;
            index >= maxCharacters ~/ 2;
            index--) {
          if (_clauseMarks.contains(String.fromCharCode(runes[index]))) {
            cut = index + 1;
            break;
          }
        }
        bounded.add(TtsRoleRun(
          text: String.fromCharCodes(runes.take(cut)).trim(),
          role: run.role,
        ));
        rest = String.fromCharCodes(runes.skip(cut));
      }
      final tail = rest.trim();
      if (tail.isNotEmpty) bounded.add(TtsRoleRun(text: tail, role: run.role));
    }
    return bounded.where((run) => run.text.isNotEmpty).toList(growable: false);
  }
}

/// Turns collected passages into per-voice [TtsSentence] runs.
///
/// Only the last run of a passage advances the reader cursor, so splitting a
/// paragraph never skips text or double-counts a paragraph pause.
class TtsRolePlan {
  TtsRolePlan({
    required this.config,
    required this.fallbackVoice,
    TtsRoleSplitter splitter = const TtsRoleSplitter(),
  }) : _splitter = splitter;

  final TtsRoleConfig config;

  /// Voice used when the configuration leaves a role empty.
  final String fallbackVoice;
  final TtsRoleSplitter _splitter;

  bool get active => config.enabled && narrationVoice != dialogueVoice;

  String get narrationVoice => config.narrationVoiceFor(fallbackVoice);
  String get dialogueVoice => config.dialogueVoiceFor(fallbackVoice);

  /// Returns one or more sentences. The input itself is returned untouched when
  /// splitting cannot change the voice.
  List<TtsSentence> expand(TtsSentence sentence) {
    if (!config.enabled) return [sentence];
    if (!active) {
      if (narrationVoice.isEmpty || narrationVoice == fallbackVoice) {
        return [sentence];
      }
      return [
        TtsSentence(
            text: sentence.text,
            cfi: sentence.cfi,
            endsParagraph: sentence.endsParagraph,
            voice: narrationVoice,
            role: TtsSpeakerRole.narration,
            advanceCursor: sentence.advanceCursor)
      ];
    }
    final runs = _splitter.split(sentence.text);
    if (runs.length <= 1) {
      final only = runs.isEmpty ? null : runs.first;
      if (only == null) return [sentence];
      // Single-role passage: keep one request, only pin the voice.
      return [
        TtsSentence(
          text: sentence.text,
          cfi: sentence.cfi,
          endsParagraph: sentence.endsParagraph,
          voice: only.role == TtsSpeakerRole.dialogue
              ? dialogueVoice
              : narrationVoice,
          role: only.role,
        ),
      ];
    }
    final expanded = <TtsSentence>[];
    for (var index = 0; index < runs.length; index++) {
      final run = runs[index];
      final last = index == runs.length - 1;
      expanded.add(TtsSentence(
        text: run.text,
        cfi: sentence.cfi,
        // One paragraph pause per source passage, at its end.
        endsParagraph: last && sentence.endsParagraph,
        voice: run.role == TtsSpeakerRole.dialogue
            ? dialogueVoice
            : narrationVoice,
        role: run.role,
        advanceCursor: last,
      ));
    }
    return expanded;
  }
}
