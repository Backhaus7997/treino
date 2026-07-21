// Widget tests for TarifaCard — sección Planes comerciales (Fase 10, WU-04).
//
// SCENARIO-TC-01: labels de cadencia es-AR (mensual/semanal/porSesion/suelto)
//   + sufijo de precio correcto por cadencia.
// SCENARIO-TC-02: formato de precio (fmtArs) y conteo de alumnos honesto.
// SCENARIO-TC-03: chip "Más usada" solo aparece cuando `masUsada: true`.
// SCENARIO-TC-04: Semantics describe la tarifa completa (cadencia + precio +
//   alumnos).
// SCENARIO-TC-05: hover (con onTap wired) cambia el color real del root —
//   sin onTap (default), la card queda estática (read-only honesto).
// SCENARIO-TC-06: smoke dark+light sin crash.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/planes/tarifas_model.dart';
import 'package:treino/features/coach_hub/presentation/sections/planes/widgets/tarifa_card.dart';
import 'package:treino/features/coach_hub/presentation/widgets/treino_interactive_state.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: SizedBox(width: 320, height: 200, child: child)),
    );

void main() {
  group('SCENARIO-TC-01/02 — TarifaCard: labels de cadencia + precio', () {
    testWidgets('mensual → badge MENSUAL, precio + /mes, N alumnos',
        (tester) async {
      await tester.pumpWidget(_wrap(const TarifaCard(
        group: TarifaGroup(
          amountArs: 15000,
          cadence: BillingCadence.mensual,
          alumnosCount: 3,
        ),
      )));
      await tester.pump();

      expect(find.text('MENSUAL'), findsOneWidget);
      expect(find.text(r'$15.000'), findsOneWidget);
      expect(find.text('/mes'), findsOneWidget);
      expect(find.text('3 alumnos'), findsOneWidget);
    });

    testWidgets('semanal → badge SEMANAL, precio + /semana', (tester) async {
      await tester.pumpWidget(_wrap(const TarifaCard(
        group: TarifaGroup(
          amountArs: 8000,
          cadence: BillingCadence.semanal,
          alumnosCount: 2,
        ),
      )));
      await tester.pump();

      expect(find.text('SEMANAL'), findsOneWidget);
      expect(find.text(r'$8.000'), findsOneWidget);
      expect(find.text('/semana'), findsOneWidget);
      expect(find.text('2 alumnos'), findsOneWidget);
    });

    testWidgets('porSesion → badge POR SESIÓN, precio + /sesión',
        (tester) async {
      await tester.pumpWidget(_wrap(const TarifaCard(
        group: TarifaGroup(
          amountArs: 30000,
          cadence: BillingCadence.porSesion,
          alumnosCount: 1,
        ),
      )));
      await tester.pump();

      expect(find.text('POR SESIÓN'), findsOneWidget);
      expect(find.text(r'$30.000'), findsOneWidget);
      expect(find.text('/sesión'), findsOneWidget);
      expect(find.text('1 alumnos'), findsOneWidget);
    });

    testWidgets('suelto → badge SUELTO, precio + único', (tester) async {
      await tester.pumpWidget(_wrap(const TarifaCard(
        group: TarifaGroup(
          amountArs: 5000,
          cadence: BillingCadence.suelto,
          alumnosCount: 4,
        ),
      )));
      await tester.pump();

      expect(find.text('SUELTO'), findsOneWidget);
      expect(find.text(r'$5.000'), findsOneWidget);
      expect(find.text('único'), findsOneWidget);
    });
  });

  group('SCENARIO-TC-03 — TarifaCard: chip "Más usada"', () {
    const group = TarifaGroup(
      amountArs: 15000,
      cadence: BillingCadence.mensual,
      alumnosCount: 3,
    );

    testWidgets('masUsada: false → sin chip', (tester) async {
      await tester.pumpWidget(_wrap(const TarifaCard(group: group)));
      await tester.pump();

      expect(find.text('Más usada'), findsNothing);
    });

    testWidgets('masUsada: true → chip visible', (tester) async {
      await tester
          .pumpWidget(_wrap(const TarifaCard(group: group, masUsada: true)));
      await tester.pump();

      expect(find.text('Más usada'), findsOneWidget);
      expect(
          find.byKey(const Key('tarifa_card_mas_usada_chip')), findsOneWidget);
    });
  });

  group('SCENARIO-TC-04 — TarifaCard: Semantics', () {
    testWidgets('el label describe cadencia, precio y alumnos', (tester) async {
      await tester.pumpWidget(_wrap(const TarifaCard(
        group: TarifaGroup(
          amountArs: 15000,
          cadence: BillingCadence.mensual,
          alumnosCount: 3,
        ),
        masUsada: true,
      )));
      await tester.pump();

      final semantics = tester.getSemantics(
        find.byKey(const Key('tarifa_card_root')),
      );
      expect(semantics.label, contains('MENSUAL'));
      expect(semantics.label, contains(r'$15.000'));
      expect(semantics.label, contains('3 alumnos'));
      expect(semantics.label, contains('más usada'));
    });
  });

  group('SCENARIO-TC-05 — TarifaCard: hover', () {
    const group = TarifaGroup(
      amountArs: 15000,
      cadence: BillingCadence.mensual,
      alumnosCount: 3,
    );

    testWidgets('sin onTap (default) → sin MouseRegion interactivo real',
        (tester) async {
      await tester.pumpWidget(_wrap(const TarifaCard(group: group)));
      await tester.pump();

      // Read-only honesto: TreinoInteractiveState con onTap null no envuelve
      // en MouseRegion/Semantics(button) — mismo comportamiento que KpiCard
      // sin onTap.
      expect(find.byType(TreinoInteractiveState), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TreinoInteractiveState),
          matching: find.byType(MouseRegion),
        ),
        findsNothing,
      );
    });

    testWidgets('con onTap wired → hover cambia el color real del root',
        (tester) async {
      await tester.pumpWidget(_wrap(TarifaCard(group: group, onTap: () {})));
      await tester.pump();

      Color decorationColor() {
        final container = tester.widget<AnimatedContainer>(
          find.byKey(const Key('tarifa_card_root')),
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      final normalColor = decorationColor();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(
        tester.getCenter(find.byKey(const Key('tarifa_card_root'))),
      );
      await tester.pump();

      final hoverColor = decorationColor();
      expect(hoverColor, isNot(equals(normalColor)));
    });
  });

  group('SCENARIO-TC-06 — TarifaCard: smoke', () {
    testWidgets('dark+light sin crash', (tester) async {
      const group = TarifaGroup(
        amountArs: 15000,
        cadence: BillingCadence.mensual,
        alumnosCount: 3,
      );
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester
            .pumpWidget(_wrap(const TarifaCard(group: group), theme: theme));
        await tester.pump();
        expect(find.text('MENSUAL'), findsOneWidget);
      }
    });
  });
}
