// Contraste de lo que el tema le hereda a los widgets Material.
//
// `colorScheme.onPrimary` es el color de TODO lo que Material pinta sobre el
// acento sin que nadie lo pida: el texto de un ElevatedButton, el número
// seleccionado del time picker, un chip seleccionado. En el tema claro valía
// `palette.bg` —blanco— y eso daba ~1,6:1 sobre el mint (#1504, #1494, #1505,
// #1506, #1509). En oscuro `palette.bg` es casi negro y por eso no se veía.
//
// Y `TextButton` toma `colorScheme.primary` como color de texto: mint sobre
// blanco en claro (Cancelar/ACEPTAR del picker, #1494). Va `accentText`.
//
// AGENTS.md, regla 2: todo par se mide en LAS DOS paletas.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/chat_message_bubble.dart'
    show kChatOwnMetaAlpha;

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // `testWidgets` y el tema construido ADENTRO: GoogleFonts necesita el
  // binding, y armarlo al declarar los tests revienta la carga del archivo.
  final temas = <String, (ThemeData Function(), AppPalette)>{
    'dark': (AppTheme.dark, AppPalette.mintMagenta),
    'light': (AppTheme.light, AppPalette.mintMagentaLight),
  };

  for (final MapEntry(key: nombre, value: (crear, p)) in temas.entries) {
    group('AppTheme.$nombre', () {
      testWidgets('onPrimary sobre primary ≥ 4,5:1', (_) async {
        final tema = crear();
        final s = tema.colorScheme;
        expect(_ratio(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5),
            reason: 'texto heredado sobre el acento (botones, picker, chips)');
      });

      testWidgets('el texto de TextButton habilitado ≥ 4,5:1 sobre bg y bgCard',
          (_) async {
        final tema = crear();
        final fg =
            tema.textButtonTheme.style?.foregroundColor?.resolve(const {});
        expect(fg, isNotNull, reason: 'sin tema hereda colorScheme.primary');
        expect(_ratio(fg!, p.bg), greaterThanOrEqualTo(4.5));
        expect(_ratio(fg, p.bgCard), greaterThanOrEqualTo(4.5));
      });

      testWidgets('el TextButton deshabilitado NO se pinta como habilitado',
          (_) async {
        final tema = crear();
        final style = tema.textButtonTheme.style!;
        expect(
          style.foregroundColor!.resolve({WidgetState.disabled}),
          isNot(style.foregroundColor!.resolve(const {})),
        );
      });
    });
  }

  // El `textButtonTheme` vive en el ThemeData: si su color no tiene `==`, el
  // tema nunca compara igual y la app entera rebuildea en cada frame.
  testWidgets('el textButtonTheme compara por valor', (_) async {
    expect(AppTheme.light().textButtonTheme, AppTheme.light().textButtonTheme);
    expect(AppTheme.dark().textButtonTheme, AppTheme.dark().textButtonTheme);
    // Control negativo: un `==` que devuelva siempre true no pasa.
    expect(
      AppTheme.light().textButtonTheme,
      isNot(AppTheme.dark().textButtonTheme),
    );
  });

  // La metadata de la burbuja propia del chat (hora, check) es ink ATENUADO
  // sobre el acento: se mide la mezcla real, cuantizada a 8 bits, no el ink
  // puro. Con `palette.bg` daba ~1,4:1 en claro (Codex en #1520).
  for (final (nombre, p) in [
    ('dark', AppPalette.mintMagenta),
    ('light', AppPalette.mintMagentaLight),
  ]) {
    test('metadata de la burbuja propia ≥ 4,5:1 sobre el acento ($nombre)', () {
      final mezcla = Color.alphaBlend(
        TreinoButtonTokens.ink.withValues(alpha: kChatOwnMetaAlpha),
        p.accent,
      );
      double q(double v) => (v * 255).round() / 255;
      final pixel = Color.from(
          alpha: 1, red: q(mezcla.r), green: q(mezcla.g), blue: q(mezcla.b));
      expect(_ratio(pixel, p.accent), greaterThanOrEqualTo(4.5));
    });
  }
}
