import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';

Widget _wrap(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: appChild!,
      ),
      home: Scaffold(body: child),
    );

/// Opacidad del label de un tab. Vive acá arriba porque lo usan dos grupos.
double labelOpacityOf(WidgetTester tester, String label) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.text(label, skipOffstage: false),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

void main() {
  group('TreinoBottomBar — Coach tab badge', () {
    testWidgets('coachUnreadCount 0 → no badge rendered', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            coachUnreadCount: 0,
          ),
        ),
      );
      await tester.pump();

      // No badge text should be visible
      expect(find.text('1'), findsNothing);
      expect(find.text('5'), findsNothing);
      expect(find.text('99+'), findsNothing);
    });

    testWidgets('coachUnreadCount 3 → badge "3" visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            coachUnreadCount: 3,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('coachUnreadCount 100 → badge shows "99+"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            coachUnreadCount: 100,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets('coachUnreadCount defaults to 0 (no badge)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            // no coachUnreadCount parameter
          ),
        ),
      );
      await tester.pump();

      // Confirm no badge-style text leaks in
      expect(find.text('0'), findsNothing);
    });
  });

  group('TreinoBottomBar — Feed tab badge', () {
    testWidgets('feedUnreadCount 0 → no badge rendered', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 0,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1'), findsNothing);
      expect(find.text('5'), findsNothing);
      expect(find.text('99+'), findsNothing);
    });

    testWidgets('feedUnreadCount 2 → badge "2" visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 2,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('feedUnreadCount 100 → badge shows "99+"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 100,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets('feed 2 + coach 3 → both badges visible independently',
        (tester) async {
      // Regression guard: the two badges must not shadow each other. This
      // reproduces the "message from friend surfaces on both tabs" bug —
      // pre-split, only one badge existed and could render on the wrong tab.
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 2,
            coachUnreadCount: 3,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  // El álgebra de la barra, sin fuentes de por medio.
  //
  // Por qué unit test y no widget test: el proyecto usa google_fonts sin
  // bundlear las tipografías, así que se bajan por red; y flutter_test mockea
  // HTTP devolviendo 400 a todo. En test Barlow Condensed NUNCA carga y todo
  // se mide con una fuente fallback bastante más ancha. Un widget test que
  // preguntara "¿entra ENTRENAR?" estaría midiendo la fuente equivocada.
  // Tomando maxLabelWidth como entrada, esto es aritmética exacta.
  group('resolveBarMetrics', () {
    TreinoBarMetrics metrics({
      double availableWidth = 350,
      int itemCount = 5,
      double maxLabelWidth = 46,
      double maxLabelHeight = 12,
    }) =>
        resolveBarMetrics(
          availableWidth: availableWidth,
          itemCount: itemCount,
          maxLabelWidth: maxLabelWidth,
          maxLabelHeight: maxLabelHeight,
        );

    test('reparte el ancho en partes iguales', () {
      expect(metrics(availableWidth: 350).tabWidth, 70);
    });

    test('la caja del label descuenta la CURVA del pill, no solo su caja', () {
      // Este es el bug que se arregló. El pill mide `tabWidth - 16` = 54, pero
      // el label se apoya abajo, donde el redondeo ya se metió ~3.3px por lado.
      // Medir contra 54 daba por bueno un label que la curva igual recortaba.
      final m = metrics(availableWidth: 350);
      expect(m.labelBoxWidth, lessThan(54));
      expect(m.labelBoxWidth, closeTo(47.41, 0.01));
    });

    test('un label que entra en la caja pero NO en la curva no entra', () {
      // 50 < 54 (la caja del pill) pero > 47.41 (lo que deja la curva).
      // Con la lógica vieja esto daba `true` y la palabra salía recortada.
      expect(metrics(maxLabelWidth: 50).labelsFit, isFalse);
    });

    test('el label entra cuando mide menos que su caja útil', () {
      expect(metrics(maxLabelWidth: 46).labelsFit, isTrue);
      expect(metrics(maxLabelWidth: 60).labelsFit, isFalse);
    });

    test('la frontera exacta cuenta como que entra', () {
      final box = metrics().labelBoxWidth;
      expect(metrics(maxLabelWidth: box).labelsFit, isTrue);
      expect(metrics(maxLabelWidth: box + 0.1).labelsFit, isFalse);
    });

    test('textScale grande deja de entrar', () {
      expect(metrics(maxLabelWidth: 46 * 1.6).labelsFit, isFalse);
    });

    test('no hardcodea 5 tabs — role-aware-shell propone 4 para trainer', () {
      expect(metrics(availableWidth: 350, itemCount: 4).tabWidth, 87.5);
    });

    test('el alto nunca baja de minHeight', () {
      expect(metrics(maxLabelHeight: 12).barHeight, TreinoBottomBar.minHeight);
      expect(metrics(maxLabelHeight: 40).barHeight, 90);
    });
  });

  group('TreinoBottomBar — los 5 destinos entran siempre', () {
    const labels = ['ENTRENAR', 'FEED', 'INICIO', 'COACH', 'PERFIL'];

    testWidgets('nunca scrollea horizontalmente, a ninguna escala', (
      tester,
    ) async {
      // Invariante de docs/design-decisions.md: "la barra permanece visible
      // siempre". Es independiente de la fuente — el widget no existe en
      // ningún camino de código.
      for (final scale in [1.0, 2.0, 3.2]) {
        await tester.pumpWidget(
          _wrap(
            TreinoBottomBar(currentIndex: 0, onTap: (_) {}),
            textScaler: TextScaler.linear(scale),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(SingleChildScrollView),
          findsNothing,
          reason: 'a escala $scale la barra se volvió scrolleable',
        );
      }
    });

    testWidgets('los 5 destinos son TAPEABLES a escala normal', (tester) async {
      await tester.pumpWidget(
        _wrap(TreinoBottomBar(currentIndex: 0, onTap: (_) {})),
      );
      await tester.pumpAndSettle();

      for (final label in labels) {
        // hitTestable() es el assert que faltaba: el test viejo se llamaba
        // "...and tappable" y nunca lo llamaba, así que pasaba en verde
        // mientras COACH y PERFIL quedaban fuera de pantalla.
        expect(
          find.bySemanticsLabel(label).hitTestable(),
          findsOneWidget,
          reason: '$label no es tapeable',
        );
      }
    });

    testWidgets('los 5 destinos siguen siendo TAPEABLES a textScale 3.2', (
      tester,
    ) async {
      // Viewport forzado al ancho de un teléfono real. En el viewport default
      // de flutter_test (800x600) la caja del label mide 136, y ahí la fuente
      // fallback (262) y la real (~134) caen de LADOS DISTINTOS del umbral: el
      // test afirmaría cosas opuestas según qué fuente cargó. A 390 lógicos la
      // caja mide 54 y las dos fuentes coinciden en que no entra.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(currentIndex: 0, onTap: (_) {}),
          textScaler: const TextScaler.linear(3.2),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in labels) {
        expect(
          find.bySemanticsLabel(label).hitTestable(),
          findsOneWidget,
          reason: '$label dejó de ser alcanzable a textScale 3.2',
        );
      }
      // El label se apaga, pero el nombre sigue anunciándose: se sacrifica el
      // texto visible, no el acceso.
      expect(labelOpacityOf(tester, 'ENTRENAR'), 0);
    });
  });

  group('TreinoBottomBar — colapso al scrollear', () {
    /// Alto VISUAL de la pill. No sirve medir `TreinoBottomBar`: en el
    /// `Scaffold.body` del wrapper recibe constraints tight y ocupa la
    /// pantalla entera. El `ClipRRect` es el que envuelve la caja animada.
    double barHeight(WidgetTester tester) => tester
        .getSize(
          find
              .descendant(
                of: find.byType(TreinoBottomBar),
                matching: find.byType(ClipRRect),
              )
              .first,
        )
        .height;

    double labelOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.text('ENTRENAR', skipOffstage: false),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    testWidgets('collapsed false → alto expandido y labels a la vista', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(TreinoBottomBar(currentIndex: 0, onTap: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(
          barHeight(tester), greaterThanOrEqualTo(TreinoBottomBar.minHeight));
      expect(labelOpacity(tester), 1);
    });

    testWidgets('collapsed true → la barra se achica y el label se apaga', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(currentIndex: 0, onTap: (_) {}, collapsed: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(barHeight(tester), TreinoBottomBar.collapsedHeight);
      // El label sigue en el árbol —la semántica no se pierde— pero invisible.
      expect(labelOpacity(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('colapsar y expandir no desborda en ningún frame intermedio', (
      tester,
    ) async {
      // El overflow por desincronización entre alto y label es JUSTO el bug
      // que la animación única previene. Pumpeamos frame a frame para que,
      // si alguna vez desborda, el test lo vea.
      await tester.pumpWidget(
        _wrap(TreinoBottomBar(currentIndex: 0, onTap: (_) {})),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(currentIndex: 0, onTap: (_) {}, collapsed: true),
        ),
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
    });
  });
}
