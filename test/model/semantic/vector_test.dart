import 'dart:math';
import 'dart:typed_data';

import 'package:aves/model/semantic/vector.dart';
import 'package:test/test.dart';

double _norm(List<double> v) => sqrt(v.fold(0.0, (sum, x) => sum + x * x));

void main() {
  test('normalization yields unit vectors', () {
    expect(_norm(normalizeVector([3, 4])), closeTo(1, 1e-6));
    expect(normalizeVector([3, 4]), [closeTo(.6, 1e-6), closeTo(.8, 1e-6)]);
    expect(normalizeVector([0, 0]), [0, 0]);
  });

  test('Matryoshka truncation keeps leading dimensions and re-normalizes', () {
    final truncated = truncateVector([1, 1, 5, 5], 2);
    expect(truncated.length, 2);
    expect(_norm(truncated), closeTo(1, 1e-6));
    expect(truncated[0], closeTo(truncated[1], 1e-6));
    expect(() => truncateVector([1, 2], 3), throwsArgumentError);
  });

  test('int8 quantization round trip is close to the original', () {
    final random = Random(42);
    final vector = normalizeVector(List.generate(256, (_) => random.nextDouble() * 2 - 1));
    final quantized = QuantizedVector.quantize(vector);
    final restored = quantized.dequantize();
    for (var i = 0; i < vector.length; i++) {
      expect(restored[i], closeTo(vector[i], quantized.scale));
    }
    expect(quantized.dot(vector), closeTo(1, 1e-2));

    final fromBytes = QuantizedVector.fromBytes(quantized.toBytes(), quantized.scale);
    expect(fromBytes, quantized);
  });

  test('quantization of zero vector', () {
    final quantized = QuantizedVector.quantize(Float32List(4));
    expect(quantized.values, [0, 0, 0, 0]);
    expect(quantized.dot([1, 1, 1, 1]), 0);
  });

  group('matrix', () {
    SemanticVectorMatrix buildMatrix() {
      final matrix = SemanticVectorMatrix(2);
      matrix.put(1, prepareVector([1, 0], 2));
      matrix.put(2, prepareVector([0, 1], 2));
      matrix.put(3, prepareVector([1, 1], 2));
      matrix.put(4, prepareVector([-1, 0], 2));
      return matrix;
    }

    test('search sorts by decreasing score and applies limits', () {
      final matrix = buildMatrix();
      final query = normalizeVector([1, .1]);

      final all = matrix.search(query, maxResults: 10);
      expect(all.map((v) => v.id), [1, 3, 2, 4]);

      expect(matrix.search(query, maxResults: 2).map((v) => v.id), [1, 3]);
      expect(matrix.search(query, maxResults: 10, minScore: .5).map((v) => v.id), [1, 3]);
      expect(matrix.search(query, maxResults: 10, restrictTo: {2, 4}).map((v) => v.id), [2, 4]);
      expect(matrix.search(query, maxResults: 10, exclude: {1}).map((v) => v.id), [3, 2, 4]);
      expect(matrix.search(query, maxResults: 0), isEmpty);
    });

    test('put replaces, remove compacts', () {
      final matrix = buildMatrix();
      matrix.put(1, prepareVector([0, -1], 2));
      expect(matrix.length, 4);
      expect(matrix.search(normalizeVector([0, -1]), maxResults: 1).single.id, 1);

      matrix.remove(2);
      matrix.remove(42);
      expect(matrix.length, 3);
      expect(matrix.contains(2), isFalse);
      expect(matrix.ids.toSet(), {1, 3, 4});
      expect(matrix.vectorOf(4), prepareVector([-1, 0], 2));
      expect(matrix.search(normalizeVector([-1, 0]), maxResults: 1).single.id, 4);
    });

    test('grows beyond initial capacity', () {
      final matrix = SemanticVectorMatrix(4);
      for (var id = 0; id < 200; id++) {
        matrix.put(id, prepareVector([id.toDouble(), 1, 0, 0], 4));
      }
      expect(matrix.length, 200);
      expect(matrix.vectorOf(150), prepareVector([150, 1, 0, 0], 4));
    });

    test('snapshot round trip', () {
      final matrix = buildMatrix();
      final copy = SemanticVectorMatrix.fromSnapshot(matrix.snapshot());
      expect(copy.ids.toSet(), matrix.ids.toSet());
      for (final id in matrix.ids) {
        expect(copy.vectorOf(id), matrix.vectorOf(id));
      }
    });

    test('rejects mismatched dimensions', () {
      final matrix = buildMatrix();
      expect(() => matrix.put(5, prepareVector([1, 2, 3], 3)), throwsArgumentError);
      expect(() => matrix.search([1, 2, 3], maxResults: 1), throwsArgumentError);
    });
  });
}
