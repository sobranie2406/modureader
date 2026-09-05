import 'dart:convert';

import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/service/config_transfer/settings_config_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConfigTransferCodec', () {
    test('round-trips compressed UTF-8 Modu configuration', () {
      final token = ConfigTransferCodec.encode(
        kind: 'webdav',
        data: {
          'backendType': 'webdav',
          'config': {'url': 'https://例子.test/dav'},
        },
      );

      expect(token, startsWith('modu:'));
      final decoded = ConfigTransferCodec.decode(token);
      expect(decoded.source, ConfigTransferSource.modu);
      expect(decoded.kind, 'webdav');
      expect(decoded.version, 1);
      expect(
        (decoded.data['config'] as Map)['url'],
        'https://例子.test/dav',
      );
    });

    test('decodes ReadAny base64 JSON tokens', () {
      final raw = {
        'backendType': 'webdav',
        'config': {'url': 'https://dav.example.com'},
      };
      final token = 'readany:${base64Encode(utf8.encode(jsonEncode(raw)))}';

      final decoded = ConfigTransferCodec.decode(token);
      expect(decoded.source, ConfigTransferSource.readAny);
      expect(decoded.kind, isNull);
      expect(decoded.data['backendType'], 'webdav');
    });

    test('rejects unknown token prefixes', () {
      expect(
        () => ConfigTransferCodec.decode('unknown:value'),
        throwsFormatException,
      );
    });
  });

  group('WebdavConfigTransfer', () {
    test('parses the ReadAny sync payload shape', () {
      final result = WebdavConfigTransfer.parse({
        'backendType': 'webdav',
        'config': {
          'type': 'webdav',
          'url': 'https://dav.example.com',
          'username': 'reader',
          'autoSync': true,
          'wifiOnly': true,
          'notifyOnComplete': false,
        },
        'password': 'secret',
      });

      expect(result.syncInfo['url'], 'https://dav.example.com');
      expect(result.syncInfo['username'], 'reader');
      expect(result.syncInfo['password'], 'secret');
      expect(result.autoSync, isTrue);
      expect(result.wifiOnly, isTrue);
      expect(result.notifyOnComplete, isFalse);
    });
  });

  group('AiConfigTransfer', () {
    test('preserves Modu multi-key providers', () {
      final provider = AiProvider(
        id: 'provider-1',
        title: '测试服务',
        url: 'https://api.example.com/v1',
        protocol: AiProtocol.openai,
        apiKeys: const [
          AiApiKey(id: 'key-1', key: 'secret-1'),
          AiApiKey(id: 'key-2', key: 'secret-2'),
        ],
        model: 'model-a',
        temperature: 0.2,
        maxTokens: 16384,
        contextTurns: 12,
      );
      final payload = AiConfigTransfer.createPayload(
        providers: [provider],
        selectedProviderId: provider.id,
        temperature: 0.5,
        maxTokens: 4096,
        contextTurns: 6,
        rpm: 20,
        translationProviderId: provider.id,
      );
      final token = ConfigTransferCodec.encode(kind: 'ai', data: payload);
      final result = AiConfigTransfer.parse(
        ConfigTransferCodec.decode(token).data,
      );

      expect(result.providers, hasLength(1));
      expect(result.providers.single.apiKeys, hasLength(2));
      expect(result.providers.single.model, 'model-a');
      expect(result.providers.single.temperature, 0.2);
      expect(result.providers.single.maxTokens, 16384);
      expect(result.providers.single.contextTurns, 12);
      expect(result.selectedProviderId, provider.id);
      expect(result.temperature, 0.2);
      expect(result.maxTokens, 16384);
      expect(result.contextTurns, 12);
      expect(result.rpm, 20);
      expect(result.translationProviderId, provider.id);
    });

    test('converts a ReadAny AIConfig endpoint', () {
      final result = AiConfigTransfer.parse({
        'endpoints': [
          {
            'id': 'claude-endpoint',
            'name': 'Claude',
            'provider': 'anthropic',
            'apiKey': 'sk-test',
            'baseUrl': 'https://api.anthropic.com',
            'models': ['claude-sonnet'],
            'modelsFetched': true,
          },
        ],
        'activeEndpointId': 'claude-endpoint',
        'activeModel': 'claude-sonnet',
        'temperature': 0.6,
        'maxTokens': 8192,
        'slidingWindowSize': 10,
      });

      expect(result.providers.single.protocol, AiProtocol.claude);
      expect(result.providers.single.currentApiKey, 'sk-test');
      expect(result.providers.single.model, 'claude-sonnet');
      expect(result.providers.single.temperature, 0.6);
      expect(result.providers.single.maxTokens, 8192);
      expect(result.providers.single.contextTurns, 10);
      expect(result.selectedProviderId, 'claude-endpoint');
    });

    test('falls back to ReadAny endpoints when Modu providers are empty', () {
      final result = AiConfigTransfer.parse({
        'moduProviders': <dynamic>[],
        'endpoints': [
          {
            'id': 'readany-openai',
            'name': 'ReadAny OpenAI',
            'provider': 'openai',
            'apiKey': 'sk-test',
            'baseUrl': 'https://api.openai.com/v1',
            'models': ['gpt-4o-mini'],
          },
        ],
        'activeEndpointId': 'readany-openai',
        'activeModel': 'gpt-4o-mini',
      });

      expect(result.providers, hasLength(1));
      expect(result.providers.single.id, 'readany-openai');
    });

    test('repairs known ReadAny endpoint URLs and non-chat model defaults', () {
      final result = AiConfigTransfer.parse({
        'endpoints': [
          {
            'id': 'siliconflow',
            'name': 'SiliconFlow',
            'provider': 'siliconflow',
            'apiKey': 'sf-key',
            'baseUrl': 'https://api.siliconflow.cn',
            'models': ['BAAI/bge-large-en-v1.5', 'Qwen/QwQ-32B'],
          },
          {
            'id': 'minimax',
            'name': 'Minimax',
            'provider': 'anthropic',
            'apiKey': 'minimax-key',
            'baseUrl': 'https://api.minimaxi.com/anthropic',
            'models': <String>[],
          },
          {
            'id': 'moonshot',
            'name': 'Moonshot (Kimi)',
            'provider': 'moonshot',
            'apiKey': 'moonshot-key',
            'baseUrl': 'https://api.moonshot.cn',
            'models': ['kimi-k2.5'],
          },
          {
            'id': 'qiniu',
            'name': '七牛云',
            'provider': 'openai',
            'apiKey': 'qiniu-key',
            'baseUrl': 'https://api.qnaigc.com/v1',
            'models': ['deepseek-r1'],
          },
        ],
        'activeEndpointId': 'moonshot',
        'activeModel': 'kimi-k2.5',
      });

      final byId = {
        for (final provider in result.providers) provider.id: provider
      };
      expect(byId['siliconflow']!.url, 'https://api.siliconflow.cn/v1');
      expect(byId['siliconflow']!.model, 'Qwen/Qwen3.5-27B');
      expect(byId['minimax']!.url, 'https://api.minimaxi.com/v1');
      expect(byId['minimax']!.protocol, AiProtocol.openai);
      expect(byId['minimax']!.model, 'MiniMax-M2.7');
      expect(byId['moonshot']!.url, 'https://api.moonshot.cn/v1');
      expect(byId['moonshot']!.model, 'kimi-k2.6');
      expect(byId['qiniu']!.model, 'deepseek/deepseek-v4-flash');
    });
  });
}
