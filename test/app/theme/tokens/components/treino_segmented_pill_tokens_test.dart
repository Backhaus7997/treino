import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_button_tokens.dart';
import 'package:treino/app/theme/tokens/components/treino_segmented_pill_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';

/// Widget helper que inyecta [AppPalette] en el árbol (igual al patrón de
/// component_tokens_test.dart).
Widget _withTheme({required AppPalette palette, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(extensions: [palette]),
    home: child,
  );
}

/// Ratio de contraste WCAG 2.x entre dos colores OPACOS.
///
/// ⚠ Ambos argumentos tienen que estar ya compuestos: `computeLuminance()`
/// IGNORA el canal alpha. Medir un color translúcido directamente da el ratio
/// de un color que nunca se pinta — y el test pasa en verde mientras la UI
/// falla. Componer con [_on] antes de llamar acá.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Compone [fg] (posiblemente translúcido) sobre [bg] opaco.
Color _on(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// Diferencia máxima por canal, en 0-255.
///
/// Se usa en vez de `isNot(equals(...))` a propósito: `Color.alphaBlend`
/// devuelve componentes `double`, así que componer un color sobre sí mismo da
/// diferencias de punto flotante que NO son iguales pero tampoco son visibles.
/// Un test de igualdad pasa con ese ruido y no detecta nada.
int _delta(Color a, Color b) {
  int ch(double x, double y) => ((x - y).abs() * 255).round();
  return math.max(ch(a.r, b.r), math.max(ch(a.g, b.g), ch(a.b, b.b)));
}

/// Lee los tokens resueltos bajo [palette].
Future<TreinoSegmentedPillTokens> _resolve(
  WidgetTester tester,
  AppPalette palette,
) async {
  late TreinoSegmentedPillTokens tokens;
  await tester.pumpWidget(
    _withTheme(
      palette: palette,
      child: Builder(
        builder: (ctx) {
          tokens = TreinoSegmentedPillTokens.of(ctx);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return tokens;
}

void main() {
  const palettes = <String, AppPalette>{
    'dark (mintMagenta)': AppPalette.mintMagenta,
    'light (mintMagentaLight)': AppPalette.mintMagentaLight,
  };

  palettes.forEach((name, palette) {
    group('TreinoSegmentedPillTokens — $name', () {
      testWidgets(
          'el contorno de la pista cumple 3:1 contra el fondo de '
          'página (WCAG 1.4.11)', (tester) async {
        // Este es el contrato de #646. El borde original (textMuted al 12%)
        // daba 1.50:1 en dark y 1.26:1 en light: el control no tenía contorno.
        final t = await _resolve(tester, palette);

        // El borde se pinta HACIA ADENTRO, así que compone sobre el relleno
        // de la propia pista, no sobre la página.
        final track = _on(t.trackFill, palette.bg);
        final border = _on(t.trackBorder, track);

        expect(
          _ratio(border, palette.bg),
          greaterThanOrEqualTo(3.0),
          reason: 'sin un contorno a 3:1 el control no se identifica como '
              'control — es el hallazgo de usabilidad de #646',
        );
      });

      testWidgets(
          'el estado seleccionado se identifica a 3:1 por relleno o '
          'por keyline', (tester) async {
        // Asimétrico A PROPÓSITO: en dark lo carga el relleno mint (11.29:1) y
        // en light el keyline de ink (19.80:1), porque el mint sobre una pista
        // clara da apenas 1.64:1. Alcanza con que UNO de los dos cumpla.
        final t = await _resolve(tester, palette);
        final track = _on(t.trackFill, palette.bg);

        final byFill = _ratio(t.activeFill, track);
        final byKeyline = _ratio(TreinoSegmentedPillTokens.activeInk, track);

        expect(
          math.max(byFill, byKeyline),
          greaterThanOrEqualTo(3.0),
          reason: 'sacar el keyline deja al tema claro sin forma de mostrar '
              'qué pestaña está activa (relleno solo: '
              '${byFill.toStringAsFixed(2)}:1)',
        );
      });

      testWidgets('el label activo cumple AA sobre el acento', (tester) async {
        final t = await _resolve(tester, palette);

        expect(
          _ratio(TreinoSegmentedPillTokens.activeInk, t.activeFill),
          greaterThanOrEqualTo(4.5),
        );
      });

      testWidgets('el label inactivo cumple AA sobre la pista', (tester) async {
        // Candado de un estado que YA pasaba antes de #646 (6.19:1 / 5.74:1).
        // El issue daba por sentado que este contraste fallaba; no fallaba.
        // Está acá para que nadie lo "arregle" y rompa la jerarquía visual.
        final t = await _resolve(tester, palette);
        final track = _on(t.trackFill, palette.bg);

        expect(
          _ratio(_on(t.inactiveLabel, track), track),
          greaterThanOrEqualTo(4.5),
        );
      });

      testWidgets('los overlays se perciben sobre la pista', (tester) async {
        // Sólo sobre la PISTA, a propósito: la tinta de Material se pinta
        // debajo de todo el subárbol y TabBar mete el indicador en un
        // CustomPaint que pinta antes que los hijos, así que el thumb opaco
        // tapa el overlay de la celda activa. Asertar visibilidad sobre
        // activeFill sería pedirle al test que compruebe algo que el framework
        // no hace. Ver el dartdoc de TreinoSegmentedPillTokens.hoverOverlay.
        final t = await _resolve(tester, palette);
        final track = _on(t.trackFill, palette.bg);

        // Umbral perceptual, no igualdad exacta: ver el dartdoc de [_delta].
        const minDelta = 8;

        for (final entry in {
          'hover': t.hoverOverlay,
          'pressed': t.pressedOverlay,
          'focus': t.focusOverlay,
        }.entries) {
          expect(
            _delta(_on(entry.value, track), track),
            greaterThanOrEqualTo(minDelta),
            reason: '${entry.key} es imperceptible sobre la pista',
          );
        }
      });
    });
  });

  group('TreinoSegmentedPillTokens — invariantes', () {
    testWidgets('activeInk es el mismo ink que TreinoButtonTokens.foreground', (
      tester,
    ) async {
      // Los dos resuelven "texto legible sobre el acento mint". Si divergen,
      // uno de los dos deja de cumplir AA sin que nadie se entere.
      late Color buttonForeground;
      await tester.pumpWidget(
        _withTheme(
          palette: AppPalette.mintMagenta,
          child: Builder(
            builder: (ctx) {
              buttonForeground = TreinoButtonTokens.foreground(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(TreinoSegmentedPillTokens.activeInk, buttonForeground);
    });

    test('AppPalette.bg sobre el acento FALLA AA en tema claro', () {
      // Test que documenta el bug, no el arreglo. `labelColor: palette.bg` es
      // lo que usaban las copias migradas y da 1.57:1 en light. Si alguien lo
      // repone, este test explica por qué no.
      final ratio = _ratio(
        AppPalette.mintMagentaLight.bg,
        AppPalette.mintMagentaLight.accent,
      );

      expect(
        ratio,
        lessThan(4.5),
        reason: 'si esto pasa a cumplir, la paleta clara cambió y el keyline '
            'del thumb puede revisarse',
      );
    });

    test('las formas están pineadas', () {
      expect(TreinoSegmentedPillTokens.trackRadius, AppRadius.full);
      expect(TreinoSegmentedPillTokens.segmentRadius, AppRadius.full);
      expect(TreinoSegmentedPillTokens.borderWidth, 1.0);
      expect(TreinoSegmentedPillTokens.trackPadding, AppSpacing.hairline);
      expect(TreinoSegmentedPillTokens.trackPadding, 4.0);
      expect(TreinoSegmentedPillTokens.labelPadding, AppSpacing.s8);
      expect(TreinoSegmentedPillTokens.labelVerticalRoom, AppSpacing.s20);
      // Piso de área tapeable — las 4 copias migradas estaban en 38-40.
      expect(TreinoSegmentedPillTokens.minSegmentHeight, 44.0);
      expect(TreinoSegmentedPillTokens.scrollTextScaleThreshold, 1.3);
      expect(TreinoSegmentedPillTokens.dividerColor.a, 0);
    });

    testWidgets('los overlays de interacción son distintos entre sí', (
      tester,
    ) async {
      // Hoy los pills setean splashBorderRadius pero dejan el overlay en el
      // default de ThemeData, imperceptible sobre casi-negro.
      final t = await _resolve(tester, AppPalette.mintMagenta);

      expect(t.hoverOverlay, isNot(equals(t.pressedOverlay)));
      expect(t.pressedOverlay, isNot(equals(t.focusOverlay)));
      expect(t.hoverOverlay.a, closeTo(0.08, 0.01));
      expect(t.pressedOverlay.a, closeTo(0.12, 0.01));
      expect(t.focusOverlay.a, closeTo(0.20, 0.01));
    });
  });
}
