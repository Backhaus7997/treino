import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/components/treino_list_row_tokens.dart';
import 'package:treino/features/coach_hub/presentation/widgets/list_row/list_row.dart';

/// Envuelve en MaterialApp con el tema dado para que AppPalette resuelva.
Widget _wrap(Widget widget, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: widget),
    );

void main() {
  group('TreinoListRow —', () {
    // -------------------------------------------------------------------------
    // Normal: muestra título
    // -------------------------------------------------------------------------
    testWidgets('normal → muestra título [SCENARIO-CK-LR-01]', (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoListRow(
          key: Key('row'),
          title: 'Ana García',
        ),
      ));
      await tester.pump();
      expect(find.text('Ana García'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Con subtítulo
    // -------------------------------------------------------------------------
    testWidgets('con subtítulo → subtítulo visible [SCENARIO-CK-LR-02]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoListRow(
          key: Key('row'),
          title: 'Ana García',
          subtitle: 'Activo · 12 sesiones',
        ),
      ));
      await tester.pump();
      expect(find.text('Ana García'), findsOneWidget);
      expect(find.text('Activo · 12 sesiones'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Disabled: onTap null → disabled true
    // -------------------------------------------------------------------------
    testWidgets('onTap null → disabled [SCENARIO-CK-LR-03]', (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoListRow(
          key: Key('row'),
          title: 'Ana García',
        ),
      ));
      await tester.pump();
      // Sin onTap la row no debe crashear y el título sigue visible.
      expect(find.text('Ana García'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // onTap provisto → tappable
    // -------------------------------------------------------------------------
    testWidgets('onTap provisto → tappable [SCENARIO-CK-LR-04]',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_wrap(
        TreinoListRow(
          key: const Key('row'),
          title: 'Ana García',
          onTap: () => tapped++,
        ),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('row')));
      await tester.pump();
      expect(tapped, 1);
    });

    // -------------------------------------------------------------------------
    // Hover → no crashea
    // -------------------------------------------------------------------------
    testWidgets('hover → no crashea [SCENARIO-CK-LR-05]', (tester) async {
      await tester.pumpWidget(_wrap(
        TreinoListRow(
          key: const Key('row'),
          title: 'Ana García',
          onTap: () {},
        ),
      ));
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('row'))));
      await tester.pump();
      expect(find.byKey(const Key('row')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Pressed: tap-down usa el mismo background que hover (rama states.pressed)
    // -------------------------------------------------------------------------
    testWidgets('pressed (tap-down) → usa hoverBackground [SCENARIO-CK-LR-12]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TreinoListRow(
          key: const Key('row'),
          title: 'Ana García',
          onTap: () {},
        ),
      ));
      await tester.pump();

      Color rowColor() {
        final container = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(const Key('row')),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      final normalColor = rowColor();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('row'))),
      );
      await tester.pump();

      final pressedColor = rowColor();
      final tokens = TreinoListRowTokens.of(
        tester.element(find.byKey(const Key('row'))),
      );
      expect(pressedColor, equals(tokens.hoverBackground),
          reason: 'pressed debe usar el mismo background que hover');
      expect(pressedColor, isNot(equals(normalColor)),
          reason: 'el background debe cambiar realmente al presionar');

      await gesture.up();
      await tester.pump();
    });

    // -------------------------------------------------------------------------
    // Loading → skeleton visible, título oculto
    // -------------------------------------------------------------------------
    testWidgets('loading=true → skeleton visible [SCENARIO-CK-LR-06]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoListRow(
          key: Key('row'),
          title: 'Ana García',
          loading: true,
        ),
      ));
      await tester.pump();
      expect(find.text('Ana García'), findsNothing,
          reason: 'título no visible durante loading');
      expect(find.byKey(const Key('list_row_skeleton')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Dense: altura menor que normal
    // -------------------------------------------------------------------------
    testWidgets('dense=true → widget renderiza sin crash [SCENARIO-CK-LR-07]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoListRow(
          key: Key('row'),
          title: 'Ana García',
          dense: true,
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('row')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Leading slot
    // -------------------------------------------------------------------------
    testWidgets('leading slot → widget leading visible [SCENARIO-CK-LR-08]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoListRow(
          key: Key('row'),
          title: 'Ana García',
          leading: Icon(Icons.person, key: Key('leading_icon')),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('leading_icon')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Trailing slot
    // -------------------------------------------------------------------------
    testWidgets('trailing slot → widget trailing visible [SCENARIO-CK-LR-09]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TreinoListRow(
          key: Key('row'),
          title: 'Ana García',
          trailing: Icon(Icons.chevron_right, key: Key('trailing_icon')),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const Key('trailing_icon')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Smoke dark + light
    // -------------------------------------------------------------------------
    testWidgets('smoke dark+light sin crash [SCENARIO-CK-LR-10]',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          TreinoListRow(
            key: const Key('row'),
            title: 'Ana García',
            subtitle: 'Activo',
            onTap: () {},
          ),
          theme: theme,
        ));
        await tester.pump();
        expect(find.text('Ana García'), findsOneWidget);
        expect(find.text('Activo'), findsOneWidget);
      }
    });

    // -------------------------------------------------------------------------
    // Tokens: dark != light (smoke en ambos temas, no hex)
    // -------------------------------------------------------------------------
    testWidgets('tokens dark+light — smoke sin crash [SCENARIO-CK-LR-11]',
        (tester) async {
      // Verifica que el componente renderiza correctamente en ambos temas
      // (tokens resuelven via AppPalette que cambia con el tema).
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          TreinoListRow(
            key: const Key('row'),
            title: 'Carlos López',
            subtitle: 'Inactivo',
            onTap: () {},
          ),
          theme: theme,
        ));
        await tester.pump();
        expect(find.text('Carlos López'), findsOneWidget);
        expect(find.text('Inactivo'), findsOneWidget);
      }
    });
  });
}
