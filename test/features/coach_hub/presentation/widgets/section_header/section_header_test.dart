import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/widgets/section_header/section_header.dart';

/// Envuelve en MaterialApp con el tema dado.
Widget _wrap(Widget widget, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: widget),
    );

void main() {
  group('TreinoSectionHeader —', () {
    // -------------------------------------------------------------------------
    // Normal: muestra título en UPPERCASE
    // -------------------------------------------------------------------------
    testWidgets('normal → título en UPPERCASE [SCENARIO-CK-SH-01]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoSectionHeader(title: 'Mis alumnos'),
      ));
      await tester.pump();
      // El widget transforma el texto a uppercase.
      expect(find.text('MIS ALUMNOS'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Título ya en UPPERCASE: renderiza sin duplicar
    // -------------------------------------------------------------------------
    testWidgets('título UPPERCASE ya → renderiza sin crash [SCENARIO-CK-SH-02]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoSectionHeader(title: 'GESTIÓN'),
      ));
      await tester.pump();
      expect(find.text('GESTIÓN'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Con acción: botón visible
    // -------------------------------------------------------------------------
    testWidgets('con acción → botón de acción visible [SCENARIO-CK-SH-03]',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        TreinoSectionHeader(
          title: 'Alumnos',
          action: TreinoSectionHeaderAction(
            label: 'Ver todos',
            onTap: () => pressed++,
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('VER TODOS'), findsNothing,
          reason: 'el label de acción no se convierte a uppercase');
      expect(find.text('Ver todos'), findsOneWidget);
      await tester.tap(find.text('Ver todos'));
      await tester.pump();
      expect(pressed, 1);
    });

    // -------------------------------------------------------------------------
    // Con count: número visible
    // -------------------------------------------------------------------------
    testWidgets(
        'con count → número visible junto al título [SCENARIO-CK-SH-04]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoSectionHeader(
          title: 'Alumnos',
          count: 24,
        ),
      ));
      await tester.pump();
      expect(find.text('ALUMNOS'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Disabled: acción no activable
    // -------------------------------------------------------------------------
    testWidgets('disabled=true → acción no llama callback [SCENARIO-CK-SH-05]',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        TreinoSectionHeader(
          title: 'Alumnos',
          disabled: true,
          action: TreinoSectionHeaderAction(
            label: 'Ver todos',
            onTap: () => pressed++,
          ),
        ),
      ));
      await tester.pump();
      // El botón existe pero no llama al callback (disabled).
      await tester.tap(find.text('Ver todos'), warnIfMissed: false);
      await tester.pump();
      expect(pressed, 0);

      // Sin TreinoInteractiveState: no debe existir la key de acción
      // interactiva ni foco de teclado alcanzable.
      expect(find.byKey(const Key('sh_action')), findsNothing,
          reason: 'acción disabled no debe ser interactiva/focusable');
    });

    // -------------------------------------------------------------------------
    // Con acción: focus + Enter activa, expone Semantics(button)
    // -------------------------------------------------------------------------
    testWidgets(
        'acción → focusable, Enter (teclado) activa, Semantics(button) '
        '[SCENARIO-CK-SH-08]', (tester) async {
      final handle = tester.ensureSemantics();
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        TreinoSectionHeader(
          title: 'Alumnos',
          action: TreinoSectionHeaderAction(
            label: 'Ver todos',
            onTap: () => pressed++,
          ),
        ),
      ));
      await tester.pump();

      final semantics = tester.getSemantics(
        find.byKey(const Key('sh_action')),
      );
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: 'acción interactiva debe exponer Semantics(button: true)');

      final focusNode = Focus.of(
        tester.element(find.byKey(const Key('sh_action'))),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, 1, reason: 'Enter debe activar la acción');

      handle.dispose();
    });

    // -------------------------------------------------------------------------
    // Con acción: hover cambia el estilo del label (token-driven, no smoke)
    // -------------------------------------------------------------------------
    testWidgets(
        'acción → hover subraya el label (cambio real, no smoke-only) '
        '[SCENARIO-CK-SH-09]', (tester) async {
      await tester.pumpWidget(_wrap(
        TreinoSectionHeader(
          title: 'Alumnos',
          action: TreinoSectionHeaderAction(
            label: 'Ver todos',
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();

      TextDecoration? decoration() => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('sh_action')),
              matching: find.text('Ver todos'),
            ),
          )
          .style
          ?.decoration;

      expect(decoration(), TextDecoration.none);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture
          .moveTo(tester.getCenter(find.byKey(const Key('sh_action'))));
      await tester.pump();

      expect(decoration(), TextDecoration.underline,
          reason: 'el label debe subrayarse en hover (cambio real)');
    });

    // -------------------------------------------------------------------------
    // Smoke dark + light
    // -------------------------------------------------------------------------
    testWidgets('smoke dark+light sin crash [SCENARIO-CK-SH-06]',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          const TreinoSectionHeader(title: 'Rutinas'),
          theme: theme,
        ));
        await tester.pump();
        expect(find.text('RUTINAS'), findsOneWidget);
      }
    });

    // -------------------------------------------------------------------------
    // Tipografía: Barlow Condensed 700
    // -------------------------------------------------------------------------
    testWidgets('tipografía Barlow Condensed 700 [SCENARIO-CK-SH-07]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoSectionHeader(title: 'Agenda'),
      ));
      await tester.pump();

      // Verifica que el Text tiene el estilo correcto.
      final textWidget = tester.widget<Text>(find.byKey(const Key('sh_title')));
      expect(textWidget.style?.fontFamily, 'Barlow Condensed');
      expect(textWidget.style?.fontWeight, FontWeight.w700);
    });
  });
}
