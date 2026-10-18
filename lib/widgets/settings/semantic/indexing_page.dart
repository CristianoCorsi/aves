import 'dart:async';

import 'package:aves/model/filters/filters.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/semantic.dart';
import 'package:aves/services/analysis_service.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/buttons/outlined_button.dart';
import 'package:aves/widgets/dialogs/pick_dialogs/album_pick_page.dart';
import 'package:aves/widgets/filter_grids/common/enums.dart';
import 'package:aves/widgets/navigation/drawer/tile.dart';
import 'package:aves/widgets/settings/common/tiles/single_selection.dart';
import 'package:aves/widgets/settings/common/tiles/switch_list.dart';
import 'package:aves/widgets/settings/semantic/semantic.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class SemanticIndexingPage extends StatefulWidget {
  static const routeName = '/settings/semantic/indexing';

  static const List<String> settingKeys = [
    SettingKeys.semanticIndexScopeKey,
    SettingKeys.semanticIncludedAlbumsKey,
    SettingKeys.semanticExcludedAlbumsKey,
    SettingKeys.semanticIndexVideosKey,
    SettingKeys.semanticBackgroundModeKey,
    SettingKeys.semanticRequireIdleKey,
  ];

  const new({super.key});

  @override
  State<SemanticIndexingPage> createState() => _SemanticIndexingPageState();
}

class _SemanticIndexingPageState extends State<SemanticIndexingPage> {
  late Future<(int, int)> _statsLoader;
  StreamSubscription? _indexSubscription;

  CollectionSource get source => context.read<CollectionSource>();

  @override
  void initState() {
    super.initState();
    _statsLoader = source.semanticIndexStats();
    _indexSubscription = source.eventBus.on<SemanticIndexChangedEvent>().listen((_) => _refreshStats());
  }

  @override
  void dispose() {
    _indexSubscription?.cancel();
    super.dispose();
  }

  void _refreshStats() {
    if (!mounted) return;
    setState(() => _statsLoader = source.semanticIndexStats());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesScaffold(
      appBar: AppBar(
        title: Text(l10n.settingsSemanticIndexingTile),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            FutureBuilder<(int, int)>(
              future: _statsLoader,
              builder: (context, snapshot) {
                final stats = snapshot.data;
                return ListTile(
                  title: Text(stats != null ? l10n.settingsSemanticIndexStatus(stats.$1, stats.$2) : ''),
                  subtitle: stats != null && stats.$2 > 0 ? LinearProgressIndicator(value: stats.$1 / stats.$2) : null,
                );
              },
            ),
            ListTile(
              leading: const Icon(AIcons.semantic),
              title: Text(l10n.settingsSemanticIndexNow),
              onTap: _indexNow,
            ),
            ListTile(
              leading: const Icon(AIcons.reset),
              title: Text(l10n.settingsSemanticRebuildIndex),
              onTap: _rebuildIndex,
            ),
            const Divider(),
            SettingsSelectionListTile<SemanticIndexScope>(
              values: SemanticIndexScope.values,
              getName: (context, v) => v.getName(context),
              selector: (context, s) => s.semanticIndexScope,
              onSelection: (v) {
                settings.semanticIndexScope = v;
                _refreshStats();
              },
              tileTitle: (context) => l10n.settingsSemanticIndexScope,
            ),
            Selector<Settings, SemanticIndexScope>(
              selector: (context, s) => s.semanticIndexScope,
              builder: (context, scope, child) {
                if (scope != SemanticIndexScope.selected) return const SizedBox();
                return Selector<Settings, Set<CollectionFilter>>(
                  selector: (context, s) => s.semanticIncludedAlbums,
                  builder: (context, filters, child) => _AlbumListEditor(
                    title: l10n.settingsSemanticIncludedAlbums,
                    filters: filters,
                    onChanged: (v) {
                      settings.semanticIncludedAlbums = v;
                      _refreshStats();
                    },
                  ),
                );
              },
            ),
            Selector<Settings, Set<CollectionFilter>>(
              selector: (context, s) => s.semanticExcludedAlbums,
              builder: (context, filters, child) => _AlbumListEditor(
                title: l10n.settingsSemanticExcludedAlbums,
                filters: filters,
                onChanged: (v) {
                  settings.semanticExcludedAlbums = v;
                  _refreshStats();
                },
              ),
            ),
            SettingsSwitchListTile(
              selector: (context, s) => s.semanticIndexVideos,
              onChanged: (v) {
                settings.semanticIndexVideos = v;
                _refreshStats();
              },
              title: (context) => l10n.settingsSemanticIndexVideos,
            ),
            const Divider(),
            SettingsSelectionListTile<SemanticBackgroundMode>(
              values: SemanticBackgroundMode.values,
              getName: (context, v) => v.getName(context),
              selector: (context, s) => s.semanticBackgroundMode,
              onSelection: (v) => settings.semanticBackgroundMode = v,
              tileTitle: (context) => l10n.settingsSemanticBackgroundMode,
            ),
            Selector<Settings, SemanticBackgroundMode>(
              selector: (context, s) => s.semanticBackgroundMode,
              builder: (context, mode, child) {
                if (mode == SemanticBackgroundMode.off) return const SizedBox();
                return SettingsSwitchListTile(
                  selector: (context, s) => s.semanticRequireIdle,
                  onChanged: (v) => settings.semanticRequireIdle = v,
                  title: (context) => l10n.settingsSemanticRequireIdle,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // indexing runs within the analysis service, so that it can go on when the app is in the background
  Future<void> _indexNow() async {
    if (!source.isSemanticReady) return;
    await AnalysisService.startService(force: false);
  }

  Future<void> _rebuildIndex() async {
    if (!source.isSemanticReady) return;
    await source.clearSemanticIndex();
    _refreshStats();
    await AnalysisService.startService(force: false);
  }
}

class _AlbumListEditor extends StatelessWidget {
  final String title;
  final Set<CollectionFilter> filters;
  final ValueChanged<Set<CollectionFilter>> onChanged;

  const new({
    required this.title,
    required this.filters,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sortedFilters = filters.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(title),
          subtitle: sortedFilters.isEmpty ? Text(l10n.settingsSemanticNoAlbum) : null,
        ),
        ...sortedFilters.map(
          (filter) => ListTile(
            key: ValueKey(filter.key),
            leading: DrawerFilterIcon(filter: filter),
            title: DrawerFilterTitle(filter: filter),
            trailing: IconButton(
              icon: const Icon(AIcons.clear),
              onPressed: () => onChanged({...filters}..remove(filter)),
              tooltip: l10n.actionRemove,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: AvesOutlinedButton(
              icon: const Icon(AIcons.add),
              label: l10n.settingsSemanticAddAlbum,
              onPressed: () async {
                final albumFilter = await pickAlbum(
                  context: context,
                  moveType: null,
                  chipTypes: AlbumChipType.values.toSet(),
                  initialGroup: null,
                );
                if (albumFilter == null || filters.contains(albumFilter)) return;
                onChanged({...filters, albumFilter});
              },
            ),
          ),
        ),
      ],
    );
  }
}
