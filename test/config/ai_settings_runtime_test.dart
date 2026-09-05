import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/knowledge/embedding_provider.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AI parameter setters expose the same bounded values used at runtime',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    Prefs().aiTemperature = 2;
    Prefs().aiMaxTokens = 99;
    Prefs().aiContextTurns = 100;
    Prefs().aiRpm = -5;

    expect(Prefs().aiTemperature, 1);
    expect(Prefs().aiMaxTokens, 1024);
    expect(Prefs().aiContextTurns, 30);
    expect(Prefs().aiRpm, 0);
  });

  test('translation runtime falls back to an enabled provider with a key',
      () async {
    SharedPreferences.setMockInitialValues({
      'selectedAiService': 'disabled',
      'translationAiService': 'disabled',
      'aiProviders': jsonEncode([
        {
          'id': 'disabled',
          'enabled': false,
          'model': 'model-a',
          'apiKeys': [
            {'key': 'key-a', 'enabled': true},
          ],
        },
        {
          'id': 'usable',
          'enabled': true,
          'model': 'model-b',
          'apiKeys': [
            {'key': 'key-b', 'enabled': true},
          ],
        },
      ]),
    });
    await Prefs().initPrefs();

    expect(Prefs().translationAiService, 'usable');
  });

  test('vector and speech runtime factories use their settings selections',
      () async {
    SharedPreferences.setMockInitialValues({
      'vectorModelEnabled': true,
      'vectorModelMode': 'remote',
      'vectorModelConfig': jsonEncode({
        'name': 'Test embeddings',
        'modelId': 'embedding-test',
        'endpoint': 'https://example.com/v1/embeddings',
        'apiKey': 'secret',
      }),
      'ttsService': 'edge',
    });
    await Prefs().initPrefs();

    final embedding = EmbeddingProviderFactory.fromPrefs();
    expect(embedding, isA<OpenAiCompatibleEmbeddingProvider>());
    expect(embedding!.modelId, 'embedding-test');
    expect(getTtsService(Prefs().ttsService), TtsService.edge);

    Prefs().vectorModelEnabled = false;
    expect(EmbeddingProviderFactory.fromPrefs(), isNull);
  });
}
