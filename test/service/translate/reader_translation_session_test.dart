import 'dart:async';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/service/translate/reader_translation_session.dart';
import 'package:anx_reader/service/translate/translation_answer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anx_reader/service/translate/microsoft_free.dart';
import 'package:anx_reader/enums/lang_list.dart';

void main() {
  test('cancelled free translation does not process subsequent text chunks',
      () async {
    final cancelled = Completer<void>()..complete();
    final results = await MicrosoftFreeTranslateProvider()
        .translateStream(List.filled(10000, 'text').join(' '),
            LangListEnum.auto, LangListEnum.english,
            whenCancelled: cancelled.future)
        .toList();
    expect(results.where((value) => value != '...'), isEmpty);
  });
  test('translation drops reasoning, including nested/case/prefill variants',
      () {
    expect(translationAnswer('<think>secret</think>译文'), '译文');
    expect(translationAnswer('<THINK>secret</THINK>注意'), '注意');
    expect(
        translationAnswer('<think>one<think>two</think>three</think>答'), '答');
    expect(translationAnswer('reasoning prefill</think>答'), '答');
    expect(translationAnswer('<think>unfinished reasoning'), '');
    expect(translationAnswer('译文 <thi'), '译文');
    expect(translationAnswer('Plain answer'), 'Plain answer');
    expect(translationAnswer('前<think>secret</think>后'), '前后');
  });

  test('streaming prefixes never expose reasoning', () {
    const text = '<think>private reasoning</think>最终译文';
    for (var end = 0; end <= text.length; end++) {
      final answer = translationAnswer(text.substring(0, end));
      expect(answer, isNot(contains('private')));
      expect(answer, isNot(contains('<')));
    }
  });

  test('a new reader never resumes requests without explicit start', () async {
    final session = ReaderTranslationSession();
    var started = false;
    await expectLater(
        session.translate(0, (_) {
          started = true;
          return Stream.value('answer');
        }),
        throwsA(isA<TranslationCancelled>()));
    expect(started, isFalse);
  });

  test('stop cancels runner and pending stream, not waiting for a server reply',
      () async {
    final session = ReaderTranslationSession();
    final id = session.start();
    late CancelableLangchainRunner runner;
    var cancelled = false;
    final stream = StreamController<String>(onCancel: () {
      cancelled = true;
    });
    final result = session.translate(id, (r) {
      runner = r;
      return stream.stream;
    });
    final assertion = expectLater(result, throwsA(isA<TranslationCancelled>()));
    stream.add('partial');
    session.stop();
    await assertion;
    expect(runner.isCancelled, isTrue);
    expect(cancelled, isTrue);
    stream.add('late answer');
    await stream.close();
    expect(session.enabled, isFalse);
  });

  test('restart rejects stale bridge jobs and accepts only the new session',
      () async {
    final session = ReaderTranslationSession();
    final old = session.start();
    final current = session.start();
    await expectLater(session.translate(old, (_) => Stream.value('old')),
        throwsA(isA<TranslationCancelled>()));
    expect(
        await session.translate(
            current, (_) => Stream.fromIterable(['', '译文'])),
        '译文');
    session.stop();
  });

  test(
      'empty reasoning-only response is a failure, never cached as translation',
      () async {
    final session = ReaderTranslationSession();
    final id = session.start();
    await expectLater(session.translate(id, (_) => Stream.value('')),
        throwsA(isA<StateError>()));
    session.stop();
  });
}
