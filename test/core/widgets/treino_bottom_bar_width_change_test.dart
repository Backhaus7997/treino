// #734 — el pill DURANTE un cambio de ancho de la barra.
//
// El barrido de `treino_bottom_bar_test.dart` mide el pill contra su tab en 80
// configuraciones, pero SIEMPRE después de `pumpAndSettle()`: mide el estado
// final, que es correcto incluso con el bug puesto. Y
// `router_post_login_bottom_bar_test.dart` (#634) sí mide frame a frame, pero
// en una transición donde el ancho NO cambia — que es justo la condición que
// dispara el desajuste.
//
// Este archivo cierra ese hueco: cambia el ancho lógico de la pantalla y mide
// el desvío pill↔tab en CADA frame de la transición.
//
// Por qué el ancho de la barra cambia en producción: rotación en iOS, abrir un
// foldable, split view en tablet, y —sin rotar nada— cuando `resolveBarLayout`
// flipea entre el margen ideal (20) y el apretado (12) porque el textScale del
// usuario movió la medición de los labels.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';

const _labels = ['ENTRENAR', 'FEED', 'INICIO', 'COACH', 'PERFIL'];

/// Rect REAL del pill de gradient, buscado por su key pública: el widget de
/// posición no tiene RenderObject propio, así que `getRect` tiene que bajar a
/// la caja que efectivamente se pinta, con su parentData ya aplicada por el
/// `Stack`.
Rect _pillRect(WidgetTester tester) =>
    tester.getRect(find.byKey(TreinoBottomBar.pillKey));

/// Rect del tab. El `Semantics` de cada tab recibe constraints tight del
/// `Expanded`, así que su caja ES la celda del tab.
Rect _tabRect(WidgetTester tester, String label) =>
    tester.getRect(find.bySemanticsLabel(label));

/// Una foto de la geometría de la barra en un frame.
class _Frame {
  _Frame({required this.n, required this.pill, required this.tabs});

  final int n;
  final Rect pill;
  final List<Rect> tabs;

  @override
  String toString() => 'frame $n · '
      'pill=[${pill.left.toStringAsFixed(2)}..${pill.right.toStringAsFixed(2)}] '
      'cx=${pill.center.dx.toStringAsFixed(2)} · '
      'tabW=${tabs.first.width.toStringAsFixed(2)}';
}

_Frame _capture(WidgetTester tester, int n) => _Frame(
      n: n,
      pill: _pillRect(tester),
      tabs: [for (final l in _labels) _tabRect(tester, l)],
    );

Future<void> _pumpBar(
  WidgetTester tester, {
  required int index,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, appChild) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
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
}

void main() {
  group('TreinoBottomBar — pill vs tabs durante un cambio de ancho (#734)', () {
    /// 16ms por frame; 30 frames ≈ 480ms, holgado sobre los 320ms de
    /// `AppMotion.slow`.
    const frameCount = 30;

    /// Cambios de ancho que se ven en producción. El alto no importa acá.
    const transitions = <({String name, double from, double to})>[
      (name: 'Android 360dp → 440dp (fold)', from: 360, to: 440),
      (name: 'iPhone 393pt → 852pt (rotación)', from: 393, to: 852),
      (name: 'tablet 834pt → 500pt (split view)', from: 834, to: 500),
      (name: '440dp → 360dp (cerrar el fold)', from: 440, to: 360),
    ];

    for (final t in transitions) {
      for (var index = 0; index < _labels.length; index++) {
        testWidgets(
            'el pill sigue pegado a ${_labels[index]} en TODOS los frames — '
            '${t.name}', (tester) async {
          tester.view.physicalSize = Size(t.from, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await _pumpBar(tester, index: index);
          await tester.pumpAndSettle();

          // El cambio de ancho. Un solo frame lo entrega entero, igual que una
          // rotación o un fold: el `Row` de `Expanded` se reacomoda de golpe.
          tester.view.physicalSize = Size(t.to, 900);

          final frames = <_Frame>[];
          for (var i = 0; i < frameCount; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            frames.add(_capture(tester, i));
          }

          for (final f in frames) {
            printOnFailure(f.toString());
          }

          for (final f in frames) {
            final tab = f.tabs[index];
            expect(
              f.pill.center.dx,
              closeTo(tab.center.dx, 0.01),
              reason: 'el pill se despegó del centro de su tab — $f',
            );
            // Centrado no alcanza: si el pill conserva el ancho viejo puede
            // estar centrado y aun así pisar los tabs de al lado.
            expect(
              f.pill.left,
              greaterThanOrEqualTo(tab.left - 0.01),
              reason: 'el pill se sale por la izquierda de su tab — $f',
            );
            expect(
              f.pill.right,
              lessThanOrEqualTo(tab.right + 0.01),
              reason: 'el pill se sale por la derecha de su tab — $f',
            );
          }
        });
      }
    }

    testWidgets(
        'el margen lateral puede flipear sin que el pill se despegue '
        '(1pt de pantalla, 15pt de barra)', (tester) async {
      // El escenario insidioso de la issue: la barra cambia de ancho SIN que
      // haga falta rotar nada. `resolveBarLayout` elige entre
      // `_kSideMarginIdeal` (20) y `_kSideMarginTight` (12) según si los
      // labels entran, y esa decisión se toma al filo: un punto de pantalla
      // alcanza para cruzarla, y cuando se cruza la barra salta 16pt de ancho
      // de un frame al otro — MÁS que en muchas rotaciones.
      //
      // El punto exacto donde flipea NO se hardcodea: depende del ancho de los
      // labels, y en test los labels se miden con la fuente FALLBACK, no con
      // Barlow Condensed (ver el dartdoc de `TreinoBarMetrics`). Se busca
      // barriendo, así que si algún día cambia la fuente del entorno de test
      // el test sigue midiendo el flip real en vez de pasar sin ejercitar nada.
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      double? flipFrom;
      var previousMargin = 0.0;
      for (var w = 320.0; w <= 460.0; w += 1) {
        tester.view.physicalSize = Size(w, 900);
        await _pumpBar(tester, index: 2);
        await tester.pumpAndSettle();
        final margin = (w - _tabRect(tester, _labels.first).width * 5) / 2;
        if (w > 320 && (margin - previousMargin).abs() > 0.01) {
          flipFrom = w - 1;
          break;
        }
        previousMargin = margin;
      }

      expect(
        flipFrom,
        isNotNull,
        reason: 'no se encontró ningún ancho entre 320 y 460 donde '
            'resolveBarLayout cambie de margen; el test no está ejercitando '
            'el flip',
      );

      tester.view.physicalSize = Size(flipFrom!, 900);
      await _pumpBar(tester, index: 2);
      await tester.pumpAndSettle();
      final before = _tabRect(tester, _labels.first).width;

      // Un solo punto de pantalla más: lo que cambia es el margen, no el
      // tamaño del device.
      tester.view.physicalSize = Size(flipFrom + 1, 900);

      final frames = <_Frame>[];
      for (var i = 0; i < frameCount; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        frames.add(_capture(tester, i));
      }
      for (final f in frames) {
        printOnFailure(f.toString());
      }

      expect(
        (frames.last.tabs.first.width - before).abs(),
        greaterThan(1),
        reason: 'la barra no cambió de ancho al cruzar el flip — $flipFrom',
      );

      for (final f in frames) {
        final tab = f.tabs[2];
        expect(
          f.pill.center.dx,
          closeTo(tab.center.dx, 0.01),
          reason: 'el pill se despegó del centro de INICIO — $f',
        );
        expect(
          f.pill.left,
          greaterThanOrEqualTo(tab.left - 0.01),
          reason: 'el pill se sale por la izquierda de su tab — $f',
        );
        expect(
          f.pill.right,
          lessThanOrEqualTo(tab.right + 0.01),
          reason: 'el pill se sale por la derecha de su tab — $f',
        );
      }
    });

    testWidgets('cambiar de tab SIGUE deslizando el pill (no se volvió salto)',
        (tester) async {
      // La otra mitad del contrato de #734: "que el pill y sus tabs se muevan
      // juntos" NO puede resolverse matando la animación del pill. Este test
      // falla si alguien "arregla" el desajuste volviendo el pill instantáneo.
      tester.view.physicalSize = const Size(393, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpBar(tester, index: 0);
      await tester.pumpAndSettle();
      final origin = _pillRect(tester).center.dx;

      await _pumpBar(tester, index: 4);
      await tester.pump(const Duration(milliseconds: 16));

      final mid = _pillRect(tester).center.dx;
      final target = _tabRect(tester, _labels[4]).center.dx;
      expect(
        mid,
        greaterThan(origin),
        reason: 'el pill no arrancó a moverse hacia el tab nuevo',
      );
      expect(
        mid,
        lessThan(target),
        reason: 'el pill saltó al tab nuevo en un frame: la animación de '
            'cambio de tab se perdió',
      );

      await tester.pump(AppMotion.slow);
      await tester.pumpAndSettle();
      expect(_pillRect(tester).center.dx, closeTo(target, 0.01));
    });
  });
}
