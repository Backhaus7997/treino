// #1503: el switch apagado era el default de M3 — pulgar y contorno en
// `colorScheme.outline`, casi negro y grueso. Sólo se estila el estado
// apagado y habilitado; encendido y deshabilitado siguen en el default.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';

void main() {
  for (final (nombre, crearTema) in [
    ('claro', AppTheme.light),
    ('oscuro', AppTheme.dark),
  ]) {
    testWidgets('switch apagado del kit en tema $nombre', (tester) async {
      final tema = crearTema();
      final palette = tema.extension<AppPalette>()!;
      final sw = tema.switchTheme;

      expect(sw.thumbColor!.resolve({}), palette.textMuted);
      expect(sw.trackColor!.resolve({}), palette.bgCard);
      expect(sw.trackOutlineColor!.resolve({}), palette.border);

      for (final otro in [
        {WidgetState.selected},
        {WidgetState.disabled},
      ]) {
        expect(sw.thumbColor!.resolve(otro), isNull);
        expect(sw.trackOutlineColor!.resolve(otro), isNull);
      }

      // Igualdad de VALOR: un `resolveWith` rebuildea la app entera.
      expect(crearTema().switchTheme, sw);
    });
  }
}
