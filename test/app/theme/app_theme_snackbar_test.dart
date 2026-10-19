// #1560: sin `snackBarTheme` los avisos salían con el default de Material
// (banda blanca/negra de borde a borde, sin radio, tapando la nav flotante).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';

void main() {
  for (final (nombre, crearTema) in [
    ('claro', AppTheme.light),
    ('oscuro', AppTheme.dark),
  ]) {
    testWidgets('snackBarTheme flotante del kit en tema $nombre',
        (tester) async {
      final tema = crearTema();
      final palette = tema.extension<AppPalette>()!;
      final sb = tema.snackBarTheme;

      expect(sb.behavior, SnackBarBehavior.floating);
      expect(sb.backgroundColor, palette.bgCard);
      expect(sb.elevation, 0);
      expect(
        sb.insetPadding,
        const EdgeInsets.fromLTRB(20, 0, 20, TreinoBottomBar.toastBottomMargin),
      );
      final shape = sb.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(AppRadius.sm));
      expect(shape.side.color, palette.border);
      expect(sb.contentTextStyle!.color, palette.textPrimary);
      expect(sb.contentTextStyle!.fontFamily, contains('Barlow'));
    });
  }
}
