import 'package:flutter/foundation.dart';

// on-device embedding model, mapping text and images in a single vector space
abstract class SemanticEngine {
  // whether this build can run a model at all
  bool get isSupported;

  bool get isLoaded;

  // `backend`: `auto`, `cpu`, `gpu` or `npu`
  Future<void> load({
    required String modelPath,
    required String backend,
  });

  Future<void> unload();

  // vectors are returned as computed by the model, without truncation
  Future<List<Float32List>> embedTexts(List<String> texts);

  // `images`: JPEG or PNG bytes
  // returns `null` for images that could not be embedded
  Future<List<Float32List?>> embedImages(List<Uint8List> images);

  Future<SemanticEngineInfo?> getInfo();
}

@immutable
class SemanticEngineInfo {
  // `null` when no model is loaded
  final String? backend;
  final int? dimension;
  // cf Android `PowerManager.THERMAL_STATUS_*`
  final int? thermalStatus;

  static const _thermalStatusSevere = 3;

  const new({
    required this.backend,
    required this.dimension,
    required this.thermalStatus,
  });

  bool get isThermallyThrottled => (thermalStatus ?? 0) >= _thermalStatusSevere;

  @override
  String toString() => '$runtimeType#${shortHash(this)}{backend=$backend, dimension=$dimension, thermalStatus=$thermalStatus}';
}

class SemanticEngineException implements Exception {
  final String code;
  final String? message;

  const new(this.code, this.message);

  @override
  String toString() => '$runtimeType{code=$code, message=$message}';
}
