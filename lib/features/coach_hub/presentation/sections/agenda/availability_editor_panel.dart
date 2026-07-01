// PR3a — Panel de edición de reglas de disponibilidad (Dialog web idiom).
// Strings en español hardcodeado + // i18n. NO se usa AppL10n (constraint C-6).
// Dialogs: showDialog/AlertDialog (ADR-AGW-3). NO showModalBottomSheet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/availability_rule.dart';
import '../../../../coach/presentation/agenda_formatters.dart';
import 'rule_form_dialog.dart';

// ─── AvailabilityEditorPanel ──────────────────────────────────────────────────

/// Dialog que lista y permite CRUD de reglas de disponibilidad semanal.
///
/// Paridad funcional con la pantalla móvil de "Mis horarios"
/// (AvailabilityEditorScreen, sección de reglas).
/// Reusa [availabilityRulesStreamProvider] y [availabilityRepositoryProvider].
///
/// REQ-AGW-301 (SCENARIO-301-A/B/C/D).
class AvailabilityEditorPanel extends ConsumerWidget {
  const AvailabilityEditorPanel({super.key, required this.trainerId});

  final String trainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final rulesAsync = ref.watch(availabilityRulesStreamProvider(trainerId));

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'MIS HORARIOS DE TRABAJO', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 1.2,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: palette.textMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cerrar', // i18n
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),

            // ── Body ──────────────────────────────────────────────────────────
            Flexible(
              child: rulesAsync.when(
                loading: () => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: palette.accent),
                  ),
                ),
                error: (e, _) => _ErrorState(
                  palette: palette,
                  onRetry: () => ref
                      .invalidate(availabilityRulesStreamProvider(trainerId)),
                ),
                data: (rules) => _RulesList(
                  rules: rules,
                  trainerId: trainerId,
                  palette: palette,
                ),
              ),
            ),

            // ── Footer — botón Agregar ─────────────────────────────────────
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openAddForm(context, trainerId),
                  icon: Icon(Icons.add, size: 18, color: palette.accent),
                  label: Text(
                    'AGREGAR HORARIO', // i18n
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.8,
                      color: palette.accent,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.accent),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddForm(BuildContext context, String trainerId) async {
    await showDialog<void>(
      context: context,
      builder: (_) => RuleFormDialog(trainerId: trainerId),
    );
  }
}

// ─── _RulesList ───────────────────────────────────────────────────────────────

class _RulesList extends ConsumerWidget {
  const _RulesList({
    required this.rules,
    required this.trainerId,
    required this.palette,
  });

  final List<AvailabilityRule> rules;
  final String trainerId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rules.isEmpty) {
      return _EmptyHint(
        // i18n
        message:
            'Sin horarios configurados. Agregá uno para que tus alumnos puedan reservar.',
        palette: palette,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      shrinkWrap: true,
      itemCount: rules.length,
      itemBuilder: (context, index) {
        final rule = rules[index];
        return _RuleTile(
          rule: rule,
          onEdit: () => _openEditForm(context, rule),
          onDelete: () => _confirmDelete(context, ref, rule),
          palette: palette,
        );
      },
    );
  }

  Future<void> _openEditForm(
      BuildContext context, AvailabilityRule rule) async {
    await showDialog<void>(
      context: context,
      builder: (_) => RuleFormDialog(
        trainerId: trainerId,
        existing: rule,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AvailabilityRule rule,
  ) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Text(
          '¿Eliminar este horario?', // i18n
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'CANCELAR', // i18n
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: palette.textPrimary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.bg,
            ),
            child: Text(
              'CONFIRMAR', // i18n
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(availabilityRepositoryProvider).deleteRule(
          trainerId,
          rule.id,
        );
  }
}

// ─── _RuleTile ────────────────────────────────────────────────────────────────

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.onEdit,
    required this.onDelete,
    required this.palette,
  });

  final AvailabilityRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final dayLabel =
        AgendaFormatters.dayOfWeekLabels[rule.dayOfWeek] ?? '${rule.dayOfWeek}';
    final startStr =
        '${rule.startHour.toString().padLeft(2, '0')}:${rule.startMinute.toString().padLeft(2, '0')}';
    final endStr =
        '${rule.endHour.toString().padLeft(2, '0')}:${rule.endMinute.toString().padLeft(2, '0')}';
    final durationStr = '${rule.slotDurationMin} min'; // i18n

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayLabel,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$startStr – $endStr · $durationStr',
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 20, color: palette.textMuted),
            onPressed: onEdit,
            tooltip: 'Editar', // i18n
          ),
          IconButton(
            icon:
                Icon(Icons.delete_outline, size: 20, color: palette.highlight),
            onPressed: onDelete,
            tooltip: 'Eliminar', // i18n
          ),
        ],
      ),
    );
  }
}

// ─── _EmptyHint ───────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message, required this.palette});
  final String message;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Text(
          message,
          style: GoogleFonts.barlow(
            fontWeight: FontWeight.w400,
            fontSize: 13,
            color: palette.textMuted,
          ),
        ),
      ),
    );
  }
}

// ─── _ErrorState ──────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.palette, required this.onRetry});
  final AppPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Error al cargar los horarios.', // i18n
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.accent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9999),
              ),
            ),
            child: Text(
              'REINTENTAR', // i18n
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.8,
                color: palette.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
