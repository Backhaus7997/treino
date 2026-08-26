import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/core/widgets/treino_glass_surface.dart';

/// Contención VISUAL del pill activo dentro de la barra (#821).
///
/// El reporte era "el pill sobresale y tapa contenido de arriba". La geometría
/// nunca fue el problema —este archivo lo fija como regresión— sino que la
/// superficie de la barra no se leía contra el fondo: el pill quedaba como el
/// único objeto visible de la zona y se leía flotando sobre el contenido.
///
/// Por eso hay dos grupos de aserciones acá:
///
/// 1. **Geometría**: el pill entra entero en la superficie, con el mismo aire
///    en los cuatro lados. Es la intención que ya estaba escrita en el código.
/// 2. **Contraste del borde**: el filo de la barra se distingue del fondo de
///    la app. Sin esto el punto 1 es cierto y no se ve, que es exactamente el
///    bug que se reportó.
///
/// El punto 2 se mide sobre PÍXELES REALES (se rasteriza el árbol y se leen
/// los bytes), no sobre los colores declarados: el filo lo pintan tres capas
/// encimadas —fill translúcido, borde y el reflejo especular de
/// [TreinoGlassSurface]— y el color declarado del borde no es el que sale.

/// Componente sRGB linealizado, según la fórmula de contraste de WCAG 2.2.
double _linearize(double channel) => channel <= 0.03928
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// Luminancia relativa de un píxel RGB de 8 bits.
double _luminance(List<int> rgb) =>
    0.2126 * _linearize(rgb[0] / 255) +
    0.7152 * _linearize(rgb[1] / 255) +
    0.0722 * _linearize(rgb[2] / 255);

/// Razón de contraste WCAG entre dos píxeles ya compuestos.
double _contrast(List<int> a, List<int> b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Piso de contraste para el filo de la barra contra el fondo de la app.
///
/// Es el mínimo de WCAG 2.2 SC 1.4.11 (Non-text Contrast) para el LÍMITE de un
/// componente de interfaz. La barra es justamente eso: el contenedor que tiene
/// que leerse para que el pill se lea adentro.
const double _kMinEdgeContrast = 3.0;

void main() {
  /// Monta la barra en el mismo armado que el shell de producción
  /// (`_ShellScaffold` en `app/router.dart`): `extendBody: true`, el body
  /// envuelto en [AppBackground] y la barra en el slot `bottomNavigationBar`.
  /// Cualquier medición hecha fuera de este armado mide otra cosa.
  Future<({Rect surface, Rect pill, ui.Image image, double publishedBottom})>
      pumpBar(WidgetTester tester, {required bool dark}) async {
    tester.view.physicalSize = const Size(430, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding.zero;
    addTearDown(tester.view.reset);

    final boundaryKey = GlobalKey();
    var publishedBottom = 0.0;

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: Scaffold(
            extendBody: true,
            body: AppBackground(
              child: SafeArea(
                bottom: false,
                child: Builder(
                  builder: (context) {
                    publishedBottom = MediaQuery.paddingOf(context).bottom;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
            bottomNavigationBar:
                TreinoBottomBar(currentIndex: 0, onTap: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Rect rectOf(Finder finder) {
      final box = tester.renderObject<RenderBox>(finder);
      return box.localToGlobal(Offset.zero) & box.size;
    }

    late ui.Image image;
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      image = await boundary.toImage();
    });

    return (
      surface: rectOf(find.byType(TreinoGlassSurface)),
      pill: rectOf(find.byKey(TreinoBottomBar.pillKey)),
      image: image,
      publishedBottom: publishedBottom,
    );
  }

  group('TreinoBottomBar — contención geométrica del pill (#821)', () {
    testWidgets('el pill entra entero en la superficie de la barra',
        (tester) async {
      final r = await pumpBar(tester, dark: true);
      addTearDown(r.image.dispose);

      expect(r.pill.top - r.surface.top, closeTo(6, 0.01));
      expect(r.surface.bottom - r.pill.bottom, closeTo(6, 0.01));
      expect(r.pill.left - r.surface.left, closeTo(6, 0.01));
      expect(
        r.surface.right - r.pill.right,
        greaterThanOrEqualTo(6 - 0.01),
        reason: 'el pill del primer tab nunca puede pasarse del borde derecho',
      );
    });

    testWidgets(
        'el alto que la barra publica deja el contenido por encima del pill',
        (tester) async {
      final r = await pumpBar(tester, dark: true);
      addTearDown(r.image.dispose);

      // El `Scaffold` con `extendBody` publica el alto ENTERO del widget de la
      // barra en el `MediaQuery.padding.bottom` del body. Una pantalla que lo
      // respeta —las cinco del shell lo hacen— corta su contenido acá.
      final contentEdge = 800 - r.publishedBottom;
      expect(
        r.pill.top,
        greaterThan(contentEdge),
        reason: 'el pill no puede empezar por encima del borde del contenido',
      );
      expect(r.pill.top - contentEdge, closeTo(14, 0.01));
    });
  });

  group('TreinoBottomBar — el filo de la barra se lee contra el fondo (#821)',
      () {
    /// Mide el contraste del filo superior de la barra contra el fondo de la
    /// app inmediatamente por encima.
    ///
    /// La columna se toma en la juntura entre el tercer y el cuarto tab: ahí no
    /// hay ni ícono, ni label, ni el resplandor del pill activo, así que lo que
    /// se lee es la superficie sola.
    Future<double> edgeContrast(WidgetTester tester,
        {required bool dark}) async {
      final r = await pumpBar(tester, dark: dark);
      addTearDown(r.image.dispose);

      late double contrast;
      await tester.runAsync(() async {
        final bytes =
            (await r.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        List<int> pixelAt(num x, num y) {
          final offset = (y.round() * r.image.width + x.round()) * 4;
          return [
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          ];
        }

        final x = r.surface.left + r.surface.width * 3 / 5;
        final background = pixelAt(x, r.surface.top - 8);
        // El filo no cae siempre en el mismo píxel: el borde se dibuja hacia
        // adentro y el ClipRRect lo antialiasea. De las tres filas del entorno
        // del filo se toma la de mayor DIFERENCIA absoluta de luminancia contra
        // el fondo, que es la que el ojo lee como línea. Ojo: NO es "la más
        // clara". En la paleta oscura coinciden, pero en la clara el filo es
        // más OSCURO que el relleno casi blanco, así que quedarse con la de
        // mayor luminancia mediría el relleno (~1,0:1) y no el filo (#821).
        var edge = pixelAt(x, r.surface.top);
        for (var dy = 0; dy <= 2; dy++) {
          final candidate = pixelAt(x, r.surface.top + dy);
          if ((_luminance(candidate) - _luminance(background)).abs() >
              (_luminance(edge) - _luminance(background)).abs()) {
            edge = candidate;
          }
        }
        contrast = _contrast(edge, background);
      });
      return contrast;
    }

    testWidgets('paleta oscura (mintMagenta)', (tester) async {
      final contrast = await edgeContrast(tester, dark: true);
      expect(
        contrast,
        greaterThanOrEqualTo(_kMinEdgeContrast),
        reason: 'filo de la barra vs ${AppPalette.mintMagenta.bg} — '
            'medido ${contrast.toStringAsFixed(2)}:1',
      );
    });

    testWidgets('paleta clara (mintMagentaLight)', (tester) async {
      final contrast = await edgeContrast(tester, dark: false);
      expect(
        contrast,
        greaterThanOrEqualTo(_kMinEdgeContrast),
        reason: 'filo de la barra vs ${AppPalette.mintMagentaLight.bg} — '
            'medido ${contrast.toStringAsFixed(2)}:1',
      );
    });
  });
}
