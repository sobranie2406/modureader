/// The playback path supports compressed MP3 and RIFF/WAVE, not raw PCM.
String ttsAudioMimeType(List<int> bytes) {
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45) {
    return 'audio/wav';
  }
  return 'audio/mpeg';
}
