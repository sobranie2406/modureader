import 'package:modu_reader/service/ocr/document_page_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('page ranges are one-based, sorted, and deduplicated', () {
    expect(parseDocumentPageRange(' 3-5,1，4, 8–9 ', 10), [0, 2, 3, 4, 7, 8]);
    expect(parseDocumentPageRange('1', 1), [0]);
  });
  test('invalid or out-of-document ranges are rejected before extraction', () {
    for (final value in [
      '',
      '0',
      '4-2',
      '1-11',
      '1,',
      '-2',
      '1.5',
      '1-2-3',
      '999999999999999999999999999999999999'
    ]) {
      expect(() => parseDocumentPageRange(value, 10), throwsFormatException,
          reason: value);
    }
  });
}
