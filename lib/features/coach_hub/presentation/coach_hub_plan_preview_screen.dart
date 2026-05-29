import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../coach/application/trainer_link_providers.dart';
import '../../coach/domain/trainer_link.dart';
import '../../coach/domain/trainer_link_status.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/domain/experience_level.dart';
import '../../workout/application/exercise_providers.dart';
import '../../workout/domain/exercise.dart';
import '../../workout/application/routine_providers.dart';
import '../../workout/domain/routine.dart';
import '../../workout/domain/routine_day.dart';
import '../../workout/domain/routine_slot.dart';
import '../../workout/domain/routine_source.dart';
import '../../workout/domain/routine_visibility.dart';
import '../application/plan_import_providers.dart';
import '../domain/parsed_plan.dart';

/// Preview del plan importado. Muestra:
/// - Nombre / días / semanas / nivel
/// - Lista de ejercicios por día (con badge "Sin match" para los no
///   resueltos contra `exercises`)
/// - Selector de atleta (de los vínculos activos del PF)
/// - Botón "Asignar plan" → crea Routine + redirige a dashboard
class CoachHubPlanPreviewScreen extends ConsumerStatefulWidget {
  const CoachHubPlanPreviewScreen({super.key});

  @override
  ConsumerState<CoachHubPlanPreviewScreen> createState() =>
      _CoachHubPlanPreviewScreenState();
}

class _CoachHubPlanPreviewScreenState
    extends ConsumerState<CoachHubPlanPreviewScreen> {
  final Set<String> _selectedAthleteIds = <String>{};
  bool _saving = false;
  String? _error;

  void _toggleAthlete(String athleteId) {
    setState(() {
      if (_selectedAthleteIds.contains(athleteId)) {
        _selectedAthleteIds.remove(athleteId);
      } else {
        _selectedAthleteIds.add(athleteId);
      }
      _error = null;
    });
  }

  Future<void> _assign(ParsedPlan plan, String trainerUid) async {
    if (_selectedAthleteIds.isEmpty) {
      setState(() => _error = 'Elegí al menos un atleta antes de asignar.');
      return;
    }
    if (plan.unmatched.isNotEmpty) {
      setState(() => _error =
          'Hay ejercicios sin match. Asignalos manualmente antes de continuar.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(routineRepositoryProvider);
    final athleteIds = _selectedAthleteIds.toList();
    final failed = <String>[];

    final analytics = ref.read(analyticsServiceProvider);
    for (final athleteId in athleteIds) {
      final routine = _buildRoutine(
        plan: plan,
        trainerUid: trainerUid,
        athleteId: athleteId,
      );
      try {
        final created = await repo.createAssigned(routine);
        analytics.logPlanAssigned(
          routineId: created.id,
          assignedBy: trainerUid,
          assignedTo: athleteId,
        );
      } catch (_) {
        failed.add(athleteId);
      }
    }

    if (!mounted) return;

    if (failed.length == athleteIds.length) {
      setState(() {
        _error = 'No pudimos guardar el plan. Probá de nuevo.';
        _saving = false;
      });
      return;
    }

    ref.read(parsedPlanProvider.notifier).state = null;
    final ok = athleteIds.length - failed.length;
    final msg = failed.isEmpty
        ? (ok == 1
            ? 'Plan asignado correctamente.'
            : 'Plan asignado a $ok atletas.')
        : 'Plan asignado a $ok atleta(s). ${failed.length} fallaron.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    context.go('/dashboard');
  }

  /// Abre un modal con el catálogo de ejercicios para que el PF asigne
  /// manualmente uno de los ejercicios "sin match". Una vez elegido,
  /// actualiza el `parsedPlanProvider` con el item mapeado y lo saca de
  /// la lista `unmatched`.
  Future<void> _pickExerciseFor({
    required int dayNumber,
    required String rowName,
  }) async {
    final exercises = await ref.read(exercisesProvider.future);
    if (!mounted) return;

    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ExercisePickerSheet(
        rowName: rowName,
        exercises: exercises,
      ),
    );
    if (picked == null) return;

    final current = ref.read(parsedPlanProvider);
    if (current == null) return;

    final updatedDays = current.days
        .map((d) => d.dayNumber != dayNumber
            ? d
            : d.copyWith(
                items: d.items
                    .map(
                        (it) => (it.rowName == rowName && it.exerciseId == null)
                            ? it.copyWith(
                                exerciseId: picked.id,
                                exerciseName: picked.name,
                                muscleGroup: picked.muscleGroup,
                              )
                            : it)
                    .toList(),
              ))
        .toList();

    final updatedUnmatched = current.unmatched
        .where((u) => !(u.dayNumber == dayNumber && u.rowName == rowName))
        .toList();

    ref.read(parsedPlanProvider.notifier).state = current.copyWith(
      days: updatedDays,
      unmatched: updatedUnmatched,
    );
    setState(() => _error = null);
  }

  Routine _buildRoutine({
    required ParsedPlan plan,
    required String trainerUid,
    required String athleteId,
  }) {
    final days = plan.days
        .map(
          (d) => RoutineDay(
            dayNumber: d.dayNumber,
            name: 'Día ${d.dayNumber}',
            slots: d.items
                .map(
                  (i) => RoutineSlot(
                    exerciseId: i.exerciseId ?? '',
                    exerciseName: i.exerciseName,
                    muscleGroup: i.muscleGroup ?? '',
                    targetSets: i.sets,
                    targetRepsMin: i.repsMin,
                    targetRepsMax: i.repsMax,
                    restSeconds: i.restSec ?? 60,
                    targetWeightKg: i.weightKg,
                    notes: i.notes,
                  ),
                )
                .toList(),
          ),
        )
        .toList();

    return Routine(
      id: '',
      name: plan.name,
      split: 'Custom',
      level: plan.level,
      days: days,
      source: RoutineSource.trainerAssigned,
      assignedBy: trainerUid,
      assignedTo: athleteId,
      visibility: RoutineVisibility.private,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final plan = ref.watch(parsedPlanProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;

    if (plan == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/upload-plan');
      });
      return Scaffold(
        backgroundColor: palette.bg,
        body: Center(child: CircularProgressIndicator(color: palette.accent)),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: palette.bg,
        body: Center(child: CircularProgressIndicator(color: palette.accent)),
      );
    }

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
                  if (plan.unmatched.isNotEmpty) ...[
                    _UnmatchedWarning(palette: palette, plan: plan),
                    const SizedBox(height: 18),
                  ],
                  ...plan.days.map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _DayCard(
                        palette: palette,
                        day: d,
                        onPickManual: (item) => _pickExerciseFor(
                          dayNumber: d.dayNumber,
                          rowName: item.rowName,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _AthletePicker(
                    palette: palette,
                    trainerId: profile.uid,
                    selectedAthleteIds: _selectedAthleteIds,
                    onToggle: _toggleAthlete,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.danger, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed:
                        _saving ? null : () => _assign(plan, profile.uid),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                      disabledBackgroundColor:
                          palette.accent.withValues(alpha: 0.3),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.bg,
                            ),
                          )
                        : Text(
                            _selectedAthleteIds.length > 1
                                ? 'ASIGNAR PLAN A ${_selectedAthleteIds.length} ATLETAS'
                                : 'ASIGNAR PLAN',
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 1.4,
                            ),
                          ),
                  ),
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
                'PREVIEW',
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
  final ParsedPlan plan;

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
            value: '${plan.daysPerWeek}',
          ),
          _MetaTile(
            palette: palette,
            label: 'Duración',
            value: '${plan.durationWeeks} sem',
          ),
          _MetaTile(
            palette: palette,
            label: 'Nivel',
            value: plan.level.displayNameEs,
          ),
        ],
      ),
    );
  }
}

class _MetaTile extends StatelessWidget {
  const _MetaTile({
    required this.palette,
    required this.label,
    required this.value,
  });
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
  const _UnmatchedWarning({required this.palette, required this.plan});
  final AppPalette palette;
  final ParsedPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.warning, color: palette.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.unmatched.length} ejercicio(s) sin match',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No los encontramos en el catálogo. Ajustá los nombres en el '
                  'Excel y volvé a subirlo. No se puede asignar hasta que '
                  'estén todos resueltos.',
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

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.palette,
    required this.day,
    required this.onPickManual,
  });
  final AppPalette palette;
  final ParsedPlanDay day;
  final Future<void> Function(ParsedPlanItem item) onPickManual;

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
          ...day.items.map(
            (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                i.exerciseName,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (i.exerciseId == null) ...[
                              const SizedBox(width: 8),
                              _UnmatchedBadge(palette: palette),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _itemSubtitle(i),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        if (i.exerciseId == null) ...[
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: () => onPickManual(i),
                            icon: Icon(
                              TreinoIcon.search,
                              size: 16,
                              color: palette.accent,
                            ),
                            label: Text(
                              'Asignar manualmente',
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
                      ],
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

  String _itemSubtitle(ParsedPlanItem i) {
    final reps =
        i.repsMin == i.repsMax ? '${i.repsMin}' : '${i.repsMin}-${i.repsMax}';
    final base = '${i.sets} × $reps';
    final rest = i.restSec != null ? ' · ${i.restSec}s' : '';
    final w = i.weightKg != null ? ' · ${i.weightKg} kg' : '';
    return '$base$rest$w';
  }
}

/// Bottom sheet con search + lista del catálogo de exercises.
/// Devuelve el Exercise elegido (o null si el PF cancela).
class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet({
    required this.rowName,
    required this.exercises,
  });
  final String rowName;
  final List<Exercise> exercises;

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Exercise> get _filtered {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return widget.exercises;
    return widget.exercises.where((e) {
      if (e.name.toLowerCase().contains(q)) return true;
      if (e.muscleGroup.toLowerCase().contains(q)) return true;
      for (final alias in e.aliases) {
        if (alias.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final filtered = _filtered;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Asignar a "${widget.rowName}"',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar ejercicio…',
                hintStyle: TextStyle(color: palette.textMuted),
                prefixIcon: Icon(TreinoIcon.search, color: palette.textMuted),
                filled: true,
                fillColor: palette.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.accent, width: 1.5),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Sin resultados.',
                        style: TextStyle(color: palette.textMuted),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: palette.border,
                      ),
                      itemBuilder: (_, i) {
                        final ex = filtered[i];
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            ex.name,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            ex.muscleGroup,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(ex),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
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

class _AthletePicker extends ConsumerWidget {
  const _AthletePicker({
    required this.palette,
    required this.trainerId,
    required this.selectedAthleteIds,
    required this.onToggle,
  });
  final AppPalette palette;
  final String trainerId;
  final Set<String> selectedAthleteIds;
  final void Function(String athleteId) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksAsync = ref.watch(linksForTrainerProvider(trainerId));
    return linksAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Text(
        'No pudimos cargar tus alumnos.',
        style: TextStyle(color: palette.textMuted),
      ),
      data: (links) {
        final active =
            links.where((l) => l.status == TrainerLinkStatus.active).toList();
        if (active.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              'No tenés alumnos activos para asignarles este plan. '
              'Esperá que un atleta acepte tu vínculo y volvé a importar.',
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          );
        }
        final count = selectedAthleteIds.length;
        final label = count == 0
            ? 'ASIGNAR A (ELEGÍ UNO O MÁS)'
            : 'ASIGNAR A · $count seleccionado(s)';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                color: palette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            ...active.map(
              (link) => _AthleteOption(
                palette: palette,
                link: link,
                selected: selectedAthleteIds.contains(link.athleteId),
                onTap: () => onToggle(link.athleteId),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AthleteOption extends ConsumerWidget {
  const _AthleteOption({
    required this.palette,
    required this.link,
    required this.selected,
    required this.onTap,
  });
  final AppPalette palette;
  final TrainerLink link;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final name = pubAsync.valueOrNull?.displayName ?? 'Atleta';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? palette.accent.withValues(alpha: 0.12)
              : palette.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? TreinoIcon.checkCircleFill
                  : TreinoIcon.checkCircleEmpty,
              color: selected ? palette.accent : palette.textMuted,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
