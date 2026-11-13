import 'package:modu_reader/enums/sync_direction.dart';
import 'package:modu_reader/enums/sync_trigger.dart';
import 'package:modu_reader/models/sync_state_model.dart';
import 'package:modu_reader/providers/sync.dart';
import 'package:modu_reader/widgets/bookshelf/sync_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sync extends Notifier<SyncStateModel> implements Sync {
  final calls = <(SyncDirection, SyncTrigger, WidgetRef?)>[];

  @override
  SyncStateModel build() => const SyncStateModel(
      direction: SyncDirection.both,
      isSyncing: false,
      total: 0,
      count: 0,
      fileName: '');

  void syncing(bool value) => state = state.copyWith(isSyncing: value);

  @override
  Future<void> syncData(SyncDirection direction, WidgetRef? widgetRef,
      {SyncTrigger trigger = SyncTrigger.auto,
      bool Function()? shouldStart,
      bool immediate = false,
      Future<void>? savedReading}) async {
    calls.add((direction, trigger, widgetRef));
    syncing(true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final disableAnimations in [false, true]) {
    testWidgets('tap syncs directly, reduced motion=$disableAnimations',
        (tester) async {
      final sync = _Sync();
      await tester.pumpWidget(ProviderScope(
        overrides: [syncProvider.overrideWith(() => sync)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: disableAnimations),
              child: child!),
          home: const Scaffold(body: SyncButton()),
        ),
      ));
      expect(sync.calls, isEmpty);
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(sync.calls, hasLength(1));
      expect(sync.calls.single.$1, SyncDirection.both);
      expect(sync.calls.single.$2, SyncTrigger.manual);
      expect(sync.calls.single.$3, isNotNull);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(
          tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
      expect(
          find.descendant(
              of: find.byType(SyncButton),
              matching: find.byType(RotationTransition)),
          disableAnimations ? findsNothing : findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(sync.calls, hasLength(1));

      sync.syncing(false);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed,
          isNotNull);
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(sync.calls, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
