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

    // La caja CRUDA del pill a 350 de ancho útil y 5 tabs: `tabWidth - 2 *
    // inset` = 70 - 12. El inset es 6 (era 8, y esos 4px de más eran justo los
    // que dejaban a un Android de 360dp sin labels).
    const pillWidth = 58.0;

    test('la caja del label descuenta la CURVA del pill, no solo su caja', () {
      // Este es el bug que se arregló. El pill mide 58, pero el label se apoya
      // abajo, donde el redondeo ya se metió ~2.1px por lado. Medir contra 58
      // daba por bueno un label que la curva igual recortaba.
      final m = metrics(availableWidth: 350);
      expect(m.labelBoxWidth, lessThan(pillWidth));
      expect(m.labelBoxWidth, closeTo(53.72, 0.01));
    });

    test('un label que entra en la caja pero NO en la curva no entra', () {
      // Un ancho en la franja de entre medio: menor que la caja del pill, pero
      // mayor que lo que la curva deja libre. Con la lógica vieja esto daba
      // `true` y la palabra salía recortada. Se deriva en vez de hardcodearse
      // para que siga probando la franja si las constantes se vuelven a tocar.
      final box = metrics().labelBoxWidth;
      final between = (box + pillWidth) / 2;
      expect(between, greaterThan(box));
      expect(between, lessThan(pillWidth));
      expect(metrics(maxLabelWidth: between).labelsFit, isFalse);
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

  // Anchos de "ENTRENAR" —el label más largo— medidos con la fuente REAL ya
  // cargada, corriendo el mismo TextPainter del widget contra Barlow Condensed
  // 10/w700/letterSpacing 0.8. No se pueden obtener desde acá: en test la
  // fuente nunca baja (ver la nota del grupo de arriba), así que van fijos.
  const entrenarAt1x = 44.36;
  const entrenarAt115x = 50.05;

  group('resolveBarLayout — la barra no se compacta en pantallas reales', () {
    TreinoBarLayout layoutFor(double screenWidth, double maxLabelWidth) =>
        resolveBarLayout(
          totalWidth: screenWidth,
          itemCount: 5,
          maxLabelWidth: maxLabelWidth,
          maxLabelHeight: maxLabelWidth == entrenarAt115x ? 14 : 12,
        );

    // La regresión que motivó todo esto: la barra se quedaba en íconos PARA
    // SIEMPRE en Android. No era "un bug de Android" — era el ancho: 360dp es
    // el más común del parque y la caja del label daba 41,41 contra 44,36 que
    // mide la palabra. En un iPhone de 393 entraba por 3,65 y no se veía.
    test('360dp —el ancho más común de Android— muestra los labels', () {
      final l = layoutFor(360, entrenarAt1x);
      expect(l.metrics.labelsFit, isTrue);
      expect(l.metrics.labelBoxWidth, greaterThan(entrenarAt1x));
    });

    test('ningún teléfono actual se compacta a escala normal', () {
      for (final width in [360.0, 375.0, 384.0, 393.0, 412.0, 440.0]) {
        expect(
          layoutFor(width, entrenarAt1x).metrics.labelsFit,
          isTrue,
          reason: '$width debería mostrar los labels',
        );
      }
    });

    test('el margen ideal se respeta mientras los labels entren', () {
      // 360dp entra sin apretar: sería un error cobrarle los 8pt de aire.
      expect(layoutFor(360, entrenarAt1x).sideMargin, 20);
    });

    test('aprieta el margen SOLO cuando con el ideal no entrarían', () {
      // A textScale 1.15 un iPhone SE no entra con margen 20, pero sí con 12.
      final se = layoutFor(375, entrenarAt115x);
      expect(se.sideMargin, 12);
      expect(se.metrics.labelsFit, isTrue);
    });

    test('si ni apretando entran, vuelve al margen ideal y va a íconos', () {
      // Nada entra: que al menos no le cobre el aire a cambio de nada.
      final l = layoutFor(360, 200);
      expect(l.metrics.labelsFit, isFalse);
      expect(l.sideMargin, 20);
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

  // Issue #634 — "barra nav desplazada y no centrada" después del login.
  //
  // La issue vino SIN datos de repro (plataforma, device, screenshot y versión
  // vacíos), así que esto es diagnóstico antes que fix: barre los 5 índices,
  // varios anchos de pantalla y insets izquierdo≠derecho, y mide la geometría
  // REAL renderizada. Si el pill se corriera de su tab —o la barra del centro
  // de la pantalla— acá se ve.
  //
  // Se mide con `getRect` y no con aritmética porque lo que se sospecha es
  // justamente un desajuste entre lo que `resolveBarLayout` calcula y lo que
  // el `Stack` pinta: repetir la cuenta en el test no probaría nada.
  group('TreinoBottomBar — centrado del pill y de la barra (#634)', () {
    const labels = ['ENTRENAR', 'FEED', 'INICIO', 'COACH', 'PERFIL'];

    /// Anchos lógicos reales del parque. 320 es el piso (iPhone SE 1ª gen),
    /// 360 el ancho más común de Android, 440 un phablet.
    const widths = [320.0, 360.0, 393.0, 440.0];

    /// Insets de dispositivo. El caso interesante es izquierdo ≠ derecho:
    /// es lo que produce un notch en landscape, y es la única entrada
    /// asimétrica que la barra recibe.
    const paddings = <String, EdgeInsets>{
      'sin insets': EdgeInsets.zero,
      'inset solo a la izquierda': EdgeInsets.only(left: 44, bottom: 21),
      'inset solo a la derecha': EdgeInsets.only(right: 44, bottom: 21),
      'insets asimétricos a ambos lados':
          EdgeInsets.only(left: 44, right: 20, bottom: 21),
    };

    /// Sin `Scaffold`: el body de un Scaffold consume padding por su cuenta y
    /// enmascararía justo lo que se quiere medir — cómo trata la barra los
    /// insets que le llegan por `MediaQuery`.
    Future<void> pumpBar(
      WidgetTester tester, {
      required double width,
      required EdgeInsets padding,
      required int index,
    }) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, appChild) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: padding, viewPadding: padding),
            child: appChild!,
          ),
          home: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TreinoBottomBar(currentIndex: index, onTap: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Rect REAL del pill de gradient. El `AnimatedPositioned` no tiene
    /// RenderObject propio, así que `getRect` baja al `_PillHighlight` — o
    /// sea, a la caja que efectivamente se pinta con su parentData ya
    /// aplicada por el `Stack`.
    Rect pillRect(WidgetTester tester) => tester.getRect(
          find.descendant(
            of: find.byType(TreinoBottomBar),
            matching: find.byType(AnimatedPositioned),
          ),
        );

    /// Rect del tab. El `Semantics` de cada tab recibe constraints tight del
    /// `Expanded`, así que su caja ES la celda del tab.
    Rect tabRect(WidgetTester tester, String label) =>
        tester.getRect(find.bySemanticsLabel(label));

    /// Caja visual de la barra: el `ClipRRect` que envuelve el vidrio.
    Rect barRect(WidgetTester tester) => tester.getRect(
          find
              .descendant(
                of: find.byType(TreinoBottomBar),
                matching: find.byType(ClipRRect),
              )
              .first,
        );

    testWidgets('el pill queda centrado en su tab en los 5 índices', (
      tester,
    ) async {
      for (final width in widths) {
        for (final entry in paddings.entries) {
          for (var index = 0; index < labels.length; index++) {
            await pumpBar(
              tester,
              width: width,
              padding: entry.value,
              index: index,
            );

            final pill = pillRect(tester);
            final tab = tabRect(tester, labels[index]);
            final ctx = '${labels[index]} @ ${width}dp, ${entry.key}';

            expect(
              pill.center.dx,
              closeTo(tab.center.dx, 0.01),
              reason: 'el pill no está centrado en su tab — $ctx',
            );
            // El pill vive ADENTRO de su celda: si se pasara, estaría pisando
            // el tab de al lado aunque el centro coincidiera.
            expect(
              pill.left,
              greaterThanOrEqualTo(tab.left - 0.01),
              reason: 'el pill se sale por la izquierda de su tab — $ctx',
            );
            expect(
              pill.right,
              lessThanOrEqualTo(tab.right + 0.01),
              reason: 'el pill se sale por la derecha de su tab — $ctx',
            );
          }
        }
      }
    });

    testWidgets('los 5 tabs se reparten el ancho en partes iguales', (
      tester,
    ) async {
      // Si la distribución se corriera —la otra mitad de lo que reporta la
      // issue: "la distribución de los items queda corrida"— se vería acá
      // aunque el pill siguiera pegado a su tab.
      for (final width in widths) {
        for (final entry in paddings.entries) {
          await pumpBar(tester, width: width, padding: entry.value, index: 2);

          final rects = [for (final l in labels) tabRect(tester, l)];
          final ctx = '${width}dp, ${entry.key}';

          for (final r in rects) {
            expect(
              r.width,
              closeTo(rects.first.width, 0.01),
              reason: 'los tabs no miden todos lo mismo — $ctx',
            );
          }
          for (var i = 1; i < rects.length; i++) {
            expect(
              rects[i].left,
              closeTo(rects[i - 1].right, 0.01),
              reason: 'hay un hueco o un solape entre tabs — $ctx',
            );
          }
        }
      }
    });

    testWidgets('la barra queda centrada respecto de la pantalla', (
      tester,
    ) async {
      // Esta SÍ falla sin el fix. El `SafeArea` de la barra tiene `top: false`
      // pero aplicaba el inset izquierdo y el derecho tal como venían; el
      // margen lateral que resuelve `resolveBarLayout` es simétrico pero se
      // aplica DESPUÉS, adentro de una caja que el SafeArea ya dejó corrida.
      // A 320dp con inset izquierdo de 44, el centro de la barra caía en 182
      // en vez de 160: 22pt = medio inset.
      for (final width in widths) {
        for (final entry in paddings.entries) {
          await pumpBar(tester, width: width, padding: entry.value, index: 2);

          final bar = barRect(tester);
          expect(
            bar.center.dx,
            closeTo(width / 2, 0.01),
            reason: 'la barra quedó descentrada en pantalla — '
                '${width}dp, ${entry.key}',
          );
        }
      }
    });

    testWidgets('la barra nunca se mete debajo del recorte del dispositivo', (
      tester,
    ) async {
      // La otra mitad del contrato: centrarla no puede lograrse a costa de
      // meterla abajo del notch. El inset se simetriza tomando el MAYOR de
      // los dos, así que el lado del recorte se sigue respetando entero.
      for (final width in widths) {
        for (final entry in paddings.entries) {
          await pumpBar(tester, width: width, padding: entry.value, index: 2);

          final bar = barRect(tester);
          final ctx = '${width}dp, ${entry.key}';
          expect(
            bar.left,
            greaterThanOrEqualTo(entry.value.left - 0.01),
            reason: 'la barra invade el inset izquierdo — $ctx',
          );
          expect(
            bar.right,
            lessThanOrEqualTo(width - entry.value.right + 0.01),
            reason: 'la barra invade el inset derecho — $ctx',
          );
        }
      }
    });
  });
}
