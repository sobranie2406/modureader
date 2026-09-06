import 'dart:io';
import 'package:anx_reader/service/feedback/crash_journal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() async {
    CrashJournal.resetForTesting();
    root = await Directory.systemTemp.createTemp('modu-crash-journal-');
    await CrashJournal.initialize(directory: root);
  });
  tearDown(() async {
    CrashJournal.resetForTesting();
    await root.delete(recursive: true);
  });
  test('error message and absolute paths never reach disk or preview', () {
    CrashJournal.recordError(
        StateError('sk-SECRET private book'),
        StackTrace.fromString(
            '#0 Reader.open (package:anx_reader/page/reader.dart:10:2)\n'
            '#1 open (/Users/private/SECRET.dart:12)'));
    final stored = File('${root.path}/session.json').readAsStringSync();
    expect(stored, contains('reader.dart:10:2'));
    expect(stored, isNot(contains('SECRET')));
    expect(CrashJournal.preview(), isNot(contains('/Users')));
  });
  test(
      'records survive restart and unexpected exit is not falsely called a crash',
      () async {
    CrashJournal.indexState(3, 16, 200, 3);
    CrashJournal.resetForTesting();
    await CrashJournal.initialize(directory: root);
    expect(CrashJournal.preview(), contains('previous_session_unconfirmed'));
    expect(CrashJournal.preview(), contains('done=16'));
    expect(CrashJournal.preview(), contains('not proof of a crash'));
  });
  test('clean close is not reported as unexpected on restart', () async {
    CrashJournal.closeSession();
    CrashJournal.resetForTesting();
    await CrashJournal.initialize(directory: root);
    expect(CrashJournal.preview(),
        isNot(contains('previous_session_unconfirmed')));
  });
  test('journal is bounded and does not grow with indexing length', () {
    for (var i = 0; i < 100; i++) {
      CrashJournal.indexState(3, i, 100, 3);
    }
    expect(File('${root.path}/session.json').lengthSync(), lessThan(32768));
    expect(CrashJournal.preview(), isNot(contains('done=0 ')));
    expect(CrashJournal.preview(), contains('done=99 '));
  });
}
