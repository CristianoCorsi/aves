import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math';

import 'package:aves/model/filters/semantic.dart';
import 'package:aves/model/semantic/prompts.dart';
import 'package:aves/model/semantic/vector.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:flutter/foundation.dart';

final SemanticSearch semanticSearch = SemanticSearch._private();

// resolves semantic filters to scored entry IDs, asynchronously
class SemanticSearch {
  // scoring is moved to another isolate for large indexes
  static const _isolateThreshold = 20000;
  static const _queryCacheSize = 32;

  final Map<String, Map<int, double>> _resultsByKey = {};
  final Map<String, Future<void>> _pendingByKey = {};
  final LinkedHashMap<String, Float32List> _queryVectors = LinkedHashMap();

  new _private();

  bool isResolved(SemanticFilter filter) => _resultsByKey.containsKey(filter.key);

  bool contains(SemanticFilter filter, int id) => _resultsByKey[filter.key]?.containsKey(id) ?? false;

  double? scoreOf(SemanticFilter filter, int id) => _resultsByKey[filter.key]?[id];

  // highest score among resolved filters, for relevance sorting
  double? bestScore(Iterable<SemanticFilter> filters, int id) => filters.map((filter) => scoreOf(filter, id)).nonNulls.fold<double?>(null, (prev, v) => prev == null ? v : max(prev, v));

  void clear() {
    _resultsByKey.clear();
    _queryVectors.clear();
  }

  Future<void> resolve(SemanticFilter filter, CollectionSource source) {
    final key = filter.key;
    if (_resultsByKey.containsKey(key)) return SynchronousFuture(null);
    return _pendingByKey[key] ??= () async {
      try {
        _resultsByKey[key] = await _search(filter, source);
      } catch (error, stack) {
        debugPrint('$runtimeType failed to resolve filter=$filter with error=$error\n$stack');
        _resultsByKey[key] = {};
      } finally {
        _pendingByKey.removeWhere((k, _) => k == key);
      }
      source.eventBus.fire(SemanticSearchResolvedEvent(key));
    }();
  }

  Future<Map<int, double>> _search(SemanticFilter filter, CollectionSource source) async {
    final matrix = await source.getSemanticMatrix();
    if (matrix == null || matrix.isEmpty) return {};

    Float32List? queryVector;
    final query = filter.query;
    final entryId = filter.entryId;
    if (query != null) {
      queryVector = await _getQueryVector(query, matrix.dimension);
    } else if (entryId != null) {
      queryVector = matrix.vectorOf(entryId)?.dequantize();
    }
    if (queryVector == null) return {};

    final maxResults = settings.semanticMaxResults;
    final minScore = settings.semanticMinSimilarity;
    final exclude = entryId != null ? {entryId} : null;

    final List<SemanticMatch> matches;
    if (matrix.length < _isolateThreshold) {
      matches = matrix.search(queryVector, maxResults: maxResults, minScore: minScore, exclude: exclude);
    } else {
      final snapshot = matrix.snapshot();
      final vector = queryVector;
      matches = await Isolate.run(() => SemanticVectorMatrix.fromSnapshot(snapshot).search(vector, maxResults: maxResults, minScore: minScore, exclude: exclude));
    }
    return {for (final match in matches) match.id: match.score};
  }

  Future<Float32List?> _getQueryVector(String query, int dimension) async {
    final cacheKey = '${settings.semanticModelId}-$dimension-$query';
    final cached = _queryVectors.remove(cacheKey);
    if (cached != null) {
      _queryVectors[cacheKey] = cached;
      return cached;
    }

    final modelPath = settings.semanticModelPath;
    if (modelPath == null) return null;
    if (!semanticEngine.isLoaded) {
      await semanticEngine.load(modelPath: modelPath, backend: settings.semanticPerformanceParams.backend.name);
    }
    final raw = (await semanticEngine.embedTexts([SemanticPrompts.query(query)])).firstOrNull;
    if (raw == null || raw.length < dimension) return null;

    final vector = truncateVector(raw, dimension);
    _queryVectors[cacheKey] = vector;
    while (_queryVectors.length > _queryCacheSize) {
      _queryVectors.remove(_queryVectors.keys.first);
    }
    return vector;
  }
}

class SemanticSearchResolvedEvent {
  final String key;

  const new(this.key);
}
