import 'dart:math';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// dimensions supported by Matryoshka truncation of EmbeddingGemma 2 vectors
const semanticVectorDimensions = [768, 512, 256, 128];

// returns a unit length copy of the vector
Float32List normalizeVector(List<double> vector) {
  var sumSquares = 0.0;
  for (final v in vector) {
    sumSquares += v * v;
  }
  final result = Float32List(vector.length);
  if (sumSquares == 0) return result;

  final norm = sqrt(sumSquares);
  for (var i = 0; i < vector.length; i++) {
    result[i] = vector[i] / norm;
  }
  return result;
}

// Matryoshka truncation: keep the leading dimensions, then re-normalize
Float32List truncateVector(List<double> vector, int dimension) {
  if (dimension <= 0 || dimension > vector.length) {
    throw ArgumentError.value(dimension, 'dimension', 'must be in [1, ${vector.length}]');
  }
  return normalizeVector(vector.sublist(0, dimension));
}

double dotProduct(List<double> a, List<double> b) {
  assert(a.length == b.length);
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

// symmetric int8 quantization with a per vector scale
@immutable
class QuantizedVector extends Equatable {
  final Int8List values;
  final double scale;

  @override
  List<Object?> get props => [values, scale];

  const new(this.values, this.scale);

  factory quantize(List<double> vector) {
    var maxAbs = 0.0;
    for (final v in vector) {
      final a = v.abs();
      if (a > maxAbs) maxAbs = a;
    }
    // scale is kept at float32 precision, as it is when stored in a matrix
    final scale = (Float32List(1)..[0] = maxAbs == 0 ? 1.0 : maxAbs / 127)[0];
    final values = Int8List(vector.length);
    for (var i = 0; i < vector.length; i++) {
      values[i] = (vector[i] / scale).round().clamp(-127, 127);
    }
    return QuantizedVector(values, scale);
  }

  factory fromBytes(Uint8List bytes, double scale) => QuantizedVector(Int8List.fromList(bytes.buffer.asInt8List(bytes.offsetInBytes, bytes.lengthInBytes)), scale);

  int get dimension => values.length;

  Uint8List toBytes() => Uint8List.fromList(values.buffer.asUint8List(values.offsetInBytes, values.lengthInBytes));

  Float32List dequantize() {
    final result = Float32List(values.length);
    for (var i = 0; i < values.length; i++) {
      result[i] = values[i] * scale;
    }
    return result;
  }

  double dot(List<double> other) {
    assert(other.length == values.length);
    var sum = 0.0;
    for (var i = 0; i < values.length; i++) {
      sum += values[i] * other[i];
    }
    return sum * scale;
  }
}

// from a raw model output to the vector stored in the index
QuantizedVector prepareVector(List<double> rawVector, int dimension) => QuantizedVector.quantize(truncateVector(rawVector, dimension));

@immutable
class SemanticMatch extends Equatable {
  final int id;
  final double score;

  @override
  List<Object?> get props => [id, score];

  const new(this.id, this.score);
}

// flat matrix of quantized vectors, scored by brute force
class SemanticVectorMatrix {
  final int dimension;
  final List<int> _ids = [];
  final Map<int, int> _rowById = {};
  Int8List _values = Int8List(0);
  Float32List _scales = Float32List(0);

  new(this.dimension);

  int get length => _ids.length;

  bool get isEmpty => _ids.isEmpty;

  Iterable<int> get ids => _ids;

  bool contains(int id) => _rowById.containsKey(id);

  QuantizedVector? vectorOf(int id) {
    final row = _rowById[id];
    if (row == null) return null;
    final start = row * dimension;
    return QuantizedVector(Int8List.fromList(_values.sublist(start, start + dimension)), _scales[row]);
  }

  void put(int id, QuantizedVector vector) {
    if (vector.dimension != dimension) {
      throw ArgumentError('vector dimension=${vector.dimension} does not match matrix dimension=$dimension');
    }
    var row = _rowById[id];
    if (row == null) {
      row = _ids.length;
      _ensureCapacity(row + 1);
      _ids.add(id);
      _rowById[id] = row;
    }
    _values.setRange(row * dimension, (row + 1) * dimension, vector.values);
    _scales[row] = vector.scale;
  }

  void remove(int id) {
    final row = _rowById.remove(id);
    if (row == null) return;

    // move last row into the freed slot
    final lastRow = _ids.length - 1;
    if (row != lastRow) {
      final lastId = _ids[lastRow];
      _values.setRange(row * dimension, (row + 1) * dimension, _values, lastRow * dimension);
      _scales[row] = _scales[lastRow];
      _ids[row] = lastId;
      _rowById[lastId] = row;
    }
    _ids.removeLast();
  }

  void removeAll(Iterable<int> ids) => ids.forEach(remove);

  void clear() {
    _ids.clear();
    _rowById.clear();
    _values = Int8List(0);
    _scales = Float32List(0);
  }

  void _ensureCapacity(int rows) {
    final capacity = _scales.length;
    if (rows <= capacity) return;

    final newCapacity = max(rows, max(64, capacity * 2));
    final values = Int8List(newCapacity * dimension)..setRange(0, _ids.length * dimension, _values);
    final scales = Float32List(newCapacity)..setRange(0, _ids.length, _scales);
    _values = values;
    _scales = scales;
  }

  // returns the best matches, sorted by decreasing score
  List<SemanticMatch> search(
    List<double> query, {
    required int maxResults,
    double minScore = -1,
    Set<int>? restrictTo,
    Set<int>? exclude,
  }) {
    if (query.length != dimension) {
      throw ArgumentError('query dimension=${query.length} does not match matrix dimension=$dimension');
    }
    if (maxResults <= 0 || isEmpty) return [];

    final matches = <SemanticMatch>[];
    for (var row = 0; row < _ids.length; row++) {
      final id = _ids[row];
      if (restrictTo != null && !restrictTo.contains(id)) continue;
      if (exclude != null && exclude.contains(id)) continue;

      var sum = 0.0;
      final offset = row * dimension;
      for (var i = 0; i < dimension; i++) {
        sum += _values[offset + i] * query[i];
      }
      final score = sum * _scales[row];
      if (score >= minScore) {
        matches.add(SemanticMatch(id, score));
      }
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.length > maxResults ? matches.sublist(0, maxResults) : matches;
  }

  // compact representation that can be sent to another isolate
  SemanticMatrixSnapshot snapshot() => SemanticMatrixSnapshot(
    dimension: dimension,
    ids: Int64List.fromList(_ids),
    values: Int8List.fromList(_values.sublist(0, _ids.length * dimension)),
    scales: Float32List.fromList(_scales.sublist(0, _ids.length)),
  );

  factory fromSnapshot(SemanticMatrixSnapshot snapshot) {
    final matrix = SemanticVectorMatrix(snapshot.dimension);
    final dimension = snapshot.dimension;
    for (var row = 0; row < snapshot.ids.length; row++) {
      final start = row * dimension;
      matrix.put(snapshot.ids[row], QuantizedVector(Int8List.fromList(snapshot.values.sublist(start, start + dimension)), snapshot.scales[row]));
    }
    return matrix;
  }
}

@immutable
class SemanticMatrixSnapshot {
  final int dimension;
  final Int64List ids;
  final Int8List values;
  final Float32List scales;

  const new({
    required this.dimension,
    required this.ids,
    required this.values,
    required this.scales,
  });
}
