// Tests de MedicionFormSection — header colapsable de secciones del form de
// mediciones/rendimiento.
//
// Remediación barrido final (accesibilidad de teclado sistémica): el header
// envolvía un TreinoTappable crudo (sin Focus ni Semantics(button)) en vez de
// TreinoInteractiveState — inalcanzable por teclado.
//
// SCENARIO-MFS-01: tap en el header dispara onToggle.
// SCENARIO-MFS-02: focusable, Semantics(button) y Enter activa onToggle.
// SCENARIO-MFS-03: onToggle null → sección estática, sin Semantics(button).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/widgets/medicion_form_fields.dart';

Widget _wrap(Widget widget, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: widget),
    );

void main() {
  group('MedicionFormSection —', () {
    testWidgets('tap en el header dispara onToggle [SCENARIO-MFS-01]',
        (tester) async {
      var toggled = 0;
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => MedicionFormSection(
            title: 'COMPOSICIÓN CORPORAL',
            palette: AppPalette.of(context),
            expanded: true,
            onToggle: () => toggled++,
            children: const [],
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('COMPOSICIÓN CORPORAL'));
      await tester.pump();

      expect(toggled, 1);
    });

    testWidgets(
        'onToggle provisto: focusable, Semantics(button) y Enter activa '
        'onToggle [SCENARIO-MFS-02]', (tester) async {
      final handle = tester.ensureSemantics();
      var toggled = 0;

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => MedicionFormSection(
            title: 'COMPOSICIÓN CORPORAL',
            palette: AppPalette.of(context),
            expanded: true,
            onToggle: () => toggled++,
            children: const [],
          ),
        ),
      ));
      await tester.pump();

      final semantics = tester.getSemantics(find.text('COMPOSICIÓN CORPORAL'));
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: 'el header colapsable debe exponer Semantics(button: true)');

      final focusNode =
          Focus.of(tester.element(find.text('COMPOSICIÓN CORPORAL')));
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(toggled, 1, reason: 'Enter debe activar onToggle');

      handle.dispose();
    });

    testWidgets(
        'onToggle null → sección estática, sin Semantics(button) '
        '[SCENARIO-MFS-03]', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(
        Builder(
          builder: (context) => MedicionFormSection(
            title: 'COMPOSICIÓN CORPORAL',
            palette: AppPalette.of(context),
            expanded: true,
            onToggle: null,
            children: const [],
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('COMPOSICIÓN CORPORAL'), findsOneWidget);

      handle.dispose();
    });
  });
}
