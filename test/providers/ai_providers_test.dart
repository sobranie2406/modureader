import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reconciles missing built-ins and retired models for existing users',
      () async {
    SharedPreferences.setMockInitialValues({
      'selectedAiService': 'openai',
      'aiTemperature': 0.4,
      'aiMaxTokens': 16384,
      'aiContextTurns': 14,
      'aiProviders': jsonEncode([
        {
          'id': 'openai',
          'title': 'OpenAI',
          'url': 'https://api.openai.com/v1/chat/completions',
          'protocol': 'openai',
          'enabled': false,
          'isBuiltin': true,
          'model': 'gpt-4o-mini',
        },
        {
          'id': 'claude',
          'title': 'Claude',
          'url': 'https://api.anthropic.com/v1/messages',
          'protocol': 'claude',
          'enabled': true,
          'isBuiltin': true,
          'model': 'claude-3-5-sonnet-20240620',
        },
        {
          'id': 'deepseek',
          'title': 'DeepSeek',
          'url': 'https://api.deepseek.com/v1/chat/completions',
          'protocol': 'openai',
          'enabled': true,
          'isBuiltin': true,
          'model': 'deepseek-chat',
        },
        {
          'id': 'openrouter',
          'title': 'OpenRouter',
          'url': 'https://openrouter.ai/api/v1/chat/completions',
          'protocol': 'openai',
          'enabled': true,
          'isBuiltin': true,
          'model': 'gpt-4o-mini',
        },
      ]),
    });
    await Prefs().initPrefs();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final providers = container.read(aiProvidersProvider);

    expect(providers.map((provider) => provider.id), contains('glm'));
    expect(providers.map((provider) => provider.id), contains('gemini'));
    expect(
      providers.firstWhere((provider) => provider.id == 'claude').model,
      'claude-sonnet-4-6',
    );
    expect(
      providers.firstWhere((provider) => provider.id == 'deepseek').model,
      'deepseek-v4-flash',
    );
    expect(
      providers.firstWhere((provider) => provider.id == 'openrouter').model,
      'openai/gpt-4o-mini',
    );
    expect(Prefs().selectedAiService, 'claude');
    expect(providers.every((provider) => provider.temperature == 0.4), isTrue);
    expect(providers.every((provider) => provider.maxTokens == 16384), isTrue);
    expect(providers.every((provider) => provider.contextTurns == 14), isTrue);
  });

  test('disabling the selected provider selects another enabled provider',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(aiProvidersProvider.notifier);

    notifier.setSelectedProvider('openai');
    notifier.toggleProvider('openai', false);

    expect(notifier.getSelectedProvider(), isNotNull);
    expect(notifier.getSelectedProvider()!.id, isNot('openai'));
    expect(notifier.getSelectedProvider()!.enabled, isTrue);
  });
}
