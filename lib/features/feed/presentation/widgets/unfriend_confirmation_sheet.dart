import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../l10n/app_l10n.dart';

/// Qué acción confirma el sheet. Las dos borran UNA arista saliente, pero le
/// significan cosas distintas al usuario: una corta un vínculo vigente, la otra
/// retira un pedido que todavía nadie contestó. Mezclar el copy haría que
/// cancelar una solicitud se lea como "eliminar" algo que nunca existió.
enum UnfollowSheetMode {
  /// Arista saliente `accepted` — dejar de seguir.
  unfollow,

  /// Arista saliente `pending` — cancelar la solicitud enviada.
  cancelRequest,
}

/// Bottom sheet que pide confirmación antes de borrar la arista SALIENTE.
///
/// Lo usa [PublicProfileFollowButton] tanto en SIGUIENDO como en SOLICITUD
/// ENVIADA; [mode] decide el copy. [onConfirm] se invoca sólo al confirmar —
/// el botón de descarte cierra sin disparar nada (ADR-FRI-011).
class UnfriendConfirmationSheet extends StatelessWidget {
  const UnfriendConfirmationSheet({
    super.key,
    required this.friendDisplayName,
    required this.onConfirm,
    this.mode = UnfollowSheetMode.unfollow,
  });

  /// The friend's display name to interpolate into the confirmation copy.
  final String friendDisplayName;

  /// Callback invoked when the user confirms the action.
  final VoidCallback onConfirm;

  /// Qué acción se está confirmando. Default: dejar de seguir.
  final UnfollowSheetMode mode;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final isCancel = mode == UnfollowSheetMode.cancelRequest;
    final title = isCancel
        ? l10n.feedCancelRequestConfirmTitle(friendDisplayName)
        : l10n.feedUnfollowConfirmTitle(friendDisplayName);
    final dismissLabel =
        isCancel ? l10n.feedCancelRequestDismiss : l10n.feedUnfollowDismiss;
    final confirmLabel = isCancel
        ? l10n.feedCancelRequestConfirmAction
        : l10n.feedUnfollowConfirmAction;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      // Sin override de distance: usa el default del sistema (slideMd),
      // igual que ReviewBottomSheet (review_bottom_sheet.dart:144) — ambos
      // son sheets de confirmación/formulario de tamaño comparable, la
      // divergencia de 8px vs 12px era arbitraria.
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
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Title
            Text(
              title,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Buttons row
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: dismissLabel,
                    bg: Colors.transparent,
                    borderColor: palette.border,
                    textColor: palette.textPrimary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SheetButton(
                    label: confirmLabel,
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
// Private button widget
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
          borderRadius: BorderRadius.circular(20),
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
