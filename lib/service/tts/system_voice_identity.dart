import 'dart:convert';

/// Engine names are not unique: Huawei may return "zh" for several locales.
String systemVoiceId(Map<dynamic, dynamic> voice) => 'system:${jsonEncode([
          voice['name']?.toString() ?? '',
          (voice['locale']?.toString() ?? '')
              .replaceAll('_', '-')
              .toLowerCase(),
        ])}';

Map<dynamic, dynamic>? findSystemVoice(List voices, String selected) {
  final candidates = voices.whereType<Map>().toList();
  for (final voice in candidates) {
    if (systemVoiceId(voice) == selected) return voice;
  }
  // Migrate legacy name-only selections to the same first match the old
  // player used. Once saved, list ordering can no longer change the voice.
  for (final voice in candidates) {
    if (voice['name'] == selected) return voice;
  }
  return null;
}
