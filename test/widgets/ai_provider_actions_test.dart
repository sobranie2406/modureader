import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_reasoning_effort.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/page/settings_page/ai_provider_detail_page.dart';
import 'package:anx_reader/page/settings_page/ai_provider_list_page.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const custom = AiProvider(
    id: 'custom',
    title: 'Custom test',
    url: 'https://example.com/v1/chat/completions',
    model: 'test-model',
    protocol: AiProtocol.openai,
    apiKeys: [AiApiKey(id: 'test-key', key: 'fixture-not-a-real-key')]);

Widget app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              ...GlobalMaterialLocalizations.delegates
            ],
            home: home));

void main() {
  late ProviderContainer container;
  late AiProviders notifier;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('zh'));
    container = ProviderContainer();
    notifier = container.read(aiProvidersProvider.notifier);
    container.read(aiProvidersProvider);
  });
  tearDown(() => container.dispose());

  test(
      'restore shipped template for every builtin, clearing keys and resetting enabled state',
      () {
    for (final option in buildDefaultAiServices()) {
      final previous = notifier.getProviderById(option.identifier)!;
      notifier.updateProvider(previous.copyWith(
          title: 'Changed',
          url: 'https://example.com/v1',
          model: 'changed-model',
          enabled: false,
          keyIndex: 7,
          temperature: 0.1,
          maxTokens: 1024,
          contextTurns: 2,
          reasoningEffort: AiReasoningEffort.none,
          apiKeys: custom.apiKeys));
      // Global legacy settings are not factory defaults.
      Prefs().aiTemperature = 0.2;
      Prefs().saveAiConfig(option.identifier, {
        'api_key': 'fixture-legacy-key',
        'url': 'https://example.com/legacy',
      });
      final restored = notifier.restoreBuiltinDefaults(option.identifier);
      expect(restored.title, option.title);
      expect(restored.url, option.defaultUrl);
      expect(restored.model, option.defaultModel);
      expect(restored.temperature, 0.7);
      expect(restored.maxTokens, 8192);
      expect(restored.contextTurns, 8);
      expect(restored.reasoningEffort, AiReasoningEffort.auto);
      expect(restored.apiKeys, isEmpty);
      expect(restored.currentApiKey, isNull);
      expect(restored.keyIndex, 0);
      expect(restored.enabled, true);
      expect(Prefs().getAiConfig(option.identifier), isEmpty);
      expect(restored.createdAt, previous.createdAt);
      notifier.refresh();
      expect(notifier.getProviderById(option.identifier), restored);
    }
  });

  void addCustom() {
    Prefs().saveAiProviders([custom, ...container.read(aiProvidersProvider)]);
    notifier.refresh();
  }

  test(
      'delete custom clears chat and translation references, persisted across refresh',
      () {
    addCustom();
    notifier.setSelectedProvider(custom.id);
    Prefs().translationAiService = custom.id;
    notifier.deleteProvider(custom.id);
    expect(Prefs().selectedAiService, isNot(custom.id));
    expect(Prefs().prefs.getString('translationAiService'), '');
    notifier.refresh();
    expect(notifier.getProviderById(custom.id), isNull);
    notifier.deleteProvider(
        custom.id); // Idempotent when a sync already removed it.
  });
  test('delete last enabled provider leaves no stale selection', () {
    for (final provider in container.read(aiProvidersProvider)) {
      notifier.toggleProvider(provider.id, false);
    }
    addCustom();
    notifier.setSelectedProvider(custom.id);
    notifier.deleteProvider(custom.id);
    expect(Prefs().selectedAiService, '');
    expect(notifier.getSelectedProvider(), isNull);
  });
  test(
      'builtins cannot be deleted and custom providers have no restore template',
      () {
    expect(() => notifier.deleteProvider('claude'), throwsException);
    addCustom();
    expect(
        () => notifier.restoreBuiltinDefaults(custom.id), throwsArgumentError);
    expect(notifier.getProviderById(custom.id), isNotNull);
  });

  testWidgets(
      'restore confirms, cancels or persists and refreshes the open form',
      (tester) async {
    final original = notifier.getProviderById('claude')!;
    notifier.updateProvider(original.copyWith(
        title: 'Changed',
        url: 'https://example.com',
        model: 'custom-model',
        apiKeys: custom.apiKeys));
    await tester.pumpWidget(
        app(container, const AiProviderDetailPage(providerId: 'claude')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('delete-provider')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('restore-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(notifier.getProviderById('claude')!.title, 'Changed');
    expect(notifier.getProviderById('claude')!.apiKeys, custom.apiKeys);
    await tester.tap(find.byKey(const ValueKey('restore-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '恢复默认值'));
    await tester.pumpAndSettle();
    expect(notifier.getProviderById('claude')!.title, original.title);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller!.text, original.title);
    expect(fields[1].controller!.text, original.url);
    expect(fields[2].controller!.text, original.model);
    expect(notifier.getProviderById('claude')!.apiKeys, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('custom detail has visible delete; delete returns safely to list',
      (tester) async {
    addCustom();
    await tester.pumpWidget(app(container, const AiProviderListPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom test'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('restore-provider')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('delete-provider')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.byType(AiProviderDetailPage), findsNothing);
    expect(notifier.getProviderById(custom.id), isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('custom swipe requires confirmation and builtins cannot swipe',
      (tester) async {
    addCustom();
    await tester.pumpWidget(app(container, const AiProviderListPage()));
    await tester.pumpAndSettle();
    expect(find.byType(Dismissible), findsOneWidget);
    final row = find.byKey(const ValueKey('provider-custom'));
    await tester.drag(row, const Offset(-700, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(notifier.getProviderById(custom.id), isNotNull);
    await tester.drag(row, const Offset(-700, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(notifier.getProviderById(custom.id), isNull);
    expect(tester.takeException(), isNull);
  });
}
