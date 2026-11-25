import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/tts/models/tts_voice.dart';
import 'package:modu_reader/service/tts/tts_service.dart';
import 'package:modu_reader/service/tts/tts_service_provider.dart';
import 'package:modu_reader/service/tts/tts_synthesis_error.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// DeepSeek speech synthesis (POST /v1/tools/tts).
///
/// The endpoint streams a WAV body and exposes no speed or pitch parameter, so
/// the player applies rate and pitch locally. Raw PCM is not offered: the
/// playback path only decodes MP3 and RIFF/WAVE.
class DeepSeekTtsProvider extends TtsServiceProvider {
  static final DeepSeekTtsProvider _instance = DeepSeekTtsProvider._internal();

  factory DeepSeekTtsProvider() => _instance;

  DeepSeekTtsProvider._internal() : _client = null;

  @visibleForTesting
  DeepSeekTtsProvider.forTesting({required http.Client client})
      : _client = client;

  final http.Client? _client;

  static const String _defaultUrl = 'https://api.deepseek.com/v1/tools/tts';
  static const String _defaultVoice = 'stella';
  static const Set<String> _voiceIds = {'stella', 'tide'};

  /// Book passages are short, but a long chapter may stream for a while.
  @override
  Duration get synthesisTimeout => const Duration(seconds: 60);

  @override
  TtsService get service => TtsService.deepseek;

  @override
  String getLabel(BuildContext context) => 'DeepSeek';

  String _label(BuildContext context, String zh, String en) =>
      ModuStrings.text(context, zh, en);

  @override
  List<ConfigItem> getConfigItems(BuildContext context) => [
        ConfigItem(
          key: 'tip',
          label: _label(context, '说明', 'Help'),
          type: ConfigItemType.tip,
          defaultValue: _label(
            context,
            'DeepSeek 语音合成：文本直接流式返回音频，语种按文本自动识别。音色仅 stella（女声）与 tide（男声）；不支持调节语速，倍速由播放器本地实现。',
            'DeepSeek speech returns streamed audio and detects the language from the text. Only the stella (female) and tide (male) voices exist; speed is applied locally by the player.',
          ),
        ),
        ConfigItem(
          key: 'url',
          label: 'URL',
          description:
              _label(context, 'DeepSeek TTS 接口地址', 'DeepSeek TTS endpoint URL'),
          type: ConfigItemType.text,
          defaultValue: _defaultUrl,
        ),
        ConfigItem(
          key: 'key',
          label: 'API Key',
          description: _label(context, 'DeepSeek API Key', 'DeepSeek API key'),
          type: ConfigItemType.password,
          defaultValue: '',
        ),
        ConfigItem(
          key: 'voice',
          label: _label(context, '音色', 'Voice'),
          description: _label(
              context, 'stella 为女声，tide 为男声', 'stella is female, tide is male'),
          type: ConfigItemType.select,
          defaultValue: _defaultVoice,
          options: [
            {
              'label': _label(context, 'stella · 海星（女声）', 'stella · female'),
              'value': 'stella',
            },
            {
              'label': _label(context, 'tide · 暗潮（男声）', 'tide · male'),
              'value': 'tide',
            },
          ],
        ),
        ConfigItem(
          key: 'filterMarkdown',
          label: _label(context, '朗读前去掉 Markdown', 'Strip Markdown'),
          description: _label(
            context,
            '默认由服务端去掉 Markdown 标记；关闭后符号可能被一并读出。',
            'The service removes Markdown by default; disabling it may read the symbols aloud.',
          ),
          type: ConfigItemType.toggle,
          defaultValue: true,
        ),
      ];

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getOnlineTtsConfig(serviceId);
    final voice = _text(config['voice']);
    // Transfers keep every value as a string; store this provider the same way.
    return {
      'url': _text(config['url']).isEmpty ? _defaultUrl : _text(config['url']),
      'key': _text(config['key']),
      'voice': _voiceIds.contains(voice) ? voice : _defaultVoice,
      'filterMarkdown':
          _text(config['filterMarkdown']) == 'false' ? 'false' : 'true',
    };
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveOnlineTtsConfig(serviceId, {
      for (final entry in config.entries) entry.key: _text(entry.value),
    });
  }

  static String _text(Object? value) {
    if (value == null) return '';
    if (value is bool) return value ? 'true' : 'false';
    return value.toString();
  }

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    final config = getConfig();
    final key = config['key'] as String;
    if (key.isEmpty) {
      throw TtsSynthesisError(
          TtsFailureReason.configuration, 'DeepSeek TTS：请填写 API Key。');
    }
    if (text.trim().isEmpty) {
      throw TtsSynthesisError(
          TtsFailureReason.configuration, 'DeepSeek TTS：朗读文本为空。');
    }
    final voiceId = resolveVoice(voice).trim();
    if (!_voiceIds.contains(voiceId)) {
      throw TtsSynthesisError(
          TtsFailureReason.configuration, 'DeepSeek TTS：只支持 stella 与 tide 音色。');
    }

    http.Response response;
    try {
      response = await (_client?.post ?? http.post)(
        Uri.parse(config['url'] as String),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
          'Accept': 'audio/wav',
        },
        body: jsonEncode({
          'text': text,
          'voice_id': voiceId,
          'format': 'wav',
          'filter_markdown': config['filterMarkdown'] != 'false',
        }),
      ).timeout(synthesisTimeout);
    } on TimeoutException {
      throw TtsSynthesisError(
          TtsFailureReason.timeout, 'DeepSeek TTS：合成超时，请重试或缩短文本。');
    } on Exception {
      // Never log the endpoint, the key, or the narrated text.
      throw TtsSynthesisError(TtsFailureReason.network, 'DeepSeek TTS：网络请求失败。');
    }

    if (response.statusCode != 200) {
      final hint = switch (response.statusCode) {
        400 => '没有可朗读的文本，或文本未通过内容审核',
        429 => '同时进行的请求数超过上限，请稍后重试',
        503 => '服务繁忙，请稍后重试',
        504 => '合成超时，请稍后重试',
        401 || 403 => '请检查 API Key',
        _ => '服务暂不可用，请稍后重试',
      };
      throw TtsSynthesisError(
          TtsFailureReason.http, 'DeepSeek TTS（${response.statusCode}）：$hint。',
          statusCode: response.statusCode,
          retryAfter: TtsSynthesisError.parseRetryAfter(
              response.headers['retry-after']));
    }

    final bytes = response.bodyBytes;
    // A body that stops early is a failure, not a shorter sentence.
    final declared = int.tryParse(response.headers['content-length'] ?? '');
    if (declared != null &&
        !response.headers.containsKey('transfer-encoding') &&
        bytes.length != declared) {
      throw TtsSynthesisError(
          TtsFailureReason.truncated, 'DeepSeek TTS：音频返回不完整，请重试。',
          statusCode: 200);
    }
    if (!_isWave(bytes)) {
      throw TtsSynthesisError(
          TtsFailureReason.invalidAudio, 'DeepSeek TTS：没有返回有效的 WAV 音频。',
          statusCode: 200);
    }
    return bytes;
  }

  static bool _isWave(List<int> bytes) =>
      bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45;

  @override
  Future<List<TtsVoice>> getVoices() async {
    return const [
      TtsVoice(
        shortName: 'stella',
        name: 'Stella',
        locale: 'zh-CN',
        gender: 'Female',
        description: '海星 · 女声',
      ),
      TtsVoice(
        shortName: 'tide',
        name: 'Tide',
        locale: 'zh-CN',
        gender: 'Male',
        description: '暗潮 · 男声',
      ),
    ];
  }

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    if (voiceData is TtsVoice) return voiceData;
    if (voiceData is Map<String, dynamic>) {
      return TtsVoice.fromMap(voiceData);
    }
    return const TtsVoice(shortName: '', name: '', locale: '');
  }

  @override
  String getSelectedVoice() {
    final voice = getConfig()['voice'] as String;
    return voice.isEmpty ? _defaultVoice : voice;
  }

  @override
  void setSelectedVoice(String voice) {
    if (!_voiceIds.contains(voice)) return;
    final config = getConfig();
    config['voice'] = voice;
    saveConfig(config);
  }
}
