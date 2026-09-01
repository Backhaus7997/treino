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
      addDayLabel: 'Agregar día',
      statusLabel: (e) => e == DayTabStatus.empty ? 'día vacío' : 'sin reps',
    );

/// Todos los labels de semántica presentes en el árbol.
///
/// Se mira el conjunto y no un ancestro puntual: `find.ancestor(...).first`
/// devuelve el Semantics más externo —el del Scaffold— cuyo label es null.
Iterable<String> _labels(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((s) => s.properties.label)
    .whereType<String>();

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
        addDayLabel: 'Agregar día',
        statusLabel: (_) => '',
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

  // Guards de accesibilidad — salieron del review del bot en #883/#884.
  testWidgets('el botón + tiene nombre accesible', (tester) async {
    // El control anterior era un TextButton.icon con "Agregar día" VISIBLE.
    // Este es sólo un "+": sin label, un lector de pantalla anuncia un botón
    // sin nombre y el usuario no sabe qué hace.
    await tester.pumpWidget(_host(AppPalette.mintMagenta, _barra()));
    expect(_labels(tester), contains('Agregar día'));
  });

  testWidgets('una pestaña inactiva con problema lo ANUNCIA, no sólo lo pinta',
      (tester) async {
    // El punto de color no existe para asistencia técnica: sin label, un día
    // vacío y uno con sets sin completar suenan idénticos.
    await tester.pumpWidget(_host(AppPalette.mintMagenta, _barra()));

    final labels = _labels(tester);
    // 0 está seleccionada: sin sufijo de estado.
    expect(labels, contains('Día 1'));
    // 1 vacía, 2 inválida: cada una dice lo suyo.
    expect(labels, contains('Día 2, día vacío'));
    expect(labels, contains('Día 3, sin reps'));
  });

  testWidgets('el label accesible usa el nombre COMPLETO, no el truncado',
      (tester) async {
    await tester.pumpWidget(_host(
      AppPalette.mintMagenta,
      DayTabBar(
        labels: const ['Pecho, hombro y tríceps completo'],
        statuses: const [DayTabStatus.ok],
        selectedIndex: 0,
        onSelect: (_) {},
        onAddDay: () {},
        addDayLabel: 'Agregar día',
        statusLabel: (_) => '',
      ),
    ));
    // La elipsis es una limitación de ancho, no información.
    expect(_labels(tester), contains('Pecho, hombro y tríceps completo'));
  });

  testWidgets('las pestañas llegan al mínimo táctil de 48', (tester) async {
    // El `SizedBox` de la barra capa el alto de CADA pestaña y del control de
    // agregar día: con 44 ninguno llegaba al mínimo que fija la épica #862
    // para todo target interactivo. Lo encontró el bot de review.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.mintMagenta]),
        home: Scaffold(
          body: DayTabBar(
            labels: const ['Día 1', 'Día 2'],
            statuses: const [DayTabStatus.ok, DayTabStatus.ok],
            selectedIndex: 0,
            onSelect: (_) {},
            onAddDay: () {},
            addDayLabel: 'Día',
            statusLabel: (_) => '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(DayTabBar)).height,
        greaterThanOrEqualTo(48));
    for (var i = 0; i < 2; i++) {
      expect(tester.getSize(find.byKey(Key('day_tab_$i'))).height,
          greaterThanOrEqualTo(48),
          reason: 'pestaña $i');
    }
  });
}
