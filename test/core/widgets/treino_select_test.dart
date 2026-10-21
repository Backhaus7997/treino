import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/core/widgets/treino_select.dart';

const _opciones = [
  TreinoSelectOption<String?>(value: null, label: 'Ninguno', muted: true),
  TreinoSelectOption<String?>(value: 'pecho', label: 'Pecho'),
  TreinoSelectOption<String?>(value: 'espalda', label: 'Espalda'),
];

Widget _harness({
  required ThemeData theme,
  required Widget child,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(width: 320, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

void _tamanio(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  // Los temas resuelven tipografía por GoogleFonts al construirse en el
  // encabezado del `for`, antes de que corra ningún test.
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in <(String, ThemeData)>[
    ('oscuro', AppTheme.dark()),
    ('claro', AppTheme.light()),
  ]) {
    testWidgets(
        'en teléfono abre una hoja del kit y marca la elegida '
        '(${entry.$1})', (tester) async {
      _tamanio(tester, const Size(390, 844));
      String? elegido = 'pecho';
      var llamadas = 0;
      await tester.pumpWidget(
        _harness(
          theme: entry.$2,
          child: StatefulBuilder(
            builder: (context, setState) => TreinoSelectField<String?>(
              value: elegido,
              options: _opciones,
              sheetTitle: 'Grupo muscular',
              onChanged: (v) => setState(() {
                llamadas++;
                elegido = v;
              }),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pecho'));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold));
      final palette = AppPalette.of(context);

      // Hoja con el chrome de las otras hojas de la app.
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        palette.bgElevated,
      );
      expect(find.text('GRUPO MUSCULAR'), findsOneWidget);

      // Un solo check visible, en la fila elegida, pintado con accentText
      // (no `accent`: en claro el mint como tinta da 1,57:1).
      final checks = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byIcon(TreinoIcon.checkBare),
              matching: find.byType(Opacity),
            ),
          )
          .where((o) => o.opacity == 1)
          .toList();
      expect(checks, hasLength(1));
      final filaPecho = find.ancestor(
        of: find.text('Pecho').last,
        matching: find.byType(Row),
      );
      final iconoPecho = tester.widget<Icon>(
        find.descendant(
            of: filaPecho, matching: find.byIcon(TreinoIcon.checkBare)),
      );
      expect(iconoPecho.color, palette.accentText);

      // Elegir «Ninguno» devuelve null como VALOR — distinto de cerrar.
      await tester.tap(find.text('Ninguno'));
      await tester.pumpAndSettle();
      expect(llamadas, 1);
      expect(elegido, isNull);
      expect(find.byType(BottomSheet), findsNothing);
    });
  }

  testWidgets('cerrar sin elegir no llama a onChanged', (tester) async {
    _tamanio(tester, const Size(390, 844));
    var llamadas = 0;
    await tester.pumpWidget(
      _harness(
        theme: AppTheme.light(),
        child: TreinoSelectField<String?>(
          value: 'pecho',
          options: _opciones,
          sheetTitle: 'Grupo muscular',
          onChanged: (_) => llamadas++,
        ),
      ),
    );

    await tester.tap(find.text('Pecho'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // la barrera
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(llamadas, 0);
  });

  testWidgets('sin valor muestra el hint y no marca ninguna fila',
      (tester) async {
    _tamanio(tester, const Size(390, 844));
    await tester.pumpWidget(
      _harness(
        theme: AppTheme.dark(),
        child: TreinoSelectField<String>(
          value: null,
          hint: 'Seleccionar…',
          options: const [
            TreinoSelectOption(value: 'a', label: 'A'),
            TreinoSelectOption(value: 'b', label: 'B'),
          ],
          sheetTitle: 'Letra',
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Seleccionar…'), findsOneWidget);
    await tester.tap(find.text('Seleccionar…'));
    await tester.pumpAndSettle();
    final visibles = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.byIcon(TreinoIcon.checkBare),
            matching: find.byType(Opacity),
          ),
        )
        .where((o) => o.opacity == 1);
    expect(visibles, isEmpty);
  });

  testWidgets('una lista larga abre con la elegida a la vista', (tester) async {
    _tamanio(tester, const Size(390, 700));
    final opciones = [
      for (var i = 0; i < 30; i++)
        TreinoSelectOption<int>(value: i, label: 'Opción $i'),
    ];
    await tester.pumpWidget(
      _harness(
        theme: AppTheme.dark(),
        child: TreinoSelectField<int>(
          value: 25,
          options: opciones,
          sheetTitle: 'Muchas',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Opción 25'));
    await tester.pumpAndSettle();

    final hoja = tester.getRect(find.byType(BottomSheet));
    final fila = tester.getRect(find.text('Opción 25').last);
    expect(hoja.contains(fila.center), isTrue);
    // Y la hoja no tapa la pantalla entera.
    expect(hoja.height, lessThanOrEqualTo(700 * 0.7 + 1));
  });

  testWidgets('en pantalla ancha es un menú anclado debajo del campo',
      (tester) async {
    _tamanio(tester, const Size(1280, 800));
    String? elegido;
    await tester.pumpWidget(
      _harness(
        theme: AppTheme.light(),
        child: TreinoSelectField<String?>(
          value: null,
          hint: 'Elegí',
          options: _opciones,
          sheetTitle: 'Grupo muscular',
          onChanged: (v) => elegido = v,
        ),
      ),
    );

    final campo = tester.getRect(find.byType(InputDecorator));
    await tester.tap(find.byType(InputDecorator));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    final menu = tester.getRect(
      find
          .ancestor(of: find.text('Espalda'), matching: find.byType(Material))
          .last,
    );
    expect(menu.top, greaterThanOrEqualTo(campo.bottom));
    expect(menu.width, closeTo(campo.width, 0.5));
    expect(menu.left, closeTo(campo.left, 0.5));

    await tester.tap(find.text('Espalda'));
    await tester.pumpAndSettle();
    expect(elegido, 'espalda');
  });

  testWidgets('con reducir movimiento el menú aparece sin animar',
      (tester) async {
    _tamanio(tester, const Size(1280, 800));
    await tester.pumpWidget(
      _harness(
        theme: AppTheme.dark(),
        reduceMotion: true,
        child: TreinoSelectField<String?>(
          value: 'pecho',
          options: _opciones,
          sheetTitle: 'Grupo muscular',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Pecho'));
    await tester.pump();
    await tester.pump();

    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
              of: find.text('Espalda'), matching: find.byType(FadeTransition))
          .first,
    );
    expect(fade.opacity.value, 1);
  });

  testWidgets('sin onChanged el campo no abre nada', (tester) async {
    _tamanio(tester, const Size(390, 844));
    await tester.pumpWidget(
      _harness(
        theme: AppTheme.dark(),
        child: const TreinoSelectField<String?>(
          value: 'pecho',
          options: _opciones,
          sheetTitle: 'Grupo muscular',
          onChanged: null,
        ),
      ),
    );

    await tester.tap(find.text('Pecho'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  // El campo y las filas excluyen la semántica de su InkWell para anunciarse
  // limpias; si no reponen la acción, VoiceOver/TalkBack anuncian un botón
  // que no responde al doble toque. `tester.tap` no lo ve: va por puntero.
  testWidgets('el lector de pantalla puede abrir el campo y elegir',
      (tester) async {
    _tamanio(tester, const Size(390, 844));
    final handle = tester.ensureSemantics();
    String? elegido = 'pecho';
    await tester.pumpWidget(
      _harness(
        theme: AppTheme.dark(),
        child: StatefulBuilder(
          builder: (context, setState) => TreinoSelectField<String?>(
            value: elegido,
            options: _opciones,
            sheetTitle: 'Grupo muscular',
            onChanged: (v) => setState(() => elegido = v),
          ),
        ),
      ),
    );

    final campo = find.bySemanticsLabel('Grupo muscular');
    expect(
      tester.getSemantics(campo),
      isSemantics(isButton: true, hasTapAction: true, value: 'Pecho'),
    );
    tester.semantics.tap(find.semantics.byLabel('Grupo muscular'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Pecho')),
      isSemantics(isButton: true, isSelected: true, hasTapAction: true),
    );
    tester.semantics.tap(find.semantics.byLabel('Espalda'));
    await tester.pumpAndSettle();
    expect(elegido, 'espalda');
    handle.dispose();
  });

  // El campo pinta `bgCard` encima del highlight de foco del InkWell: si el
  // foco no llega al InputDecorator, navegar con Tab (Coach Hub) no muestra
  // nada hasta que el selector ya está abierto.
  testWidgets('el foco de teclado se ve antes de abrir', (tester) async {
    _tamanio(tester, const Size(1280, 800));
    await tester.pumpWidget(
      _harness(
        theme: AppTheme.light(),
        child: TreinoSelectField<String?>(
          value: 'pecho',
          options: _opciones,
          sheetTitle: 'Grupo muscular',
          onChanged: (_) {},
        ),
      ),
    );

    bool enfocado() =>
        tester.widget<InputDecorator>(find.byType(InputDecorator)).isFocused;
    expect(enfocado(), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(enfocado(), isTrue);

    final context = tester.element(find.byType(InputDecorator));
    final borde = tester
        .widget<InputDecorator>(find.byType(InputDecorator))
        .decoration
        .focusedBorder as OutlineInputBorder;
    expect(borde.borderSide.color, AppPalette.of(context).accentText);
    // Y nada se abrió: es sólo el indicador.
    expect(find.text('Espalda'), findsNothing);
  });
}
