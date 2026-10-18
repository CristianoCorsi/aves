import 'package:aves_semantic/aves_semantic.dart';
import 'package:flutter/foundation.dart';

class PlatformSemanticEngine extends SemanticEngine {
  static const _unsupported = SemanticEngineException('unsupported', 'semantic engine is not available in this build');

  @override
  bool get isSupported => false;

  @override
  bool get isLoaded => false;

  @override
  Future<void> load({required String modelPath, required String backend}) => Future.error(_unsupported);

  @override
  Future<void> unload() => SynchronousFuture(null);

  @override
  Future<List<Float32List>> embedTexts(List<String> texts) => Future.error(_unsupported);

  @override
  Future<List<Float32List?>> embedImages(List<Uint8List> images) => Future.error(_unsupported);

  @override
  Future<SemanticEngineInfo?> getInfo() => SynchronousFuture(null);
}
