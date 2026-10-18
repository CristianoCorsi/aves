import 'dart:typed_data';

import 'package:aves_semantic/aves_semantic.dart';
import 'package:test/fake.dart';

// maps inputs to one-hot vectors, so that similarity is predictable:
// image bytes `[n]` and text `'n'` both map to dimension `n`
class FakeSemanticEngine extends Fake implements SemanticEngine {
  static const dimension = 768;

  bool _isLoaded = false;
  int embeddedImageCount = 0;

  @override
  bool get isSupported => true;

  @override
  bool get isLoaded => _isLoaded;

  @override
  Future<void> load({required String modelPath, required String backend}) async => _isLoaded = true;

  @override
  Future<void> unload() async => _isLoaded = false;

  @override
  Future<List<Float32List>> embedTexts(List<String> texts) async => texts.map((text) => _oneHot(int.tryParse(text.split(' ').last) ?? 0)).toList();

  @override
  Future<List<Float32List?>> embedImages(List<Uint8List> images) async {
    embeddedImageCount += images.length;
    return images.map((bytes) => _oneHot(bytes.first)).toList();
  }

  @override
  Future<SemanticEngineInfo?> getInfo() async => const SemanticEngineInfo(backend: 'cpu', dimension: dimension, thermalStatus: 0);

  Float32List _oneHot(int index) => Float32List(dimension)..[index % dimension] = 1;
}
