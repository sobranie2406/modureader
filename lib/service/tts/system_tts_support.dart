import 'dart:io';

/// flutter_tts has no Linux or OpenHarmony implementation in this build.
bool supportsSystemTts({String? operatingSystem}) => const {
      'android',
      'ios',
      'macos',
      'windows',
    }.contains(operatingSystem ?? Platform.operatingSystem);

String systemTtsUnsupportedMessage({bool chinese = false}) => chinese
    ? '此平台暂不支持系统语音，请在「设置 → 朗读」中主动选择在线语音。在线服务会发送朗读文本给所选服务商。'
    : 'System speech is unavailable on this platform. Choose an online service in Settings → Read aloud. Online speech sends text to the selected provider.';
