import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

abstract class ReadAnyCompatibleTtsProvider extends TtsServiceProvider {
  ReadAnyCompatibleTtsProvider({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  String get defaultBaseUrl;
  String get defaultEndpoint => '/v1/audio/speech';
  String get defaultModel;
  String get defaultVoice;
  String get providerName;
  String get providerDescription;
  List<TtsVoice> get bundledVoices;

  String _label(BuildContext context, String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  String getLabel(BuildContext context) => providerName;

  @override
  List<ConfigItem> getConfigItems(BuildContext context) => [
        ConfigItem(
          key: 'description',
          label: providerName,
          type: ConfigItemType.tip,
          defaultValue: providerDescription,
        ),
        ConfigItem(
          key: 'baseUrl',
          label: _label(context, '基础 URL', 'Base URL'),
          type: ConfigItemType.text,
          defaultValue: defaultBaseUrl,
        ),
        ConfigItem(
          key: 'key',
          label: _label(context, 'API 密钥', 'API key'),
          type: ConfigItemType.password,
          defaultValue: '',
        ),
        ConfigItem(
          key: 'endpoint',
          label: _label(context, '接口', 'Endpoint'),
          type: ConfigItemType.text,
          defaultValue: defaultEndpoint,
        ),
        ConfigItem(
          key: 'model',
          label: _label(context, '模型', 'Model'),
          type: ConfigItemType.text,
          defaultValue: defaultModel,
        ),
        ConfigItem(
          key: 'voice',
          label: _label(context, '音色', 'Voice'),
          type: ConfigItemType.text,
          defaultValue: defaultVoice,
        ),
        ConfigItem(
          key: 'format',
          label: _label(context, '格式', 'Format'),
          type: ConfigItemType.select,
          defaultValue: 'mp3',
          options: const [
            {'label': 'MP3', 'value': 'mp3'},
            {'label': 'WAV', 'value': 'wav'},
            {'label': 'AAC', 'value': 'aac'},
            {'label': 'PCM', 'value': 'pcm'},
          ],
        ),
        ConfigItem(
          key: 'stylePrompt',
          label: _label(context, '朗读风格', 'Reading style'),
          type: ConfigItemType.text,
          defaultValue: _label(
            context,
            '自然、平稳、适合长时间听书。',
            'Natural, steady, and suitable for long-form listening.',
          ),
        ),
      ];

  @override
  Map<String, dynamic> getConfig() {
    final saved = Prefs().getOnlineTtsConfig(serviceId);
    return {
      'description': providerDescription,
      'baseUrl': saved['baseUrl'] ?? defaultBaseUrl,
      'key': saved['key'] ?? '',
      'endpoint': saved['endpoint'] ?? defaultEndpoint,
      'model': saved['model'] ?? defaultModel,
      'voice': saved['voice'] ?? defaultVoice,
      'format': saved['format'] ?? 'mp3',
      'stylePrompt': saved['stylePrompt'] ?? '',
    };
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveOnlineTtsConfig(serviceId, config);
  }

  @override
  Future<Uint8List> speak(
    String text,
    String? voice,
    double rate,
    double pitch,
  ) async {
    final config = getConfig();
    final apiKey = config['key']?.toString().trim() ?? '';
    if (apiKey.isEmpty) {
      throw StateError('$providerName API key is missing');
    }
    final uri = resolveSpeechEndpoint(
      config['baseUrl']?.toString() ?? '',
      config['endpoint']?.toString() ?? '',
    );
    final style = config['stylePrompt']?.toString().trim() ?? '';
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'audio/*, application/json',
      },
      body: jsonEncode({
        'model': config['model']?.toString().trim() ?? defaultModel,
        'voice': resolveVoice(voice),
        'input': text,
        'response_format': config['format']?.toString() ?? 'mp3',
        'speed': rate.clamp(0.25, 4.0),
        if (style.isNotEmpty)
          'instructions':
              '$style\nPitch multiplier: ${pitch.toStringAsFixed(2)}.',
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '$providerName request failed (${response.statusCode}): ${response.body}',
      );
    }
    return decodeTtsAudioResponse(response);
  }

  @override
  Future<List<TtsVoice>> getVoices() async => bundledVoices;

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) return voiceData;
    if (voiceData is Map<String, dynamic>) return TtsVoice.fromMap(voiceData);
    return const TtsVoice(shortName: '', name: '', locale: '');
  }

  @override
  String getSelectedVoice() {
    final voice = getConfig()['voice']?.toString() ?? '';
    return voice.isEmpty ? defaultVoice : voice;
  }

  @override
  void setSelectedVoice(String voice) {
    final config = getConfig();
    config['voice'] = voice;
    saveConfig(config);
  }
}

class DashScopeTtsProvider extends ReadAnyCompatibleTtsProvider {
  static final DashScopeTtsProvider _instance = DashScopeTtsProvider._();

  factory DashScopeTtsProvider() => _instance;

  DashScopeTtsProvider._();

  @override
  TtsService get service => TtsService.dashscope;

  @override
  String get providerName => 'DashScope';

  @override
  String get providerDescription => '阿里云 qwen3-tts-flash 语音';

  @override
  String get defaultBaseUrl => 'https://dashscope.aliyuncs.com/compatible-mode';

  @override
  String get defaultModel => 'qwen3-tts-flash';

  @override
  String get defaultVoice => 'Cherry';

  @override
  List<TtsVoice> get bundledVoices => const [
        TtsVoice(shortName: 'Cherry', name: 'Cherry', locale: 'zh-CN'),
        TtsVoice(shortName: 'Serena', name: 'Serena', locale: 'zh-CN'),
        TtsVoice(shortName: 'Ethan', name: 'Ethan', locale: 'zh-CN'),
        TtsVoice(shortName: 'Chelsie', name: 'Chelsie', locale: 'zh-CN'),
      ];
}

class XiaomiMimoTtsProvider extends ReadAnyCompatibleTtsProvider {
  static final XiaomiMimoTtsProvider _instance = XiaomiMimoTtsProvider._();

  factory XiaomiMimoTtsProvider() => _instance;

  XiaomiMimoTtsProvider._();

  @override
  TtsService get service => TtsService.xiaomi;

  @override
  String get providerName => 'Xiaomi MiMo';

  @override
  String get providerDescription => 'MiMo-V2.5-TTS，支持自定义音色和朗读风格';

  @override
  String get defaultBaseUrl => '';

  @override
  String get defaultModel => 'MiMo-V2.5-TTS';

  @override
  String get defaultVoice => 'default';

  @override
  List<TtsVoice> get bundledVoices => const [
        TtsVoice(shortName: 'default', name: 'Default', locale: 'zh-CN'),
      ];
}

Uri resolveSpeechEndpoint(String baseUrl, String endpoint) {
  final endpointValue = endpoint.trim();
  if (endpointValue.startsWith('http://') ||
      endpointValue.startsWith('https://')) {
    return Uri.parse(endpointValue);
  }
  final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  if (base.isEmpty) {
    throw const FormatException('Base URL is required');
  }
  final path = endpointValue.isEmpty ? '/v1/audio/speech' : endpointValue;
  return Uri.parse('$base/${path.replaceFirst(RegExp(r'^/+'), '')}');
}

Uint8List decodeTtsAudioResponse(http.Response response) {
  final contentType = response.headers['content-type']?.toLowerCase() ?? '';
  if (contentType.startsWith('audio/') ||
      contentType.contains('application/octet-stream')) {
    return response.bodyBytes;
  }

  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  dynamic audio;
  if (decoded is Map) {
    audio = decoded['audio'];
    final data = decoded['data'];
    if (audio == null && data is String) audio = data;
    if (audio == null && data is Map) audio = data['audio'] ?? data['data'];
    final output = decoded['output'];
    if (audio == null && output is Map) {
      audio = output['audio'] ?? output['data'];
    }
    final choices = decoded['choices'];
    if (audio == null && choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map && first['message'] is Map) {
        final messageAudio = first['message']['audio'];
        if (messageAudio is Map) audio = messageAudio['data'];
      }
    }
  }
  if (audio is Map) audio = audio['data'] ?? audio['audio'];
  if (audio is! String || audio.isEmpty) {
    throw const FormatException('TTS response does not contain audio data');
  }
  final normalized = audio.contains(',') ? audio.split(',').last : audio;
  return Uint8List.fromList(base64Decode(normalized));
}
