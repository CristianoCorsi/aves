import 'package:aves/l10n/l10n.dart';
import 'package:aves/model/settings/settings.dart';
import 'package:aves/model/source/collection_source.dart';
import 'package:aves/model/source/media_store_source.dart';
import 'package:aves/theme/colors.dart';
import 'package:aves/widgets/common/providers/durations_provider.dart';
import 'package:aves/widgets/settings/semantic/auto_tag_page.dart';
import 'package:aves/widgets/settings/semantic/indexing_page.dart';
import 'package:aves/widgets/settings/semantic/performance_page.dart';
import 'package:aves_model/aves_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../common.dart';

void main() {
  setUpAll(() async {
    await setUpAllServices();
  });

  setUp(() async {
    await setUpServices();
  });

  tearDownAll(() async {
    await tearDownAllServices();
  });

  Widget wrap(Widget child, CollectionSource source) => MultiProvider(
    providers: [
      ChangeNotifierProvider<Settings>.value(value: settings),
      Provider<CollectionSource>.value(value: source),
      DurationsProvider(),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: AvesColorsProvider(child: child),
    ),
  );

  testWidgets('performance page switches to custom profile on parameter change', (tester) async {
    final source = MediaStoreSource();
    settings.semanticPerformanceProfile = SemanticPerformanceProfile.balanced;
    await tester.pumpWidget(wrap(const SemanticPerformancePage(), source));
    expect(find.text('Balanced'), findsOneWidget);

    await tester.tap(find.text('Items per run'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2000').last);
    await tester.pumpAndSettle();

    expect(settings.semanticPerformanceProfile, SemanticPerformanceProfile.custom);
    expect(settings.semanticPerformanceParams.maxItemsPerRun, 2000);
    expect(settings.semanticPerformanceParams.vectorDimension, 256);
  });

  testWidgets('indexing page shows selected folders editor only for selected scope', (tester) async {
    final source = MediaStoreSource();
    settings.semanticIndexScope = SemanticIndexScope.all;
    await tester.pumpWidget(wrap(const SemanticIndexingPage(), source));
    await tester.pumpAndSettle();
    expect(find.text('Selected folders'), findsNothing);
    expect(find.text('Excluded folders'), findsOneWidget);

    settings.semanticIndexScope = SemanticIndexScope.selected;
    await tester.pumpAndSettle();
    expect(find.text('Selected folders'), findsOneWidget);
  });

  testWidgets('auto tag page adds custom labels', (tester) async {
    final source = MediaStoreSource();
    await tester.pumpWidget(wrap(const SemanticAutoTagPage(), source));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Add label'), 100);
    await tester.tap(find.text('Add label'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' boat ');
    await tester.tap(find.text('APPLY'));
    await tester.pumpAndSettle();
    expect(settings.semanticAutoTagCustomLabels, ['boat']);
    expect(find.text('boat'), findsOneWidget);
  });
}
