import 'dart:async';
import 'dart:math';

import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/semantic/auto_tagger.dart';
import 'package:aves/model/semantic/rows.dart';
import 'package:aves/model/semantic/scope.dart';
import 'package:aves/model/semantic/search.dart';
import 'package:aves/model/semantic/vector.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/analysis_controller.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/tag.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/semantic/model_service.dart';
import 'package:aves_model/aves_model.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

mixin SemanticMixin on SourceBase, TagMixin {
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
    semanticSearch.clear();
    eventBus.fire(SemanticIndexChangedEvent());
  }

  // returns how many items in the indexing scope are indexed (including failures), and their total count
  Future<(int, int)> semanticIndexStats() async {
    final modelId = settings.semanticModelId;
    final scope = semanticScope;
    final inScope = visibleEntries.where(scope.test).map((entry) => entry.id).toSet();
    if (modelId == null) return (0, inScope.length);

    final indexState = await localMediaDb.loadSemanticIndexState(modelId, settings.semanticPerformanceParams.vectorDimension);
    return (inScope.where(indexState.containsKey).length, inScope.length);
  }

  Future<void> clearSemanticIndex() async {
    await localMediaDb.clearSemanticData();
    allEntries.forEach((entry) => entry.autoTags = const {});
    invalidateSemanticMatrix();
    onCatalogMetadataChanged();
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
    // hidden items are kept out of the index, for privacy
    final visible = visibleEntries;
    final todo = candidateEntries.where((entry) {
      if (!visible.contains(entry) || !scope.test(entry)) return false;
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

  Future<void> onSemanticEmbeddingsChanged(Set<SemanticEmbeddingRow> rows) async {
    if (settings.semanticAutoTagEnabled) {
      await _autoTag(rows);
    }
    eventBus.fire(SemanticIndexChangedEvent());
  }

  // auto tagging

  List<SemanticLabelVector>? _labelVectors;
  String? _labelVectorsKey;

  static bool get _showAutoTags => settings.semanticEnabled && settings.semanticAutoTagEnabled && settings.semanticAutoTagShowAsTags;

  void onAutoTagSettingsChanged() {
    // flag is shared by all sources, so derived tags are invalidated regardless of previous value
    AvesEntry.showAutoTags = _showAutoTags;
    onCatalogMetadataChanged();
  }

  Future<void> loadSemanticTags({Set<int>? ids}) async {
    AvesEntry.showAutoTags = _showAutoTags;
    final rows = await localMediaDb.loadSemanticTags(ids: ids);
    final tagsById = <int, Set<String>>{};
    rows.forEach((row) => tagsById.putIfAbsent(row.id, () => {}).add(row.tag));

    var changed = false;
    void update(AvesEntry entry) {
      final newTags = tagsById[entry.id] ?? const <String>{};
      if (!const SetEquality<String>().equals(entry.autoTags, newTags)) {
        entry.autoTags = newTags;
        changed = true;
      }
    }

    if (ids == null) {
      allEntries.forEach(update);
    } else {
      ids.map(getEntryById).nonNulls.forEach(update);
    }
    if (changed) {
      onCatalogMetadataChanged();
    }
  }

  Future<List<SemanticLabelVector>> _getLabelVectors(String modelId, int dimension) async {
    final languageCode = settings.resolvedLocale.languageCode;
    final labels = [
      ...await SemanticAutoTagger.builtInLabels(languageCode),
      ...SemanticAutoTagger.customLabels(settings.semanticAutoTagCustomLabels),
    ];
    final key = '$modelId-$dimension-${Object.hashAll(labels)}';
    if (_labelVectorsKey == key && _labelVectors != null) return _labelVectors!;

    final modelPath = settings.semanticModelPath;
    if (modelPath != null && !semanticEngine.isLoaded) {
      await semanticEngine.load(modelPath: modelPath, backend: settings.semanticPerformanceParams.backend.name);
    }
    final vectors = await SemanticAutoTagger.labelVectors(
      labels: labels,
      modelId: modelId,
      dimension: dimension,
      loadCache: () => localMediaDb.loadSemanticLabels(modelId, dimension),
      saveCache: localMediaDb.saveSemanticLabels,
      embedTexts: semanticEngine.embedTexts,
    );
    _labelVectors = vectors;
    _labelVectorsKey = key;
    return vectors;
  }

  Future<void> _autoTag(Set<SemanticEmbeddingRow> rows) async {
    final modelId = settings.semanticModelId;
    if (modelId == null || rows.isEmpty) return;

    final dimension = settings.semanticPerformanceParams.vectorDimension;
    try {
      final labelVectors = await _getLabelVectors(modelId, dimension);
      final tagRows = SemanticAutoTagger.tagRows(
        rows,
        labelVectors,
        threshold: settings.semanticAutoTagThreshold,
        maxCount: settings.semanticAutoTagMaxPerItem,
      );
      final ids = rows.map((row) => row.id).toSet();
      await localMediaDb.replaceSemanticTags(ids, tagRows);
      await loadSemanticTags(ids: ids);
    } catch (error, stack) {
      debugPrint('$runtimeType failed to auto tag with error=$error\n$stack');
    }
  }

  // recomputes auto tags of all indexed items, e.g. after label or threshold changes
  Future<void> recomputeSemanticTags() async {
    final modelId = settings.semanticModelId;
    if (!isSemanticReady || modelId == null) return;

    await localMediaDb.clearSemanticTags();
    if (settings.semanticAutoTagEnabled) {
      final dimension = settings.semanticPerformanceParams.vectorDimension;
      final rows = await localMediaDb.loadSemanticEmbeddings(modelId, dimension);
      for (final slice in rows.slices(500)) {
        await _autoTag(slice.toSet());
      }
    }
    await loadSemanticTags();
    onCatalogMetadataChanged();
  }
}

class SemanticIndexChangedEvent;
