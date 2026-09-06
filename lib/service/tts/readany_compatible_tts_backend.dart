import 'dart:convert';
import 'dart:async';
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

  XiaomiMimoTtsProvider.forTesting({required http.Client client})
      : super(client: client);

  @override
  TtsService get service => TtsService.xiaomi;

  @override
  String get providerName => 'Xiaomi MiMo';

  @override
  String get providerDescription =>
      '小米官方聊天语音接口：内置音色或文字设计音色。语速、音高通过风格指令控制，非精确倍率。仅播放 MP3/WAV，旧 AAC/PCM 配置自动改用 MP3。不支持声音克隆。';

  @override
  String get defaultBaseUrl => 'https://api.xiaomimimo.com';

  @override
  String get defaultEndpoint => '/v1/chat/completions';

  @override
  String get defaultModel => 'mimo-v2.5-tts';

  @override
  String get defaultVoice => 'mimo_default';

  @override
  Duration get synthesisTimeout => const Duration(seconds: 60);

  @override
  Map<String, dynamic> getConfig() => normalizeConfig(super.getConfig());

  // Effective migration is also used by the settings form. Preserve credentials
  // and custom hosts; never silently redirect a configured proxy to Xiaomi.
  Map<String, dynamic> normalizeConfig(Map<String, dynamic> saved) {
    final config = Map<String, dynamic>.from(saved);
    String value(String key) => config[key]?.toString().trim() ?? '';
    if (value('baseUrl').isEmpty) config['baseUrl'] = defaultBaseUrl;
    if (value('endpoint').isEmpty ||
        const {'/v1/audio/speech', 'v1/audio/speech', '/audio/speech'}
            .contains(value('endpoint'))) {
      config['endpoint'] = defaultEndpoint;
    }
    final endpointUri = Uri.tryParse(value('endpoint'));
    if (endpointUri?.host == 'api.xiaomimimo.com' &&
        const {'/v1/audio/speech', '/audio/speech'}
            .contains(endpointUri?.path)) {
      config['endpoint'] =
          endpointUri!.replace(path: defaultEndpoint).toString();
    }
    final model = value('model');
    if (model.isEmpty || model.toLowerCase() == defaultModel) {
      config['model'] = defaultModel;
    }
    if (value('voice').isEmpty || value('voice') == 'default') {
      config['voice'] = defaultVoice;
    }
    if (!const {'mp3', 'wav'}.contains(value('format'))) {
      config['format'] = 'mp3';
    }
    return config;
  }

  @override
  List<ConfigItem> getConfigItems(BuildContext context) =>
      super.getConfigItems(context).map((item) {
        if (item.key == 'format') {
          return ConfigItem(
            key: 'format',
            label: item.label,
            type: ConfigItemType.select,
            defaultValue: 'mp3',
            options: const [
              {'label': 'MP3', 'value': 'mp3'},
              {'label': 'WAV', 'value': 'wav'},
            ],
          );
        }
        if (item.key == 'model') {
          return ConfigItem(
            key: 'model',
            label: item.label,
            type: ConfigItemType.select,
            defaultValue: defaultModel,
            options: [
              {'label': 'MiMo · 内置音色', 'value': 'mimo-v2.5-tts'},
              {'label': 'MiMo · 文字设计音色', 'value': 'mimo-v2.5-tts-voicedesign'},
              if (!const {'mimo-v2.5-tts', 'mimo-v2.5-tts-voicedesign'}
                  .contains(getConfig()['model']))
                {'label': '旧模型不受支持，请重新选择', 'value': getConfig()['model']},
            ],
          );
        }
        return item;
      }).toList();

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    final config = getConfig();
    final key = config['key']?.toString().trim() ?? '';
    if (key.isEmpty) throw StateError('Xiaomi MiMo：请填写 API Key。');
    if (text.trim().isEmpty) throw StateError('Xiaomi MiMo：朗读文本为空。');
    final model = config['model'].toString();
    final design = model == 'mimo-v2.5-tts-voicedesign';
    if (!design && model != defaultModel) {
      throw StateError('Xiaomi MiMo：请选择内置音色或文字设计音色模型。');
    }
    final style = config['stylePrompt']?.toString().trim() ?? '';
    if (design && style.isEmpty) {
      throw StateError('Xiaomi MiMo：文字设计音色需要填写朗读风格/音色描述。');
    }
    final selected = resolveVoice(voice).trim();
    final resolved = selected == 'default' ? defaultVoice : selected;
    if (!design && !bundledVoices.any((v) => v.shortName == resolved)) {
      throw StateError('Xiaomi MiMo：请选择官方内置音色。');
    }
    final directions = [
      if (style.isNotEmpty) style,
      if (rate.isFinite && rate != 1)
        '语速约为正常语速的 ${rate.clamp(0.25, 4).toStringAsFixed(2)} 倍。',
      if (pitch.isFinite && pitch != 1) pitch > 1 ? '音调适当提高。' : '音调适当降低。',
    ].join('\n');
    final uri = resolveMimoEndpoint(
        config['baseUrl'].toString(), config['endpoint'].toString());
    http.Response response;
    try {
      response = await _client
          .post(uri,
              headers: {
                'Authorization': 'Bearer $key',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'model': model,
                'messages': [
                  if (directions.isNotEmpty)
                    {'role': 'user', 'content': directions},
                  {'role': 'assistant', 'content': text},
                ],
                'audio': {
                  'format': config['format'],
                  if (!design) 'voice': resolved,
                  if (design) 'optimize_text_preview': false,
                },
                'stream': false,
              }))
          .timeout(synthesisTimeout);
    } on TimeoutException {
      throw StateError('Xiaomi MiMo：语音生成超时，请重试或缩短文本。');
    } on Exception {
      // Do not expose a proxy URL, echoed key, or private text in app logs.
      throw StateError('Xiaomi MiMo：网络请求失败，请检查地址和网络。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final hint = switch (response.statusCode) {
        401 || 403 => '请检查 API Key 和模型访问权限',
        429 => '请求限流或额度不足，请稍后重试',
        400 || 404 || 422 => '请检查接口地址、模型及音色参数',
        _ => '服务暂不可用，请稍后重试',
      };
      throw StateError('Xiaomi MiMo（${response.statusCode}）：$hint。');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final choice = (decoded['choices'] as List).first;
      if (choice['finish_reason'] != 'stop') {
        throw const FormatException('Incomplete speech');
      }
      final audio = base64Decode(choice['message']['audio']['data'] as String);
      if (audio.isEmpty) throw const FormatException('Empty speech');
      return audio;
    } catch (_) {
      throw StateError('Xiaomi MiMo：没有返回完整有效的音频，已保留原文位置，请重试。');
    }
  }

  @override
  List<TtsVoice> get bundledVoices => const [
        TtsVoice(shortName: 'mimo_default', name: 'MiMo 默认', locale: 'zh-CN'),
        TtsVoice(shortName: '冰糖', name: '冰糖', locale: 'zh-CN'),
        TtsVoice(shortName: '茉莉', name: '茉莉', locale: 'zh-CN'),
        TtsVoice(shortName: '苏打', name: '苏打', locale: 'zh-CN'),
        TtsVoice(shortName: '白桦', name: '白桦', locale: 'zh-CN'),
        TtsVoice(shortName: 'Mia', name: 'Mia', locale: 'en-US'),
        TtsVoice(shortName: 'Chloe', name: 'Chloe', locale: 'en-US'),
        TtsVoice(shortName: 'Milo', name: 'Milo', locale: 'en-US'),
        TtsVoice(shortName: 'Dean', name: 'Dean', locale: 'en-US'),
      ];
}

Uri resolveMimoEndpoint(String baseUrl, String endpoint) {
  var base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  var path = endpoint.trim();
  if (!path.startsWith('https://') && !path.startsWith('http://')) {
    if (base.endsWith('/chat/completions')) {
      path = base;
    } else if (base.endsWith('/v1') && path.startsWith('/v1/')) {
      base = base.substring(0, base.length - 3);
    }
  }
  final uri = resolveSpeechEndpoint(base, path);
  if (uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'https' &&
          !(uri.scheme == 'http' &&
              const {'localhost', '127.0.0.1', '::1'}.contains(uri.host)))) {
    throw const FormatException('Xiaomi MiMo：请使用不带密钥参数的 HTTPS 接口地址。');
  }
  return uri;
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
