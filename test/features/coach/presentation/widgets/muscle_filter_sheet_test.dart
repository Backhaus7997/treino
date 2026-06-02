import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/muscle_filter_sheet.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  group('MuscleFilterSheet — T-RER-019', () {
    testWidgets('renders reset row + title + all 6 muscle groups', (
      tester,
    ) async {
      // Give a tall frame so all rows are visible
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showMuscleFilterSheet(ctx),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Grupo muscular'), findsOneWidget);
      expect(find.text('Todos los músculos'), findsOneWidget);
      for (final g in MuscleGroupDisplay.displayOrder) {
        expect(find.text(g.displayLabel), findsOneWidget);
      }
    });

    testWidgets('each muscle row shows PNG asset', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showMuscleFilterSheet(ctx),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNWidgets(6));
    });

    testWidgets('tapping a row pops with that MuscleGroupDisplay', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      MuscleGroupDisplay? result;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showMuscleFilterSheet(ctx);
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(MuscleGroupDisplay.piernas.displayLabel));
      await tester.pumpAndSettle();

      expect(result, MuscleGroupDisplay.piernas);
    });

    testWidgets('tapping reset row pops with null', (tester) async {
      MuscleGroupDisplay? result = MuscleGroupDisplay.pecho;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showMuscleFilterSheet(
                ctx,
                current: MuscleGroupDisplay.pecho,
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Todos los músculos'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('active group shows checkmark trailing icon', (tester) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showMuscleFilterSheet(
              ctx,
              current: MuscleGroupDisplay.hombros,
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Exactly one check icon should be in the tree (for the active group)
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('dismissing sheet pops with null', (tester) async {
      MuscleGroupDisplay? result = MuscleGroupDisplay.pecho;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showMuscleFilterSheet(
                ctx,
                current: MuscleGroupDisplay.pecho,
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
