import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Top header for [ProfileScreen].
///
/// Renders "TU CUENTA" eyebrow label, "PERFIL" Barlow Condensed title, and a
/// gear icon that navigates to `/profile/settings` on tap.
///
/// No back-navigation arrow — this is a top-level shell screen. // i18n: Fase 6 Etapa 3
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
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
          // 48×48 hit area (12px padding around 24px icon — per design §4.1)
          GestureDetector(
            key: const Key('profile_header_gear'),
            onTap: () => context.push('/profile/settings'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                TreinoIcon.settings,
                size: 24,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
