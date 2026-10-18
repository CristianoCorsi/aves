import 'package:aves/model/semantic/profile.dart';
import 'package:aves/model/semantic/vector.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/settings/common/tiles/single_selection.dart';
import 'package:aves/widgets/settings/semantic/semantic.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';

class SemanticPerformancePage extends StatelessWidget {
  static const routeName = '/settings/semantic/performance';

  static const List<String> settingKeys = [
    SettingKeys.semanticPerformanceProfileKey,
    SettingKeys.semanticBackendKey,
    SettingKeys.semanticVectorDimensionKey,
    SettingKeys.semanticThumbnailSizeKey,
    SettingKeys.semanticMaxItemsPerRunKey,
    SettingKeys.semanticItemDelayMillisKey,
  ];

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // editing a single parameter switches to the custom profile
    void update(SemanticPerformanceParams Function(SemanticPerformanceParams params) f) {
      settings.semanticPerformanceParams = f(settings.semanticPerformanceParams);
    }

    return AvesScaffold(
      appBar: AppBar(
        title: Text(l10n.settingsSemanticPerformanceTile),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            SettingsSelectionListTile<SemanticPerformanceProfile>(
              values: SemanticPerformanceProfile.values,
              getName: (context, v) => v.getName(context),
              selector: (context, s) => s.semanticPerformanceProfile,
              onSelection: (v) {
                if (v == SemanticPerformanceProfile.custom) {
                  // keep current values as a starting point
                  settings.semanticPerformanceParams = settings.semanticPerformanceParams;
                } else {
                  settings.semanticPerformanceProfile = v;
                }
              },
              tileTitle: (context) => l10n.settingsSemanticProfile,
            ),
            const Divider(),
            SettingsSelectionListTile<SemanticBackend>(
              values: SemanticBackend.values,
              getName: (context, v) => v.getName(context),
              selector: (context, s) => s.semanticPerformanceParams.backend,
              onSelection: (v) => update((params) => params.copyWith(backend: v)),
              tileTitle: (context) => l10n.settingsSemanticBackend,
            ),
            SettingsSelectionListTile<int>(
              values: semanticVectorDimensions,
              getName: (context, v) => '$v',
              selector: (context, s) => s.semanticPerformanceParams.vectorDimension,
              onSelection: (v) => update((params) => params.copyWith(vectorDimension: v)),
              tileTitle: (context) => l10n.settingsSemanticVectorDimension,
              dialogTitle: l10n.settingsSemanticVectorDimensionSubtitle,
            ),
            SettingsSelectionListTile<int>(
              values: SemanticPerformanceParams.thumbnailSizeOptions,
              getName: (context, v) => '$v px',
              selector: (context, s) => s.semanticPerformanceParams.thumbnailSize,
              onSelection: (v) => update((params) => params.copyWith(thumbnailSize: v)),
              tileTitle: (context) => l10n.settingsSemanticThumbnailSize,
            ),
            SettingsSelectionListTile<int>(
              values: SemanticPerformanceParams.maxItemsPerRunOptions,
              getName: (context, v) => '$v',
              selector: (context, s) => s.semanticPerformanceParams.maxItemsPerRun,
              onSelection: (v) => update((params) => params.copyWith(maxItemsPerRun: v)),
              tileTitle: (context) => l10n.settingsSemanticMaxItemsPerRun,
            ),
            SettingsSelectionListTile<int>(
              values: SemanticPerformanceParams.itemDelayMillisOptions,
              getName: (context, v) => '$v ms',
              selector: (context, s) => s.semanticPerformanceParams.itemDelayMillis,
              onSelection: (v) => update((params) => params.copyWith(itemDelayMillis: v)),
              tileTitle: (context) => l10n.settingsSemanticItemDelay,
            ),
          ],
        ),
      ),
    );
  }
}
