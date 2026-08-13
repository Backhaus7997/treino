// Tests para SetEntrySheet — formato del hint "Objetivo" y del stepper de
// peso vía formatWeightKg (#436): enteros sin ".0", fraccionarios intactos.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/presentation/widgets/set_entry_sheet.dart';

import '../../application/stub_factories.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  group('SetEntrySheet — formato de peso', () {
    testWidgets('objetivo con peso entero muestra "20 kg", no "20.0 kg"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SetEntrySheet(
          slot: makeSlot(targetWeightKg: 20.0),
          setNumber: 1,
          onCheck: (_, __) {},
        ),
      ));

      expect(find.textContaining('· 20 kg'), findsOneWidget);
      expect(find.textContaining('20.0'), findsNothing);
      // El stepper arranca en el peso objetivo, con el mismo formato.
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('objetivo fraccionario conserva su decimal ("17.5 kg")',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SetEntrySheet(
          slot: makeSlot(targetWeightKg: 17.5),
          setNumber: 1,
          onCheck: (_, __) {},
        ),
      ));

      expect(find.textContaining('· 17.5 kg'), findsOneWidget);
      expect(find.text('17.5'), findsOneWidget);
    });

    testWidgets('sin peso objetivo muestra el placeholder "– kg"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SetEntrySheet(
          slot: makeSlot(targetWeightKg: null),
          setNumber: 1,
          onCheck: (_, __) {},
        ),
      ));

      expect(find.textContaining('– kg'), findsOneWidget);
    });
  });
}
