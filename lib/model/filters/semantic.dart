import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/semantic/search.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:flutter/widgets.dart';

// content based search, either from a text query or from a reference item
class SemanticFilter extends CollectionFilter {
  static const type = 'semantic';

  final String? query;
  final int? entryId;
  // label of the reference item, for display only
  final String? entryLabel;

  @override
  List<Object?> get props => [query, entryId, reversed];

  const new query(String this.query, {super.reversed = false}) : entryId = null, entryLabel = null;

  const new similar(int this.entryId, {this.entryLabel, super.reversed = false}) : query = null;

  factory fromMap(Map<String, Object?> json) {
    final query = json['query'] as String?;
    final entryId = json['entryId'] as int?;
    final reversed = json['reversed'] as bool? ?? false;
    if (entryId != null) {
      return SemanticFilter.similar(entryId, entryLabel: json['entryLabel'] as String?, reversed: reversed);
    }
    return SemanticFilter.query(query ?? '', reversed: reversed);
  }

  @override
  Map<String, Object?> toJsonMap() => {
    'type': type,
    if (query != null) 'query': query,
    if (entryId != null) 'entryId': entryId,
    if (entryLabel != null) 'entryLabel': entryLabel,
    if (reversed) 'reversed': reversed,
  };

  @override
  EntryPredicate get positiveTest =>
      (entry) => semanticSearch.contains(this, entry.id);

  @override
  bool get exclusiveProp => true;

  @override
  String get universalLabel => query ?? entryLabel ?? '#$entryId';

  @override
  String getLabel(BuildContext context) => query ?? context.l10n.semanticSimilarToFilterLabel(entryLabel ?? '#$entryId');

  @override
  Widget? iconBuilder(BuildContext context, double size, {bool allowGenericIcon = true}) => Icon(AIcons.semantic, size: size);

  @override
  String get category => type;

  @override
  String get key => '$type-$reversed-${entryId ?? ''}-${query ?? ''}';
}
