// Los widgets de «color de estado» (badge de pago, chip de alumno, aviso de
// moderación) usan UN color para el relleno, el punto Y el texto. Como relleno
// `danger` y `accent` andan; como texto no llegan a AA (danger en oscuro,
// accent en claro). `textVariantOf` da la versión para texto del mismo color.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';

void main() {
  for (final (nombre, p) in [
    ('dark', AppPalette.mintMagenta),
    ('light', AppPalette.mintMagentaLight),
  ]) {
    group('textVariantOf — $nombre', () {
      test('danger → dangerText', () {
        expect(p.textVariantOf(p.danger), p.dangerText);
      });
      test('accent → accentText', () {
        expect(p.textVariantOf(p.accent), p.accentText);
      });
      test('lo que ya es texto queda igual', () {
        expect(p.textVariantOf(p.textMuted), p.textMuted);
        expect(p.textVariantOf(p.textPrimary), p.textPrimary);
        expect(p.textVariantOf(p.warning), p.warning);
      });
    });
  }
}
