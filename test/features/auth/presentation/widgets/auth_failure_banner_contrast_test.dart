// #1505: el banner de error del login era texto oscuro sobre el
// `errorContainer` de Material — rojo saturado en tema claro. Se medía el
// contraste del texto contra el fondo REAL del banner (compuesto sobre el
// fondo de la pantalla), en los dos temas.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/auth/presentation/widgets/auth_failure_banner.dart';

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (nombre, crearTema) in [
    ('claro', AppTheme.light),
    ('oscuro', AppTheme.dark),
  ]) {
    testWidgets('el texto del banner se lee (AA) en tema $nombre',
        (tester) async {
      final tema = crearTema();
      await tester.pumpWidget(MaterialApp(
        theme: tema,
        home: const Scaffold(
          body: AuthFailureBanner(failure: AuthFailure.invalidCredentials()),
        ),
      ));

      final palette = tema.extension<AppPalette>()!;
      final caja = tester.widget<Container>(find.byType(Container).first);
      final fondo = Color.alphaBlend(
        (caja.decoration! as BoxDecoration).color!,
        palette.bg,
      );
      final texto = tester
          .widget<Text>(find.text('Email o contraseña incorrectos'))
          .style!
          .color!;

      expect(_contraste(texto, fondo), greaterThanOrEqualTo(4.5),
          reason: 'texto $texto sobre $fondo');
    });
  }
}
