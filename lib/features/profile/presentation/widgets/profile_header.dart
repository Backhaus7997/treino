import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// Top header for [ProfileScreen].
///
/// Renders "TU CUENTA" eyebrow label and "PERFIL" Barlow Condensed title.
/// No gear icon — settings surface deferred until real settings exist
/// (notifications/theme/language). Removed 2026-05-28 per PR#4 pivot.
///
/// No back-navigation arrow — this is a top-level shell screen. // i18n: Fase 6 Etapa 3
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    // Wrapped in SizedBox(width: double.infinity) so the inner Column's
    // crossAxisAlignment.start actually left-aligns across the full screen.
    // Without this, the parent Column in ProfileScreen (no crossAxisAlignment
    // → default center) collapses this widget to its natural width and
    // centers it. Mockup parity 2026-06-01 polish pass.
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TU CUENTA', // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.4,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'PERFIL', // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 28,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
