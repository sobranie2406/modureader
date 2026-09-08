import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_reasoning_effort.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ai_provider_detail_page.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final isNew in [true, false]) {
    testWidgets('${isNew ? 'new' : 'existing'} model can save and reopen Off',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final initial = container.read(aiProvidersProvider).first;
      var providerId = isNew ? null : initial.id;
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          home: Builder(
              builder: (context) => Scaffold(
                      body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                AiProviderDetailPage(providerId: providerId))),
                    child: const Text('Open model'),
                  ))),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open model'));
      await tester.pumpAndSettle();
      if (isNew) {
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Reasoning test');
        await tester.enterText(fields.at(1), 'https://example.test/v1');
        await tester.enterText(fields.at(2), 'gpt-5.1');
      }
      final dropdown = find.byType(DropdownButtonFormField<AiReasoningEffort>);
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭推理').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = container.read(aiProvidersProvider).firstWhere(
          (p) => isNew ? p.title == 'Reasoning test' : p.id == initial.id);
      expect(saved.reasoningEffort, AiReasoningEffort.none);
      providerId = saved.id;
      await tester.tap(find.text('Open model'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      final state = tester.state<FormFieldState<AiReasoningEffort>>(dropdown);
      expect(state.value, AiReasoningEffort.none);
      expect(tester.takeException(), isNull);
    });
  }
}
