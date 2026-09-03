// Mediciones del bloque de superserie y de los botones de acción del editor de
// rutina (#869).
//
// El handoff de diseño llegó con los alphas tomados de un mock en dark, y tres
// de ellos NO sobreviven la medición en las dos paletas. El patrón es siempre
// el mismo, y es el que ya motivó `AppPalette.accentText` en el slice 0:
// **el magenta pleno es un color de FONDO**. Pintado como tinta sobre su propio
// relleno mide 3,2:1 a 4,1:1 según el caso — por debajo del 4,5:1 que WCAG AA
// pide para texto chico.
//
// Dónde se resolvió: el título del bloque, el label del botón SUPERSERIE y el
// texto del badge van en `textPrimary`. El magenta se queda en el relleno, el
// borde y los íconos, que son gráficos y les alcanza el 3:1 de SC 1.4.11.
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
/// termina en el framebuffer.
///
/// ⚠ La cuantización no es un detalle de precisión. `Color.alphaBlend` devuelve
/// componentes en punto flotante; en el slice 0 la diferencia entre la mezcla
/// ideal y el píxel real (4,515:1 contra 4,484:1) fue suficiente para que un
/// token entrara a la paleta creyendo que cumplía.
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

/// Diferencia máxima por canal, en 0-255. Es la medida que sirve para
/// "¿se despega esta superficie de la de abajo?", donde el ratio de contraste
/// todavía no dice nada útil.
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

/// Mínimo WCAG 2.2 SC 1.4.11 para gráficos y controles.
const double _kGraficoAA = 3.0;

/// Los alphas que pinta el código. Si alguno cambia, este archivo tiene que
/// cambiar con él — es el punto: los números se justifican midiendo.
const int _kBloqueRelleno = 20;
const int _kBloqueBorde = 140;
const int _kBadgeRelleno = 46;
const int _kBloqueRellenoResaltado = 46;
const int _kBloqueBordeResaltado = 255;
const int _kAgarreSuperserie = 40;
const int _kBotonPrimario = 30;
const int _kBotonSecundario = 36;
const int _kContornoPunteado = 200;

void main() {
  const paletas = <String, AppPalette>{
    'dark': AppPalette.mintMagenta,
    'light': AppPalette.mintMagentaLight,
  };

  // El estado RESALTADO: el bloque como destino explícito del drop durante el
  // drag. Su dartdoc afirmaba que el borde supera 3:1 y esa afirmación llegó
  // sin medir — que es justo lo que este archivo existe para impedir.
  group('bloque resaltado como destino del drop', () {
    for (final entry in paletas.entries) {
      final nombre = entry.key;
      final p = entry.value;

      test('$nombre: el borde resaltado cumple el 3:1 de SC 1.4.11', () {
        final relleno =
            _on(p.highlight.withAlpha(_kBloqueRellenoResaltado), p.bgCard);
        final borde =
            _on(p.highlight.withAlpha(_kBloqueBordeResaltado), relleno);
        final ratio = _ratio(borde, relleno);
        expect(ratio, greaterThanOrEqualTo(_kGraficoAA),
            reason: 'El borde es lo que dice "acá cae". $nombre: '
                '${ratio.toStringAsFixed(2)}:1');
      });

      test('$nombre: el resaltado se despega del bloque en reposo', () {
        final reposo = _on(p.highlight.withAlpha(_kBloqueRelleno), p.bgCard);
        final activo =
            _on(p.highlight.withAlpha(_kBloqueRellenoResaltado), p.bgCard);
        final delta = _maxChannelDelta(activo, reposo);
        expect(delta, greaterThanOrEqualTo(16),
            reason: 'Si el resaltado no se distingue del reposo, el usuario '
                'arrastra sin saber si va a unir o a reordenar. $nombre: '
                '$delta sobre 255 por canal.');
      });

      test('$nombre: el título sigue en AA sobre el relleno resaltado', () {
        final activo =
            _on(p.highlight.withAlpha(_kBloqueRellenoResaltado), p.bgCard);
        final ratio = _ratio(_on(p.textPrimary, activo), activo);
        expect(ratio, greaterThanOrEqualTo(_kTextAA),
            reason: 'El relleno sube al resaltarse y el texto no se mueve: '
                'hay que medirlo de nuevo. $nombre: '
                '${ratio.toStringAsFixed(2)}:1');
      });
    }
  });

  group('bloque de superserie — el relleno que lo hace existir', () {
    for (final entry in paletas.entries) {
      final nombre = entry.key;
      final p = entry.value;

      test('$nombre: se despega de la card del día', () {
        final bloque = _on(p.highlight.withAlpha(_kBloqueRelleno), p.bgCard);
        expect(
          _maxChannelDelta(bloque, p.bgCard),
          greaterThanOrEqualTo(16),
          reason: 'El bloque tiene que verse como un bloque. En $nombre mide '
              '${_maxChannelDelta(bloque, p.bgCard)} sobre 255 por canal.',
        );
      });

      test('$nombre: el título en textPrimary cumple AA sobre el relleno', () {
        final bloque = _on(p.highlight.withAlpha(_kBloqueRelleno), p.bgCard);
        final ratio = _ratio(_on(p.textPrimary, bloque), bloque);
        expect(ratio, greaterThanOrEqualTo(_kTextAA),
            reason: '"SUPERSERIE · N EJERCICIOS" en $nombre: '
                '${ratio.toStringAsFixed(2)}:1');
      });

      test('$nombre: el ícono en highlight cumple el 3:1 de SC 1.4.11', () {
        final bloque = _on(p.highlight.withAlpha(_kBloqueRelleno), p.bgCard);
        final ratio = _ratio(_on(p.highlight, bloque), bloque);
        expect(ratio, greaterThanOrEqualTo(_kGraficoAA),
            reason: 'La llama es lo que le da identidad magenta al bloque una '
                'vez que el texto pasó a textPrimary. $nombre: '
                '${ratio.toStringAsFixed(2)}:1');
      });
    }

    test('el α12 anterior era el bug: la mitad de separación', () {
      const p = AppPalette.mintMagenta;
      final antes = _on(p.highlight.withAlpha(12), p.bgCard);
      final ahora = _on(p.highlight.withAlpha(_kBloqueRelleno), p.bgCard);
      final deltaAntes = _maxChannelDelta(antes, p.bgCard);
      final deltaAhora = _maxChannelDelta(ahora, p.bgCard);
      expect(
        deltaAhora,
        greaterThan(deltaAntes),
        reason: 'El bloque se pintaba al 4,7% y medía $deltaAntes sobre 255: '
            'a esa distancia el usuario no ve que dos ejercicios están '
            'agrupados. Ahora mide $deltaAhora.',
      );
    });

    test('el título en highlight NO habría pasado AA — por qué va textPrimary',
        () {
      for (final entry in paletas.entries) {
        final p = entry.value;
        final bloque = _on(p.highlight.withAlpha(_kBloqueRelleno), p.bgCard);
        final comoTinta = _ratio(_on(p.highlight, bloque), bloque);
        expect(
          comoTinta,
          lessThan(_kTextAA),
          reason: 'Si el magenta pasara a cumplir AA como tinta sobre su '
              'propio relleno, este slice podría volver al color del handoff '
              'y habría que corregir el dartdoc de SupersetBlock. '
              '${entry.key}: ${comoTinta.toStringAsFixed(2)}:1',
        );
      }
    });

    test('el borde NO llega a 3:1, y es una decisión — no un olvido', () {
      for (final entry in paletas.entries) {
        final p = entry.value;
        final bloque = _on(p.highlight.withAlpha(_kBloqueRelleno), p.bgCard);
        final borde = _on(p.highlight.withAlpha(_kBloqueBorde), p.bgCard);
        expect(
          _ratio(borde, bloque),
          lessThan(_kGraficoAA),
          reason: 'Llegar a 3:1 pediría α215, un magenta casi pleno que se lee '
              'como jaula. Se acepta porque el borde NO es el único canal que '
              'comunica la agrupación: están el relleno (medido arriba), el '
              'encabezado de texto y los badges A1/A2. El precedente de #821 '
              '—borderStrong calibrado a 3:1— era el caso contrario: ahí el '
              'borde era el único límite. Si este expect falla, alguien subió '
              'el alpha y conviene revisar si el argumento sigue en pie.',
        );
      }
    });
  });

  group('badge A1/A2 — la marca de orden dentro del grupo', () {
    for (final entry in paletas.entries) {
      final nombre = entry.key;
      final p = entry.value;

      test('$nombre: se despega del relleno del bloque', () {
        final bloque = _on(p.highlight.withAlpha(_kBloqueRelleno), p.bgCard);
        final badge = _on(p.highlight.withAlpha(_kBadgeRelleno), bloque);
        expect(_maxChannelDelta(badge, bloque), greaterThanOrEqualTo(16),
            reason: 'El badge se apoya sobre el bloque, no sobre la card.');
      });

      test('$nombre: "A1" en textPrimary cumple AA', () {
        final bloque = _on(p.highlight.withAlpha(_kBloqueRelleno), p.bgCard);
        final badge = _on(p.highlight.withAlpha(_kBadgeRelleno), bloque);
        final ratio = _ratio(_on(p.textPrimary, badge), badge);
        expect(ratio, greaterThanOrEqualTo(_kTextAA),
            reason: 'Barlow Condensed 11/700 NO es texto grande (WCAG pide '
                '18,66 px en bold), así que le aplica el 4,5:1 completo. '
                '$nombre: ${ratio.toStringAsFixed(2)}:1');
      });

      test('$nombre: el agarre teñido se despega de la card', () {
        final agarre = _on(p.highlight.withAlpha(_kAgarreSuperserie), p.bgCard);
        expect(_maxChannelDelta(agarre, p.bgCard), greaterThanOrEqualTo(16),
            reason: 'El agarre magenta es la marca de "esta card es de un '
                'grupo" que se ve incluso con la card colapsada.');
      });
    }
  });

  group('botones de acción del día', () {
    for (final entry in paletas.entries) {
      final nombre = entry.key;
      final p = entry.value;

      test('$nombre: EJERCICIO — accentText sobre relleno accent cumple AA',
          () {
        final relleno = _on(p.accent.withAlpha(_kBotonPrimario), p.bgCard);
        final ratio = _ratio(_on(p.accentText, relleno), relleno);
        expect(ratio, greaterThanOrEqualTo(_kTextAA),
            reason: '$nombre: ${ratio.toStringAsFixed(2)}:1');
      });

      test('$nombre: EJERCICIO — el relleno se ve como contenedor', () {
        final relleno = _on(p.accent.withAlpha(_kBotonPrimario), p.bgCard);
        expect(_maxChannelDelta(relleno, p.bgCard), greaterThanOrEqualTo(16),
            reason: 'Un botón sin contenedor visible es lo que la revisión en '
                'device señaló como el problema.');
      });

      test('$nombre: SUPERSERIE — label en textPrimary cumple AA', () {
        final relleno = _on(p.highlight.withAlpha(_kBotonSecundario), p.bgCard);
        final ratio = _ratio(_on(p.textPrimary, relleno), relleno);
        expect(ratio, greaterThanOrEqualTo(_kTextAA),
            reason: '$nombre: ${ratio.toStringAsFixed(2)}:1');
      });

      test('$nombre: SUPERSERIE — el ícono en highlight cumple 3:1', () {
        final relleno = _on(p.highlight.withAlpha(_kBotonSecundario), p.bgCard);
        final ratio = _ratio(_on(p.highlight, relleno), relleno);
        expect(ratio, greaterThanOrEqualTo(_kGraficoAA),
            reason: '$nombre: ${ratio.toStringAsFixed(2)}:1');
      });

      test('$nombre: SUPERSERIE — el magenta como tinta NO alcanza', () {
        final relleno = _on(p.highlight.withAlpha(_kBotonSecundario), p.bgCard);
        final comoTinta = _ratio(_on(p.highlight, relleno), relleno);
        expect(
          comoTinta,
          lessThan(_kTextAA),
          reason: 'Esta es la razón por la que el label va en textPrimary y no '
              'en highlight como pedía el handoff. $nombre: '
              '${comoTinta.toStringAsFixed(2)}:1',
        );
      });

      test('$nombre: + AGREGAR SET — el contorno punteado se ve', () {
        final contorno =
            _on(p.accentText.withAlpha(_kContornoPunteado), p.bgCard);
        expect(_ratio(contorno, p.bgCard), greaterThanOrEqualTo(_kGraficoAA),
            reason: 'El contorno es lo ÚNICO que delimita este botón: no tiene '
                'relleno, así que le aplica SC 1.4.11 sin atenuantes. '
                '$nombre: ${_ratio(contorno, p.bgCard).toStringAsFixed(2)}:1');
      });

      test('$nombre: + AGREGAR SET — sobre `accent` NO se vería en light', () {
        final conAccent = _on(p.accent.withAlpha(255), p.bgCard);
        final ratio = _ratio(conAccent, p.bgCard);
        if (nombre == 'light') {
          expect(
            ratio,
            lessThan(_kGraficoAA),
            reason: 'El mint pleno sobre papel mide '
                '${ratio.toStringAsFixed(2)}:1 al 100% de opacidad: como '
                'contorno no se ve a NINGUNA intensidad. Por eso el punteado '
                'va sobre accentText. Si esto pasara a cumplir, accentText '
                'perdió su razón de ser y hay que revisar su dartdoc.',
          );
        } else {
          expect(ratio, greaterThanOrEqualTo(_kGraficoAA),
              reason: 'En dark el mint sí funciona como contorno '
                  '(${ratio.toStringAsFixed(2)}:1) — el problema es sólo de '
                  'la paleta clara.');
        }
      });
    }
  });
}
