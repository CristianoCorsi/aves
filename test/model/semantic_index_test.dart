import 'dart:async';
import 'dart:io';

import 'package:aves/model/filters/covered/stored_album.dart';
import 'package:aves/model/semantic/scope.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/analysis_controller.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves_model/aves_model.dart';
import 'package:aves_semantic/aves_semantic.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common.dart';
import '../fake/availability.dart';
import '../fake/db.dart';
import '../fake/media_fetch_service.dart';
import '../fake/media_store_service.dart';
import '../fake/semantic_engine.dart';
import '../fake/storage_service.dart';

FakeAvesDb get db => localMediaDb as FakeAvesDb;

void main() {
  const albumA = '${FakeStorageService.primaryPath}Pictures/a';
  const albumB = '${FakeStorageService.primaryPath}Pictures/b';
  const modelId = 'model1';

  late Directory tempDir;

  setUpAll(() async {
    await setUpAllServices();
    getIt.registerLazySingleton<SemanticEngine>(FakeSemanticEngine.new);
  });

  setUp(() async {
    await setUpServices();
    tempDir = await Directory.systemTemp.createTemp('aves_semantic_index_test');
    final modelFile = File('${tempDir.path}/model.litertlm');
    await modelFile.writeAsString('fake');

    (availability as FakeAvesAvailability).semanticSupported = true;
    (mediaFetchService as FakeMediaFetchService).thumbnailFailures = {};
    await db.clearSemanticData();
    await semanticEngine.unload();

    settings.semanticEnabled = true;
    settings.semanticModelPath = modelFile.path;
    settings.semanticModelId = modelId;
    settings.semanticPerformanceProfile = SemanticPerformanceProfile.high;
  });

  tearDown(() async => tempDir.delete(recursive: true));

  tearDownAll(() async {
    await tearDownAllServices();
  });

  Future<MediaStoreSource> initSource() async {
    final source = MediaStoreSource();
    final readyCompleter = Completer();
    source.stateNotifier.addListener(() {
      if (source.isReady && !readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
    });
    await source.init(scope: CollectionSource.fullScope);
    await readyCompleter.future;
    return source;
  }

  test('scope selects included albums, minus excluded ones and unsupported items', () {
    final a1 = FakeMediaStoreService.newImage(albumA, 'a1');
    final b1 = FakeMediaStoreService.newImage(albumB, 'b1');
    final trashed = FakeMediaStoreService.newImage(albumA, 'trashed')..trashed = true;

    final selected = SemanticScope(
      scope: SemanticIndexScope.selected,
      included: {StoredAlbumFilter(albumA, null)},
      excluded: {},
      includeVideos: false,
    );
    expect(selected.test(a1), isTrue);
    expect(selected.test(b1), isFalse);
    expect(selected.test(trashed), isFalse);

    final all = SemanticScope(
      scope: SemanticIndexScope.all,
      included: {},
      excluded: {StoredAlbumFilter(albumB, null)},
      includeVideos: false,
    );
    expect(all.test(a1), isTrue);
    expect(all.test(b1), isFalse);
  });

  test('nothing is indexed when disabled', () async {
    settings.semanticEnabled = false;
    settings.semanticIndexScope = SemanticIndexScope.all;
    (mediaStoreService as FakeMediaStoreService).entries = {FakeMediaStoreService.newImage(albumA, 'a1')};

    await initSource();
    expect(db.semanticEmbeddings, isEmpty);
    expect(semanticEngine.isLoaded, isFalse);
  });

  test('nothing is indexed when semantic engine cannot be used', () async {
    (availability as FakeAvesAvailability).semanticSupported = false;
    settings.semanticIndexScope = SemanticIndexScope.all;
    (mediaStoreService as FakeMediaStoreService).entries = {FakeMediaStoreService.newImage(albumA, 'a1')};

    await initSource();
    expect(db.semanticEmbeddings, isEmpty);
  });

  test('indexing covers selected albums, marks failures, and skips up-to-date entries', () async {
    final a1 = FakeMediaStoreService.newImage(albumA, 'a1');
    final a2 = FakeMediaStoreService.newImage(albumA, 'a2');
    final b1 = FakeMediaStoreService.newImage(albumB, 'b1');
    (mediaStoreService as FakeMediaStoreService).entries = {a1, a2, b1};
    (mediaFetchService as FakeMediaFetchService).thumbnailFailures = {a2.uri};
    settings.semanticIndexScope = SemanticIndexScope.selected;
    settings.semanticIncludedAlbums = {StoredAlbumFilter(albumA, null)};

    final source = await initSource();
    // IDs are reassigned when entries are saved
    final idByUri = {for (final entry in source.allEntries) entry.uri: entry.id};
    final a1Id = idByUri[a1.uri]!, a2Id = idByUri[a2.uri]!;
    expect(db.semanticEmbeddings.keys.toSet(), {a1Id, a2Id});
    expect(db.semanticEmbeddings[a1Id]!.isFailure, isFalse);
    expect(db.semanticEmbeddings[a1Id]!.vector.dimension, settings.semanticPerformanceParams.vectorDimension);
    expect(db.semanticEmbeddings[a2Id]!.isFailure, isTrue);

    final engine = semanticEngine as FakeSemanticEngine;
    final countBefore = engine.embeddedImageCount;
    await source.indexSemanticEntries(AnalysisController(), source.allEntries);
    expect(engine.embeddedImageCount, countBefore);

    // modified file is indexed again
    final a1Entry = source.allEntries.firstWhere((entry) => entry.id == a1Id);
    a1Entry.dateModifiedMillis = (a1Entry.dateModifiedMillis ?? 0) + 1000;
    await source.indexSemanticEntries(AnalysisController(), source.allEntries);
    expect(engine.embeddedImageCount, countBefore + 1);

    final matrix = await source.getSemanticMatrix();
    expect(matrix!.ids.toSet(), {a1Id});
  });

  test('vectors of another model or dimension are discarded', () async {
    final a1 = FakeMediaStoreService.newImage(albumA, 'a1');
    (mediaStoreService as FakeMediaStoreService).entries = {a1};
    settings.semanticIndexScope = SemanticIndexScope.all;

    final source = await initSource();
    final a1Id = source.allEntries.single.id;
    expect(db.semanticEmbeddings[a1Id]!.vector.dimension, 512);

    settings.semanticPerformanceProfile = SemanticPerformanceProfile.balanced;
    await source.indexSemanticEntries(AnalysisController(), source.allEntries);
    expect(db.semanticEmbeddings[a1Id]!.vector.dimension, 256);
    expect((await source.getSemanticMatrix())!.dimension, 256);
  });

  test('indexing stops at the configured limit per run', () async {
    final entries = List.generate(5, (i) => FakeMediaStoreService.newImage(albumA, 'item$i')).toSet();
    (mediaStoreService as FakeMediaStoreService).entries = entries;
    settings.semanticIndexScope = SemanticIndexScope.all;
    settings.semanticPerformanceParams = settings.semanticPerformanceParams.copyWith(maxItemsPerRun: 2, itemDelayMillis: 0);

    final source = await initSource();
    expect(db.semanticEmbeddings.length, 2);
    await source.indexSemanticEntries(AnalysisController(), source.allEntries);
    expect(db.semanticEmbeddings.length, 4);
  });
}
