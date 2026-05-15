import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// 4-column stats row for the public profile. All values are hardcoded `'0'`
/// in Etapa 4 (real workouts/racha/seguidores/siguiendo numbers arrive in
/// Fase 4 with the Session model). RACHA is rendered in accent color to
/// match the mockup; the others use `textPrimary`.
class PublicProfileStatsRow extends StatelessWidget {
  const PublicProfileStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: _StatTile(label: 'WORKOUTS', value: '0')),
        Expanded(child: _StatTile(label: 'RACHA', value: '0', isAccent: true)),
        Expanded(child: _StatTile(label: 'SEGUIDORES', value: '0')),
        Expanded(child: _StatTile(label: 'SIGUIENDO', value: '0')),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.isAccent = false,
  });

  final String label;
  final String value;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.barlow(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: isAccent ? palette.accent : palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 1.0,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}
