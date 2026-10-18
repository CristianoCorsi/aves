import 'dart:async';

import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/semantic/model_service.dart';
import 'package:aves/theme/colors.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/settings/common/tile_leading.dart';
import 'package:aves/widgets/settings/common/tiles/single_selection.dart';
import 'package:aves/widgets/settings/common/tiles/sub_page.dart';
import 'package:aves/widgets/settings/common/tiles/switch_list.dart';
import 'package:aves/widgets/settings/semantic/auto_tag_page.dart';
import 'package:aves/widgets/settings/semantic/indexing_page.dart';
import 'package:aves/widgets/settings/semantic/model_page.dart';
import 'package:aves/widgets/settings/semantic/performance_page.dart';
import 'package:aves/widgets/settings/settings_definition.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class SemanticSection extends SettingsSection {
  @override
  String get key => 'semantic';

  @override
  Widget icon(BuildContext context) => SettingsTileLeading(
    icon: AIcons.semantic,
    color: context.select<AvesColorsData, Color>((v) => v.semantic),
  );

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticSectionTitle;

  @override
  Future<List<SettingsTile>> tiles(BuildContext context) async {
    if (!await availability.canUseSemantic) {
      return [SettingsTileSemanticUnavailable()];
    }
    semanticModels.refreshStatus();
    return [
      SettingsTileSemanticEnabled(),
      SettingsTileSemanticModel(),
      SettingsTileSemanticIndexing(),
      SettingsTileSemanticPerformance(),
      SettingsTileSemanticMaxResults(),
      SettingsTileSemanticMinSimilarity(),
      SettingsTileSemanticSearchByDefault(),
      SettingsTileSemanticAutoTag(),
    ];
  }
}

class SettingsTileSemanticUnavailable extends SettingsTile {
  @override
  List<String> get settingKeys => [];

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticEnable;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title(context)),
    subtitle: Text(context.l10n.settingsSemanticUnavailable),
    enabled: false,
  );
}

class SettingsTileSemanticEnabled extends SettingsTile {
  @override
  List<String> get settingKeys => [SettingKeys.semanticEnabledKey];

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticEnable;

  @override
  Widget build(BuildContext context) => SettingsSwitchListTile(
    selector: (context, s) => s.semanticEnabled,
    onChanged: (v) => settings.semanticEnabled = v,
    title: title,
    subtitle: (context) => context.l10n.settingsSemanticEnableSubtitle,
  );
}

class SettingsTileSemanticModel extends SettingsTile {
  @override
  List<String> get settingKeys => SemanticModelPage.settingKeys;

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticModelTile;

  @override
  Widget build(BuildContext context) => SettingsSubPageTile(
    title: title,
    subtitle: (context) => ValueListenableBuilder<SemanticModelStatus>(
      valueListenable: semanticModels.statusNotifier,
      builder: (context, status, child) => Text(status.getName(context)),
    ),
    routeName: SemanticModelPage.routeName,
    builder: (context) => const SemanticModelPage(),
  );
}

class SettingsTileSemanticIndexing extends SettingsTile {
  @override
  List<String> get settingKeys => SemanticIndexingPage.settingKeys;

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticIndexingTile;

  @override
  Widget build(BuildContext context) => SettingsSubPageTile(
    title: title,
    routeName: SemanticIndexingPage.routeName,
    builder: (context) => const SemanticIndexingPage(),
  );
}

class SettingsTileSemanticPerformance extends SettingsTile {
  @override
  List<String> get settingKeys => SemanticPerformancePage.settingKeys;

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticPerformanceTile;

  @override
  Widget build(BuildContext context) => SettingsSubPageTile(
    title: title,
    subtitle: (context) => Selector<Settings, SemanticPerformanceProfile>(
      selector: (context, s) => s.semanticPerformanceProfile,
      builder: (context, profile, child) => Text(profile.getName(context)),
    ),
    routeName: SemanticPerformancePage.routeName,
    builder: (context) => const SemanticPerformancePage(),
  );
}

class SettingsTileSemanticMaxResults extends SettingsTile {
  static const options = [50, 100, 200, 500, 1000, 2000];

  @override
  List<String> get settingKeys => [SettingKeys.semanticMaxResultsKey];

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticMaxResults;

  @override
  Widget build(BuildContext context) => SettingsSelectionListTile<int>(
    values: options,
    getName: (context, v) => '$v',
    selector: (context, s) => s.semanticMaxResults,
    onSelection: (v) => settings.semanticMaxResults = v,
    tileTitle: title,
  );
}

class SettingsTileSemanticMinSimilarity extends SettingsTile {
  static const options = [.0, .1, .15, .2, .25, .3, .4, .5];

  @override
  List<String> get settingKeys => [SettingKeys.semanticMinSimilarityKey];

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticMinSimilarity;

  @override
  Widget build(BuildContext context) => SettingsSelectionListTile<double>(
    values: options,
    getName: (context, v) => v.toStringAsFixed(2),
    selector: (context, s) => s.semanticMinSimilarity,
    onSelection: (v) => settings.semanticMinSimilarity = v,
    tileTitle: title,
  );
}

class SettingsTileSemanticSearchByDefault extends SettingsTile {
  @override
  List<String> get settingKeys => [SettingKeys.semanticSearchByDefaultKey];

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticSearchByDefault;

  @override
  Widget build(BuildContext context) => SettingsSwitchListTile(
    selector: (context, s) => s.semanticSearchByDefault,
    onChanged: (v) => settings.semanticSearchByDefault = v,
    title: title,
  );
}

class SettingsTileSemanticAutoTag extends SettingsTile {
  @override
  List<String> get settingKeys => SemanticAutoTagPage.settingKeys;

  @override
  String title(BuildContext context) => context.l10n.settingsSemanticAutoTagTile;

  @override
  Widget build(BuildContext context) => SettingsSubPageTile(
    title: title,
    routeName: SemanticAutoTagPage.routeName,
    builder: (context) => const SemanticAutoTagPage(),
  );
}

extension ExtraSemanticModelStatusView on SemanticModelStatus {
  String getName(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      SemanticModelStatus.absent => l10n.settingsSemanticModelStatusAbsent,
      SemanticModelStatus.downloading => l10n.settingsSemanticModelStatusDownloading,
      SemanticModelStatus.verifying => l10n.settingsSemanticModelStatusVerifying,
      SemanticModelStatus.installed => l10n.settingsSemanticModelStatusInstalled,
    };
  }
}

extension ExtraSemanticPerformanceProfileView on SemanticPerformanceProfile {
  String getName(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      SemanticPerformanceProfile.low => l10n.settingsSemanticProfileLow,
      SemanticPerformanceProfile.balanced => l10n.settingsSemanticProfileBalanced,
      SemanticPerformanceProfile.high => l10n.settingsSemanticProfileHigh,
      SemanticPerformanceProfile.custom => l10n.settingsSemanticProfileCustom,
    };
  }
}

extension ExtraSemanticBackendView on SemanticBackend {
  String getName(BuildContext context) {
    return switch (this) {
      SemanticBackend.auto => context.l10n.settingsSemanticBackendAuto,
      SemanticBackend.cpu => 'CPU',
      SemanticBackend.gpu => 'GPU',
      SemanticBackend.npu => 'NPU',
    };
  }
}

extension ExtraSemanticBackgroundModeView on SemanticBackgroundMode {
  String getName(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      SemanticBackgroundMode.off => l10n.settingsSemanticBackgroundModeOff,
      SemanticBackgroundMode.whileCharging => l10n.settingsSemanticBackgroundModeWhileCharging,
      SemanticBackgroundMode.always => l10n.settingsSemanticBackgroundModeAlways,
    };
  }
}

extension ExtraSemanticIndexScopeView on SemanticIndexScope {
  String getName(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      SemanticIndexScope.all => l10n.settingsSemanticIndexScopeAll,
      SemanticIndexScope.selected => l10n.settingsSemanticIndexScopeSelected,
    };
  }
}
