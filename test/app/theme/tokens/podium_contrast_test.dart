// Mediciones de los metálicos del podio de Rankings (top 3).
//
// El numeral de puesto es texto de 15 px — TEXTO CHICO. La barra es 4,5:1
// (WCAG AA, SC 1.4.3), no el 3:1 de gráficos: son glifos, no íconos.
//
// Se mide contra DOS fondos por paleta, no uno:
//   - `bgCard`, el relleno del contenedor del leaderboard;
//   - `bgCard` + `accent` al 8%, que es la fila del propio atleta.
//
// El segundo es el que decide. `#9A6B00` —el oro light que salía primero— da
// 4,69:1 sobre `bgCard` y **4,48:1 sobre la fila propia**: pasaba la medición
// obvia y fallaba justo en la fila que el atleta más mira. Por eso el token
// terminó en `#8A6100`. Es el mismo modo de falla que documenta
// `superset_block_contrast_test.dart`: medir contra un solo fondo.
//
// AGENTS.md, regla 2: todo par de tokens se mide en LAS DOS paletas.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';

/// Ratio de contraste WCAG 2.x entre dos colores OPACOS.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Compone [fg] sobre [bg] **y cuantiza a 8 bits por canal**, que es lo que
/// termina en el framebuffer. Sin cuantizar, la mezcla ideal en punto flotante
/// deja pasar tokens que el píxel real no cumple.
Color _on(Color fg, Color bg) {
  final blended = Color.alphaBlend(fg, bg);
  double q(double v) => (v * 255).round() / 255;
  return Color.from(
    alpha: 1.0,
    red: q(blended.r),
    green: q(blended.g),
    blue: q(blended.b),
  );
}

/// Fondo de la fila propia: `bgCard` con el overlay de acento al 8% que pinta
/// `_LeaderboardRow` cuando `isMe`. Mismo alpha que el widget.
Color _myRowBg(AppPalette p) => _on(p.accent.withValues(alpha: 0.08), p.bgCard);

void main() {
  const themes = {
    'dark': AppPalette.mintMagenta,
    'light': AppPalette.mintMagentaLight,
  };

  for (final entry in themes.entries) {
    final name = entry.key;
    final p = entry.value;

    group('Podio — paleta $name', () {
      final medals = {
        'oro': p.podiumGold,
        'plata': p.podiumSilver,
        'bronce': p.podiumBronze,
      };

      for (final medal in medals.entries) {
        test('${medal.key} cumple 4,5:1 sobre bgCard', () {
          expect(
            _ratio(medal.value, p.bgCard),
            greaterThanOrEqualTo(4.5),
            reason: '${medal.key} ($name) sobre bgCard: '
                '${_ratio(medal.value, p.bgCard).toStringAsFixed(2)}:1',
          );
        });

        test('${medal.key} cumple 4,5:1 sobre la fila propia (accent 8%)', () {
          final bg = _myRowBg(p);
          expect(
            _ratio(medal.value, bg),
            greaterThanOrEqualTo(4.5),
            reason: '${medal.key} ($name) sobre la fila propia: '
                '${_ratio(medal.value, bg).toStringAsFixed(2)}:1 — '
                'el overlay de accent aclara el fondo y come margen',
          );
        });
      }

      test('los tres metálicos se distinguen entre sí', () {
        final values = medals.values.toList();
        for (var i = 0; i < values.length; i++) {
          for (var j = i + 1; j < values.length; j++) {
            expect(values[i], isNot(values[j]));
          }
        }
      });

      test('ninguno colisiona con textMuted, que es el color del 4º en adelante',
          () {
        for (final medal in medals.entries) {
          expect(medal.value, isNot(p.textMuted));
        }
      });
    });
  }

  test('la fila propia es un fondo MÁS exigente que bgCard en las dos paletas',
      () {
    // Guard del razonamiento, no del número: si algún día el overlay de `isMe`
    // deja de aclarar el fondo, medir sólo contra `bgCard` volvería a alcanzar
    // y este test avisa que la nota de arriba quedó vieja.
    for (final p in themes.values) {
      final gold = p.podiumGold;
      expect(_ratio(gold, _myRowBg(p)), lessThan(_ratio(gold, p.bgCard)));
    }
  });
}
