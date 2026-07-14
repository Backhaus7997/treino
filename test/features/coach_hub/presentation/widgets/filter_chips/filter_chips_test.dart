import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/widgets/filter_chips/filter_chips.dart';

/// Envuelve en MaterialApp con tema dado.
Widget _wrap(Widget widget, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: Center(child: widget)),
    );

/// Opciones de prueba.
const _options = ['Activos', 'Inactivos', 'Pausados'];

void main() {
  group('TreinoFilterChips —', () {
    // -------------------------------------------------------------------------
    // Renderiza todas las opciones
    // -------------------------------------------------------------------------
    testWidgets('renderiza todas las opciones [SCENARIO-CK-FC-01]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {},
          onChanged: (_) {},
        ),
      ));
      await tester.pump();
      for (final o in _options) {
        expect(find.text(o), findsOneWidget);
      }
      // Spacing en escala 8/12/14/18/20 — Finding W4 (no vertical:6 crudo).
      final chip = tester.widget<AnimatedContainer>(
        find.byKey(const Key('filter_chip_Activos')),
      );
      expect(
        chip.padding,
        const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
      );
    });

    // -------------------------------------------------------------------------
    // Selección individual (single select)
    // -------------------------------------------------------------------------
    testWidgets(
        'tap chip → onChanged con la opción seleccionada '
        '[SCENARIO-CK-FC-02]', (tester) async {
      Set<String> lastSelected = {};
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {},
          onChanged: (s) => lastSelected = s,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Activos'));
      await tester.pump();
      expect(lastSelected, contains('Activos'));
    });

    // -------------------------------------------------------------------------
    // Multi-select: dos chips seleccionados
    // -------------------------------------------------------------------------
    testWidgets(
        'multiSelect → puede tener múltiples seleccionados '
        '[SCENARIO-CK-FC-03]', (tester) async {
      Set<String> lastSelected = {};
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {'Activos'},
          multiSelect: true,
          onChanged: (s) => lastSelected = s,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Inactivos'));
      await tester.pump();
      expect(lastSelected, containsAll(['Activos', 'Inactivos']));
    });

    // -------------------------------------------------------------------------
    // Deselección: tap en chip ya seleccionado lo quita
    // -------------------------------------------------------------------------
    testWidgets(
        'tap en chip seleccionado → lo deselecciona '
        '[SCENARIO-CK-FC-04]', (tester) async {
      Set<String> lastSelected = {'Activos'};
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {'Activos'},
          multiSelect: true,
          onChanged: (s) => lastSelected = s,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Activos'));
      await tester.pump();
      expect(lastSelected, isNot(contains('Activos')));
    });

    // -------------------------------------------------------------------------
    // Estado disabled: no dispara onChanged
    // -------------------------------------------------------------------------
    testWidgets(
        'disabled → onChanged no se llama al tap '
        '[SCENARIO-CK-FC-05]', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {},
          onChanged: (_) => called = true,
          disabled: true,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Activos'));
      await tester.pump();
      expect(called, isFalse, reason: 'disabled no debe disparar onChanged');
    });

    // -------------------------------------------------------------------------
    // Badge de conteo: muestra el count badge cuando se provee
    // -------------------------------------------------------------------------
    testWidgets('badge count → muestra el conteo [SCENARIO-CK-FC-06]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {'Activos'},
          onChanged: (_) {},
          badgeCounts: const {'Activos': 5},
        ),
      ));
      await tester.pump();
      expect(find.text('5'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Hover: decoration usa background de hover (token real, no smoke-only)
    // -------------------------------------------------------------------------
    testWidgets(
        'hover → decoration usa background de hover (token real) '
        '[SCENARIO-CK-FC-07]', (tester) async {
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {},
          onChanged: (_) {},
        ),
      ));
      await tester.pump();

      Color decorationColor() {
        final container = tester.widget<AnimatedContainer>(
          find.byKey(const Key('filter_chip_Activos')),
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      final normalColor = decorationColor();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Activos')));
      await tester.pump();

      final hoverColor = decorationColor();
      expect(hoverColor, isNot(equals(normalColor)),
          reason: 'el color de fondo debe cambiar realmente en hover');
    });

    // -------------------------------------------------------------------------
    // Focus + Space activa chip
    // -------------------------------------------------------------------------
    testWidgets('Space key activa chip con focus [SCENARIO-CK-FC-08]',
        (tester) async {
      Set<String> lastSelected = {};
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {},
          onChanged: (s) => lastSelected = s,
        ),
      ));
      await tester.pump();

      // Tab para enfocar el primer chip
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      // Al menos una opción fue seleccionada (la primera focuseada)
      expect(lastSelected, isNotEmpty);
    });

    // -------------------------------------------------------------------------
    // Focus + Enter activa chip, y expone Semantics(button)
    // -------------------------------------------------------------------------
    testWidgets(
        'focus + Enter activa chip, expone Semantics(button) '
        '[SCENARIO-CK-FC-11]', (tester) async {
      final handle = tester.ensureSemantics();
      Set<String> lastSelected = {};
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {},
          onChanged: (s) => lastSelected = s,
        ),
      ));
      await tester.pump();

      final semantics = tester.getSemantics(
        find.byKey(const Key('filter_chip_Activos')),
      );
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: 'chip interactivo debe exponer Semantics(button: true)');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(lastSelected, isNotEmpty, reason: 'Enter debe activar el chip');

      handle.dispose();
    });

    // -------------------------------------------------------------------------
    // Disabled: no es focusable ni activable por teclado
    // -------------------------------------------------------------------------
    testWidgets(
        'disabled → no focusable, Enter no dispara onChanged '
        '[SCENARIO-CK-FC-12]', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {},
          onChanged: (_) => called = true,
          disabled: true,
        ),
      ));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(called, isFalse,
          reason: 'chip disabled no debe activarse por teclado');
    });

    // -------------------------------------------------------------------------
    // Smoke dark+light
    // -------------------------------------------------------------------------
    testWidgets('smoke dark+light sin crash [SCENARIO-CK-FC-09]',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          TreinoFilterChips(
            options: _options,
            selected: const {'Activos'},
            onChanged: (_) {},
          ),
          theme: theme,
        ));
        await tester.pump();
        for (final o in _options) {
          expect(find.text(o), findsOneWidget);
        }
      }
    });

    // -------------------------------------------------------------------------
    // Single-select: cambiar selección reemplaza la anterior
    // -------------------------------------------------------------------------
    testWidgets('single-select → tap cambia selección [SCENARIO-CK-FC-10]',
        (tester) async {
      Set<String> lastSelected = {'Activos'};
      await tester.pumpWidget(_wrap(
        TreinoFilterChips(
          options: _options,
          selected: const {'Activos'},
          multiSelect: false,
          onChanged: (s) => lastSelected = s,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Inactivos'));
      await tester.pump();
      expect(lastSelected, equals({'Inactivos'}));
    });
  });
}
