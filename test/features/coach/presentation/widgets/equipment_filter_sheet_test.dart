import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/equipment_filter_sheet.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    );

void main() {
  // TODO PR2-followup: rewrite for the multi-select sheet API
  // (toggle semantics + sticky Aplicar button + Set<EquipmentType>
  // return). The old single-select tests were removed because the API
  // changed in the PR2 refinement (user feedback during smoke). The
  // sheet behaviour is exercised manually for now.
  group(
    'EquipmentFilterSheet — T-RER-021 (stubbed)',
    () {
      testWidgets('sheet opens with multi-select API (smoke)', (tester) async {
        tester.view.physicalSize = const Size(400, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Set<EquipmentType>? result;
        await tester.pumpWidget(_wrap(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showEquipmentFilterSheet(
                  ctx,
                  current: const {EquipmentType.mancuerna},
                );
              },
              child: const Text('open'),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // The sheet should render with a multi-select list.
        expect(find.text(EquipmentType.mancuerna.label), findsOneWidget);
        expect(result, isNull);
      });
    },
  );
}
