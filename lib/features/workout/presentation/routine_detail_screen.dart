import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart' show userProfileProvider;
import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/domain/user_role.dart';
import '../application/plan_gating.dart';
import '../application/plan_progress.dart' show CompletedKey;
import '../application/routine_providers.dart';
import '../application/session_providers.dart'
    show currentUidProvider, lastWeightByExerciseProvider, planProgressProvider;
import '../domain/routine.dart';
import '../domain/routine_day.dart';
import '../domain/routine_slot.dart';
import '../domain/routine_source.dart';
import 'widgets/exercise_slot_row.dart';
import 'widgets/stat_tile.dart';

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
                return _NotFoundState(
                    label: AppL10n.of(context).routineDetailNotFound);
              }
              // `clamp(0, length - 1)` throws when length == 0 — empty-check
              // BEFORE clamping.
              if (routine.days.isEmpty) {
                return _EmptyState(
                    message:
                        AppL10n.of(context).routineDetailNoDaysConfigured);
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
                  // `name` is the slot's display name, carried through so
                  // slotExerciseProvider can do a name/alias fallback when
                  // `exerciseId` drifted from the catalogue.
                  final nameParam =
                      'name=${Uri.encodeQueryComponent(slot.exerciseName)}';
                  final target = ownerId != null && ownerId.isNotEmpty
                      ? '/workout/exercise/${slot.exerciseId}?ownerId=$ownerId&$nameParam'
                      : '/workout/exercise/${slot.exerciseId}?$nameParam';
                  context.push(target);
                },
              );
            },
            loading: () => const _RoutineLoadingSkeleton(),
            error: (_, __) => _ErrorState(
              message: AppL10n.of(context).routineDetailLoadError,
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
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8),
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label: l10n.commonBack,
          child: IconButton(
            tooltip: l10n.commonBack,
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/workout'),
          ),
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

  /// Authored estimate when present; otherwise a rough computed one so the
  /// stat isn't a dead "—" for athlete/trainer routines (device feedback
  /// 2026-06-11). Per set: work time (duration as-is, or ~3s/rep for rep
  /// sets) + the slot's rest. Prefixed "~" to read as an estimate.
  String _minutesValue(RoutineDay d, int week) {
    if (d.estimatedMinutes != null) return '${d.estimatedMinutes}';
    var seconds = 0;
    for (final slot in d.slots) {
      if (!slot.isPresentInWeek(week)) continue;
      for (final s in slot.effectiveSetsForWeek(week)) {
        final work = (s.durationSeconds != null && s.durationSeconds! > 0)
            ? s.durationSeconds!
            : (s.reps ?? s.repsMax ?? s.repsMin ?? 12) * 3;
        seconds += work + slot.restSeconds;
      }
    }
    if (seconds <= 0) return '—';
    return '~${(seconds / 60).round()}';
  }

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
  ///
  /// When [isPeriodized] is true, slots are pre-filtered by
  /// `isPresentInWeek(viewedWeek)` before grouping (ADR-WPRES-07, REQ-WPRES-020).
  /// Absent superset members are naturally excluded; a group reduced to 1 member
  /// falls back to a standalone ExerciseSlotRow (existing run-length < 2 path).
  List<Widget> _buildExerciseList(int viewedWeek, {bool isPeriodized = false}) {
    // REQ-WPRES-020: filter by presence when numWeeks > 1.
    // REQ-WPRES-015: numWeeks==1 → isPeriodized is false → no filter applied.
    final slots = isPeriodized
        ? [
            for (final s in day.slots)
              if (s.isPresentInWeek(viewedWeek)) s
          ]
        : day.slots;

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
      widgets.add(_SlotRowWithLastWeight(
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

  /// Returns the exercise list widgets, or an informational "no exercises this
  /// week" message when all slots are filtered out by presence.
  ///
  /// REQ-WPRES-028: zero present slots in [viewedWeek] → show info, not a lock.
  /// REQ-WPRES-015: [isPeriodized] is false for single-week plans → no filter.
  List<Widget> _buildPresenceFilteredSection(
    int viewedWeek,
    bool isPeriodized, {
    required String emptyWeekMessage,
  }) {
    // Build the list (filtering applied inside _buildExerciseList when needed).
    final exerciseWidgets =
        _buildExerciseList(viewedWeek, isPeriodized: isPeriodized);
    if (isPeriodized && exerciseWidgets.isEmpty) {
      // All slots absent for this week → informational message (not a lock).
      return [_EmptyState(message: emptyWeekMessage)];
    }
    return exerciseWidgets;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REQ-PERIOD-042 HARD INVARIANT: when numWeeks == 1, render the
    // single-week path untouched — no week selector, no locks, all days free.
    final isPeriodized = routine.numWeeks > 1;

    // For single-week plans the viewed week is always 0.
    final viewedWeek = isPeriodized ? selectedWeekIndex : 0;

    final l10n = AppL10n.of(context);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HeroStrip(
            routine: routine,
            badgeText:
                '${(routine.split ?? l10n.workoutSplitFallback).toUpperCase()} · ${l10n.routineDetailDayLabel(day.dayNumber)}',
            titleText: day.name.toUpperCase(),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, MediaQuery.paddingOf(context).bottom),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 20),
              _StatRow(
                tiles: [
                  StatTile(
                    label: l10n.routineDetailStatExercises,
                    value: '${day.slots.length}',
                  ),
                  StatTile(
                    label: l10n.routineDetailStatSets,
                    value: '${_totalSets(day)}',
                  ),
                  StatTile(
                    label: l10n.routineDetailStatMinutes,
                    value: _minutesValue(day, selectedWeekIndex),
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
              _SectionHeader(text: l10n.routineDetailStatExercises),
              const SizedBox(height: 12),
              if (day.slots.isEmpty)
                _EmptyState(message: l10n.routineDetailNoExercisesThisDay)
              else
                // REQ-WPRES-020: filter by presence when periodized.
                // REQ-WPRES-028: zero present slots → show info message.
                ..._buildPresenceFilteredSection(
                  viewedWeek,
                  isPeriodized,
                  emptyWeekMessage: l10n.routineDetailNoExercisesThisWeek,
                ),
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
                  AppL10n.of(context).routineDetailSuperset,
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
            _SlotRowWithLastWeight(
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

/// Wraps [ExerciseSlotRow] to resolve the athlete's last logged weight for the
/// slot's exercise (badge "ÚLTIMO"). Kept separate so ExerciseSlotRow stays a
/// pure StatelessWidget. Reads the shared [lastWeightByExerciseProvider] —
/// cached per uid, so every row shares a single computation.
class _SlotRowWithLastWeight extends ConsumerWidget {
  const _SlotRowWithLastWeight({
    required this.slot,
    required this.index,
    required this.week,
    required this.onTap,
  });

  final RoutineSlot slot;
  final int index;
  final int week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider) ?? '';
    final kg = ref
        .watch(lastWeightByExerciseProvider(uid))
        .valueOrNull?[slot.exerciseId];
    return ExerciseSlotRow(
      slot: slot,
      index: index,
      week: week,
      onTap: onTap,
      // 0 kg (movilidad / peso corporal) se muestra como "—": no aporta.
      lastWeightDisplay: (kg == null || kg == 0) ? null : _formatWeight(kg),
    );
  }
}

/// "15 kg" para enteros, "17.5 kg" para fraccionarios.
String _formatWeight(double kg) {
  final text = kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toString();
  return '$text kg';
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

    // Only the public seeded catalogue ships a photo asset
    // (`assets/routines/{id}.png`). Trainer-defined plans AND athlete-created
    // routines have none — render a compact header (badges + title, no image
    // / 320px gradient / scrims) instead of the green gradient block the
    // missing-asset errorBuilder used to paint (device feedback 2026-06-11).
    final hasHeroPhoto = routine.source == RoutineSource.system;
    if (!hasHeroPhoto) {
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
    final l10n = AppL10n.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(assignedBy));

    final label = profileAsync.when(
      data: (profile) =>
          '${l10n.coachAssignedByPrefix}${profile?.displayName ?? '?'}',
      loading: () => l10n.coachAssignedByLoading,
      error: (_, __) => l10n.coachAssignedByError,
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
    final l10n = AppL10n.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(days.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                l10n.routineDetailDayLabel(days[i].dayNumber),
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
    final l10n = AppL10n.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(numWeeks, (i) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                l10n.routineDetailWeekLabel(i + 1),
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
        final l10n = AppL10n.of(context);

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
                    l10n.routineDetailPlanComplete,
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

        // REQ-WPRES-022: compute requiredPairs so gating functions know which
        // (week, day) combos have zero present slots (auto-satisfied).
        // Mirrors planProgressProvider's requiredPairs computation so gating
        // here stays consistent with the progress derivation.
        final requiredPairs = <CompletedKey>{};
        for (var w = 0; w < routine.numWeeks; w++) {
          for (final d in routine.days) {
            final hasPresent = d.slots.any((s) => s.isPresentInWeek(w));
            if (hasPresent) {
              requiredPairs.add((week: w, day: d.dayNumber));
            }
          }
        }

        final viewedDay = day.dayNumber;
        final weekLocked = !isWeekUnlocked(
          viewedWeek,
          progress.completed,
          dayNumbers,
          requiredPairs: requiredPairs,
        );
        final dayLocked = !isDayUnlocked(
          viewedWeek,
          viewedDay,
          progress.completed,
          dayNumbers,
          requiredPairs: requiredPairs,
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
                    l10n.routineDetailCompleted,
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
                    weekLocked
                        ? l10n.routineDetailWeekLocked
                        : l10n.routineDetailDayLocked,
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
                  // By this point alreadyDone, weekLocked, and dayLocked have
                  // all early-returned above, so this day is always startable.
                  onPressed: () {
                    ref.read(analyticsServiceProvider).logRoutineStarted(
                          routineId: routine.id,
                          routineName: routine.name,
                        );
                    context.push(
                      '/workout/session/${routine.id}/${day.dayNumber}?week=$viewedWeek',
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
                    l10n.routineDetailStart,
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
    final l10n = AppL10n.of(context);
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
                l10n.routineDetailStart,
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
              AppL10n.of(context).workoutButtonRetry,
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
