import 'dart:math' as math;

import 'package:anx_reader/service/knowledge/onnx_embedding_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ONNX embedding pooling', () {
    test('mean-pools unmasked tokens and L2-normalizes the result', () {
      final vector = poolAndNormalizeEmbedding(
        [
          1,
          0,
          1,
          2,
          100,
          100,
        ],
        [1, 3, 2],
        [1, 1, 0],
      );

      expect(vector[0], closeTo(1 / math.sqrt(2), 1e-10));
      expect(vector[1], closeTo(1 / math.sqrt(2), 1e-10));
    });

    test('normalizes an already pooled sentence embedding', () {
      expect(
        poolAndNormalizeEmbedding([3, 4], [1, 2], [1]),
        [0.6, 0.8],
      );
    });

    test('rejects a zero vector', () {
      expect(
        () => poolAndNormalizeEmbedding([0, 0], [1, 2], [1]),
        throwsFormatException,
      );
    });
  });
}
