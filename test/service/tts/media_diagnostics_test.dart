import 'dart:convert';
import 'package:modu_reader/service/tts/base_tts.dart';
import 'package:modu_reader/service/tts/tts_media_state.dart';
import 'package:modu_reader/service/tts/media_diagnostics.dart';
import 'package:modu_reader/service/tts/media_diagnostic_fields.dart';
import 'package:modu_reader/service/feedback/detailed_runtime_log.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  test('ordinary builds leave diagnostic collection disabled', () {
    expect(MediaDiagnostics.enabled, isFalse);
  });
  test('desired state captures switching controls and stable capabilities', () {
    for (final state in TtsStateEnum.values) {
      final playback = ttsMediaState(PlaybackState(), state);
      final fields = MediaDiagnostics.describeState(playback);
      expect(safeMediaDiagnosticFields(fields), fields);
      expect(fields['playing'], state == TtsStateEnum.playing);
      if (state == TtsStateEnum.playing) {
        expect(fields['controls'], contains(MediaAction.pause.index));
      } else if (state == TtsStateEnum.paused) {
        expect(fields['controls'], contains(MediaAction.play.index));
      } else if (state == TtsStateEnum.stopped) {
        expect(fields['controls'], isEmpty);
      }
    }
  });
  test('native state and notification fields survive export without secrets',
      () {
    final input = {
      'source': 'android',
      'event': 'snapshot',
      'sdk': 35,
      'state': 3,
      'actions': 518,
      'canPause': true,
      'notificationPresent': true,
      'tokenPresent': true,
      'importance': 2,
      'notificationActions': 4,
      'compatActive': true,
      'stopCompatActive': true,
      'notificationPlayRequests': 2,
      'sessionPlayCallbacks': 3,
      'actionIconPresent': [true, true],
      'actionIconTypes': [2, 2],
      'actionIconResources': [213123, 213124],
      'actionIntents': [true, true],
      'compact': [0, 1, 2],
      'titlePresent': true,
      'title': 'SECRET BOOK',
      'token': 'SECRET TOKEN',
      'extras': {'password': 'SECRET'},
      'error': 'SECRET URL',
    };
    final safe = safeMediaDiagnosticFields(input);
    expect(safe['actions'], 518);
    expect(safe['canPause'], true);
    expect(safe['compact'], [0, 1, 2]);
    expect(safe['compatActive'], true);
    expect(safe['stopCompatActive'], true);
    expect(safe['notificationPlayRequests'], 2);
    expect(safe['sessionPlayCallbacks'], 3);
    expect(safe['actionIconPresent'], [true, true]);
    expect(safe['actionIconResources'], [213123, 213124]);
    expect(jsonEncode(safe), isNot(contains('SECRET')));
    DetailedRuntimeLog.clear();
    DetailedRuntimeLog.record(LogRecord(
        Level.INFO, 'TTS media diagnostic: ${jsonEncode(input)}', 'test'));
    final exported = DetailedRuntimeLog.preview();
    expect(exported, contains('"mediaDiagnostic"'));
    expect(exported, contains('"canPause":true'));
    expect(exported, contains('"stopCompatActive":true'));
    expect(exported, contains('"notificationPlayRequests":2'));
    expect(exported, contains('"sessionPlayCallbacks":3'));
    expect(exported, isNot(contains('SECRET')));
  });
  test('invalid fields and unbounded input are not forwarded', () {
    expect(safeMediaDiagnosticFields('private'), isEmpty);
    final fields = safeMediaDiagnosticFields({
      'source': 'SECRET',
      'event': 'SECRET',
      'sdk': 'SECRET',
      'playing': 1,
      'stopCompatActive': 'SECRET',
      'actions': double.nan,
      'controls': List.generate(100, (i) => i),
      'compact': [-1, 'SECRET', 1],
      'actionIntents': [false, 'SECRET'],
    });
    expect(
        fields.keys, unorderedEquals(['controls', 'compact', 'actionIntents']));
    expect((fields['controls'] as List).length, 32);
    expect(fields['compact'], [1]);
    expect(fields['actionIntents'], [false]);
    final malformed = DetailedRuntimeLog.format(LogRecord(
        Level.INFO, 'TTS media diagnostic: SECRET invalid JSON', 'test'));
    expect(malformed, isNot(contains('SECRET')));
  });
}
