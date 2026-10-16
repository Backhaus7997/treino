import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/domain/set_enums.dart';
import '../../../workout/domain/set_spec.dart';
import '../../data/periodized_import_draft.dart';
import '../../data/periodized_routine_mapper.dart';
import '../../domain/periodized_plan.dart';
import 'button/treino_button.dart';
import 'filter_chips/filter_chips.dart';
import 'import_plan_widgets.dart';

/// Vista previa del plan periodizado: selector de semana y una tarjeta por
/// día con los renglones, las superseries agrupadas y los chips de cada serie.

/// Etiqueta del chip de la semana [index] (0-based).
String weekLabel(int index) => 'SEMANA ${index + 1}';

/// Selector SEMANA 1..N. Siempre hay una semana elegida: tocar la elegida no
/// la deselecciona.
class PeriodizedWeekSelector extends StatelessWidget {
  const PeriodizedWeekSelector({
    super.key,
    required this.numWeeks,
    required this.selected,
    required this.onChanged,
  });

  final int numWeeks;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = [for (var w = 0; w < numWeeks; w++) weekLabel(w)];
    return TreinoFilterChips(
      options: labels,
      selected: {weekLabel(selected)},
      onChanged: (next) {
        if (next.isEmpty) return;
        onChanged(labels.indexOf(next.first));
      },
    );
  }
}

/// Resumen en texto de las series de una semana: `3 × 8`, `3 × 8 + 1 × 6`, o
/// sólo la cantidad de series cuando el detalle va en los chips (fallo,
/// duración, distancia).
String describeWeekSets(List<SetSpec> sets) {
  final groups = <String, int>{};
  for (final s in sets) {
    final token = switch (s) {
      SetSpec(type: SetType.failure) => '',
      SetSpec(durationSeconds: final d?) when d > 0 => '',
      SetSpec(distanceMeters: final m?) when m > 0 => '',
      SetSpec(reps: final r?) => '$r',
      _ => '',
    };
    groups[token] = (groups[token] ?? 0) + 1;
  }
  final withReps = {
    for (final e in groups.entries)
      if (e.key.isNotEmpty) e.key: e.value,
  };
  final noDetail = groups[''] ?? 0;
  final parts = [
    for (final e in withReps.entries) '${e.value} × ${e.key}',
    if (noDetail > 0) '$noDetail ${noDetail == 1 ? 'serie' : 'series'}',
  ];
  return parts.join(' + ');
}

String _formatMinutes(int seconds) {
  if (seconds % 60 == 0) return '${seconds ~/ 60} min';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return m == 0 ? '$s s' : '$m min $s s';
}

String _formatMeters(double m) =>
    m == m.truncateToDouble() ? '${m.toInt()} m' : '$m m';

/// Una tarjeta por día.
class PeriodizedDayPreviewCard extends StatelessWidget {
  const PeriodizedDayPreviewCard({
    super.key,
    required this.day,
    required this.week,
    required this.draft,
    required this.onConfirmSuggestion,
    required this.onPickManual,
    required this.onCreateCustom,
  });

  final PeriodizedDay day;

  /// Semana mostrada (0-based).
  final int week;
  final PeriodizedImportDraft draft;
  final void Function(ExerciseKey key) onConfirmSuggestion;
  final void Function(ExerciseKey key, String rawName) onPickManual;

  /// «Crear como propio»: el padre pasa por el tope del plan y abre el
  /// formulario de ejercicio propio con [rawName] precargado.
  final void Function(ExerciseKey key, String rawName) onCreateCustom;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ImportCard(
      padding: AppSpacing.s14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DÍA ${day.dayNumber}',
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: palette.highlight,
              fontSize: AppTextSize.caption,
              fontWeight: AppFonts.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final row in day.rows)
            _RowBlock(
              day: day,
              row: row,
              week: week,
              draft: draft,
              onConfirmSuggestion: onConfirmSuggestion,
              onPickManual: onPickManual,
              onCreateCustom: onCreateCustom,
            ),
        ],
      ),
    );
  }
}

class _RowBlock extends StatelessWidget {
  const _RowBlock({
    required this.day,
    required this.row,
    required this.week,
    required this.draft,
    required this.onConfirmSuggestion,
    required this.onPickManual,
    required this.onCreateCustom,
  });

  final PeriodizedDay day;
  final PeriodizedRow row;
  final int week;
  final PeriodizedImportDraft draft;
  final void Function(ExerciseKey key) onConfirmSuggestion;
  final void Function(ExerciseKey key, String rawName) onPickManual;

  /// «Crear como propio»: el padre pasa por el tope del plan y abre el
  /// formulario de ejercicio propio con [rawName] precargado.
  final void Function(ExerciseKey key, String rawName) onCreateCustom;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final lines = [
      for (final ex in row.exercises)
        _ExerciseLine(
          key: ValueKey('ex-${day.dayNumber}-${row.excelRow}-${ex.component}'),
          exKey: exerciseKeyOf(day, row, ex),
          exercise: ex,
          week: week,
          draft: draft,
          onConfirmSuggestion: onConfirmSuggestion,
          onPickManual: onPickManual,
          onCreateCustom: onCreateCustom,
        ),
    ];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (row.isSuperset)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.hairline),
            child: Text(
              'SUPERSERIE',
              style: importText(
                palette.accent,
                size: AppTextSize.micro,
                weight: AppFonts.w700,
              ),
            ),
          ),
        ...lines,
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            if (row.isWarmup)
              ImportChip(label: 'CALENTAMIENTO', color: palette.warning),
            ImportChip(label: 'Descanso ${row.restSeconds} s'),
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: row.isSuperset
          // Las superseries se agrupan con un borde de acento y un fondo propio: se leen como UN bloque con varios ejercicios.
          ? Container(
              key: ValueKey('superset-${day.dayNumber}-${row.excelRow}'),
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: palette.accent),
              ),
              child: content,
            )
          : content,
    );
  }
}

class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({
    super.key,
    required this.exKey,
    required this.exercise,
    required this.week,
    required this.draft,
    required this.onConfirmSuggestion,
    required this.onPickManual,
    required this.onCreateCustom,
  });

  final ExerciseKey exKey;
  final PeriodizedExercise exercise;
  final int week;
  final PeriodizedImportDraft draft;
  final void Function(ExerciseKey key) onConfirmSuggestion;
  final void Function(ExerciseKey key, String rawName) onPickManual;

  /// «Crear como propio»: el padre pasa por el tope del plan y abre el
  /// formulario de ejercicio propio con [rawName] precargado.
  final void Function(ExerciseKey key, String rawName) onCreateCustom;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final assigned = draft.assignments[exKey];
    final suggestion = draft.suggestions[exKey];
    final resolved = assigned != null;
    final emptyWeek = exercise.emptyWeeks.contains(week);
    final sets =
        week < exercise.weeks.length ? exercise.weeks[week] : const <SetSpec>[];

    // Un ejercicio con la celda de la semana vacía va igual, pero en rojo.
    final nameColor = emptyWeek ? palette.danger : palette.textPrimary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  resolved ? assigned.name : exercise.rawName,
                  style: importText(nameColor, weight: AppFonts.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!resolved) ...[
                const SizedBox(width: AppSpacing.s8),
                ImportChip(
                  label:
                      suggestion != null ? 'sugerencia pendiente' : 'sin match',
                  color: palette.warning,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.hairline),
          if (emptyWeek)
            Row(
              children: [
                Icon(TreinoIcon.warning, color: palette.dangerText),
                const SizedBox(width: AppSpacing.hairline),
                Text(
                  'falta cargar reps',
                  style: importText(
                    palette.dangerText,
                    size: AppTextSize.caption,
                    weight: AppFonts.w600,
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.hairline,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  describeWeekSets(sets),
                  style: importText(
                    palette.textMuted,
                    size: AppTextSize.caption,
                  ),
                ),
                ..._chipsFor(sets, exercise.note, palette),
              ],
            ),
          if (!resolved && suggestion != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Sugerencia: ${suggestion.name}',
              style: importText(
                palette.accent,
                size: AppTextSize.bodyDense,
                weight: AppFonts.w600,
              ),
            ),
          ],
          if (!resolved) ...[
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                if (suggestion != null)
                  TreinoButton(
                    label: 'Confirmar',
                    variant: TreinoButtonVariant.primary,
                    size: TreinoButtonSize.sm,
                    onPressed: () => onConfirmSuggestion(exKey),
                  ),
                TreinoButton(
                  label: suggestion != null
                      ? 'Cambiar'
                      : 'Vincular con la biblioteca',
                  icon: TreinoIcon.search,
                  variant: TreinoButtonVariant.ghostAccent,
                  size: TreinoButtonSize.sm,
                  onPressed: () => onPickManual(exKey, exercise.rawName),
                ),
                // Sólo sin candidato: con una sugerencia el camino es
                // confirmarla o cambiarla.
                if (suggestion == null)
                  TreinoButton(
                    label: 'Crear como propio',
                    icon: TreinoIcon.plus,
                    variant: TreinoButtonVariant.ghostAccent,
                    size: TreinoButtonSize.sm,
                    onPressed: () => onCreateCustom(exKey, exercise.rawName),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Chips de las series de la semana: AL FALLO, duración, distancia y la
  /// nota del slot (`c/pierna`…).
  List<Widget> _chipsFor(List<SetSpec> sets, String? note, AppPalette palette) {
    final durations = <String>{
      for (final s in sets)
        if ((s.durationSeconds ?? 0) > 0) _formatMinutes(s.durationSeconds!),
    };
    final distances = <String>{
      for (final s in sets)
        if ((s.distanceMeters ?? 0) > 0) _formatMeters(s.distanceMeters!),
    };
    return [
      if (sets.any((s) => s.type == SetType.failure))
        ImportChip(label: 'AL FALLO', color: palette.highlight),
      for (final d in durations) ImportChip(label: d),
      for (final m in distances) ImportChip(label: m),
      if (note != null && note.isNotEmpty) ImportChip(label: note),
    ];
  }
}
