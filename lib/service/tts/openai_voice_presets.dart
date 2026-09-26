import 'package:anx_reader/service/tts/mimo_voice_presets.dart';

/// Editable Modu instructions, not provider voice IDs or voice-cloning presets.
class OpenAiVoicePresets {
  static bool isLegacyModel(String model) =>
      const {'tts-1', 'tts-1-hd'}.contains(model.trim());

  static bool sendsInstructions(Map<String, dynamic> config) =>
      config['instructionsEnabled'] != 'false' &&
      !isLegacyModel(config['model']?.toString() ?? '');

  static const templates = {
    ...MimoVoicePresets.styles,
    '温暖柔和': '声音温暖柔和，语气亲切，减少尖锐感，保持吐字清晰，以自然的节奏讲述。',
    '低沉稳重': '使用偏低沉、稳重的表达，语气从容，情绪克制，保持清晰度，不刻意压低到含混。',
    '清亮轻快': '声音清亮，语气轻快自然，表达有活力但不过分夸张，句间留出自然停顿。',
  };

  static const phrases = {
    ...MimoVoicePresets.phrases,
    '稍慢语速': '语速稍慢，不拖长尾音。',
    '稍快语速': '语速稍快，仍保持每个字清楚。',
    '温暖音色': '声音温暖柔和，减少尖锐感。',
    '低沉音色': '声音稍低沉，保持清晰自然。',
    '标准普通话': '使用标准普通话，自然表达。',
  };
}
