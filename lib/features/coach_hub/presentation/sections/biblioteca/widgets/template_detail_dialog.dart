// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/template_format.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';

/// Opens an [AlertDialog] with the details of a trainer template.
///
/// Entry point: [showTemplateDetailDialog].
///
/// Shows: name, level, días/sem · semanas, and a per-day slot-count summary.
/// When [onEdit] is provided, an "Editar" action closes the dialog and runs it
/// (the caller navigates to the template editor). When [onUse] is provided, a
/// "Usar en un alumno" action closes the dialog and runs it (the caller opens
/// the athlete picker and copies the template into an assigned routine —
/// parity with mobile's template-card "Asignar"). Both actions hand off to the
/// caller so this widget stays context-safe after the dialog pops.
///
/// REQ-BIBW-10, SCENARIO-BIBW-10a.
void showTemplateDetailDialog(
  BuildContext context,
  Routine routine, {
  VoidCallback? onEdit,
  VoidCallback? onUse,
  VoidCallback? onDelete,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => _TemplateDetailDialog(
      routine: routine,
      onEdit: onEdit,
      onUse: onUse,
      onDelete: onDelete,
    ),
  );
}

class _TemplateDetailDialog extends StatelessWidget {
  const _TemplateDetailDialog({
    required this.routine,
    this.onEdit,
    this.onUse,
    this.onDelete,
  });

  final Routine routine;
  final VoidCallback? onEdit;
  final VoidCallback? onUse;

  /// When provided, an "Eliminar" action pops the dialog and hands off to the
  /// caller (which shows the confirmation + deletes) — same context-safe
  /// pop-then-hand-off contract as [onEdit]/[onUse].
  final VoidCallback? onDelete;

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: 0.3),
                  ),
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
                routineCadenceLabel(routine), // i18n
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
              color: palette.textMuted,
            ),
          ),
        ),
        if (onDelete != null)
          TextButton(
            key: const Key('template_detail_delete_button'),
            onPressed: () {
              Navigator.of(context).pop();
              onDelete!();
            },
            child: Text(
              'Eliminar', // i18n
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w600,
                color: palette.danger,
              ),
            ),
          ),
        if (onEdit != null)
          TextButton(
            key: const Key('template_detail_edit_button'),
            // Pop first, then hand off — the caller's context does the
            // navigation, so nothing runs on this dialog's dead context.
            onPressed: () {
              Navigator.of(context).pop();
              onEdit!();
            },
            child: Text(
              'Editar', // i18n
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w600,
                color: palette.accent,
              ),
            ),
          ),
        if (onUse != null)
          TextButton(
            key: const Key('template_detail_use_button'),
            // Same pop-then-hand-off contract as Editar: the caller owns the
            // athlete picker + assign, so nothing runs on this dead context.
            onPressed: () {
              Navigator.of(context).pop();
              onUse!();
            },
            child: Text(
              'Usar en un alumno', // i18n
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w700,
                color: palette.accent,
              ),
            ),
          ),
      ],
    );
  }
}
