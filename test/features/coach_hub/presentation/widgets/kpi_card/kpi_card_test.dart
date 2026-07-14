import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/widgets/kpi_card/kpi_card.dart';

/// Envuelve en MaterialApp con tema dado.
Widget _wrap(Widget widget, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: widget),
    );

void main() {
  group('KpiCard —', () {
    // -------------------------------------------------------------------------
    // Estado normal: muestra valor y label
    // -------------------------------------------------------------------------
    testWidgets('normal → muestra value y label [SCENARIO-CK-KPI-01]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const KpiCard(value: '1.234', label: 'Alumnos activos'),
      ));
      await tester.pump();
      expect(find.text('1.234'), findsOneWidget);
      expect(find.text('Alumnos activos'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Estado loading: muestra shimmer, oculta value
    // -------------------------------------------------------------------------
    testWidgets(
        'loading=true → oculta value, muestra skeleton '
        '[SCENARIO-CK-KPI-02]', (tester) async {
      await tester.pumpWidget(_wrap(
        const KpiCard(value: '1.234', label: 'Alumnos', loading: true),
      ));
      await tester.pump();
      expect(find.text('1.234'), findsNothing,
          reason: 'valor no debe mostrarse en loading');
      // El skeleton debe estar en el árbol (SizedBox o Container de loading)
      expect(find.byKey(const Key('kpi_card_skeleton')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Estado delta positivo
    // -------------------------------------------------------------------------
    testWidgets('delta positivo → muestra delta label [SCENARIO-CK-KPI-03]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const KpiCard(
          value: '1.234',
          label: 'Alumnos',
          delta: '+12%',
          deltaPositive: true,
        ),
      ));
      await tester.pump();
      expect(find.text('+12%'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Estado delta negativo
    // -------------------------------------------------------------------------
    testWidgets('delta negativo → muestra delta label [SCENARIO-CK-KPI-04]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const KpiCard(
          value: '1.234',
          label: 'Alumnos',
          delta: '-5%',
          deltaPositive: false,
        ),
      ));
      await tester.pump();
      expect(find.text('-5%'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // onTap: TreinoTappable activo
    // -------------------------------------------------------------------------
    testWidgets('onTap provisto → tappable [SCENARIO-CK-KPI-05]',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(
        KpiCard(
          value: '1.234',
          label: 'Alumnos',
          onTap: () => tapped++,
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('kpi_card_root')));
      await tester.pump();
      expect(tapped, 1);
    });

    // -------------------------------------------------------------------------
    // Hover: borde/bg cambia realmente a los tokens de hover (no smoke-only)
    // -------------------------------------------------------------------------
    testWidgets(
        'hover → decoration usa background/border de hover (token real) '
        '[SCENARIO-CK-KPI-06]', (tester) async {
      await tester.pumpWidget(_wrap(
        KpiCard(value: '42', label: 'Sesiones', onTap: () {}),
      ));
      await tester.pump();

      Color decorationColor() {
        final container = tester.widget<AnimatedContainer>(
          find.byKey(const Key('kpi_card_root')),
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      final normalColor = decorationColor();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture
          .moveTo(tester.getCenter(find.byKey(const Key('kpi_card_root'))));
      await tester.pump();

      final hoverColor = decorationColor();
      expect(hoverColor, isNot(equals(normalColor)),
          reason: 'el color de fondo debe cambiar realmente en hover');
    });

    // -------------------------------------------------------------------------
    // Accesibilidad de teclado: focusable + activable + Semantics(button)
    // -------------------------------------------------------------------------
    testWidgets(
        'onTap provisto → focusable, Enter activa onTap, Semantics(button) '
        '[SCENARIO-CK-KPI-09]', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(
        KpiCard(
          value: '1',
          label: 'Foco',
          onTap: () {},
        ),
      ));
      await tester.pump();

      final semantics = tester.getSemantics(
        find.byKey(const Key('kpi_card_root')),
      );
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: 'KpiCard interactivo debe exponer Semantics(button: true)');

      handle.dispose();
    });

    testWidgets(
        'onTap provisto → Enter (teclado) activa onTap [SCENARIO-CK-KPI-10]',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(
        KpiCard(
          value: '1',
          label: 'Foco',
          onTap: () => tapped++,
        ),
      ));
      await tester.pump();

      final focusNode = Focus.of(
        tester.element(find.byKey(const Key('kpi_card_root'))),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, 1, reason: 'Enter debe activar onTap');
    });

    // -------------------------------------------------------------------------
    // Smoke dark + light
    // -------------------------------------------------------------------------
    testWidgets('smoke dark+light sin crash [SCENARIO-CK-KPI-07]',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          const KpiCard(value: '99', label: 'Entrenamientos'),
          theme: theme,
        ));
        await tester.pump();
        expect(find.text('99'), findsOneWidget);
        expect(find.text('Entrenamientos'), findsOneWidget);
      }
    });

    // -------------------------------------------------------------------------
    // Sin shadow: BoxDecoration no tiene BoxShadow
    // -------------------------------------------------------------------------
    testWidgets('sin sombra — elevation-free [SCENARIO-CK-KPI-08]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const KpiCard(value: '10', label: 'Pagos'),
      ));
      await tester.pump();

      // Buscar DecoratedBox o Container con BoxDecoration
      final containers = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(const Key('kpi_card_root')),
          matching: find.byType(DecoratedBox),
        ),
      );
      for (final c in containers) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.boxShadow != null) {
          expect(dec.boxShadow, isEmpty,
              reason: 'KpiCard no debe tener sombra');
        }
      }
    });
  });
}
