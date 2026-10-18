import 'package:aves/model/entry/entry.dart';
import 'package:aves/model/entry/extensions/props.dart';
import 'package:aves/model/entry/origins.dart';
import 'package:aves/model/filters/filters.dart';
import 'package:aves_model/aves_model.dart';

// which entries should be semantically indexed
class SemanticScope {
  final SemanticIndexScope scope;
  final Set<CollectionFilter> included, excluded;
  final bool includeVideos;

  new({
    required this.scope,
    required this.included,
    required this.excluded,
    required this.includeVideos,
  });

  bool test(AvesEntry entry) {
    // vault items are kept out of the index, for privacy
    if (entry.trashed || entry.origin == EntryOrigins.vault) return false;
    if (entry.isVideo) {
      if (!includeVideos) return false;
    } else if (!entry.isImage) {
      return false;
    }
    if (excluded.any((filter) => filter.test(entry))) return false;
    return switch (scope) {
      SemanticIndexScope.all => true,
      SemanticIndexScope.selected => included.any((filter) => filter.test(entry)),
    };
  }
}
