import 'package:anx_reader/service/book_player/tts_text_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('next chapter text and explicit end-of-book survive the bridge', () {
    expect(ttsTextResult('下一章标题'), '下一章标题');
    expect(ttsTextResult(''), '');
  });
  test('missing, failed or malformed replies cannot masquerade as completion',
      () {
    for (final result in [null, false, 0, <String, dynamic>{}]) {
      expect(() => ttsTextResult(result), throwsStateError);
    }
    expect(() => ttsTextResult('', error: 'fixture'), throwsStateError);
  });
}
