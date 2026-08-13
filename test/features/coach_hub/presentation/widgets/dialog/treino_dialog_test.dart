import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/widgets/dialog/treino_dialog.dart';

/// Envuelve en MaterialApp con el tema dado. El body es un botón que abre el
/// dialog vía [showTreinoDialog] para poder testear la anatomía completa
/// (overlay + transición + Navigator).
Widget _wrap(WidgetBuilder dialogBuilder, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open_dialog'),
              onPressed: () => showTreinoDialog<void>(
                context,
                builder: dialogBuilder,
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

void main() {
  group('TreinoDialog —', () {
    // -------------------------------------------------------------------------
    // Normal: header (título) + body + actions visibles
    // -------------------------------------------------------------------------
    testWidgets(
        'normal → título, body y acciones visibles '
        '[SCENARIO-CK-DL-01]', (tester) async {
      await tester.pumpWidget(_wrap(
        (ctx) => const TreinoDialog(
          title: 'Confirmar baja',
          body: Text('¿Seguro que querés dar de baja al alumno?'),
          primaryLabel: 'Confirmar',
          secondaryLabel: 'Cancelar',
        ),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar baja'), findsOneWidget);
      expect(
        find.text('¿Seguro que querés dar de baja al alumno?'),
        findsOneWidget,
      );
      expect(find.text('Confirmar'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Botón primario → callback llamado
    // -------------------------------------------------------------------------
    testWidgets('tap primario → onPrimaryTap llamado [SCENARIO-CK-DL-02]',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        (ctx) => TreinoDialog(
          title: 'Confirmar',
          primaryLabel: 'Confirmar',
          onPrimaryTap: () => pressed++,
        ),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog_primary_button')));
      await tester.pump();
      expect(pressed, 1);
    });

    // -------------------------------------------------------------------------
    // Botón secundario → callback llamado
    // -------------------------------------------------------------------------
    testWidgets('tap secundario → onSecondaryTap llamado [SCENARIO-CK-DL-03]',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        (ctx) => TreinoDialog(
          title: 'Confirmar',
          secondaryLabel: 'Cancelar',
          onSecondaryTap: () => pressed++,
        ),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      expect(pressed, 1);
    });

    // -------------------------------------------------------------------------
    // Botón primario → activable por teclado (Enter), Semantics(button)
    // -------------------------------------------------------------------------
    testWidgets(
        'primario → focusable, Enter (teclado) activa, Semantics(button) '
        '[SCENARIO-CK-DL-11]', (tester) async {
      final handle = tester.ensureSemantics();
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        (ctx) => TreinoDialog(
          title: 'Confirmar',
          primaryLabel: 'Confirmar',
          onPrimaryTap: () => pressed++,
        ),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.byKey(const Key('dialog_primary_button')),
      );
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: 'botón primario debe exponer Semantics(button: true)');

      final focusNode = Focus.of(
        tester.element(find.byKey(const Key('dialog_primary_button'))),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(pressed, 1, reason: 'Enter debe activar el botón primario');

      handle.dispose();
    });

    // -------------------------------------------------------------------------
    // Botón secundario → activable por teclado (Space), Semantics(button)
    // -------------------------------------------------------------------------
    testWidgets(
        'secundario → focusable, Space (teclado) activa, Semantics(button) '
        '[SCENARIO-CK-DL-12]', (tester) async {
      final handle = tester.ensureSemantics();
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        (ctx) => TreinoDialog(
          title: 'Confirmar',
          secondaryLabel: 'Cancelar',
          onSecondaryTap: () => pressed++,
        ),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.byKey(const Key('dialog_secondary_button')),
      );
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: 'botón secundario debe exponer Semantics(button: true)');

      final focusNode = Focus.of(
        tester.element(find.byKey(const Key('dialog_secondary_button'))),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(pressed, 1, reason: 'Space debe activar el botón secundario');

      handle.dispose();
    });

    // -------------------------------------------------------------------------
    // Destructive: el botón primario usa el color danger (TreinoDialogTokens)
    // -------------------------------------------------------------------------
    testWidgets(
        'destructive=true → botón primario en color danger '
        '[SCENARIO-CK-DL-04]', (tester) async {
      await tester.pumpWidget(_wrap(
        (ctx) => const TreinoDialog(
          title: 'Eliminar alumno',
          primaryLabel: 'Eliminar',
          destructive: true,
        ),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('dialog_primary_button')),
          matching: find.text('Eliminar'),
        ),
      );
      final palette = AppPalette.of(
        tester.element(find.byKey(const Key('dialog_primary_button'))),
      );
      expect(text.style?.color, palette.danger);
    });

    // -------------------------------------------------------------------------
    // Loading: spinner visible en botón primario, deshabilitado
    // -------------------------------------------------------------------------
    testWidgets(
        'loading=true → spinner visible, primario deshabilitado '
        '[SCENARIO-CK-DL-05]', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        (ctx) => TreinoDialog(
          title: 'Guardando',
          primaryLabel: 'Guardar',
          onPrimaryTap: () => pressed++,
          loading: true,
        ),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      // No pumpAndSettle: CircularProgressIndicator anima indefinidamente.
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('dialog_primary_spinner')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dialog_primary_button')),
          warnIfMissed: false);
      await tester.pump();
      expect(pressed, 0);
    });

    // -------------------------------------------------------------------------
    // Error inline: mensaje visible en el body
    // -------------------------------------------------------------------------
    testWidgets('errorMessage → mensaje inline visible [SCENARIO-CK-DL-06]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        (ctx) => const TreinoDialog(
          title: 'Confirmar',
          errorMessage: 'No se pudo guardar. Intentá de nuevo.',
        ),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudo guardar. Intentá de nuevo.'),
        findsOneWidget,
      );
    });

    // -------------------------------------------------------------------------
    // Close button (header) → cierra el dialog
    // -------------------------------------------------------------------------
    testWidgets(
        'botón cerrar del header → cierra el dialog '
        '[SCENARIO-CK-DL-07]', (tester) async {
      await tester.pumpWidget(_wrap(
        (ctx) => const TreinoDialog(title: 'Confirmar'),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dialog_close_button')));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Escape key → cierra el dialog
    // -------------------------------------------------------------------------
    testWidgets('tecla Escape → cierra el dialog [SCENARIO-CK-DL-08]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        (ctx) => const TreinoDialog(title: 'Confirmar'),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Confirmar'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // reduceMotion: abre sin crash con animaciones desactivadas
    // -------------------------------------------------------------------------
    testWidgets(
        'reduceMotion → abre sin animación intermedia, sin crash '
        '[SCENARIO-CK-DL-09]', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _wrap((ctx) => const TreinoDialog(title: 'Confirmar')),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Smoke dark + light
    // -------------------------------------------------------------------------
    testWidgets('smoke dark+light sin crash [SCENARIO-CK-DL-10]',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          (ctx) => const TreinoDialog(
            title: 'Confirmar',
            body: Text('Cuerpo del dialog'),
            primaryLabel: 'Aceptar',
          ),
          theme: theme,
        ));
        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();
        expect(find.text('Confirmar'), findsOneWidget);
        expect(find.text('Cuerpo del dialog'), findsOneWidget);

        // Cierra para la siguiente iteración del loop.
        await tester.tap(find.byKey(const Key('dialog_close_button')));
        await tester.pumpAndSettle();
      }
    });

    // -------------------------------------------------------------------------
    // Tipografía real: el título usa la familia condensada (token)
    // -------------------------------------------------------------------------
    testWidgets(
        'título → fontFamily resuelve a AppFonts.barlowCondensed (token real) '
        '[SCENARIO-CK-DL-13]', (tester) async {
      await tester.pumpWidget(_wrap(
        (ctx) => const TreinoDialog(title: 'Confirmar baja'),
      ));
      await tester.tap(find.byKey(const Key('open_dialog')));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('Confirmar baja'));
      expect(
        text.style?.fontFamily,
        AppFonts.barlowCondensed,
        reason: 'el título del dialog debe usar la familia condensada real '
            '("Barlow Condensed", no "BarlowCondensed")',
      );
    });
  });
}
