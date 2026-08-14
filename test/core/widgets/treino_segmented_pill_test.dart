import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/components/treino_focus_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_segmented_pill_tokens.dart';
import 'package:treino/core/widgets/treino_segmented_pill.dart';

Widget _wrap(
  Widget child, {
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: appChild!,
      ),
      home: Scaffold(
        body: DefaultTabController(
          length: _labels.length,
          child: child,
        ),
      ),
    );

const _labels = ['TU ENTRENO', 'PLANTILLAS'];

void main() {
  group('TreinoSegmentedPill', () {
    testWidgets('renderiza un TabBar con una celda por etiqueta',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const TreinoSegmentedPill(labels: _labels)),
      );

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(Tab), findsNWidgets(2));
      for (final label in _labels) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('la pista se pinta con el contorno de 3:1, no con el de card',
        (tester) async {
      // Sin esto el test suite entero pasa aunque alguien reponga
      // `palette.border` — que es 1.40:1 y deja el control invisible otra vez.
      // Los tests de tokens sólo prueban aritmética sobre constantes; este
      // lee lo que realmente se pinta.
      late TreinoSegmentedPillTokens tokens;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) {
              tokens = TreinoSegmentedPillTokens.of(ctx);
              return const TreinoSegmentedPill(labels: _labels);
            },
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .ancestor(of: find.byType(TabBar), matching: find.byType(Container))
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(decoration.border!.top.color, tokens.trackBorder);
      expect(decoration.color, tokens.trackFill);
    });

    testWidgets('el thumb lleva el keyline que identifica el estado en claro',
        (tester) async {
      // Borrar el keyline deja al tema claro sin forma de distinguir la celda
      // activa (mint sobre pista clara: 1.64:1). Sin este test, borrarlo pasa
      // desapercibido.
      await tester.pumpWidget(
        _wrap(const TreinoSegmentedPill(labels: _labels)),
      );

      final indicator = tester.widget<TabBar>(find.byType(TabBar)).indicator!
          as BoxDecoration;

      expect(indicator.border, isNotNull,
          reason: 'el thumb necesita keyline — ver TreinoSegmentedPillTokens');
      expect(
        indicator.border!.top.color,
        TreinoSegmentedPillTokens.activeInk,
      );
    });

    testWidgets('el label activo usa ink, no palette.bg', (tester) async {
      // El bug original: palette.bg sobre el acento da 1.57:1 en tema claro.
      await tester.pumpWidget(
        _wrap(const TreinoSegmentedPill(labels: _labels)),
      );

      expect(
        tester.widget<TabBar>(find.byType(TabBar)).labelColor,
        TreinoSegmentedPillTokens.activeInk,
      );
    });

    testWidgets('el foco de teclado dibuja un anillo en la pista',
        (tester) async {
      // El overlay de foco de TabBar no se ve sobre la celda ACTIVA: la tinta
      // de Material se pinta debajo del subárbol y el thumb opaco la tapa. Sin
      // este anillo, un usuario de teclado que activa una pestaña se queda sin
      // indicador justo donde está parado — WCAG 2.4.7.
      await tester.pumpWidget(
        _wrap(const TreinoSegmentedPill(labels: _labels)),
      );

      BoxDecoration trackDecoration() => tester
          .widget<Container>(
            find
                .ancestor(
                  of: find.byType(TabBar),
                  matching: find.byType(Container),
                )
                .first,
          )
          .decoration! as BoxDecoration;

      expect(trackDecoration().boxShadow, isNull,
          reason: 'sin foco no hay anillo');

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final focused = trackDecoration().boxShadow;
      expect(focused, isNotNull,
          reason: 'con foco de teclado tiene que haber '
              'anillo visible en la pista');
      expect(focused!.single.spreadRadius, TreinoFocusTokens.ringWidth);
    });

    testWidgets('cada celda llega al área tapeable mínima', (tester) async {
      // Las cuatro copias que esto reemplaza estaban en 38-40pt, por debajo
      // del mínimo de plataforma. Es la mitad "no lo alcanzo" de #646.
      await tester.pumpWidget(
        _wrap(const TreinoSegmentedPill(labels: _labels)),
      );

      final height = tester.getSize(find.byType(Tab).first).height;
      expect(
        height,
        greaterThanOrEqualTo(TreinoSegmentedPillTokens.minSegmentHeight),
      );
    });

    testWidgets('reparte el ancho con escala normal', (tester) async {
      await tester.pumpWidget(
        _wrap(const TreinoSegmentedPill(labels: _labels)),
      );

      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect(bar.isScrollable, isFalse);
      expect(bar.tabAlignment, TabAlignment.fill);
    });

    testWidgets('aguanta escala de texto 3.2 sin desbordar', (tester) async {
      // Viewport realista: el default de 800x600 deja la fuente de fallback y
      // la real en lados opuestos del umbral.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          const TreinoSegmentedPill(labels: _labels),
          textScaler: const TextScaler.linear(3.2),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);

      // hitTestable() sólo sobre la PRIMERA: a esta escala la tira scrollea, y
      // las celdas siguientes quedan fuera del viewport hasta que el usuario
      // scrollea — que es exactamente el punto del modo scrolleable. Mismo
      // criterio que workout_screen_test.dart, que también verifica una sola.
      expect(find.text(_labels.first).hitTestable(), findsOneWidget);

      // Lo que se verifica es que la etiqueta ENTRE en su celda, no que tenga
      // tal o cual propiedad seteada. `maxLines`, `softWrap` y `overflow` son
      // inertes adentro de un `FittedBox` —layoutea con ancho infinito— así
      // que asertarlas pasaría por construcción sin comprobar nada. Ver el
      // comentario en treino_segmented_pill.dart.
      final segment = tester.getSize(find.byType(Tab).first);
      final label = tester.getSize(find.text(_labels.first));
      expect(
        label.width,
        lessThanOrEqualTo(segment.width),
        reason: 'la etiqueta desborda su celda a escala 3.2',
      );
    });

    testWidgets('el tap mueve el índice del controller ambiente',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const TreinoSegmentedPill(labels: _labels)),
      );

      final controller =
          DefaultTabController.of(tester.element(find.byType(TabBar)));
      expect(controller.index, 0);

      await tester.tap(find.text('PLANTILLAS'));
      await tester.pumpAndSettle();

      expect(controller.index, 1);
    });

    testWidgets('onTap dispara con el índice tocado', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
        _wrap(
          TreinoSegmentedPill(labels: _labels, onTap: taps.add),
        ),
      );

      await tester.tap(find.text('PLANTILLAS'));
      await tester.pumpAndSettle();

      expect(taps, [1]);
    });

    testWidgets('el overlay de interacción no queda en el default del tema',
        (tester) async {
      // Los pills originales seteaban splashBorderRadius pero dejaban el
      // overlay en ThemeData.splashColor, imperceptible sobre casi-negro.
      await tester.pumpWidget(
        _wrap(const TreinoSegmentedPill(labels: _labels)),
      );

      final overlay = tester.widget<TabBar>(find.byType(TabBar)).overlayColor!;
      final pressed = overlay.resolve({WidgetState.pressed});
      final hovered = overlay.resolve({WidgetState.hovered});
      final focused = overlay.resolve({WidgetState.focused});

      expect(pressed, isNotNull);
      expect(hovered, isNotNull);
      expect(focused, isNotNull);
      expect(pressed, isNot(equals(hovered)));
    });

    for (final entry in {
      'dark': AppTheme.dark(),
      'light': AppTheme.light(),
    }.entries) {
      testWidgets('renderiza sin excepciones en tema ${entry.key}',
          (tester) async {
        // El tema claro es el que nunca se probó — ahí vivían las dos fallas
        // de contraste que encontró #646.
        await tester.pumpWidget(
          _wrap(
            const TreinoSegmentedPill(labels: _labels),
            theme: entry.value,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(TabBar), findsOneWidget);
      });
    }
  });
}
