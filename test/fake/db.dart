import 'package:aves/model/covers.dart';
import 'package:aves/model/db/db.dart';
import 'package:aves/model/dynamic_albums.dart';
import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/favourites.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/metadata/address.dart';
import 'package:aves/model/metadata/catalog.dart';
import 'package:aves/model/metadata/trash.dart';
import 'package:aves/model/semantic/rows.dart';
import 'package:aves/model/vaults/details.dart';
import 'package:flutter/foundation.dart';
import 'package:test/fake.dart';

class FakeAvesDb extends Fake implements LocalMediaDb {
  static int _lastId = 0;

  @override
  int get nextId => ++_lastId;

  @override
  Future<void> init() => SynchronousFuture(null);

  @override
  Future<void> removeIds(Set<int> ids, {Set<EntryDataType>? dataTypes}) => SynchronousFuture(null);

  // entries

  @override
  Future<Set<AvesEntry>> loadEntries({int? origin, String? directory}) => SynchronousFuture({});

  @override
  Future<void> insertEntries(Set<AvesEntry> entries) => SynchronousFuture(null);

  @override
  Future<void> updateEntry(int id, AvesEntry entry) => SynchronousFuture(null);

  @override
  Future<Set<AvesEntry>> searchLiveDuplicates(int origin, Set<AvesEntry>? entries) => SynchronousFuture({});

  // date taken

  @override
  Future<void> clearDates() => SynchronousFuture(null);

  @override
  Future<void> clearDatesWithoutTimeZone() => SynchronousFuture(null);

  @override
  Future<Map<int, DateAndZone>> loadDates() => SynchronousFuture({});

  // catalog metadata

  @override
  Future<void> clearCatalogMetadata() => SynchronousFuture(null);

  @override
  Future<void> clearCatalogMetadataWithoutTimeZone() => SynchronousFuture(null);

  @override
  Future<Set<CatalogMetadata>> loadCatalogMetadata() => SynchronousFuture({});

  @override
  Future<void> saveCatalogMetadata(Set<CatalogMetadata> metadataEntries) => SynchronousFuture(null);

  @override
  Future<void> updateCatalogMetadata(int id, CatalogMetadata? metadata) => SynchronousFuture(null);

  // address

  @override
  Future<Set<AddressDetails>> loadAddresses() => SynchronousFuture({});

  @override
  Future<void> saveAddresses(Set<AddressDetails> addresses) => SynchronousFuture(null);

  @override
  Future<void> updateAddress(int id, AddressDetails? address) => SynchronousFuture(null);

  // vaults

  @override
  Future<Set<VaultDetails>> loadAllVaults() => SynchronousFuture({});

  // trash

  @override
  Future<void> clearTrashDetails() => SynchronousFuture(null);

  @override
  Future<Set<TrashDetails>> loadAllTrashDetails() => SynchronousFuture({});

  @override
  Future<void> updateTrash(int id, TrashDetails? details) => SynchronousFuture(null);

  // favourites

  @override
  Future<Set<FavouriteRow>> loadAllFavourites() => SynchronousFuture({});

  @override
  Future<void> addFavourites(Set<FavouriteRow> rows) => SynchronousFuture(null);

  @override
  Future<void> updateFavouriteId(int id, FavouriteRow row) => SynchronousFuture(null);

  @override
  Future<void> removeFavourites(Set<FavouriteRow> rows) => SynchronousFuture(null);

  // covers

  @override
  Future<Set<CoverRow>> loadAllCovers() => SynchronousFuture({});

  @override
  Future<void> addCovers(Set<CoverRow> rows) => SynchronousFuture(null);

  @override
  Future<void> updateCoverEntryId(int id, CoverRow row) => SynchronousFuture(null);

  @override
  Future<void> removeCovers(Set<CollectionFilter> filters) => SynchronousFuture(null);

  @override
  Future<Set<DynamicAlbumRow>> loadAllDynamicAlbums() => SynchronousFuture({});

  // dynamic albums

  @override
  Future<int> clearDynamicAlbums() => SynchronousFuture(0);

  @override
  Future<void> addDynamicAlbums(Set<DynamicAlbumRow> rows) => SynchronousFuture(null);

  @override
  Future<void> removeDynamicAlbums(Set<String> names) => SynchronousFuture(null);

  // video playback

  @override
  Future<void> removeVideoPlayback(Set<int> ids) => SynchronousFuture(null);

  // semantic

  final Map<int, SemanticEmbeddingRow> semanticEmbeddings = {};
  final Map<int, Set<SemanticTagRow>> semanticTags = {};

  @override
  Future<void> clearSemanticData() {
    semanticEmbeddings.clear();
    semanticTags.clear();
    return SynchronousFuture(null);
  }

  @override
  Future<Map<int, int?>> loadSemanticIndexState(String modelId, int dimension) => SynchronousFuture({
    for (final row in semanticEmbeddings.values.where((v) => v.modelId == modelId && (v.vector.dimension == dimension || v.isFailure))) row.id: row.dateModifiedMillis,
  });

  @override
  Future<List<SemanticEmbeddingRow>> loadSemanticEmbeddings(String modelId, int dimension, {Set<int>? ids}) => SynchronousFuture(
    semanticEmbeddings.values.where((v) => v.modelId == modelId && v.vector.dimension == dimension && (ids == null || ids.contains(v.id))).toList(),
  );

  @override
  Future<void> saveSemanticEmbeddings(Set<SemanticEmbeddingRow> rows) {
    rows.forEach((row) => semanticEmbeddings[row.id] = row);
    return SynchronousFuture(null);
  }

  @override
  Future<int> removeObsoleteSemanticEmbeddings(String modelId, int dimension) {
    final before = semanticEmbeddings.length;
    semanticEmbeddings.removeWhere((_, v) => v.modelId != modelId || (v.vector.dimension != dimension && !v.isFailure));
    return SynchronousFuture(before - semanticEmbeddings.length);
  }

  @override
  Future<List<SemanticTagRow>> loadSemanticTags({Set<int>? ids}) => SynchronousFuture(
    semanticTags.entries.where((kv) => ids == null || ids.contains(kv.key)).expand((kv) => kv.value).toList(),
  );

  @override
  Future<void> replaceSemanticTags(Set<int> ids, Set<SemanticTagRow> rows) {
    ids.forEach(semanticTags.remove);
    rows.forEach((row) => semanticTags.putIfAbsent(row.id, () => {}).add(row));
    return SynchronousFuture(null);
  }

  @override
  Future<void> removeSemanticTag(int id, String tag) {
    semanticTags[id]?.removeWhere((row) => row.tag == tag);
    return SynchronousFuture(null);
  }

  @override
  Future<void> clearSemanticTags() {
    semanticTags.clear();
    return SynchronousFuture(null);
  }

  @override
  Future<List<SemanticLabelRow>> loadSemanticLabels(String modelId, int dimension) => SynchronousFuture([]);

  @override
  Future<void> saveSemanticLabels(Set<SemanticLabelRow> rows) => SynchronousFuture(null);
}
