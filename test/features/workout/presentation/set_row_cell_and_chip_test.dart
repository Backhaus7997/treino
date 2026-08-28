// Guards del slice 1/9 del rediseño de "Crear rutina" (#863).
//
// Dos regresiones concretas que este PR arregla y que no se pueden dejar sin
// red: el chip de tipo de set era invisible, y la celda numérica medía menos
// que el mínimo táctil.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_limits.dart';
import 'package:treino/features/workout/presentation/widgets/set_cell_field.dart';
import 'package:treino/features/workout/presentation/widgets/set_type_chip.dart';

Widget _host(AppPalette palette, Widget child) => MaterialApp(
      theme: ThemeData(extensions: [palette]),
      home: Scaffold(
        backgroundColor: palette.bgCard,
        body: Center(child: child),
      ),
    );

/// Diferencia máxima por canal, en 0-255.
int _maxChannelDelta(Color a, Color b) {
  int c8(double v) => (v * 255).round();
  final d = [
    (c8(a.r) - c8(b.r)).abs(),
    (c8(a.g) - c8(b.g)).abs(),
    (c8(a.b) - c8(b.b)).abs(),
  ];
  return d.reduce((x, y) => x > y ? x : y);
}

void main() {
  const paletas = <String, AppPalette>{
    'dark': AppPalette.mintMagenta,
    'light': AppPalette.mintMagentaLight,
  };

  group('SetTypeChip — el chip normal dejó de ser invisible', () {
    // El bug: _chipColor(SetType.normal) devolvía palette.bgCard, el MISMO
    // color de la card que contiene el chip. Existía, ocupaba lugar y no se
    // veía. Por eso la rama base agregó el token surfaceSubtle.
    for (final entry in paletas.entries) {
      testWidgets('${entry.key}: se despega de la card que lo contiene',
          (tester) async {
        final palette = entry.value;
        await tester.pumpWidget(_host(
          palette,
          SetTypeChip(
            label: '1',
            type: SetType.normal,
            palette: palette,
            semanticsLabel: 'set 1',
            onTap: () {},
          ),
        ));

        final deco = tester
            .widget<Container>(find.descendant(
              of: find.byType(SetTypeChip),
              matching: find.byType(Container),
            ))
            .decoration as BoxDecoration;

        expect(
          deco.color,
          isNot(equals(palette.bgCard)),
          reason: 'Si el chip normal vuelve a pintarse con bgCard, es '
              'invisible dentro de la card. Ese era el bug de #863.',
        );
        expect(
          _maxChannelDelta(
            Color.alphaBlend(deco.color!, palette.bgCard),
            palette.bgCard,
          ),
          greaterThanOrEqualTo(8),
          reason: 'No alcanza con que el token sea distinto: compuesto sobre '
              'la card tiene que verse.',
        );
      });
    }

    testWidgets('los cuatro tipos se distinguen entre sí', (tester) async {
      const palette = AppPalette.mintMagenta;
      final fondos = <SetType, Color>{};
      for (final t in SetType.values) {
        await tester.pumpWidget(_host(
          palette,
          SetTypeChip(
            label: 'x',
            type: t,
            palette: palette,
            semanticsLabel: 'set',
            onTap: () {},
          ),
        ));
        final deco = tester
            .widget<Container>(find.descendant(
              of: find.byType(SetTypeChip),
              matching: find.byType(Container),
            ))
            .decoration as BoxDecoration;
        fondos[t] = Color.alphaBlend(deco.color!, palette.bgCard);
      }
      final vistos = <Color>[];
      for (final c in fondos.values) {
        for (final previo in vistos) {
          expect(_maxChannelDelta(c, previo), greaterThanOrEqualTo(6),
              reason: 'Dos tipos de set no se distinguen: $fondos');
        }
        vistos.add(c);
      }
    });

    testWidgets('conserva el Semantics que anuncia posición y tipo',
        (tester) async {
      const palette = AppPalette.mintMagenta;
      await tester.pumpWidget(_host(
        palette,
        SetTypeChip(
          label: 'W',
          type: SetType.warmup,
          palette: palette,
          semanticsLabel: 'set 1, calentamiento',
          onTap: () {},
        ),
      ));
      // El glifo pelado "W" no le dice nada a VoiceOver; el label sí.
      // Se mira el widget Semantics directo en vez de bySemanticsLabel: el
      // Text hijo aporta su propio nodo ("W") y el matcher del árbol compuesto
      // es frágil. Acá lo que importa es que el label no se haya perdido al
      // extraer el chip a su propio widget.
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(SetTypeChip),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.label, 'set 1, calentamiento');
      expect(semantics.properties.button, isTrue);
    });
  });

  group('altura mínima táctil de la fila de set', () {
    testWidgets('SetCellField mide 48 dp de alto', (tester) async {
      const palette = AppPalette.mintMagenta;
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_host(
        palette,
        SizedBox(
          width: 120,
          child: SetCellField(
            controller: ctrl,
            palette: palette,
            hint: 'reps',
            onChanged: (_) {},
          ),
        ),
      ));
      expect(tester.getSize(find.byType(SetCellField)).height, 48.0);
    });

    testWidgets('SetTypeChip mide 48 dp de alto', (tester) async {
      const palette = AppPalette.mintMagenta;
      await tester.pumpWidget(_host(
        palette,
        SetTypeChip(
          label: '1',
          type: SetType.normal,
          palette: palette,
          semanticsLabel: 'set 1',
          onTap: () {},
        ),
      ));
      expect(tester.getSize(find.byType(SetTypeChip)).height, 48.0);
    });
  });

  group('SetCellField conserva el contrato de _NumberField', () {
    testWidgets('el tope de dominio sigue aplicándose (BoundedNumberFormatter)',
        (tester) async {
      const palette = AppPalette.mintMagenta;
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      int? ultimo;
      await tester.pumpWidget(_host(
        palette,
        SizedBox(
          width: 120,
          child: SetCellField(
            controller: ctrl,
            palette: palette,
            onChanged: (v) => ultimo = v,
          ),
        ),
      ));

      // Un valor dentro del rango entra y llega al callback.
      await tester.enterText(find.byType(TextField), '$kMaxReps');
      await tester.pump();
      expect(ctrl.text, '$kMaxReps');
      expect(ultimo, kMaxReps);

      // QA-WKT-003: pasarse del techo NO clampea — RECHAZA la edición entera
      // (`return oldValue`). El texto que el atleta ve es siempre exactamente
      // el valor que se parsea y se guarda.
      await tester.enterText(find.byType(TextField), '${kMaxReps + 1}');
      await tester.pump();
      expect(ctrl.text, '$kMaxReps',
          reason: 'un set imposible no puede autorearse');
    });

    testWidgets('decimal parsea coma y punto', (tester) async {
      const palette = AppPalette.mintMagenta;
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      double? ultimo;
      await tester.pumpWidget(_host(
        palette,
        SizedBox(
          width: 120,
          child: SetCellField(
            controller: ctrl,
            palette: palette,
            decimal: true,
            onDecimalChanged: (v) => ultimo = v,
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), '17,5');
      await tester.pump();
      expect(ultimo, 17.5);
    });
  });
}
