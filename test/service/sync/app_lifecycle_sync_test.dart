import 'dart:async';

import 'package:anx_reader/service/sync/app_lifecycle_sync.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only real background cycles synchronize once in each direction', () {
    final calls = <bool>[];
    var pauses = 0;
    final sync = AppLifecycleSync(
      synchronize: (background) async => calls.add(background),
      pauseAutomatic: () => pauses++,
    );

    for (final state in [
      AppLifecycleState.resumed,
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      sync.update(state);
    }
    expect(calls, isEmpty);
    expect(pauses, 1);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
      AppLifecycleState.resumed,
    ]) {
      sync.update(state);
    }
    expect(calls, [true, false]);
    expect(pauses, 3);

    sync.update(AppLifecycleState.paused);
    sync.update(AppLifecycleState.hidden);
    sync.update(AppLifecycleState.resumed);
    expect(calls, [true, false, true, false]);
    expect(pauses, 4);
  });

  test('return callback starts while the background request is still pending',
      () async {
    final pending = Completer<void>();
    final calls = <bool>[];
    var pauses = 0;
    final sync = AppLifecycleSync(
      synchronize: (background) {
        expect(pauses, 1);
        calls.add(background);
        return background ? pending.future : Future<void>.value();
      },
      pauseAutomatic: () => pauses++,
    );

    sync.update(AppLifecycleState.resumed);
    sync.update(AppLifecycleState.hidden);
    sync.update(AppLifecycleState.paused);
    sync.update(AppLifecycleState.inactive);
    sync.update(AppLifecycleState.resumed);
    expect(calls, [true, false]);
    expect(pauses, 1);
    expect(pending.isCompleted, isFalse);
    pending.complete();
    await pending.future;
  });

  test('detached pauses once and does not synchronize on its own', () {
    final calls = <bool>[];
    var pauses = 0;
    final sync = AppLifecycleSync(
      synchronize: (background) async => calls.add(background),
      pauseAutomatic: () => pauses++,
    );

    sync.update(AppLifecycleState.hidden);
    sync.update(AppLifecycleState.detached);
    sync.update(AppLifecycleState.detached);
    sync.update(AppLifecycleState.resumed);
    expect(calls, [true]);
    expect(pauses, 2);
  });

  test('synchronous and asynchronous failures reach the error callback',
      () async {
    final errors = <Object>[];
    final first = StateError('background');
    final second = StateError('return');
    final completed = Completer<void>();
    final sync = AppLifecycleSync(
      synchronize: (background) {
        if (background) throw first;
        return Future<void>.error(second);
      },
      pauseAutomatic: () {},
      onError: (error, stack) {
        errors.add(error);
        expect(stack.toString(), isNotEmpty);
        if (errors.length == 2) completed.complete();
      },
    );

    sync.update(AppLifecycleState.hidden);
    sync.update(AppLifecycleState.resumed);
    await completed.future;
    expect(errors, [same(first), same(second)]);
  });
}
