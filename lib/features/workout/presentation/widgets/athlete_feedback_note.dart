import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../domain/exercise_feedback.dart';
import '../../domain/exercise_feedback_kind.dart';

/// Read-only display of one athlete-authored [ExerciseFeedback] entry.
///
/// The mirror of [CoachNote]: same inline card shape, opposite direction.
/// Tagged "DEL ALUMNO" on the trainer's surfaces so a coaching cue is never
/// confused with the athlete's own report.
///
/// [ExerciseFeedbackKind.discomfort] switches the accent to `palette.warning`
/// and swaps the tag for "MOLESTIA": a pain report has to be findable when the
/// trainer scans a long session, not buried in a wall of identical cards.
///
/// Renders nothing when the entry carries no content, so a malformed doc that
/// slipped past the rules degrades to absence rather than an empty card.
class AthleteFeedbackNote extends StatelessWidget {
  const AthleteFeedbackNote({
    super.key,
    required this.feedback,
    this.onDelete,
  });

  final ExerciseFeedback feedback;

  /// Delete affordance. Null ⇒ hidden (the trainer's view is strictly
  /// read-only; only the athlete who wrote the entry may remove it).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    if (!feedback.hasContent) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final isDiscomfort = feedback.kind == ExerciseFeedbackKind.discomfort;
    final accent = isDiscomfort ? palette.warning : palette.accent;
    final tag = isDiscomfort
        ? l10n.exerciseFeedbackDiscomfortTag
        : l10n.exerciseFeedbackFromAthleteTag;
    final text = feedback.text?.trim() ?? '';

    return Semantics(
      container: true,
      label: '$tag. $text',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _header(l10n, tag),
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: accent,
                    ),
                  ),
                ),
                if (onDelete != null)
                  // 44pt minimum tap target (a11y baseline used across the app).
                  Semantics(
                    button: true,
                    label: l10n.exerciseFeedbackDelete,
                    child: InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(9999),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                text,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                  color: palette.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "MOLESTIA · Serie 3" — the set anchor is what the chat cannot express, so
  /// it travels with the tag instead of hiding in the body text.
  String _header(AppL10n l10n, String tag) {
    final setNumber = feedback.setNumber;
    if (setNumber == null) return tag;
    return '$tag · ${l10n.exerciseFeedbackSetLabel(setNumber)}';
  }
}
