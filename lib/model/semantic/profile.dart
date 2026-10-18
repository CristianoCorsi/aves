import 'package:aves_model/aves_model.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

// resource related parameters for semantic indexing,
// either from a preset profile or customized by the user
@immutable
class SemanticPerformanceParams extends Equatable {
  final SemanticBackend backend;
  final int vectorDimension;
  final int thumbnailSize;
  final int maxItemsPerRun;
  final int itemDelayMillis;

  @override
  List<Object?> get props => [backend, vectorDimension, thumbnailSize, maxItemsPerRun, itemDelayMillis];

  const new({
    required this.backend,
    required this.vectorDimension,
    required this.thumbnailSize,
    required this.maxItemsPerRun,
    required this.itemDelayMillis,
  });

  SemanticPerformanceParams copyWith({
    SemanticBackend? backend,
    int? vectorDimension,
    int? thumbnailSize,
    int? maxItemsPerRun,
    int? itemDelayMillis,
  }) => SemanticPerformanceParams(
    backend: backend ?? this.backend,
    vectorDimension: vectorDimension ?? this.vectorDimension,
    thumbnailSize: thumbnailSize ?? this.thumbnailSize,
    maxItemsPerRun: maxItemsPerRun ?? this.maxItemsPerRun,
    itemDelayMillis: itemDelayMillis ?? this.itemDelayMillis,
  );

  static const low = SemanticPerformanceParams(
    backend: SemanticBackend.cpu,
    vectorDimension: 256,
    thumbnailSize: 256,
    maxItemsPerRun: 200,
    itemDelayMillis: 200,
  );

  static const balanced = SemanticPerformanceParams(
    backend: SemanticBackend.auto,
    vectorDimension: 256,
    thumbnailSize: 384,
    maxItemsPerRun: 500,
    itemDelayMillis: 50,
  );

  static const high = SemanticPerformanceParams(
    backend: SemanticBackend.auto,
    vectorDimension: 512,
    thumbnailSize: 512,
    maxItemsPerRun: 2000,
    itemDelayMillis: 0,
  );

  // used as base for custom values
  static const defaults = balanced;

  static SemanticPerformanceParams? forProfile(SemanticPerformanceProfile profile) {
    return switch (profile) {
      SemanticPerformanceProfile.low => low,
      SemanticPerformanceProfile.balanced => balanced,
      SemanticPerformanceProfile.high => high,
      SemanticPerformanceProfile.custom => null,
    };
  }

  static const thumbnailSizeOptions = [224, 256, 384, 512, 768];
  static const maxItemsPerRunOptions = [100, 200, 500, 1000, 2000, 5000];
  static const itemDelayMillisOptions = [0, 50, 100, 200, 500, 1000];

  // RAM thresholds, as the model (~0.5 GB) runs next to the app
  static const minRamBytes = 3 * _gb;
  static const _gb = 1024 * 1024 * 1024;

  static SemanticPerformanceProfile recommendedProfile({
    required int totalRamBytes,
    required int mediaPerformanceClass,
  }) {
    if (totalRamBytes >= 8 * _gb && mediaPerformanceClass >= 33) return SemanticPerformanceProfile.high;
    if (totalRamBytes >= 6 * _gb) return SemanticPerformanceProfile.balanced;
    return SemanticPerformanceProfile.low;
  }
}
