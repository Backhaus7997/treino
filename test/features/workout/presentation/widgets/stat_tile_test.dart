import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/presentation/widgets/stat_tile.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('StatTile', () {
    testWidgets('SCENARIO-095: label and value are both rendered',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(label: 'EJERCICIOS', value: '6'),
      ));
      expect(find.text('EJERCICIOS'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('SCENARIO-096: value null renders dash without exception',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(label: 'DURACIÓN', value: null),
      ));
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets(
        'sin icon no renderiza ícono — las 7 pantallas que ya usaban '
        'StatTile quedan igual', (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(label: 'SETS', value: '12'),
      ));
      expect(find.byType(Icon), findsNothing);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('con icon renderiza el ícono junto al valor', (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(
          icon: TreinoIcon.clock,
          label: 'DURACIÓN MIN',
          value: '67',
        ),
      ));
      expect(find.byIcon(TreinoIcon.clock), findsOneWidget);
      expect(find.text('67'), findsOneWidget);
      expect(find.text('DURACIÓN MIN'), findsOneWidget);
    });

    testWidgets('isAccent colorea sólo el valor con palette.accent',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(label: 'RACHA', value: '23', isAccent: true),
      ));

      final context = tester.element(find.byType(StatTile));
      final palette = AppPalette.of(context);
      final value = tester.widget<Text>(find.text('23'));
      final label = tester.widget<Text>(find.text('RACHA'));

      expect(value.style?.color, palette.accent);
      expect(label.style?.color, palette.textMuted);
    });

    testWidgets('isAccent defaults to the legacy textPrimary value color',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const StatTile(label: 'SETS', value: '12'),
      ));

      final context = tester.element(find.byType(StatTile));
      final value = tester.widget<Text>(find.text('12'));

      expect(value.style?.color, AppPalette.of(context).textPrimary);
    });

    // Regresión: la variante con ícono suma ancho fijo (ícono + gap) al lado
    // del número. Sin acotar el valor, desborda en celdas angostas. Este test
    // es falsable: si se quita el Flexible + FittedBox de stat_tile.dart,
    // vuelve a fallar.
    testWidgets(
        'con icon y valor largo en celda angosta no desborda a la '
        'derecha', (tester) async {
      tester.view.physicalSize = const Size(140, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final horizontalOverflows = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final message = details.exceptionAsString();
        if (message.contains('overflowed')) {
          if (message.contains('on the right')) {
            horizontalOverflows.add(details);
          }
          return; // desbordes verticales acá no son lo que se mide
        }
        originalOnError?.call(details);
      };
      try {
        await tester.pumpWidget(_wrap(
          const Center(
            child: StatTile(
              icon: TreinoIcon.dumbbell,
              label: 'VOLUMEN KG',
              value: '123.456',
            ),
          ),
        ));
        await tester.pumpAndSettle();
      } finally {
        // Restaurar ANTES de cualquier expect(): el binding reporta los fallos
        // de expect a través de FlutterError.onError.
        FlutterError.onError = originalOnError;
      }

      expect(
        horizontalOverflows.map((d) => d.exceptionAsString()).toList(),
        isEmpty,
      );
    });
  });
}
