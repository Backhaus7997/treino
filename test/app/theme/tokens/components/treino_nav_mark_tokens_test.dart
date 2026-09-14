// Candado del punto que marca una pestaña con contenido en la ficha del alumno.
//
// Existe por un defecto que NINGÚN test de pantalla puede ver: esos harness
// pumpean el tema oscuro, y en dark `AppPalette.accent` y `accentText` son el
// mismo mint. Una marca de atención cableada al `accent` pleno pasa verde ahí
// y es invisible en LIGHT, que es el tema que el PF usa en el Coach Hub.
// El defecto sólo existe en una de las dos paletas, así que el candado tiene
// que vivir donde las dos se miden.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

/// Compone [fg] (con su alpha) sobre [bg] opaco.
Color _on(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final entry in {
    'dark (mintMagenta)': AppPalette.mintMagenta,
    'light (mintMagentaLight)': AppPalette.mintMagentaLight,
  }.entries) {
    group('TreinoNavMarkTokens — ${entry.key}', () {
      final palette = entry.value;
      final t = TreinoNavMarkTokens.fromPalette(palette);
      // El punto se pinta sobre la superficie de la barra de pestañas, que es
      // el fondo de página.
      final fondo = palette.bg;

      test('las dos marcas llegan a 3:1 sobre el fondo', () {
        // 3:1 y NO un delta perceptual: el punto es un componente gráfico que
        // transmite información, o sea WCAG 1.4.11. La diferencia importa —
        // el mint pleno sobre una superficie clara SE DISTINGUE (es verde
        // contra blanco) pero compone ~1,6:1, que es exactamente el defecto
        // que `accentText` existe para evitar. Un delta perceptual lo daba
        // por bueno; el ratio no.
        for (final marca
            in {'contenido': t.content, 'atención': t.attention}.entries) {
          expect(
            _ratio(_on(marca.value, fondo), fondo),
            greaterThanOrEqualTo(3.0),
            reason: 'la marca de ${marca.key} no llega a 3:1 sobre el fondo',
          );
        }
      });

      test('la marca de atención NO es el accent pleno', () {
        // La regresión concreta que se quiere impedir. En dark esta aserción
        // es trivial (los dos tokens coinciden); en light es la que muerde.
        expect(t.attention, palette.accentText);
      });

      test('contenido y atención se distinguen entre sí', () {
        // Si convergieran, «hay algo» y «requiere acción» se verían igual y el
        // punto dejaría de decir cuál es cuál.
        expect(t.content, isNot(t.attention));
      });
    });
  }
}
