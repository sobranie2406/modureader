import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';

/// A complete, versioned snapshot. Parsing never changes preferences or starts TTS.
class TtsConfigTransfer {
  static const services = ['system', 'edge', 'dashscope', 'xiaomi', 'openai'];

  static Map<String, dynamic> defaults() => {
        'version': 1,
        'service': 'system',
        'volume': 1.0,
        'pitch': 1.0,
        'rate': 0.6,
        'allowMixWithOtherAudio': false,
        'providers': {
          for (final id in services)
            id: {'config': <String, dynamic>{}, 'voice': ''},
        },
      };

  static Map<String, dynamic> snapshot(Prefs prefs) => {
        'version': 1,
        'service': prefs.ttsService,
        'volume': prefs.ttsVolume,
        'pitch': prefs.ttsPitch,
        'rate': prefs.ttsRate,
        'allowMixWithOtherAudio': prefs.allowMixWithOtherAudio,
        'providers': {
          for (final id in services)
            id: {
              'config': prefs.getOnlineTtsConfig(id),
              'voice': prefs.getTtsVoiceModel(id),
            },
        },
      };

  static Map<String, dynamic> validate(Map<String, dynamic> data) {
    if (data['version'] != 1 || !services.contains(data['service'])) {
      throw const FormatException(
          '不支持的朗读配置版本或服务 / Unsupported TTS configuration');
    }
    double number(String key, double min, double max) {
      final value = data[key];
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException('朗读参数无效 / Invalid speech parameters');
      }
      return value.toDouble();
    }

    final rawProviders = data['providers'];
    if (data['allowMixWithOtherAudio'] is! bool ||
        rawProviders is! Map ||
        rawProviders.length != services.length ||
        !services.every(rawProviders.containsKey)) {
      throw const FormatException('朗读配置不完整 / Incomplete TTS configuration');
    }
    final providers = <String, dynamic>{};
    for (final id in services) {
      final raw = rawProviders[id];
      if (raw is! Map || raw['voice'] is! String || raw['config'] is! Map) {
        throw const FormatException('语音配置无效 / Invalid voice configuration');
      }
      final config = <String, dynamic>{};
      for (final entry in (raw['config'] as Map).entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('接口配置无效 / Invalid service configuration');
        }
        config[entry.key as String] = entry.value;
      }
      for (final key in ['url', 'baseUrl']) {
        final value = config[key] as String?;
        if (value == null || value.trim().isEmpty) continue;
        final uri = Uri.tryParse(value.trim());
        if (uri == null ||
            !['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          throw const FormatException('接口地址无效 / Invalid service URL');
        }
      }
      final format = config['format'];
      if (format != null && !['mp3', 'wav', 'aac', 'pcm'].contains(format)) {
        throw const FormatException('音频格式无效 / Invalid audio format');
      }
      // Providers with a voice field use it as the authoritative selection.
      providers[id] = {
        'config': config,
        'voice': config['voice'] ?? raw['voice']
      };
    }
    return {
      'version': 1,
      'service': data['service'],
      'volume': number('volume', 0, 1),
      'pitch': number('pitch', 0.5, 2),
      'rate': number('rate', 0, 2),
      'allowMixWithOtherAudio': data['allowMixWithOtherAudio'],
      'providers': providers,
    };
  }

  /// Validate the entire snapshot before any writes. Never clear unrelated prefs.
  /// The caller stops the player before applying and refreshes it afterwards.
  static Future<void> apply(Prefs prefs, Map<String, dynamic> data) async {
    final valid = validate(data);
    final values = <String, Object>{
      'ttsService': valid['service'],
      'ttsVolume': valid['volume'],
      'ttsPitch': valid['pitch'],
      'ttsRate': valid['rate'],
      'allowMixWithOtherAudio': valid['allowMixWithOtherAudio'],
      for (final id in services)
        'onlineTtsConfig_$id': jsonEncode(valid['providers'][id]['config']),
      for (final id in services)
        'ttsVoiceModel_$id': valid['providers'][id]['voice'],
    };
    final previous = {for (final key in values.keys) key: prefs.prefs.get(key)};
    Future<bool> write(String key, Object? value) => switch (value) {
          String v => prefs.prefs.setString(key, v),
          double v => prefs.prefs.setDouble(key, v),
          bool v => prefs.prefs.setBool(key, v),
          null => prefs.prefs.remove(key),
          _ => throw StateError('Unexpected TTS preference type'),
        };
    try {
      for (final entry in values.entries) {
        if (!await write(entry.key, entry.value)) {
          throw StateError('Could not save TTS settings');
        }
      }
    } catch (_) {
      for (final entry in previous.entries) {
        await write(entry.key, entry.value);
      }
      rethrow;
    } finally {
      prefs.notifyExternalChange();
    }
  }
}
