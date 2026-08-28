// Guards del slice 3/9 del rediseño de "Crear rutina" (#865).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/workout/presentation/widgets/day_tab_bar.dart';

Widget _host(AppPalette palette, Widget child) => MaterialApp(
      theme: ThemeData(extensions: [palette]),
      home: Scaffold(body: child),
    );

DayTabBar _barra({
  int seleccionado = 0,
  List<DayTabStatus>? estados,
  void Function(int)? onSelect,
  // `sinAgregar` y no `onAddDay: null`: un parámetro opcional nulo no se
  // distingue de uno no pasado, y el default lo tapaba.
  bool sinAgregar = false,
}) =>
    DayTabBar(
      labels: const ['Día 1', 'Día 2', 'Día 3'],
      statuses: estados ??
          const [DayTabStatus.ok, DayTabStatus.empty, DayTabStatus.invalid],
      selectedIndex: seleccionado,
      onSelect: onSelect ?? (_) {},
      onAddDay: sinAgregar ? null : () {},
    );

void main() {
  const paletas = <String, AppPalette>{
    'dark': AppPalette.mintMagenta,
    'light': AppPalette.mintMagentaLight,
  };

  testWidgets('tocar una pestaña reporta su índice', (tester) async {
    int? elegido;
    await tester.pumpWidget(_host(
      AppPalette.mintMagenta,
      _barra(onSelect: (i) => elegido = i),
    ));

    await tester.tap(find.byKey(const Key('day_tab_2')));
    expect(elegido, 2);
  });

  testWidgets('el punto de estado NO aparece en la pestaña activa',
      (tester) async {
    // Con el día abierto el problema ya se ve en el contenido; repetirlo
    // arriba es ruido. Sólo las pestañas que NO estás mirando avisan.
    const palette = AppPalette.mintMagenta;

    Future<int> puntosCon(int seleccionado) async {
      await tester.pumpWidget(_host(
        palette,
        _barra(
          seleccionado: seleccionado,
          estados: const [
            DayTabStatus.invalid,
            DayTabStatus.invalid,
            DayTabStatus.invalid,
          ],
        ),
      ));
      return find
          .byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle)
          .evaluate()
          .length;
    }

    // Tres días con problema, uno seleccionado → dos puntos.
    expect(await puntosCon(0), 2);
  });

  testWidgets('vacío e inválido se distinguen por color', (tester) async {
    const palette = AppPalette.mintMagenta;
    await tester.pumpWidget(_host(
      palette,
      _barra(
        seleccionado: 0,
        estados: const [
          DayTabStatus.ok,
          DayTabStatus.empty,
          DayTabStatus.invalid,
        ],
      ),
    ));

    final colores = tester
        .widgetList<Container>(find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle))
        .map((c) => (c.decoration! as BoxDecoration).color)
        .toSet();

    // Un día sin ejercicios es un estado intermedio legítimo (warning); uno
    // con sets sin completar bloquea el guardado (danger). Distinto color.
    expect(colores, containsAll([palette.warning, palette.danger]));
  });

  testWidgets('el botón + se deshabilita en el tope de días', (tester) async {
    await tester.pumpWidget(_host(
      AppPalette.mintMagenta,
      _barra(sinAgregar: true),
    ));

    final boton = find.byKey(const Key('day_tab_add'));
    expect(boton, findsOneWidget);
    expect(tester.widget<InkWell>(boton).onTap, isNull);
  });

  testWidgets('un nombre largo se trunca en vez de empujar las pestañas',
      (tester) async {
    await tester.pumpWidget(_host(
      AppPalette.mintMagenta,
      DayTabBar(
        labels: const ['Pecho, hombro y tríceps completo'],
        statuses: const [DayTabStatus.ok],
        selectedIndex: 0,
        onSelect: (_) {},
        onAddDay: () {},
      ),
    ));
    expect(find.text('Pecho, hombro y…'), findsOneWidget);
  });

  for (final entry in paletas.entries) {
    testWidgets('${entry.key}: la pestaña activa no usa palette.bg como texto',
        (tester) async {
      // AGENTS.md regla 2: sobre relleno accent va el ink invariante de
      // TreinoButtonTokens. En light, `bg` sobre `accent` compone 1,57:1.
      final palette = entry.value;
      await tester.pumpWidget(_host(palette, _barra(seleccionado: 0)));

      final activo = tester.widget<Text>(find.text('Día 1'));
      expect(activo.style!.color, AppColorPrimitives.ink950,
          reason: 'ink invariante, el mismo en las dos paletas');
      // En light el atajo tentador —usar palette.bg como "el color opuesto"—
      // compone 1,57:1 sobre el mint. En dark los dos valores coinciden, así
      // que la trampa sólo se puede afirmar del lado claro.
      if (palette.bg != AppColorPrimitives.ink950) {
        expect(activo.style!.color, isNot(palette.bg));
      }
    });
  }
}
