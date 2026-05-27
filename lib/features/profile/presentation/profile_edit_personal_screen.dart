import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';

/// Stub implementation for PR#1. Real form arrives in PR#2.
///
/// Renders a minimal back-navigation header so the route is usable
/// in end-to-end smoke tests mid-chain. // i18n: Fase 6 Etapa 3
class ProfileEditPersonalScreen extends StatelessWidget {
  const ProfileEditPersonalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: GestureDetector(
            onTap: () => context.pop(),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  'EDITAR PERFIL', // i18n: Fase 6 Etapa 3
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Text(
              'Próximamente en PR#2', // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
