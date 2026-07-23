import 'package:flutter/material.dart';
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
