/// Bounded online-speech tuning. Defaults preserve the previous playback units.
class TtsBufferSettings {
  const TtsBufferSettings({
    this.ahead = 3,
    this.maxCharacters = 240,
    this.concurrency = 2,
    this.paragraphPauseMs = 0,
    this.cacheMinutes = 10,
  });

  final int ahead;
  final int maxCharacters;
  final int concurrency;
  final int paragraphPauseMs;
  final int cacheMinutes;

  factory TtsBufferSettings.fromMap(Map<String, dynamic> map) {
    int read(String key, int fallback, int min, int max) {
      final value = map[key] ?? fallback;
      if (value is! int || value < min || value > max) {
        throw FormatException('Invalid speech buffer setting: $key');
      }
      return value;
    }

    return TtsBufferSettings(
      ahead: read('ahead', 3, 0, 12),
      maxCharacters: read('maxCharacters', 240, 100, 2000),
      concurrency: read('concurrency', 2, 1, 4),
      paragraphPauseMs: read('paragraphPauseMs', 0, 0, 3000),
      cacheMinutes: read('cacheMinutes', 10, 0, 120),
    );
  }

  Map<String, dynamic> toMap() => {
        'ahead': ahead,
        'maxCharacters': maxCharacters,
        'concurrency': concurrency,
        'paragraphPauseMs': paragraphPauseMs,
        'cacheMinutes': cacheMinutes,
      };
}
