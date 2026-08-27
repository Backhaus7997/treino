// Mediciones de los cuatro tokens que el rediseño de "Crear rutina" (variante
// 3a) agrega a [AppPalette]: `accentText`, `bgElevated`, `surfaceSubtle` y
// `textFaint`.
//
// El handoff de diseño llegó con valores tomados del mock en dark. Este archivo
// existe porque dos de ellos NO sobrevivían la medición tal cual venían:
//
//   - `textFaint` venía al 40% de blanco → 3,77:1 sobre `ink950`. Se subió a
//     45%. El header de columna mide 10,5 px: no es texto grande ni en bold,
//     así que le aplica el 4,5:1 completo de WCAG AA.
//   - `accentText` no existía. El mint pleno es un color de FONDO; pintado como
//     tinta sobre papel da 1,57:1. Sin este token, todo label acento del tema
//     claro quedaba ilegible.
//
// AGENTS.md, regla 2: todo par de tokens se mide en LAS DOS paletas.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';

/// Ratio de contraste WCAG 2.x entre dos colores OPACOS.
///
/// ⚠ Ambos argumentos tienen que estar ya compuestos: `computeLuminance()`
/// IGNORA el canal alpha. Medir un token translúcido directamente da el ratio
/// de un color que nunca se pinta.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Compone [fg] (posiblemente translúcido) sobre [bg] opaco.
Color _on(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// Diferencia máxima por canal, en 0-255. Sirve para "¿se ve el borde de esta
/// superficie?" donde el ratio de contraste todavía no dice nada útil.
int _maxChannelDelta(Color a, Color b) {
  int c8(double v) => (v * 255).round();
  return [
    (c8(a.r) - c8(b.r)).abs(),
    (c8(a.g) - c8(b.g)).abs(),
    (c8(a.b) - c8(b.b)).abs(),
  ].reduce(math.max);
}

/// Mínimo WCAG AA para texto chico.
const double _kTextAA = 4.5;

void main() {
  const paletas = <String, AppPalette>{
    'dark': AppPalette.mintMagenta,
    'light': AppPalette.mintMagentaLight,
  };

  group('textFaint — tercer escalón de texto, sigue siendo texto', () {
    for (final entry in paletas.entries) {
      final nombre = entry.key;
      final p = entry.value;

      test('$nombre: cumple 4,5:1 sobre bg', () {
        final ratio = _ratio(_on(p.textFaint, p.bg), p.bg);
        expect(
          ratio,
          greaterThanOrEqualTo(_kTextAA),
          reason: 'textFaint sobre bg en $nombre mide '
              '${ratio.toStringAsFixed(2)}:1. Los headers SET/KG/REPS y los '
              'hints se pintan con este token; por debajo de 4,5:1 dejan de '
              'ser legibles para buena parte de los usuarios.',
        );
      });

      test('$nombre: cumple 4,5:1 sobre bgCard', () {
        final ratio = _ratio(_on(p.textFaint, p.bgCard), p.bgCard);
        expect(
          ratio,
          greaterThanOrEqualTo(_kTextAA),
          reason: 'textFaint sobre bgCard en $nombre mide '
              '${ratio.toStringAsFixed(2)}:1.',
        );
      });

      test('$nombre: es más tenue que textMuted, no un duplicado', () {
        final faint = _ratio(_on(p.textFaint, p.bg), p.bg);
        final muted = _ratio(_on(p.textMuted, p.bg), p.bg);
        expect(
          faint,
          lessThan(muted),
          reason: 'textFaint tiene que leerse por DEBAJO de textMuted en la '
              'jerarquía; si mide igual o más, el escalón no existe y '
              'conviene borrar el token.',
        );
      });
    }

    test('el 40% del handoff original NO habría pasado — regresión', () {
      const p = AppPalette.mintMagenta;
      const white40 = Color(0x66FFFFFF);
      final ratio = _ratio(_on(white40, p.bg), p.bg);
      expect(
        ratio,
        lessThan(_kTextAA),
        reason: 'Si este valor pasara a cumplir AA, la nota de '
            'AppColorPrimitives.white45 quedó obsoleta y hay que corregirla.',
      );
    });
  });

  group('accentText — el acento cuando va como TINTA', () {
    for (final entry in paletas.entries) {
      final nombre = entry.key;
      final p = entry.value;

      test('$nombre: cumple 4,5:1 sobre bg y sobre bgCard', () {
        final sobreBg = _ratio(_on(p.accentText, p.bg), p.bg);
        final sobreCard = _ratio(_on(p.accentText, p.bgCard), p.bgCard);
        expect(sobreBg, greaterThanOrEqualTo(_kTextAA),
            reason: 'accentText sobre bg en $nombre: '
                '${sobreBg.toStringAsFixed(2)}:1');
        expect(sobreCard, greaterThanOrEqualTo(_kTextAA),
            reason: 'accentText sobre bgCard en $nombre: '
                '${sobreCard.toStringAsFixed(2)}:1');
      });
    }

    test('light: el token existe porque `accent` como tinta NO alcanza', () {
      const p = AppPalette.mintMagentaLight;
      final accentComoTinta = _ratio(_on(p.accent, p.bg), p.bg);
      expect(
        accentComoTinta,
        lessThan(_kTextAA),
        reason: 'Si el mint pleno pasara a cumplir AA sobre papel, accentText '
            'dejaría de tener razón de ser y habría que colapsarlo con accent.',
      );
      expect(
        p.accentText,
        isNot(equals(p.accent)),
        reason: 'En light accentText TIENE que divergir de accent.',
      );
    });

    test('dark: accentText colapsa en accent — el mint ya mide 12:1', () {
      const p = AppPalette.mintMagenta;
      expect(p.accentText, equals(p.accent));
      expect(_ratio(p.accent, p.bg), greaterThan(10.0));
    });
  });

  group('surfaceSubtle — el relleno que arregla el chip invisible', () {
    test('dark: se despega de bgCard, que es el bug que motivó el token', () {
      const p = AppPalette.mintMagenta;
      final chip = _on(p.surfaceSubtle, p.bgCard);
      expect(
        _maxChannelDelta(chip, p.bgCard),
        greaterThanOrEqualTo(8),
        reason: 'El chip de set se pintaba con bgCard sobre una card bgCard: '
            'invisible. surfaceSubtle tiene que separarse de su contenedor.',
      );
    });

    test('light: también se despega de bgCard', () {
      const p = AppPalette.mintMagentaLight;
      final chip = _on(p.surfaceSubtle, p.bgCard);
      expect(_maxChannelDelta(chip, p.bgCard), greaterThanOrEqualTo(8));
    });

    test('textPrimary encima del chip sigue cumpliendo AA en ambas paletas',
        () {
      for (final entry in paletas.entries) {
        final p = entry.value;
        final chip = _on(p.surfaceSubtle, p.bgCard);
        final ratio = _ratio(_on(p.textPrimary, chip), chip);
        expect(
          ratio,
          greaterThanOrEqualTo(_kTextAA),
          reason: 'El número de set va en textPrimary sobre surfaceSubtle. '
              '${entry.key}: ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('bgElevated — la capa que flota sobre el contenido', () {
    test('dark: se distingue de bgCard', () {
      const p = AppPalette.mintMagenta;
      expect(
        _maxChannelDelta(p.bgElevated, p.bgCard),
        greaterThanOrEqualTo(4),
        reason: 'La barra de accesorio y los sheets se apoyan sobre el scroll; '
            'sin sombras (regla del kit) el relleno es lo único que los separa.',
      );
    });

    test('light: coincide con bgCard A PROPÓSITO — no hay nada más claro', () {
      const p = AppPalette.mintMagentaLight;
      expect(
        p.bgElevated,
        equals(p.bgCard),
        reason: 'En light la elevación se lee por el filo superior, no por el '
            'relleno. Si esto cambia, actualizar el dartdoc de bgElevated.',
      );
    });

    test('textPrimary sobre bgElevated cumple AA en ambas paletas', () {
      for (final entry in paletas.entries) {
        final p = entry.value;
        final ratio = _ratio(_on(p.textPrimary, p.bgElevated), p.bgElevated);
        expect(ratio, greaterThanOrEqualTo(_kTextAA),
            reason: '${entry.key}: ${ratio.toStringAsFixed(2)}:1');
      }
    });
  });

  group('los primitivos nuevos no se desviaron del valor medido', () {
    test('white45 y black55 son los alphas que se documentaron', () {
      expect(AppColorPrimitives.white45, const Color(0x73FFFFFF));
      expect(AppColorPrimitives.black55, const Color(0x8C000000));
    });

    test('mintText700 mantiene el hue de marca, solo baja la luminancia', () {
      final marca = HSLColor.fromColor(AppColorPrimitives.mint500);
      final tinta = HSLColor.fromColor(AppColorPrimitives.mintText700);
      expect(
        (marca.hue - tinta.hue).abs(),
        lessThan(12.0),
        reason: 'mintText700 es el MISMO verde más oscuro, no otro color.',
      );
      expect(tinta.lightness, lessThan(marca.lightness));
    });
  });
}
