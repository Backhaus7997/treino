// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';

/// Opens a read-only [AlertDialog] with the details of a trainer template.
///
/// Entry point: [showTemplateDetailDialog].
///
/// Shows: name, level, días/sem · semanas, and a per-day slot-count summary.
/// NO edit controls — creation/editing is out of scope (W5.2/W5.4).
/// NO new provider or navigation (ADR-CHW-005 compliant).
///
/// REQ-BIBW-10, SCENARIO-BIBW-10a.
void showTemplateDetailDialog(BuildContext context, Routine routine) {
  showDialog<void>(
    context: context,
    builder: (_) => _TemplateDetailDialog(routine: routine),
  );
}

class _TemplateDetailDialog extends StatelessWidget {
  const _TemplateDetailDialog({required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      title: Text(
        routine.name,
        style: GoogleFonts.barlowCondensed(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: palette.textPrimary,
          letterSpacing: 0.5,
        ),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Level chip ───────────────────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: palette.accent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  routine.level.displayNameEs.toUpperCase(), // i18n
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.accent,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── días/sem · semanas ───────────────────────────────────────
              Text(
                '${routine.days.length} días/sem · ${routine.numWeeks} semanas', // i18n
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textMuted,
                ),
              ),
              if (routine.days.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'DÍAS DE ENTRENAMIENTO', // i18n
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.textMuted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                // Per-day slot-count summary
                for (final day in routine.days) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            day.name,
                            style: GoogleFonts.barlow(
                              fontSize: 13,
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${day.slots.length} ejercicios', // i18n
                          style: GoogleFonts.barlow(
                            fontSize: 12,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cerrar', // i18n
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w600,
              color: palette.accent,
            ),
          ),
        ),
      ],
    );
  }
}
