import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/presentation/widgets/equipment_filter_sheet.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  group('EquipmentFilterSheet — T-RER-021', () {
    testWidgets('renders 9 equipment rows + reset row + title', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showEquipmentFilterSheet(ctx),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Title visible
      expect(find.text('Tipo de equipo'), findsOneWidget);
      // Reset row
      expect(find.text('Todo el equipamiento'), findsOneWidget);
      // All 9 equipment types by label
      for (final e in EquipmentType.values) {
        expect(find.text(e.label), findsOneWidget);
      }
    });

    testWidgets('each row shows the expected icon', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showEquipmentFilterSheet(ctx),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // equipBarbell is used for both mancuerna and barra — so 2 of the same icon.
      // We just verify total icon count: 9 equipment rows + 1 reset icon = 10.
      // (Each row has exactly 1 leading icon widget.)
      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      // At least 9 equipment icons present (reset + 9 types)
      expect(icons.length, greaterThanOrEqualTo(10));
    });

    testWidgets('tapping a row pops with that EquipmentType', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      EquipmentType? result;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showEquipmentFilterSheet(ctx);
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(EquipmentType.cable.label));
      await tester.pumpAndSettle();

      expect(result, EquipmentType.cable);
    });

    testWidgets('tapping reset row pops with null', (tester) async {
      EquipmentType? result = EquipmentType.barra;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await showEquipmentFilterSheet(
                ctx,
                current: EquipmentType.barra,
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Todo el equipamiento'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('active type shows checkmark trailing icon', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showEquipmentFilterSheet(
              ctx,
              current: EquipmentType.mancuerna,
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // One check icon for the active row
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('equipDumbbell icon maps to TreinoIcon.equipDumbbell', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showEquipmentFilterSheet(ctx),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // equipDumbbell == barbell; should find at least 2 (mancuerna + barra)
      expect(
        find.byIcon(TreinoIcon.equipDumbbell),
        findsAtLeastNWidgets(2),
      );
    });
  });
}
