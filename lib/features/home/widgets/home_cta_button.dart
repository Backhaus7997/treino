import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';

/// Full-width pill CTA used on the Home screen.
/// Mirrors the visual style of [AuthPillButton] without the loading state —
/// no network call needed (navigation is synchronous, YAGNI for isLoading).
class HomeCTAButton extends StatelessWidget {
  const HomeCTAButton({
    super.key,
    required this.label,
    this.onPressed,
    this.leadingIcon,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Optional leading icon. Accepts a [TreinoIcon] constant (type: [IconData]).
  /// When null no [Icon] widget is rendered inside the button.
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.bg,
          disabledBackgroundColor: palette.accent.withValues(alpha: 0.5),
          disabledForegroundColor: palette.bg,
          shape: const StadiumBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, color: palette.bg, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 1.0,
                color: palette.bg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
