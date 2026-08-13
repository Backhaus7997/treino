import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/widgets/treino_interactive_state.dart';

/// Envuelve [widget] en un MaterialApp con el tema dado para que
/// AppPalette.of(context) resuelva correctamente.
Widget _wrap(Widget widget, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: widget),
    );

void main() {
  group('TreinoInteractiveState —', () {
    // -------------------------------------------------------------------------
    // Estado disabled: onTap == null
    // -------------------------------------------------------------------------
    testWidgets('onTap null → disabled=true en el builder [SCENARIO-CK-IS-01]',
        (tester) async {
      TreinoStates? capturedStates;
      await tester.pumpWidget(_wrap(
        TreinoInteractiveState(
          onTap: null,
          builder: (ctx, states) {
            capturedStates = states;
            return const SizedBox(key: Key('child'), width: 48, height: 48);
          },
        ),
      ));
      await tester.pump();
      expect(capturedStates, isNotNull);
      expect(capturedStates!.disabled, isTrue,
          reason: 'onTap null debe producir disabled=true');
      expect(capturedStates!.hovered, isFalse);
      expect(capturedStates!.focused, isFalse);
      expect(capturedStates!.pressed, isFalse);
    });

    // -------------------------------------------------------------------------
    // Estado enabled: onTap provisto
    // -------------------------------------------------------------------------
    testWidgets('onTap provisto → disabled=false [SCENARIO-CK-IS-02]',
        (tester) async {
      TreinoStates? capturedStates;
      await tester.pumpWidget(_wrap(
        TreinoInteractiveState(
          onTap: () {},
          builder: (ctx, states) {
            capturedStates = states;
            return const SizedBox(key: Key('child'), width: 48, height: 48);
          },
        ),
      ));
      await tester.pump();
      expect(capturedStates!.disabled, isFalse);
    });

    // -------------------------------------------------------------------------
    // Hover via mouse
    // -------------------------------------------------------------------------
    testWidgets(
        'mouse enter → hovered=true; mouse exit → hovered=false '
        '[SCENARIO-CK-IS-03]', (tester) async {
      TreinoStates? capturedStates;
      await tester.pumpWidget(_wrap(
        TreinoInteractiveState(
          onTap: () {},
          builder: (ctx, states) {
            capturedStates = states;
            return const SizedBox(key: Key('child'), width: 100, height: 48);
          },
        ),
      ));
      await tester.pump();
      expect(capturedStates!.hovered, isFalse);

      // Mueve el mouse dentro del widget
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byKey(const Key('child'))));
      await tester.pump();
      expect(capturedStates!.hovered, isTrue,
          reason: 'hover debe ser true tras mouse enter');

      await gesture.moveTo(const Offset(500, 500));
      await tester.pump();
      expect(capturedStates!.hovered, isFalse,
          reason: 'hover debe ser false tras mouse exit');
    });

    // -------------------------------------------------------------------------
    // Focus via teclado
    // -------------------------------------------------------------------------
    testWidgets(
        'focus → focused=true; unfocus → focused=false '
        '[SCENARIO-CK-IS-04]', (tester) async {
      TreinoStates? capturedStates;
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(_wrap(
        TreinoInteractiveState(
          onTap: () {},
          focusNode: focusNode,
          builder: (ctx, states) {
            capturedStates = states;
            return const SizedBox(key: Key('child'), width: 48, height: 48);
          },
        ),
      ));
      await tester.pump();
      expect(capturedStates!.focused, isFalse);

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(capturedStates!.focused, isTrue,
          reason: 'focused=true al recibir foco');

      focusNode.unfocus();
      await tester.pumpAndSettle();
      expect(capturedStates!.focused, isFalse,
          reason: 'focused=false al perder foco');
    });

    // -------------------------------------------------------------------------
    // El widget NO pinta nada por sí mismo (delega al builder)
    // -------------------------------------------------------------------------
    testWidgets(
        'no renderiza decoración propia — solo el child del builder '
        '[SCENARIO-CK-IS-05]', (tester) async {
      await tester.pumpWidget(_wrap(
        TreinoInteractiveState(
          onTap: () {},
          builder: (ctx, states) =>
              const SizedBox(key: Key('child'), width: 48, height: 48),
        ),
      ));
      await tester.pump();
      // El widget hijo es el único Container/SizedBox — no hay decoración extra.
      expect(find.byKey(const Key('child')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Disabled en hover: mouse no cambia estado
    // -------------------------------------------------------------------------
    testWidgets('disabled → hover ignorado [SCENARIO-CK-IS-06]',
        (tester) async {
      TreinoStates? capturedStates;
      await tester.pumpWidget(_wrap(
        TreinoInteractiveState(
          onTap: null,
          builder: (ctx, states) {
            capturedStates = states;
            return const SizedBox(key: Key('child'), width: 100, height: 48);
          },
        ),
      ));
      await tester.pump();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('child'))));
      await tester.pump();

      // disabled sigue true; hovered no cambia en disabled
      expect(capturedStates!.disabled, isTrue);
      expect(capturedStates!.hovered, isFalse,
          reason: 'disabled widget no debe reportar hover');
    });

    // -------------------------------------------------------------------------
    // Teclado: Enter y Space activan onTap cuando tiene focus
    // -------------------------------------------------------------------------
    testWidgets(
        'Enter key activa onTap cuando tiene focus '
        '[SCENARIO-CK-IS-07]', (tester) async {
      var tapped = 0;
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(_wrap(
        TreinoInteractiveState(
          onTap: () => tapped++,
          focusNode: focusNode,
          builder: (ctx, states) =>
              const SizedBox(key: Key('child'), width: 48, height: 48),
        ),
      ));
      await tester.pump();

      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapped, 1, reason: 'Enter debe activar onTap');
    });

    // -------------------------------------------------------------------------
    // Dark y light: no crashea en ningún tema
    // -------------------------------------------------------------------------
    testWidgets('smoke dark+light sin crash [SCENARIO-CK-IS-08]',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          TreinoInteractiveState(
            onTap: () {},
            builder: (ctx, states) =>
                const SizedBox(key: Key('child'), width: 48, height: 48),
          ),
          theme: theme,
        ));
        await tester.pump();
        expect(find.byKey(const Key('child')), findsOneWidget);
      }
    });
  });
}
