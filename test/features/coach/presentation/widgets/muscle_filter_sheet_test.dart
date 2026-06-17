import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/muscle_filter_sheet.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    );

void main() {
  group('MuscleFilterSheet — canonical taxonomy', () {
    testWidgets('opens with the granular 12-group list (multi-select)',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Set<MuscleGroup>? result;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showMuscleFilterSheet(
                ctx,
                current: const {MuscleGroup.pecho},
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Pre-selected group is visible, rendered upper-case in the filter.
      expect(find.text(MuscleGroup.pecho.label.toUpperCase()), findsOneWidget);
      // A granular group that did NOT exist in the old 6-group sheet proves
      // the filter now mirrors the creation taxonomy.
      expect(find.text(MuscleGroup.isquiotibiales.label.toUpperCase()),
          findsOneWidget);
      expect(result, isNull); // no Aplicar tap yet
    });
  });
}
