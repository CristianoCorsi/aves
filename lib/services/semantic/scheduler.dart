import 'package:aves/model/settings/settings.dart';
import 'package:aves/services/analysis_service.dart';
import 'package:aves/services/common/services.dart';
import 'package:aves/services/semantic/model_service.dart';
import 'package:aves_model/aves_model.dart';

class SemanticScheduler {
  static const _settingKeys = {
    SettingKeys.semanticEnabledKey,
    SettingKeys.semanticModelIdKey,
    SettingKeys.semanticBackgroundModeKey,
    SettingKeys.semanticRequireIdleKey,
  };

  static bool isSchedulingKey(String key) => _settingKeys.contains(key);

  // periodic background indexing is only scheduled when it can be useful
  static Future<SemanticBackgroundMode> effectiveMode() async {
    if (!settings.semanticEnabled || !semanticModels.isInstalled) return SemanticBackgroundMode.off;
    if (!await availability.canUseSemantic) return SemanticBackgroundMode.off;
    return settings.semanticBackgroundMode;
  }

  static Future<void> update() async {
    await AnalysisService.schedulePeriodicAnalysis(
      mode: await effectiveMode(),
      requireIdle: settings.semanticRequireIdle,
    );
  }
}
