import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/semantic/profile.dart';
import 'package:aves/model/settings/defaults.dart';
import 'package:aves_model/aves_model.dart';

mixin SemanticSettings on SettingsAccess {
  bool get semanticEnabled => getBool(SettingKeys.semanticEnabledKey) ?? SettingsDefaults.semanticEnabled;

  set semanticEnabled(bool newValue) => set(SettingKeys.semanticEnabledKey, newValue);

  // model

  String? get semanticModelPath => getString(SettingKeys.semanticModelPathKey);

  set semanticModelPath(String? newValue) => set(SettingKeys.semanticModelPathKey, newValue);

  String? get semanticModelId => getString(SettingKeys.semanticModelIdKey);

  set semanticModelId(String? newValue) => set(SettingKeys.semanticModelIdKey, newValue);

  bool get semanticDownloadWifiOnly => getBool(SettingKeys.semanticDownloadWifiOnlyKey) ?? SettingsDefaults.semanticDownloadWifiOnly;

  set semanticDownloadWifiOnly(bool newValue) => set(SettingKeys.semanticDownloadWifiOnlyKey, newValue);

  // indexing scope

  SemanticIndexScope get semanticIndexScope => getEnumOrDefault(SettingKeys.semanticIndexScopeKey, SettingsDefaults.semanticIndexScope, SemanticIndexScope.values);

  set semanticIndexScope(SemanticIndexScope newValue) => set(SettingKeys.semanticIndexScopeKey, newValue.name);

  Set<CollectionFilter> get semanticIncludedAlbums => _getFilters(SettingKeys.semanticIncludedAlbumsKey);

  set semanticIncludedAlbums(Set<CollectionFilter> newValue) => _setFilters(SettingKeys.semanticIncludedAlbumsKey, newValue);

  Set<CollectionFilter> get semanticExcludedAlbums => _getFilters(SettingKeys.semanticExcludedAlbumsKey);

  set semanticExcludedAlbums(Set<CollectionFilter> newValue) => _setFilters(SettingKeys.semanticExcludedAlbumsKey, newValue);

  bool get semanticIndexVideos => getBool(SettingKeys.semanticIndexVideosKey) ?? SettingsDefaults.semanticIndexVideos;

  set semanticIndexVideos(bool newValue) => set(SettingKeys.semanticIndexVideosKey, newValue);

  // background indexing

  SemanticBackgroundMode get semanticBackgroundMode => getEnumOrDefault(SettingKeys.semanticBackgroundModeKey, SettingsDefaults.semanticBackgroundMode, SemanticBackgroundMode.values);

  set semanticBackgroundMode(SemanticBackgroundMode newValue) => set(SettingKeys.semanticBackgroundModeKey, newValue.name);

  bool get semanticRequireIdle => getBool(SettingKeys.semanticRequireIdleKey) ?? SettingsDefaults.semanticRequireIdle;

  set semanticRequireIdle(bool newValue) => set(SettingKeys.semanticRequireIdleKey, newValue);

  // performance

  SemanticPerformanceProfile get semanticPerformanceProfile => getEnumOrDefault(SettingKeys.semanticPerformanceProfileKey, SettingsDefaults.semanticPerformanceProfile, SemanticPerformanceProfile.values);

  set semanticPerformanceProfile(SemanticPerformanceProfile newValue) => set(SettingKeys.semanticPerformanceProfileKey, newValue.name);

  // effective parameters, from the selected profile or from custom values
  SemanticPerformanceParams get semanticPerformanceParams {
    final preset = SemanticPerformanceParams.forProfile(semanticPerformanceProfile);
    if (preset != null) return preset;

    const base = SemanticPerformanceParams.defaults;
    return SemanticPerformanceParams(
      backend: getEnumOrDefault(SettingKeys.semanticBackendKey, base.backend, SemanticBackend.values),
      vectorDimension: getInt(SettingKeys.semanticVectorDimensionKey) ?? base.vectorDimension,
      thumbnailSize: getInt(SettingKeys.semanticThumbnailSizeKey) ?? base.thumbnailSize,
      maxItemsPerRun: getInt(SettingKeys.semanticMaxItemsPerRunKey) ?? base.maxItemsPerRun,
      itemDelayMillis: getInt(SettingKeys.semanticItemDelayMillisKey) ?? base.itemDelayMillis,
    );
  }

  // switches to the custom profile, starting from the current effective parameters
  set semanticPerformanceParams(SemanticPerformanceParams newValue) {
    semanticPerformanceProfile = SemanticPerformanceProfile.custom;
    set(SettingKeys.semanticBackendKey, newValue.backend.name);
    set(SettingKeys.semanticVectorDimensionKey, newValue.vectorDimension);
    set(SettingKeys.semanticThumbnailSizeKey, newValue.thumbnailSize);
    set(SettingKeys.semanticMaxItemsPerRunKey, newValue.maxItemsPerRun);
    set(SettingKeys.semanticItemDelayMillisKey, newValue.itemDelayMillis);
  }

  // search

  int get semanticMaxResults => getInt(SettingKeys.semanticMaxResultsKey) ?? SettingsDefaults.semanticMaxResults;

  set semanticMaxResults(int newValue) => set(SettingKeys.semanticMaxResultsKey, newValue);

  double get semanticMinSimilarity => getDouble(SettingKeys.semanticMinSimilarityKey) ?? SettingsDefaults.semanticMinSimilarity;

  set semanticMinSimilarity(double newValue) => set(SettingKeys.semanticMinSimilarityKey, newValue);

  bool get semanticSearchByDefault => getBool(SettingKeys.semanticSearchByDefaultKey) ?? SettingsDefaults.semanticSearchByDefault;

  set semanticSearchByDefault(bool newValue) => set(SettingKeys.semanticSearchByDefaultKey, newValue);

  bool get semanticSortByRelevance => getBool(SettingKeys.semanticSortByRelevanceKey) ?? SettingsDefaults.semanticSortByRelevance;

  set semanticSortByRelevance(bool newValue) => set(SettingKeys.semanticSortByRelevanceKey, newValue);

  // auto tagging

  bool get semanticAutoTagEnabled => getBool(SettingKeys.semanticAutoTagEnabledKey) ?? SettingsDefaults.semanticAutoTagEnabled;

  set semanticAutoTagEnabled(bool newValue) => set(SettingKeys.semanticAutoTagEnabledKey, newValue);

  bool get semanticAutoTagShowAsTags => getBool(SettingKeys.semanticAutoTagShowAsTagsKey) ?? SettingsDefaults.semanticAutoTagShowAsTags;

  set semanticAutoTagShowAsTags(bool newValue) => set(SettingKeys.semanticAutoTagShowAsTagsKey, newValue);

  int get semanticAutoTagMaxPerItem => getInt(SettingKeys.semanticAutoTagMaxPerItemKey) ?? SettingsDefaults.semanticAutoTagMaxPerItem;

  set semanticAutoTagMaxPerItem(int newValue) => set(SettingKeys.semanticAutoTagMaxPerItemKey, newValue);

  double get semanticAutoTagThreshold => getDouble(SettingKeys.semanticAutoTagThresholdKey) ?? SettingsDefaults.semanticAutoTagThreshold;

  set semanticAutoTagThreshold(double newValue) => set(SettingKeys.semanticAutoTagThresholdKey, newValue);

  List<String> get semanticAutoTagCustomLabels => getStringList(SettingKeys.semanticAutoTagCustomLabelsKey) ?? [];

  set semanticAutoTagCustomLabels(List<String> newValue) => set(SettingKeys.semanticAutoTagCustomLabelsKey, newValue);

  // utils

  Set<CollectionFilter> _getFilters(String key) => (getStringList(key) ?? []).map(CollectionFilter.fromJson).nonNulls.toSet();

  void _setFilters(String key, Set<CollectionFilter> filters) => set(key, filters.map((filter) => filter.toJsonString()).toList());
}
