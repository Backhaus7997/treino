// #1513: `FilledButton` y `OutlinedButton` no tenían tema y caían al default
// de Material: Barlow regular fina, y el outlined con texto mint sobre blanco
// (~1,6:1) y borde casi negro. LISTO/COMPARTIR del resumen y GUARDAR del
// check-in de ánimo eran eso.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';

void main() {
  for (final (nombre, crearTema) in [
    ('claro', AppTheme.light),
    ('oscuro', AppTheme.dark),
  ]) {
    testWidgets('botones del kit en tema $nombre', (tester) async {
      final tema = crearTema();
      final palette = tema.extension<AppPalette>()!;

      for (final style in [
        tema.filledButtonTheme.style!,
        tema.outlinedButtonTheme.style!,
      ]) {
        final label = style.textStyle!.resolve({})!;
        expect(label.fontFamily, contains('BarlowCondensed'));
        expect(label.fontWeight, FontWeight.w700);
      }

      final outlined = tema.outlinedButtonTheme.style!;
      expect(outlined.foregroundColor!.resolve({}), palette.accentText);
      expect(outlined.side!.resolve({})!.color, palette.border);

      // Igualdad de VALOR: un `resolveWith` acá rebuildea la app entera en
      // cada build del MaterialApp (no tiene `==`).
      expect(crearTema().filledButtonTheme, tema.filledButtonTheme);
      expect(crearTema().outlinedButtonTheme, tema.outlinedButtonTheme);
    });
  }
}
