import 'dart:async';

import 'package:aves/services/semantic/model_manager.dart';
import 'package:aves/services/semantic/model_service.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/widgets/common/action_mixins/feedback.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/dialogs/aves_confirmation_dialog.dart';
import 'package:aves/widgets/settings/common/tiles/switch_list.dart';
import 'package:aves/widgets/settings/semantic/semantic.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:provider/provider.dart';

class SemanticModelPage extends StatelessWidget with FeedbackMixin {
  static const routeName = '/settings/semantic/model';

  static const List<String> settingKeys = [
    SettingKeys.semanticDownloadWifiOnlyKey,
  ];

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesScaffold(
      appBar: AppBar(
        title: Text(l10n.settingsSemanticModelTile),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<SemanticModelStatus>(
          valueListenable: semanticModels.statusNotifier,
          builder: (context, status, child) {
            final busy = status == SemanticModelStatus.downloading || status == SemanticModelStatus.verifying;
            return ListView(
              children: [
                ListTile(
                  title: Text(status.getName(context)),
                  subtitle: Text(l10n.settingsSemanticModelDescription),
                ),
                if (busy)
                  ValueListenableBuilder<SemanticDownloadProgress?>(
                    valueListenable: semanticModels.progressNotifier,
                    builder: (context, progress, child) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: LinearProgressIndicator(value: status == SemanticModelStatus.downloading ? progress?.ratio : null),
                      );
                    },
                  ),
                if (status == SemanticModelStatus.downloading)
                  ListTile(
                    leading: const Icon(AIcons.clear),
                    title: Text(l10n.settingsSemanticModelCancelDownload),
                    onTap: semanticModels.cancelDownload,
                  ),
                if (status == SemanticModelStatus.absent) ...[
                  FutureBuilder<bool>(
                    future: semanticModels.hasPartialDownload,
                    builder: (context, snapshot) {
                      final resume = snapshot.data ?? false;
                      return ListTile(
                        leading: const Icon(AIcons.download),
                        title: Text(resume ? l10n.settingsSemanticModelResumeDownload : l10n.settingsSemanticModelDownload),
                        onTap: () => _download(context),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(AIcons.fileImport),
                    title: Text(l10n.settingsSemanticModelImport),
                    onTap: () => _import(context),
                  ),
                ],
                if (status == SemanticModelStatus.installed)
                  ListTile(
                    leading: const Icon(AIcons.delete),
                    title: Text(l10n.settingsSemanticModelDelete),
                    onTap: () => _delete(context),
                  ),
                SettingsSwitchListTile(
                  selector: (context, s) => s.semanticDownloadWifiOnly,
                  onChanged: (v) => settings.semanticDownloadWifiOnly = v,
                  title: (context) => l10n.settingsSemanticModelDownloadWifiOnly,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await semanticModels.download();
    } on SemanticDownloadCancelledException {
      // nothing to report
    } on SemanticNoUnmeteredNetworkException {
      if (context.mounted) {
        showFeedbackWithMessenger(context, messenger, FeedbackType.warn, l10n.settingsSemanticModelNoUnmeteredNetwork);
      }
    } catch (error) {
      debugPrint('semantic model download failed with error=$error');
      if (context.mounted) {
        showFeedbackWithMessenger(context, messenger, FeedbackType.warn, l10n.settingsSemanticModelDownloadFailed);
      }
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      await semanticModels.import();
    } catch (error) {
      debugPrint('semantic model import failed with error=$error');
      if (context.mounted) {
        showFeedback(context, FeedbackType.warn, context.l10n.genericFailureFeedback);
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    if (!await showConfirmationDialog(
      context: context,
      message: context.l10n.settingsSemanticModelDeleteConfirmationMessage,
      ok: context.l10n.deleteButtonLabel,
    )) {
      return;
    }
    if (!context.mounted) return;

    final source = context.read<CollectionSource>();
    await semanticModels.delete();
    await source.clearSemanticIndex();
  }
}
