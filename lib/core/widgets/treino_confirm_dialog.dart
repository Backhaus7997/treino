import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../app/theme/app_palette.dart';
import '../../l10n/app_l10n.dart';

/// Confirmación de mobile: título condensado, cuerpo opcional, Cancelar
/// neutro y la acción en `danger` cuando es destructiva.
///
/// Es la ÚNICA confirmación de la app mobile (#1496). Había tres: la de post
/// (Material pelado, Cancelar/Eliminar en mint sobre blanco — #1474), la de
/// horario (sin título, pills, «Confirmar» en mint) y la de medición, que era
/// la correcta y es el modelo de ésta.
///
/// El Coach Hub web tiene su propio `TreinoDialog` (anatomía de escritorio:
/// header con cerrar, botones del kit). No se reusa acá a propósito.
///
/// Devuelve `true` sólo si se confirmó: cancelar o tocar afuera dan `false`,
/// nunca `null`, así el caller no repite el `confirmed != true`.
Future<bool> showTreinoConfirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _TreinoConfirmDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      destructive: destructive,
    ),
  );
  return confirmed ?? false;
}

class _TreinoConfirmDialog extends StatelessWidget {
  const _TreinoConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.destructive,
  });

  final String title;
  final String? body;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final body = this.body;

    return AlertDialog(
      backgroundColor: palette.bgCard,
      title: Text(
        title,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: AppTextSize.title,
          color: palette.textPrimary,
        ),
      ),
      content: body == null
          ? null
          : Text(
              body,
              style: GoogleFonts.barlow(
                fontSize: AppTextSize.bodyDense,
                color: palette.textPrimary,
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            l10n.commonCancel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: AppTextSize.body,
              color: palette.textMuted,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: AppTextSize.body,
              // Texto, no relleno: `accentText` y no `accent` (mint sobre
              // blanco da ~1,6:1 en claro).
              color: destructive ? palette.danger : palette.accentText,
            ),
          ),
        ),
      ],
    );
  }
}
