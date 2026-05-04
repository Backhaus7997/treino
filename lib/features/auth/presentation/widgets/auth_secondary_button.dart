import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// Outlined pill button for social sign-in (Google, Apple).
/// When onPressed is null: opacity 0.5, wrapped in Tooltip("Próximamente").
class AuthSecondaryButton extends StatelessWidget {
  const AuthSecondaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final disabled = onPressed == null;

    Widget button = Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: palette.border, width: 1),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          backgroundColor: Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: palette.textPrimary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    if (disabled) {
      button = Tooltip(message: 'Próximamente', child: button);
    }

    return button;
  }
}
