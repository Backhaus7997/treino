import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// Bottom sheet that asks the user to confirm removing a friendship.
///
/// Used by [PublicProfileFollowButton] when the viewer taps SIGUIENDO.
/// The [friendDisplayName] is interpolated into the title copy.
/// [onConfirm] is called only when the user taps ELIMINAR — CANCELAR dismisses
/// without firing the callback (ADR-FRI-011).
class UnfriendConfirmationSheet extends StatelessWidget {
  const UnfriendConfirmationSheet({
    super.key,
    required this.friendDisplayName,
    required this.onConfirm,
  });

  /// The friend's display name to interpolate into the confirmation copy.
  final String friendDisplayName;

  /// Callback invoked when the user confirms the unfriend action.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
            '¿Eliminar amistad con $friendDisplayName?',
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
                  label: 'CANCELAR',
                  bg: Colors.transparent,
                  borderColor: palette.border,
                  textColor: palette.textPrimary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SheetButton(
                  label: 'ELIMINAR',
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
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
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
