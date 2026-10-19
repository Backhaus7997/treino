// #1560: el estilo TREINO de los avisos vive en `showTreinoToast`, NO en el
// tema global. Un `snackBarTheme` global restiliza de golpe los ~200
// `SnackBar(` crudos sin migrar (flotantes, con margen pensado para la nav,
// en pantallas que no la tienen como el Coach Hub web o el player) sin QA de
// ninguna. Cada migración a `showTreinoToast` adopta el estilo de a una.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';

void main() {
  for (final (nombre, crearTema) in [
    ('claro', AppTheme.light),
    ('oscuro', AppTheme.dark),
  ]) {
    testWidgets('snackBarTheme neutro en tema $nombre', (tester) async {
      expect(crearTema().snackBarTheme, const SnackBarThemeData());
    });
  }
}
