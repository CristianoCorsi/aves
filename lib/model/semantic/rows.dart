import 'dart:typed_data';

import 'package:aves/model/semantic/vector.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
class SemanticEmbeddingRow extends Equatable {
  final int id;
  final String modelId;
  final QuantizedVector vector;
  // modification date of the file when it was indexed, to detect stale vectors
  final int? dateModifiedMillis;

  @override
  List<Object?> get props => [id, modelId, vector, dateModifiedMillis];

  const new({
    required this.id,
    required this.modelId,
    required this.vector,
    required this.dateModifiedMillis,
  });

  // marks an entry that could not be indexed, to avoid retrying it until it is modified
  factory failure({
    required int id,
    required String modelId,
    required int? dateModifiedMillis,
  }) => SemanticEmbeddingRow(
    id: id,
    modelId: modelId,
    vector: QuantizedVector(Int8List(0), 1),
    dateModifiedMillis: dateModifiedMillis,
  );

  bool get isFailure => vector.dimension == 0;

  factory fromMap(Map<String, Object?> map) {
    return SemanticEmbeddingRow(
      id: map['id'] as int,
      modelId: map['modelId'] as String,
      vector: QuantizedVector.fromBytes(map['vector'] as Uint8List, (map['scale'] as num).toDouble()),
      dateModifiedMillis: map['dateModifiedMillis'] as int?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'modelId': modelId,
    'dimension': vector.dimension,
    'scale': vector.scale,
    'vector': vector.toBytes(),
    'dateModifiedMillis': dateModifiedMillis,
  };

  SemanticEmbeddingRow copyWith({required int id}) => SemanticEmbeddingRow(
    id: id,
    modelId: modelId,
    vector: vector,
    dateModifiedMillis: dateModifiedMillis,
  );
}

@immutable
class SemanticTagRow extends Equatable {
  final int id;
  final String tag;
  final double score;
  final String modelId;

  @override
  List<Object?> get props => [id, tag, score, modelId];

  const new({
    required this.id,
    required this.tag,
    required this.score,
    required this.modelId,
  });

  factory fromMap(Map<String, Object?> map) {
    return SemanticTagRow(
      id: map['id'] as int,
      tag: map['tag'] as String,
      score: (map['score'] as num).toDouble(),
      modelId: map['modelId'] as String,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'tag': tag,
    'score': score,
    'modelId': modelId,
  };

  SemanticTagRow copyWith({required int id}) => SemanticTagRow(
    id: id,
    tag: tag,
    score: score,
    modelId: modelId,
  );
}

// cached embedding of an auto tagging label
@immutable
class SemanticLabelRow extends Equatable {
  final String label;
  final String modelId;
  final QuantizedVector vector;

  @override
  List<Object?> get props => [label, modelId, vector];

  const new({
    required this.label,
    required this.modelId,
    required this.vector,
  });

  factory fromMap(Map<String, Object?> map) {
    return SemanticLabelRow(
      label: map['label'] as String,
      modelId: map['modelId'] as String,
      vector: QuantizedVector.fromBytes(map['vector'] as Uint8List, (map['scale'] as num).toDouble()),
    );
  }

  Map<String, Object?> toMap() => {
    'label': label,
    'modelId': modelId,
    'dimension': vector.dimension,
    'scale': vector.scale,
    'vector': vector.toBytes(),
  };
}
