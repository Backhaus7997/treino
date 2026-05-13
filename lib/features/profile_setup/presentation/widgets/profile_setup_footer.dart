import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../auth/presentation/widgets/auth_pill_button.dart';

/// Footer común a los 4 steps. Step 0 omite el botón VOLVER (no hay a dónde
/// volver). Cuando [primaryLabel] es null usa 'SIGUIENTE' por default.
class ProfileSetupFooter extends StatelessWidget {
  const ProfileSetupFooter({
    super.key,
    required this.onPrimary,
    this.onBack,
    this.primaryLabel,
  });

  /// `null` deshabilita el botón primario (step incompleto).
  final VoidCallback? onPrimary;

  /// `null` oculta el botón VOLVER (lo usa el step 1).
  final VoidCallback? onBack;

  /// Texto del CTA principal. En step 4 vale 'EMPEZAR' (cierra el flow).
  final String? primaryLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final showBack = onBack != null;

    return Row(
      children: [
        if (showBack) ...[
          SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: palette.border, width: 1),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                backgroundColor: Colors.transparent,
              ),
              child: Text(
                'VOLVER',
                style: GoogleFonts.barlowCondensed(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: AuthPillButton(
            label: primaryLabel ?? 'SIGUIENTE',
            onPressed: onPrimary,
            showArrow: false,
          ),
        ),
      ],
    );
  }
}
