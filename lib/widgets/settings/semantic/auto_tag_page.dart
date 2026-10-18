import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/theme/icons.dart';
import 'package:aves/theme/themes.dart';
import 'package:aves/widgets/common/basic/scaffold.dart';
import 'package:aves/widgets/common/extensions/build_context.dart';
import 'package:aves/widgets/common/identity/buttons/outlined_button.dart';
import 'package:aves/widgets/dialogs/aves_dialog.dart';
import 'package:aves/widgets/settings/common/tiles/single_selection.dart';
import 'package:aves/widgets/settings/common/tiles/switch_list.dart';
import 'package:aves_model/aves_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

class SemanticAutoTagPage extends StatelessWidget {
  static const routeName = '/settings/semantic/auto_tag';

  static const List<String> settingKeys = [
    SettingKeys.semanticAutoTagEnabledKey,
    SettingKeys.semanticAutoTagShowAsTagsKey,
    SettingKeys.semanticAutoTagThresholdKey,
    SettingKeys.semanticAutoTagMaxPerItemKey,
    SettingKeys.semanticAutoTagCustomLabelsKey,
  ];

  static const thresholdOptions = [.1, .15, .2, .25, .3, .35, .4, .5];
  static const maxPerItemOptions = [1, 2, 3, 5, 8, 10];

  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AvesScaffold(
      appBar: AppBar(
        title: Text(l10n.settingsSemanticAutoTagTile),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            SettingsSwitchListTile(
              selector: (context, s) => s.semanticAutoTagEnabled,
              onChanged: (v) async {
                settings.semanticAutoTagEnabled = v;
                await context.read<CollectionSource>().recomputeSemanticTags();
              },
              title: (context) => l10n.settingsSemanticAutoTagEnable,
            ),
            SettingsSwitchListTile(
              selector: (context, s) => s.semanticAutoTagShowAsTags,
              onChanged: (v) => settings.semanticAutoTagShowAsTags = v,
              title: (context) => l10n.settingsSemanticAutoTagShowAsTags,
              subtitle: (context) => l10n.settingsSemanticAutoTagShowAsTagsSubtitle,
            ),
            SettingsSelectionListTile<double>(
              values: thresholdOptions,
              getName: (context, v) => v.toStringAsFixed(2),
              selector: (context, s) => s.semanticAutoTagThreshold,
              onSelection: (v) => settings.semanticAutoTagThreshold = v,
              tileTitle: (context) => l10n.settingsSemanticAutoTagThreshold,
            ),
            SettingsSelectionListTile<int>(
              values: maxPerItemOptions,
              getName: (context, v) => '$v',
              selector: (context, s) => s.semanticAutoTagMaxPerItem,
              onSelection: (v) => settings.semanticAutoTagMaxPerItem = v,
              tileTitle: (context) => l10n.settingsSemanticAutoTagMaxPerItem,
            ),
            ListTile(
              leading: const Icon(AIcons.reset),
              title: Text(l10n.settingsSemanticAutoTagRecompute),
              onTap: () => context.read<CollectionSource>().recomputeSemanticTags(),
            ),
            const Divider(),
            Selector<Settings, List<String>>(
              selector: (context, s) => s.semanticAutoTagCustomLabels,
              builder: (context, labels, child) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(title: Text(l10n.settingsSemanticAutoTagCustomLabels)),
                    ...labels.map(
                      (label) => ListTile(
                        key: ValueKey(label),
                        leading: const Icon(AIcons.tag),
                        title: Text(label),
                        trailing: IconButton(
                          icon: const Icon(AIcons.clear),
                          onPressed: () => settings.semanticAutoTagCustomLabels = labels.where((v) => v != label).toList(),
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
                          label: l10n.settingsSemanticAutoTagAddLabel,
                          onPressed: () async {
                            final label = await showAvesDialog<String>(
                              context: context,
                              builder: (context) => const _LabelDialog(),
                            );
                            final cleanLabel = label?.trim();
                            if (cleanLabel == null || cleanLabel.isEmpty || labels.contains(cleanLabel)) return;
                            settings.semanticAutoTagCustomLabels = [...labels, cleanLabel];
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelDialog extends StatefulWidget {
  const new();

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AvesDialog(
      title: context.l10n.settingsSemanticAutoTagAddLabel,
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.maybeOf(context)?.pop(v),
      ),
      actions: [
        const CancelButton(),
        TextButton(
          onPressed: () => Navigator.maybeOf(context)?.pop(_controller.text),
          child: Text(Themes.asButtonLabel(context.l10n.applyButtonLabel)),
        ),
      ],
    );
  }
}
