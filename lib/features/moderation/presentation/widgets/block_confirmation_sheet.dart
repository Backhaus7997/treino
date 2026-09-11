import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../l10n/app_l10n.dart';

/// Bottom sheet que pide confirmación antes de bloquear a alguien.
///
/// Copia el molde de `UnfriendConfirmationSheet`
/// (`features/feed/presentation/widgets/unfriend_confirmation_sheet.dart`):
/// drag handle + título + fila de dos botones, y el mismo contrato —
/// [onConfirm] se invoca SÓLO al confirmar, el botón de descarte cierra sin
/// disparar nada. Suma una línea de cuerpo que la de unfriend no tiene:
/// bloquear corta chat, follow y reacciones en las dos direcciones a la vez
/// (design.md), una consecuencia menos obvia que "dejar de seguir" y que
/// vale la pena decir antes de confirmar.
class BlockConfirmationSheet extends StatelessWidget {
  const BlockConfirmationSheet({
    super.key,
    required this.targetDisplayName,
    required this.onConfirm,
  });

  /// Nombre a interpolar en el copy de confirmación.
  final String targetDisplayName;

  /// Se invoca sólo al confirmar. El botón de descarte cierra el sheet sin
  /// llamarlo (ADR-FRI-011, mismo criterio que `UnfriendConfirmationSheet`).
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: TreinoFadeSlideIn(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  // `AppRadius.full` se clampea al alto real del contenedor
                  // (4px) y da la misma píldora que un literal `2` — sin
                  // meter un radio crudo nuevo (no_raw_radius_scan_test).
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.moderationBlockConfirmTitle(targetDisplayName),
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.moderationBlockConfirmBody,
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Buttons row
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: l10n.moderationBlockDismiss,
                    bg: Colors.transparent,
                    borderColor: palette.border,
                    textColor: palette.textPrimary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetButton(
                    label: l10n.moderationBlockConfirmAction,
                    bg: palette.danger,
                    borderColor: palette.danger,
                    textColor: palette.onDanger,
                    onPressed: () {
                      Navigator.of(context).pop();
                      onConfirm();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private button widget — copia exacta del privado homónimo en
// UnfriendConfirmationSheet (no se comparte: cada sheet es dueño del suyo,
// mismo criterio que el resto del kit de sheets de confirmación).
// ---------------------------------------------------------------------------

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.bg,
    required this.borderColor,
    required this.textColor,
    required this.onPressed,
  });

  final String label;
  final Color bg;
  final Color borderColor;
  final Color textColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TreinoTappable(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 1.0,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
