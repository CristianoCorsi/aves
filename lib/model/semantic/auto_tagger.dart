import 'dart:convert';

import 'package:aves/model/semantic/prompts.dart';
import 'package:aves/model/semantic/rows.dart';
import 'package:aves/model/semantic/vector.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// a label to detect, with the text given to the model and the resulting tag name
@immutable
class SemanticLabel extends Equatable {
  final String prompt;
  final String tag;

  @override
  List<Object?> get props => [prompt, tag];

  const new({required this.prompt, required this.tag});
}

@immutable
class SemanticLabelVector {
  final SemanticLabel label;
  final Float32List vector;

  const new(this.label, this.vector);
}

class SemanticAutoTagger {
  static const _labelAsset = 'assets/semantic_labels.json';

  // built-in labels, with tag names in the given language when available
  static Future<List<SemanticLabel>> builtInLabels(String languageCode) async {
    final json = jsonDecode(await rootBundle.loadString(_labelAsset)) as Map;
    final labels = (json['labels'] as List).cast<Map>();
    return labels.map((v) {
      final prompt = v['en'] as String;
      return SemanticLabel(prompt: prompt, tag: (v[languageCode] as String?) ?? prompt);
    }).toList();
  }

  static List<SemanticLabel> customLabels(List<String> labels) {
    return labels.map((v) => v.trim()).where((v) => v.isNotEmpty).map((v) => SemanticLabel(prompt: v, tag: v)).toList();
  }

  // returns label vectors at the given dimension, embedding labels that are not cached yet
  static Future<List<SemanticLabelVector>> labelVectors({
    required List<SemanticLabel> labels,
    required String modelId,
    required int dimension,
    required Future<List<SemanticLabelRow>> Function() loadCache,
    required Future<void> Function(Set<SemanticLabelRow> rows) saveCache,
    required Future<List<Float32List>> Function(List<String> texts) embedTexts,
  }) async {
    final cached = {for (final row in await loadCache()) row.label: row.vector};
    final missing = labels.map((v) => v.prompt).toSet().whereNot(cached.containsKey).toList();
    if (missing.isNotEmpty) {
      final newRows = <SemanticLabelRow>{};
      const batchSize = 16;
      for (var i = 0; i < missing.length; i += batchSize) {
        final batch = missing.sublist(i, (i + batchSize).clamp(0, missing.length));
        final vectors = await embedTexts(batch.map(SemanticPrompts.label).toList());
        for (var j = 0; j < batch.length && j < vectors.length; j++) {
          final raw = vectors[j];
          if (raw.length < dimension) continue;
          final vector = prepareVector(raw, dimension);
          cached[batch[j]] = vector;
          newRows.add(SemanticLabelRow(label: batch[j], modelId: modelId, vector: vector));
        }
      }
      await saveCache(newRows);
    }
    return labels.where((v) => cached.containsKey(v.prompt)).map((v) => SemanticLabelVector(v, cached[v.prompt]!.dequantize())).toList();
  }

  // best labels for an item, by decreasing score
  static List<(String, double)> tagsFor(
    QuantizedVector vector,
    List<SemanticLabelVector> labelVectors, {
    required double threshold,
    required int maxCount,
  }) {
    final scores = <String, double>{};
    for (final labelVector in labelVectors) {
      if (labelVector.vector.length != vector.dimension) continue;
      final score = vector.dot(labelVector.vector);
      if (score < threshold) continue;
      final tag = labelVector.label.tag;
      // different labels may map to the same tag
      if ((scores[tag] ?? double.negativeInfinity) < score) {
        scores[tag] = score;
      }
    }
    final sorted = scores.entries.map((kv) => (kv.key, kv.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return sorted.take(maxCount).toList();
  }

  static Set<SemanticTagRow> tagRows(
    Iterable<SemanticEmbeddingRow> embeddings,
    List<SemanticLabelVector> labelVectors, {
    required double threshold,
    required int maxCount,
  }) {
    return embeddings
        .where((row) => !row.isFailure)
        .expand(
          (row) => tagsFor(row.vector, labelVectors, threshold: threshold, maxCount: maxCount).map(
            (v) => SemanticTagRow(id: row.id, tag: v.$1, score: v.$2, modelId: row.modelId),
          ),
        )
        .toSet();
  }
}
