import 'package:modu_reader/models/tts_role_config.dart';
import 'package:modu_reader/service/tts/models/tts_sentence.dart';
import 'package:modu_reader/service/tts/tts_role_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const splitter = TtsRoleSplitter();

  group('TtsRoleSplitter', () {
    test('narration without quotes stays one run', () {
      final runs = splitter.split('夜色渐深，他终于合上了书。');
      expect(runs, hasLength(1));
      expect(runs.single.role, TtsSpeakerRole.narration);
    });

    test('quoted speech becomes a dialogue run between narrations', () {
      final runs = splitter.split('他说：“走吧。”然后起身。');
      expect(runs.map((run) => run.role).toList(), [
        TtsSpeakerRole.narration,
        TtsSpeakerRole.dialogue,
        TtsSpeakerRole.narration,
      ]);
      expect(runs.map((run) => run.text).toList(), [
        '他说：',
        '“走吧。”',
        '然后起身。',
      ]);
    });

    test('corner quotes and nested quotes stay dialogue', () {
      final runs = splitter.split('她低声道「我听见了『别走』。」');
      expect(runs.first.role, TtsSpeakerRole.narration);
      expect(runs.last.role, TtsSpeakerRole.dialogue);
      expect(runs.last.text, '「我听见了『别走』。」');
    });

    test('an unterminated quote reads the rest as dialogue', () {
      final runs = splitter.split('他喊：“等等，别关门');
      expect(runs.first.text, '他喊：');
      expect(runs.last.role, TtsSpeakerRole.dialogue);
      expect(runs.last.text, '“等等，别关门');
    });

    test('adjacent dialogue runs merge into one request', () {
      final runs = splitter.split('“走吧。” “快些。”');
      expect(runs, hasLength(1));
      expect(runs.single.role, TtsSpeakerRole.dialogue);
    });

    test('long runs are bounded near a clause mark', () {
      final sentence = '${'很长的一段话，' * 40}结束。';
      final runs = splitter.split(sentence);
      expect(runs.every((run) => run.text.runes.length <= 240), isTrue);
      expect(runs.every((run) => run.role == TtsSpeakerRole.narration), isTrue);
    });
  });

  group('TtsRolePlan', () {
    TtsRolePlan plan({bool enabled = true, String narration = 'narrator'}) {
      return TtsRolePlan(
        config: TtsRoleConfig(
          enabled: enabled,
          narrationVoice: narration,
          dialogueVoice: 'dialogue',
        ),
        fallbackVoice: 'fallback',
      );
    }

    test('disabled configuration returns the collected sentence untouched', () {
      const sentence = TtsSentence(text: '他说：“走吧。”', cfi: 'cfi-1');
      final runs = TtsRolePlan(
        config: TtsRoleConfig.disabled,
        fallbackVoice: 'fallback',
      ).expand(sentence);
      expect(runs, [same(sentence)]);
    });

    test('identical voices keep one request per passage', () {
      final runs = TtsRolePlan(
        config: const TtsRoleConfig(
            enabled: true, narrationVoice: 'same', dialogueVoice: 'same'),
        fallbackVoice: 'fallback',
      ).expand(const TtsSentence(text: '他说：“走吧。”'));
      expect(runs, hasLength(1));
      expect(runs.single.voice, 'same');
    });

    test('identical voices still split when role speeds differ', () {
      final runs = TtsRolePlan(
        config: const TtsRoleConfig(enabled: true, dialogueRate: 1.2),
        fallbackVoice: 'same',
      ).expand(const TtsSentence(text: '他说：“走吧。”'));
      expect(runs.map((run) => run.role),
          [TtsSpeakerRole.narration, TtsSpeakerRole.dialogue]);
      expect(runs.map((run) => run.voice), ['same', 'same']);
      expect(runs.map((run) => run.advanceCursor), [false, true]);
    });

    test('equal non-default speeds apply even with inherited voices', () {
      final runs = TtsRolePlan(
        config: const TtsRoleConfig(
            enabled: true, narrationRate: 1.2, dialogueRate: 1.2),
        fallbackVoice: 'same',
      ).expand(const TtsSentence(text: '他说：“走吧。”'));
      expect(runs, hasLength(1));
      expect(runs.single.role, TtsSpeakerRole.narration);
    });

    test('following narration uses the configured voice without extra requests',
        () {
      final runs = TtsRolePlan(
        config: const TtsRoleConfig(enabled: true, narrationVoice: 'custom'),
        fallbackVoice: 'default',
      ).expand(const TtsSentence(text: '他说：“走吧。”'));
      expect(runs, hasLength(1));
      expect(runs.single.voice, 'custom');
    });

    test('empty voices fall back to the selected voice and stay unsplit', () {
      final runs = TtsRolePlan(
        config: const TtsRoleConfig(enabled: true),
        fallbackVoice: 'fallback',
      ).expand(const TtsSentence(text: '他说：“走吧。”'));
      expect(runs, hasLength(1));
      expect(runs.single.voice, isNull);
    });

    test('split runs advance the cursor once and pause at the passage end', () {
      final runs = plan().expand(const TtsSentence(
          text: '他说：“走吧。”然后起身。', cfi: 'cfi-9', endsParagraph: true));
      expect(runs, hasLength(3));
      expect(runs.map((run) => run.voice).toList(),
          ['narrator', 'dialogue', 'narrator']);
      expect(
          runs.map((run) => run.advanceCursor).toList(), [false, false, true]);
      expect(
          runs.map((run) => run.endsParagraph).toList(), [false, false, true]);
      expect(runs.every((run) => run.cfi == 'cfi-9'), isTrue);
    });

    test('a passage made only of dialogue keeps one run', () {
      final runs =
          plan().expand(const TtsSentence(text: '“走吧。”', cfi: 'cfi-1'));
      expect(runs, hasLength(1));
      expect(runs.single.voice, 'dialogue');
      expect(runs.single.role, TtsSpeakerRole.dialogue);
      expect(runs.single.advanceCursor, isTrue);
    });
  });
}
