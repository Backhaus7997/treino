import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../profile/domain/experience_level.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/domain/exercise.dart';
import '../application/plan_import_providers.dart';
import '../domain/periodized_preview.dart';
import 'widgets/exercise_picker_sheet.dart';

/// Preview de un plan PERIODIZADO importado (hoja "Programa").
///
/// Muestra metadata + un selector de semanas; por cada semana, los días con
/// sus bloques (superserie agrupada). La asignación al alumno NO está acá: ese
/// paso resuelve "semana actual" y toca la pantalla del alumno, se coordina
/// aparte. Por ahora el PF descarga, sube, valida el match y revisa.
class CoachHubPeriodizedPreviewScreen extends ConsumerStatefulWidget {
  const CoachHubPeriodizedPreviewScreen({super.key});

  @override
  ConsumerState<CoachHubPeriodizedPreviewScreen> createState() =>
      _CoachHubPeriodizedPreviewScreenState();
}

class _CoachHubPeriodizedPreviewScreenState
    extends ConsumerState<CoachHubPeriodizedPreviewScreen> {
  int _selectedWeekIndex = 0;

  Future<void> _pickExerciseFor(String rowName) async {
    final exercises = await ref.read(exercisesProvider.future);
    if (!mounted) return;

    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          ExercisePickerSheet(rowName: rowName, exercises: exercises),
    );
    if (picked == null) return;

    final current = ref.read(parsedPeriodizedPlanProvider);
    if (current == null) return;

    ref.read(parsedPeriodizedPlanProvider.notifier).state = current.mapExercise(
      rowName,
      exerciseId: picked.id,
      exerciseName: picked.name,
      muscleGroup: picked.muscleGroup,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final plan = ref.watch(parsedPeriodizedPlanProvider);

    if (plan == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/upload-plan');
      });
      return Scaffold(
        backgroundColor: palette.bg,
        body: Center(child: CircularProgressIndicator(color: palette.accent)),
      );
    }

    final weekIndex = _selectedWeekIndex.clamp(0, plan.weeks.length - 1);
    final week = plan.weeks[weekIndex];

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(palette: palette, planName: plan.name),
                  const SizedBox(height: 18),
                  _PlanMetaCard(palette: palette, plan: plan),
                  const SizedBox(height: 18),
                  if (plan.hasUnmatched) ...[
                    _UnmatchedWarning(
                      palette: palette,
                      names: plan.unmatchedNames,
                      onPick: _pickExerciseFor,
                    ),
                    const SizedBox(height: 18),
                  ],
                  _WeekSelector(
                    palette: palette,
                    weeks: plan.weeks,
                    selectedIndex: weekIndex,
                    onSelect: (i) => setState(() => _selectedWeekIndex = i),
                  ),
                  const SizedBox(height: 14),
                  ...week.days.map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _DayCard(palette: palette, day: d),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _AssignGate(palette: palette),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.palette, required this.planName});
  final AppPalette palette;
  final String planName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => context.go('/upload-plan'),
          icon: Icon(TreinoIcon.arrowLeft, color: palette.textPrimary),
          tooltip: 'Volver',
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PREVIEW · PERIODIZADO',
                style: GoogleFonts.barlowCondensed(
                  color: palette.highlight,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                planName.toUpperCase(),
                style: GoogleFonts.barlowCondensed(
                  color: palette.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  height: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanMetaCard extends StatelessWidget {
  const _PlanMetaCard({required this.palette, required this.plan});
  final AppPalette palette;
  final PeriodizedPreviewPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 12,
        children: [
          _MetaTile(
              palette: palette,
              label: 'Días/semana',
              value: '${plan.daysPerWeek}'),
          _MetaTile(
              palette: palette,
              label: 'Duración',
              value: '${plan.durationWeeks} sem'),
          _MetaTile(
              palette: palette,
              label: 'Semanas cargadas',
              value: '${plan.weeks.length}'),
          _MetaTile(
              palette: palette,
              label: 'Nivel',
              value: plan.level.displayNameEs),
        ],
      ),
    );
  }
}

class _MetaTile extends StatelessWidget {
  const _MetaTile(
      {required this.palette, required this.label, required this.value});
  final AppPalette palette;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.barlowCondensed(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _UnmatchedWarning extends StatelessWidget {
  const _UnmatchedWarning({
    required this.palette,
    required this.names,
    required this.onPick,
  });
  final AppPalette palette;
  final List<String> names;
  final Future<void> Function(String rowName) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(TreinoIcon.warning, color: palette.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${names.length} ejercicio(s) sin match',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'No los encontramos en el catálogo. Mapealos a mano (se aplica a '
            'todas las semanas) o corregí el nombre en el Excel y volvé a subirlo.',
            style:
                TextStyle(color: palette.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          ...names.map(
            (n) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      n,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => onPick(n),
                    icon: Icon(TreinoIcon.search,
                        size: 16, color: palette.accent),
                    label: Text(
                      'Asignar',
                      style: TextStyle(
                        color: palette.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector({
    required this.palette,
    required this.weeks,
    required this.selectedIndex,
    required this.onSelect,
  });
  final AppPalette palette;
  final List<PeriodizedPreviewWeek> weeks;
  final int selectedIndex;
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SEMANA',
          style: GoogleFonts.barlowCondensed(
            color: palette.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < weeks.length; i++)
              _WeekChip(
                palette: palette,
                label: '${weeks[i].weekNumber}',
                selected: i == selectedIndex,
                onTap: () => onSelect(i),
              ),
          ],
        ),
      ],
    );
  }
}

class _WeekChip extends StatelessWidget {
  const _WeekChip({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final AppPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 46,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? palette.highlight.withValues(alpha: 0.14)
              : palette.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.highlight : palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? palette.highlight : palette.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.palette, required this.day});
  final AppPalette palette;
  final PeriodizedPreviewDay day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DÍA ${day.dayNumber}',
            style: GoogleFonts.barlowCondensed(
              color: palette.highlight,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          ..._groupBlocks(day.items).map(
            (group) => group.length > 1
                ? _SupersetBlock(palette: palette, items: group)
                : _ItemRow(palette: palette, item: group.single),
          ),
        ],
      ),
    );
  }

  /// Agrupa ejercicios consecutivos con el mismo `block` (no nulo) en una
  /// superserie. Una corrida de 1 sola fila NO es superserie (queda suelta) —
  /// misma convención que el lado del alumno.
  List<List<PeriodizedPreviewItem>> _groupBlocks(
    List<PeriodizedPreviewItem> items,
  ) {
    final groups = <List<PeriodizedPreviewItem>>[];
    var i = 0;
    while (i < items.length) {
      final block = items[i].block;
      if (block == null) {
        groups.add([items[i]]);
        i++;
        continue;
      }
      final run = <PeriodizedPreviewItem>[items[i]];
      var j = i + 1;
      while (j < items.length && items[j].block == block) {
        run.add(items[j]);
        j++;
      }
      if (run.length > 1) {
        groups.add(run);
      } else {
        groups.add([items[i]]); // tag suelto → no es superserie
      }
      i = j;
    }
    return groups;
  }
}

class _SupersetBlock extends StatelessWidget {
  const _SupersetBlock({required this.palette, required this.items});
  final AppPalette palette;
  final List<PeriodizedPreviewItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.highlight.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.highlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(TreinoIcon.streak, size: 14, color: palette.highlight),
              const SizedBox(width: 6),
              Text(
                'SUPERSERIE',
                style: GoogleFonts.barlowCondensed(
                  color: palette.highlight,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...items.map((i) => _ItemRow(palette: palette, item: i)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.palette, required this.item});
  final AppPalette palette;
  final PeriodizedPreviewItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  item.exerciseName,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!item.isMatched) ...[
                const SizedBox(width: 8),
                _UnmatchedBadge(palette: palette),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _subtitle(item),
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _subtitle(PeriodizedPreviewItem i) {
    final reps =
        i.repsMin == i.repsMax ? '${i.repsMin}' : '${i.repsMin}-${i.repsMax}';
    final base = '${i.sets} × $reps';
    final rest = i.restSec != null ? ' · ${i.restSec}s' : '';
    final w = i.weightKg != null ? ' · ${i.weightKg} kg' : '';
    return '$base$rest$w';
  }
}

class _UnmatchedBadge extends StatelessWidget {
  const _UnmatchedBadge({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.warning),
      ),
      child: Text(
        'sin match',
        style: TextStyle(
          color: palette.warning,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// La asignación de planes periodizados todavía no está conectada: ese paso
/// resuelve "semana actual" del alumno y toca la pantalla del alumno (otro
/// lane). Se coordina aparte. Por ahora dejamos claro que el preview anda.
class _AssignGate extends StatelessWidget {
  const _AssignGate({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.timer, color: palette.highlight, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Próximo paso: asignación',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'El preview ya lee y valida el plan periodizado. Asignárselo a '
                  'un alumno (que avance solo de semana a semana) se conecta en '
                  'el próximo paso, junto con la pantalla del alumno.',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
