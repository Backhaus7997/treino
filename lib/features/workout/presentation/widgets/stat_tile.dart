import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// Reusable stat tile — label above, value below.
/// Used in both [RoutineDetailScreen] and [ExerciseDetailScreen].
/// [value] accepts null and renders "—" as a placeholder (Fase 2 state).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value ?? '—',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 22,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w600,
            fontSize: 10,
            letterSpacing: 1.2,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}
