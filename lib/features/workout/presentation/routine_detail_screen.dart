import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../coach/presentation/coach_strings.dart';
import '../../profile/application/user_providers.dart' show userProfileProvider;
import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/domain/user_role.dart';
import '../application/plan_gating.dart';
import '../application/routine_providers.dart';
import '../application/session_providers.dart'
    show currentUidProvider, planProgressProvider;
import '../domain/routine.dart';
import '../domain/routine_day.dart';
import '../domain/routine_slot.dart';
import '../domain/routine_source.dart';
import 'widgets/exercise_slot_row.dart';
import 'widgets/stat_tile.dart';
import 'workout_strings.dart';

/// RoutineDetailScreen — ConsumerStatefulWidget that observes routineByIdProvider.
/// selectedDayIndex is local state (ADR-RD-3).
/// No Scaffold, AppBackground, or SafeArea — provided by _ShellScaffold (REQ-RDT-011).
class RoutineDetailScreen extends ConsumerStatefulWidget {
  const RoutineDetailScreen({super.key, required this.routineId});

  final String routineId;

  @override
  ConsumerState<RoutineDetailScreen> createState() =>
      _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends ConsumerState<RoutineDetailScreen> {
  int selectedDayIndex = 0;

  /// 0-based selected week index. Only used when routine.numWeeks > 1.
  int selectedWeekIndex = 0;

  @override
  Widget build(BuildContext context) {
    final routineAsync = ref.watch(routineByIdProvider(widget.routineId));

    // Stack so the hero image can extend edge-to-edge from the top of the
    // safe area while the back button floats over it. Non-data states still
    // render the back button on top so the user can always escape.
    return Stack(
      children: [
        Positioned.fill(
          child: routineAsync.when(
            data: (routine) {
              if (routine == null) {
                return const _NotFoundState(label: 'Rutina no encontrada');
              }
              // `clamp(0, length - 1)` throws when length == 0 — empty-check
              // BEFORE clamping.
              if (routine.days.isEmpty) {
                return const _EmptyState(
                    message: 'Esta rutina no tiene días configurados.');
              }
              final dayIndex =
                  selectedDayIndex.clamp(0, routine.days.length - 1);
              final day = routine.days[dayIndex];
              return _RoutineDetailContent(
                routine: routine,
                day: day,
                selectedDayIndex: dayIndex,
                selectedWeekIndex: selectedWeekIndex,
                onSelectDay: (i) => setState(() => selectedDayIndex = i),
                onSelectWeek: (i) => setState(() => selectedWeekIndex = i),
                onSlotTap: (slot) {
                  // Pass the routine owner's uid as `ownerId` so the detail
                  // screen can fall back to that owner's customExercises
                  // subcollection when the slot references a custom exercise
                  // instead of a public-catalogue one (see slotExerciseProvider).
                  // Trainer-assigned plans → the trainer (assignedBy); athlete
                  // self-created routines → the athlete (createdBy). Without the
                  // createdBy fallback, an athlete's own custom exercise resolves
                  // to null → "Ejercicio no encontrado".
                  final ownerId = routine.assignedBy ?? routine.createdBy;
                  final target = ownerId != null && ownerId.isNotEmpty
                      ? '/workout/exercise/${slot.exerciseId}?ownerId=$ownerId'
                      : '/workout/exercise/${slot.exerciseId}';
                  context.push(target);
                },
              );
            },
            loading: () => const _RoutineLoadingSkeleton(),
            error: (_, __) => _ErrorState(
              message: 'No pudimos cargar la rutina.',
              onRetry: () =>
                  ref.invalidate(routineByIdProvider(widget.routineId)),
            ),
          ),
        ),
        const Positioned(top: 0, left: 0, child: _BackBar()),
      ],
    );
  }
}

/// Persistent top-left back button. Always visible so the user can never
/// dead-end on a deep-linked screen — even in loading, error, or not-found
/// states (REQ-RDT-016 strengthened). Now floats over the hero image with a
/// translucent chip so it stays legible on bright photos.
class _BackBar extends StatelessWidget {
  const _BackBar();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8),
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/workout'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Happy-path content
// ---------------------------------------------------------------------------

class _RoutineDetailContent extends ConsumerWidget {
  const _RoutineDetailContent({
    required this.routine,
    required this.day,
    required this.selectedDayIndex,
    required this.selectedWeekIndex,
    required this.onSelectDay,
    required this.onSelectWeek,
    required this.onSlotTap,
  });

  final Routine routine;
  final RoutineDay day;
  final int selectedDayIndex;

  /// 0-based week index. Ignored when routine.numWeeks == 1.
  final int selectedWeekIndex;

  final ValueChanged<int> onSelectDay;
  final ValueChanged<int> onSelectWeek;
  final ValueChanged<RoutineSlot> onSlotTap;

  int _totalSets(RoutineDay d) =>
      d.slots.fold(0, (sum, s) => sum + s.targetSets);

  String? _minutesValue(RoutineDay d) =>
      d.estimatedMinutes != null ? '${d.estimatedMinutes}' : null;

  /// Walks [day.slots] and emits either a standalone [ExerciseSlotRow] or a
  /// magenta "SUPERSERIE" block wrapping consecutive slots that share the same
  /// non-null [RoutineSlot.supersetGroup]. Mirrors the trainer editor's
  /// `_buildSlotRows` so the athlete sees blocks exactly as they were authored.
  ///
  /// Ordinals stay absolute over the whole day (a superset at positions 3–4
  /// shows "3" and "4"), so the numbering reads as one continuous list. A lone
  /// tagged slot (run length < 2) renders standalone — no "superset of one".
  ///
  /// [viewedWeek] is passed down to ExerciseSlotRow for week-aware prescription
  /// display (REQ-PERIOD-041).
  List<Widget> _buildExerciseList(int viewedWeek) {
    final slots = day.slots;
    final widgets = <Widget>[];
    var i = 0;
    while (i < slots.length) {
      final group = slots[i].supersetGroup;
      if (group != null) {
        final items = <({int index, RoutineSlot slot})>[];
        var scan = i;
        while (scan < slots.length && slots[scan].supersetGroup == group) {
          items.add((index: scan, slot: slots[scan]));
          scan++;
        }
        if (items.length >= 2) {
          widgets.add(_SupersetBlock(
            items: items,
            onSlotTap: onSlotTap,
            viewedWeek: viewedWeek,
          ));
          widgets.add(const SizedBox(height: 12));
          i = scan;
          continue;
        }
      }
      final slot = slots[i];
      widgets.add(ExerciseSlotRow(
        slot: slot,
        index: i + 1,
        week: viewedWeek,
        onTap: () => onSlotTap(slot),
      ));
      widgets.add(const SizedBox(height: 12));
      i++;
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REQ-PERIOD-042 HARD INVARIANT: when numWeeks == 1, render the
    // single-week path untouched — no week selector, no locks, all days free.
    final isPeriodized = routine.numWeeks > 1;

    // For single-week plans the viewed week is always 0.
    final viewedWeek = isPeriodized ? selectedWeekIndex : 0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HeroStrip(
            routine: routine,
            badgeText:
                '${(routine.split ?? WorkoutStrings.splitFallback).toUpperCase()} · DÍA ${day.dayNumber}',
            titleText: day.name.toUpperCase(),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 20),
              _StatRow(
                tiles: [
                  StatTile(
                    label: 'EJERCICIOS',
                    value: '${day.slots.length}',
                  ),
                  StatTile(
                    label: 'SETS',
                    value: '${_totalSets(day)}',
                  ),
                  StatTile(
                    label: 'MINUTOS',
                    value: _minutesValue(day),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // ── Periodized: week selector above the day selector ────────────
              if (isPeriodized) ...[
                _WeekSelector(
                  numWeeks: routine.numWeeks,
                  selectedIndex: viewedWeek,
                  onSelect: onSelectWeek,
                ),
                const SizedBox(height: 12),
              ],
              if (routine.days.length > 1) ...[
                _DaySelector(
                  days: routine.days,
                  selectedIndex: selectedDayIndex,
                  onSelect: onSelectDay,
                ),
                const SizedBox(height: 20),
              ],
              const _SectionHeader(text: 'EJERCICIOS'),
              const SizedBox(height: 12),
              if (day.slots.isEmpty)
                const _EmptyState(message: 'No hay ejercicios en este día')
              else
                ..._buildExerciseList(viewedWeek),
              const SizedBox(height: 20),
              // CTA bar — periodized vs single-week
              if (isPeriodized)
                _PeriodizedCTABar(
                  routine: routine,
                  day: day,
                  viewedWeek: viewedWeek,
                )
              else
                _StartSessionCTABar(routine: routine, day: day),
              const SizedBox(height: 18),
            ]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

/// Read-only counterpart of the trainer editor's `_SupersetGroupCard`: a
/// magenta-bordered wrapper around the exercises of one superset block, so the
/// athlete can tell those movements run back-to-back. Inner rows reuse
/// [ExerciseSlotRow] verbatim — same card, same tap target.
class _SupersetBlock extends StatelessWidget {
  const _SupersetBlock({
    required this.items,
    required this.onSlotTap,
    this.viewedWeek = 0,
  });

  final List<({int index, RoutineSlot slot})> items;
  final ValueChanged<RoutineSlot> onSlotTap;

  /// 0-based week for week-aware prescription display (REQ-PERIOD-041).
  final int viewedWeek;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: palette.highlight.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.highlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Row(
              children: [
                Icon(TreinoIcon.streak, size: 14, color: palette.highlight),
                const SizedBox(width: 6),
                Text(
                  'SUPERSERIE',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: palette.highlight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in items) ...[
            ExerciseSlotRow(
              slot: entry.slot,
              index: entry.index + 1,
              week: viewedWeek,
              onTap: () => onSlotTap(entry.slot),
            ),
            if (entry.index != items.last.index) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _HeroStrip extends ConsumerWidget {
  const _HeroStrip({
    required this.routine,
    required this.badgeText,
    required this.titleText,
  });

  final Routine routine;
  final String badgeText;
  final String titleText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    // Trainer-defined plans (assigned to an athlete OR a reusable template
    // visible to the trainer's alumnos) don't carry a photo asset — render
    // a compact header with just badges + title, no image / gradient /
    // scrims. Only the public seeded catalogue has `assets/routines/{id}.png`.
    final isTrainerDefined = routine.source == RoutineSource.trainerAssigned ||
        routine.source == RoutineSource.trainerTemplate;
    if (isTrainerDefined) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 64, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DayChipBadge(text: badgeText),
            if (routine.assignedBy != null) ...[
              const SizedBox(height: 6),
              _AssignedByChip(assignedBy: routine.assignedBy!),
            ],
            const SizedBox(height: 8),
            _DayTitle(text: titleText),
          ],
        ),
      );
    }

    final gradient = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accent.withValues(alpha: 0.85),
            palette.bg,
          ],
        ),
      ),
    );

    return SizedBox(
      height: 320,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Convention: assets/routines/{routine.id}.png. Missing asset →
          // errorBuilder paints the gradient so the screen never breaks.
          Image.asset(
            'assets/routines/${routine.id}.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => gradient,
          ),
          // Top scrim — keeps the floating back button legible on bright photos.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 96,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Bottom scrim — makes the badge + title overlay readable and
          // softens the seam between the photo and the body content.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    palette.bg.withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
          ),
          // Badge + day title overlaid at the bottom-left of the hero.
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DayChipBadge(text: badgeText),
                if (routine.source == RoutineSource.trainerAssigned &&
                    routine.assignedBy != null) ...[
                  const SizedBox(height: 6),
                  _AssignedByChip(assignedBy: routine.assignedBy!),
                ],
                const SizedBox(height: 8),
                _DayTitle(text: titleText),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip "Asignado por <PF>" — visible solo cuando source == trainerAssigned.
/// Reads userPublicProfileProvider to resolve the trainer's display name.
/// REQ-COACH-PLANS-019, SCENARIO-452, SCENARIO-453.
class _AssignedByChip extends ConsumerWidget {
  const _AssignedByChip({required this.assignedBy});

  final String assignedBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(assignedBy));

    final label = profileAsync.when(
      data: (profile) =>
          '${CoachStrings.assignedByPrefix}${profile?.displayName ?? '?'}',
      loading: () => CoachStrings.assignedByLoading,
      error: (_, __) => CoachStrings.assignedByError,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 1.2,
          color: palette.accent,
        ),
      ),
    );
  }
}

class _DayChipBadge extends StatelessWidget {
  const _DayChipBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        text,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 1.4,
          color: palette.accent,
        ),
      ),
    );
  }
}

class _DayTitle extends StatelessWidget {
  const _DayTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      text,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 36,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.tiles});

  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: tiles.map<Widget>((t) => Expanded(child: t)).toList(),
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.days,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<RoutineDay> days;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(days.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                'DÍA ${days[i].dayNumber}',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: i == selectedIndex ? palette.bg : palette.textMuted,
                ),
              ),
              selected: i == selectedIndex,
              onSelected: (_) => onSelect(i),
              selectedColor: palette.accent,
              backgroundColor: palette.bgCard,
              side: BorderSide(color: palette.border),
              showCheckmark: false,
            ),
          );
        }),
      ),
    );
  }
}

/// Week selector chips for periodized plans. Displays "SEM N" (1-based) for
/// each week. Viewing any week is always free (REQ-PERIOD-035).
class _WeekSelector extends StatelessWidget {
  const _WeekSelector({
    required this.numWeeks,
    required this.selectedIndex,
    required this.onSelect,
  });

  final int numWeeks;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(numWeeks, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                'SEM ${i + 1}',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: i == selectedIndex ? palette.bg : palette.textMuted,
                ),
              ),
              selected: i == selectedIndex,
              onSelected: (_) => onSelect(i),
              selectedColor: palette.accent,
              backgroundColor: palette.bgCard,
              side: BorderSide(color: palette.border),
              showCheckmark: false,
            ),
          );
        }),
      ),
    );
  }
}

/// Start CTA for periodized plans (numWeeks > 1). Reads [planProgressProvider]
/// to determine the active (week, day) and to show gating affordances for the
/// currently viewed (week, day) combination.
///
/// REQ-PERIOD-033/034/035/036/037/042.
class _PeriodizedCTABar extends ConsumerWidget {
  const _PeriodizedCTABar({
    required this.routine,
    required this.day,
    required this.viewedWeek,
  });

  final Routine routine;
  final RoutineDay day;

  /// 0-based week currently displayed by the parent screen.
  final int viewedWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Trainers coach — read-only view.
    final role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );
    if (role == UserRole.trainer) return const SizedBox.shrink();

    final uid = ref.watch(currentUidProvider) ?? '';
    // dayNumbers is kept locally for gating function calls below.
    // planProgressProvider resolves dayNumbers/numWeeks internally via
    // routineByIdProvider — key uses only String fields for structural equality.
    final dayNumbers =
        routine.days.map((d) => d.dayNumber).toList(growable: false);
    final progressAsync = ref.watch(planProgressProvider((
      uid: uid,
      routineId: routine.id,
    )));

    return progressAsync.when(
      loading: () => const SizedBox(height: 56),
      error: (_, __) => const SizedBox.shrink(),
      data: (progress) {
        final palette = AppPalette.of(context);

        // Plan-complete banner (REQ-PERIOD-037, SCENARIO-036).
        if (progress.planComplete) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.accent),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(TreinoIcon.check, size: 20, color: palette.accent),
                  const SizedBox(width: 10),
                  Text(
                    'PLAN COMPLETADO',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 1.2,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final viewedDay = day.dayNumber;
        final startable = isStartable(
          viewedWeek,
          viewedDay,
          progress.completed,
          dayNumbers,
        );
        final weekLocked = !isWeekUnlocked(
          viewedWeek,
          progress.completed,
          dayNumbers,
        );
        final dayLocked = !isDayUnlocked(
          viewedWeek,
          viewedDay,
          progress.completed,
          dayNumbers,
        );
        final alreadyDone =
            progress.completed.contains((week: viewedWeek, day: viewedDay));

        // Already completed this (week, day).
        if (alreadyDone) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.bgCard,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(TreinoIcon.check, size: 16, color: palette.accent),
                  const SizedBox(width: 8),
                  Text(
                    'COMPLETADO',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 1.2,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Locked (week or day not yet unlocked).
        if (weekLocked || dayLocked) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.bgCard,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(TreinoIcon.lock, size: 16, color: palette.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    weekLocked ? 'SEMANA BLOQUEADA' : 'DÍA BLOQUEADO',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 1.2,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Startable — show active CTA with the correct week.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: startable
                      ? () {
                          ref.read(analyticsServiceProvider).logRoutineStarted(
                                routineId: routine.id,
                                routineName: routine.name,
                              );
                          context.push(
                            '/workout/session/${routine.id}/${day.dayNumber}?week=$viewedWeek',
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    'EMPEZAR',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 1.0,
                      color: palette.bg,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      text,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        letterSpacing: 1.4,
        color: palette.textPrimary,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      message,
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        color: palette.textMuted,
      ),
    );
  }
}

class _StartSessionCTABar extends ConsumerWidget {
  const _StartSessionCTABar({required this.routine, required this.day});

  final Routine routine;
  final RoutineDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Trainers coach — they don't train in-app. Hide "EMPEZAR" for them so the
    // plan view is read-only; athletes still get the start CTA.
    final role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );
    if (role == UserRole.trainer) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                ref.read(analyticsServiceProvider).logRoutineStarted(
                      routineId: routine.id,
                      routineName: routine.name,
                    );
                context.push(
                  '/workout/session/${routine.id}/${day.dayNumber}',
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: Text(
                'EMPEZAR',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 1.0,
                  color: palette.bg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotFoundState extends StatelessWidget {
  const _NotFoundState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: palette.textPrimary,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Reintentar',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: palette.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineLoadingSkeleton extends StatelessWidget {
  const _RoutineLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 320,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.accent.withValues(alpha: 0.3),
                  palette.bg,
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 12, width: 100, color: palette.bgCard),
                const SizedBox(height: 8),
                Container(height: 36, width: 180, color: palette.bgCard),
                const SizedBox(height: 14),
                Row(
                  children: List.generate(
                    3,
                    (_) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(height: 40, color: palette.bgCard),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ...List.generate(
                  4,
                  (_) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      height: 76,
                      decoration: BoxDecoration(
                        color: palette.bgCard,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
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
