import 'package:aves_semantic/aves_semantic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlatformSemanticEngine extends SemanticEngine {
  static const _platform = MethodChannel('deckers.thibault/aves_semantic/engine');

  bool _isLoaded = false;

  @override
  bool get isSupported => true;

  @override
  bool get isLoaded => _isLoaded;

  @override
  Future<void> load({required String modelPath, required String backend}) async {
    try {
      await _platform.invokeMethod('load', <String, Object?>{
        'modelPath': modelPath,
        'backend': backend,
      });
      _isLoaded = true;
    } on PlatformException catch (e) {
      _isLoaded = false;
      throw SemanticEngineException(e.code, e.message);
    }
  }

  @override
  Future<void> unload() async {
    try {
      await _platform.invokeMethod('unload');
    } on PlatformException catch (e) {
      throw SemanticEngineException(e.code, e.message);
    } finally {
      _isLoaded = false;
    }
  }

  @override
  Future<List<Float32List>> embedTexts(List<String> texts) async {
    if (texts.isEmpty) return [];
    final result = await _invokeEmbed('embedTexts', <String, Object?>{'texts': texts});
    return result.map((v) => v ?? Float32List(0)).toList();
  }

  @override
  Future<List<Float32List?>> embedImages(List<Uint8List> images) async {
    if (images.isEmpty) return [];
    return _invokeEmbed('embedImages', <String, Object?>{'images': images});
  }

  Future<List<Float32List?>> _invokeEmbed(String method, Map<String, Object?> arguments) async {
    try {
      final result = await _platform.invokeMethod(method, arguments);
      if (result is List) {
        return result.map((v) => v is Float32List ? v : null).toList();
      }
      throw SemanticEngineException('invalid-result', 'unexpected result type=${result.runtimeType}');
    } on PlatformException catch (e) {
      if (e.code == 'not-loaded') {
        _isLoaded = false;
      }
      throw SemanticEngineException(e.code, e.message);
    }
  }

  @override
  Future<SemanticEngineInfo?> getInfo() async {
    try {
      final result = await _platform.invokeMethod('getInfo');
      if (result is Map) {
        _isLoaded = result['loaded'] == true;
        return SemanticEngineInfo(
          backend: result['backend'] as String?,
          dimension: result['dimension'] as int?,
          thermalStatus: result['thermalStatus'] as int?,
        );
      }
    } on PlatformException catch (e) {
      throw SemanticEngineException(e.code, e.message);
    }
    return null;
  }
}
