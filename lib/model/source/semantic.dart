import 'dart:async';
import 'dart:math';

import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/semantic/rows.dart';
import 'package:aves/model/semantic/scope.dart';
import 'package:aves/model/semantic/vector.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/analysis_controller.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/semantic/model_service.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

mixin SemanticMixin on SourceBase {
  static const _batchSize = 8;
  static const _commitCountThreshold = 64;

  SemanticVectorMatrix? _semanticMatrix;
  String? _semanticMatrixModelId;
  Future<SemanticVectorMatrix?>? _semanticMatrixLoading;

  SemanticScope get semanticScope => SemanticScope(
    scope: settings.semanticIndexScope,
    included: settings.semanticIncludedAlbums,
    excluded: settings.semanticExcludedAlbums,
    includeVideos: settings.semanticIndexVideos,
  );

  bool get isSemanticReady => settings.semanticEnabled && semanticModels.isInstalled;

  // in-memory vectors of the current model and dimension, loaded on demand
  Future<SemanticVectorMatrix?> getSemanticMatrix() async {
    final modelId = settings.semanticModelId;
    if (!isSemanticReady || modelId == null) return null;

    final dimension = settings.semanticPerformanceParams.vectorDimension;
    final current = _semanticMatrix;
    if (current != null && current.dimension == dimension && _semanticMatrixModelId == modelId) return current;

    return _semanticMatrixLoading ??= () async {
      try {
        final rows = await localMediaDb.loadSemanticEmbeddings(modelId, dimension);
        final matrix = SemanticVectorMatrix(dimension);
        rows.where((row) => !row.isFailure && row.vector.dimension == dimension).forEach((row) => matrix.put(row.id, row.vector));
        _semanticMatrix = matrix;
        _semanticMatrixModelId = modelId;
        debugPrint('$runtimeType loaded ${matrix.length} semantic vectors');
        return matrix;
      } finally {
        _semanticMatrixLoading = null;
      }
    }();
  }

  void invalidateSemanticMatrix() {
    _semanticMatrix = null;
    _semanticMatrixModelId = null;
    eventBus.fire(SemanticIndexChangedEvent());
  }

  void removeSemanticVectors(Set<int> ids) {
    _semanticMatrix?.removeAll(ids);
  }

  Future<void> copySemanticData(Map<int, int> newIdBySourceId) async {
    final modelId = settings.semanticModelId;
    if (modelId == null || newIdBySourceId.isEmpty) return;

    final dimension = settings.semanticPerformanceParams.vectorDimension;
    final rows = await localMediaDb.loadSemanticEmbeddings(modelId, dimension, ids: newIdBySourceId.keys.toSet());
    final copies = rows.map((row) => row.copyWith(id: newIdBySourceId[row.id]!)).toSet();
    await localMediaDb.saveSemanticEmbeddings(copies);
    copies.where((row) => !row.isFailure).forEach((row) => _semanticMatrix?.put(row.id, row.vector));

    final tags = await localMediaDb.loadSemanticTags(ids: newIdBySourceId.keys.toSet());
    final tagCopies = tags.map((row) => row.copyWith(id: newIdBySourceId[row.id]!)).toSet();
    await localMediaDb.replaceSemanticTags(tagCopies.map((row) => row.id).toSet(), tagCopies);
  }

  // returns whether some entries got processed
  Future<bool> indexSemanticEntries(AnalysisController controller, Set<AvesEntry> candidateEntries) async {
    if (controller.isStopping || !isSemanticReady) return false;
    if (!await availability.canUseSemantic) return false;

    final modelId = settings.semanticModelId!;
    final modelPath = settings.semanticModelPath!;
    final params = settings.semanticPerformanceParams;
    final dimension = params.vectorDimension;

    final removed = await localMediaDb.removeObsoleteSemanticEmbeddings(modelId, dimension);
    if (removed > 0) {
      invalidateSemanticMatrix();
    }

    final indexState = await localMediaDb.loadSemanticIndexState(modelId, dimension);
    final scope = semanticScope;
    final force = controller.force;
    final todo = candidateEntries.where((entry) {
      if (!scope.test(entry)) return false;
      if (force || !indexState.containsKey(entry.id)) return true;
      return indexState[entry.id] != entry.dateModifiedMillis;
    }).toList();
    if (todo.isEmpty) return false;

    // most recent items first
    todo.sort((a, b) => (b.bestDate ?? DateTime(0)).compareTo(a.bestDate ?? DateTime(0)));
    final batch = todo.take(params.maxItemsPerRun).toList();
    debugPrint('$runtimeType semantic indexing of ${batch.length}/${todo.length} entries');

    try {
      if (!semanticEngine.isLoaded) {
        await semanticEngine.load(modelPath: modelPath, backend: params.backend.name);
      }
    } catch (error, stack) {
      debugPrint('$runtimeType failed to load semantic model with error=$error\n$stack');
      return false;
    }

    state = SourceState.indexing;
    var progressDone = 0;
    final progressTotal = batch.length;
    setProgress(done: progressDone, total: progressTotal);

    final pending = <SemanticEmbeddingRow>{};
    Future<void> commitPendingRows() async {
      if (pending.isEmpty) return;
      final rows = Set.of(pending);
      pending.clear();
      await localMediaDb.saveSemanticEmbeddings(rows);
      final matrix = _semanticMatrix;
      if (matrix != null && matrix.dimension == dimension && _semanticMatrixModelId == modelId) {
        rows.forEach((row) => row.isFailure ? matrix.remove(row.id) : matrix.put(row.id, row.vector));
      }
      await onSemanticEmbeddingsChanged(rows);
    }

    var processed = false;
    for (final slice in batch.slices(_batchSize)) {
      if (controller.isStopping) break;
      if (await _isThermallyThrottled()) {
        debugPrint('$runtimeType semantic indexing paused because of device temperature');
        break;
      }

      final rows = await _embedEntries(slice, modelId: modelId, dimension: dimension, thumbnailSize: params.thumbnailSize);
      if (rows == null) break;
      pending.addAll(rows);
      processed = true;
      progressDone += slice.length;
      setProgress(done: progressDone, total: progressTotal);
      if (pending.length >= _commitCountThreshold) {
        await commitPendingRows();
      }

      final delayMillis = params.itemDelayMillis * slice.length;
      if (delayMillis > 0) {
        await Future.delayed(Duration(milliseconds: delayMillis));
      }
    }
    await commitPendingRows();
    return processed;
  }

  // returns `null` when the engine failed as a whole
  Future<Set<SemanticEmbeddingRow>?> _embedEntries(
    List<AvesEntry> entries, {
    required String modelId,
    required int dimension,
    required int thumbnailSize,
  }) async {
    final rows = <SemanticEmbeddingRow>{};
    final inputEntries = <AvesEntry>[];
    final inputImages = <Uint8List>[];
    await Future.forEach(entries, (entry) async {
      Uint8List? bytes;
      try {
        bytes = await mediaFetchService.getEncodedThumbnailBytes(entry, sizePx: thumbnailSize);
      } catch (error) {
        debugPrint('$runtimeType failed to get thumbnail for entry=$entry with error=$error');
      }
      if (bytes != null && bytes.isNotEmpty) {
        inputEntries.add(entry);
        inputImages.add(bytes);
      } else {
        rows.add(SemanticEmbeddingRow.failure(id: entry.id, modelId: modelId, dateModifiedMillis: entry.dateModifiedMillis));
      }
    });
    if (inputImages.isEmpty) return rows;

    final List<Float32List?> vectors;
    try {
      vectors = await semanticEngine.embedImages(inputImages);
    } catch (error, stack) {
      debugPrint('$runtimeType semantic engine failed with error=$error\n$stack');
      return null;
    }

    for (var i = 0; i < inputEntries.length; i++) {
      final entry = inputEntries[i];
      final raw = i < vectors.length ? vectors[i] : null;
      if (raw != null && raw.isNotEmpty) {
        rows.add(
          SemanticEmbeddingRow(
            id: entry.id,
            modelId: modelId,
            vector: prepareVector(raw, min(dimension, raw.length)),
            dateModifiedMillis: entry.dateModifiedMillis,
          ),
        );
      } else {
        rows.add(SemanticEmbeddingRow.failure(id: entry.id, modelId: modelId, dateModifiedMillis: entry.dateModifiedMillis));
      }
    }
    return rows;
  }

  Future<bool> _isThermallyThrottled() async {
    try {
      return (await semanticEngine.getInfo())?.isThermallyThrottled ?? false;
    } catch (error) {
      return false;
    }
  }

  // hook for derived data, e.g. auto tagging
  @mustCallSuper
  Future<void> onSemanticEmbeddingsChanged(Set<SemanticEmbeddingRow> rows) async {
    eventBus.fire(SemanticIndexChangedEvent());
  }
}

class SemanticIndexChangedEvent;
