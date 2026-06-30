import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';

/// Read-only display of a trainer's per-exercise note (`RoutineSlot.notes`).
///
/// Tagged "DEL COACH" so the athlete knows it is a coaching cue authored by
/// their trainer — visually distinct from the exercise catalog's technique ⓘ
/// sheet (which is a tappable icon, not inline text). Athletes never edit it.
///
/// Renders nothing for empty/whitespace text; callers may guard too, but this
/// is the single source of truth for "is there a note to show".
class CoachNote extends StatelessWidget {
  const CoachNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.exerciseNoteFromCoachTag,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 1.2,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            trimmed,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
