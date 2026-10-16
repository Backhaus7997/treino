// `dangerText`: el rojo para TEXTO e íconos de peligro.
//
// `danger` (#E53935) es un buen relleno, pero como texto sobre las superficies
// oscuras no llega a AA: 4,68 sobre `bg`, 4,37 sobre `bgCard` y 4,17 sobre
// `bgElevated`. Lo destapó el test de contraste del diálogo de confirmación
// (#1544), que tenía el caso oscuro en skip por esto.
//
// Es el mismo par que `accent` / `accentText`: el relleno no cambia, el texto
// tiene su propio token. Se mide sobre las TRES superficies donde se escribe
// (pantalla, card, sheet/dialog elevado), en las dos paletas (AGENTS.md §2).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const paletas = {
    'dark': AppPalette.mintMagenta,
    'light': AppPalette.mintMagentaLight,
  };

  for (final MapEntry(key: nombre, value: p) in paletas.entries) {
    group('dangerText — $nombre', () {
      for (final (superficie, fondo) in [
        ('bg', p.bg),
        ('bgCard', p.bgCard),
        ('bgElevated', p.bgElevated),
      ]) {
        test('≥ 4,5:1 sobre $superficie', () {
          expect(_ratio(p.dangerText, fondo), greaterThanOrEqualTo(4.5));
        });
      }
    });
  }

  // Control: el problema que motivó el token existe de verdad. Si alguien
  // aclara `danger` en oscuro, este test avisa que `dangerText` sobra.
  test('danger como texto NO llega a AA sobre bgCard oscuro', () {
    const p = AppPalette.mintMagenta;
    expect(_ratio(p.danger, p.bgCard), lessThan(4.5));
  });
}
