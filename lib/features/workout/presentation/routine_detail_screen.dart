import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/motion/treino_shimmer.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart' show userProfileProvider;
import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/domain/user_role.dart';
import '../application/routine_providers.dart';
import '../application/session_providers.dart'
    show currentUidProvider, lastWeightByExerciseProvider, planProgressProvider;
import '../domain/routine.dart';
import '../domain/routine_day.dart';
import '../domain/routine_day_duration.dart';
import '../domain/routine_slot.dart';
import '../domain/routine_source.dart';
import '../domain/routine_visibility.dart';
import 'widgets/exercise_slot_row.dart';
import 'widgets/stat_tile.dart';
import 'widgets/template_ratings_section.dart';

/// RoutineDetailScreen — ConsumerStatefulWidget that observes routineByIdStreamProvider.
/// selectedDayIndex is local state (ADR-RD-3).
/// No Scaffold, AppBackground, or SafeArea — provided by _ShellScaffold (REQ-RDT-011).
class RoutineDetailScreen extends ConsumerStatefulWidget {
  const RoutineDetailScreen({
    super.key,
    required this.routineId,
    this.initialDayNumber,
    this.initialWeekIndex,
    this.coachAthleteId,
  });

  final String routineId;

  /// Non-null ONLY when this screen is shown in the coach (PF) read-only
  /// context, reached from the TOP-LEVEL route
  /// `/coach/athlete/:athleteId/plan/:routineId` (OUTSIDE the ShellRoute).
  /// It carries the athlete's uid and switches two behaviours that would
  /// otherwise assume the athlete's in-shell placement (issue #410):
  ///  1. Tapping an exercise pushes the top-level (out-of-shell) exercise
  ///     mirror instead of the in-shell `/workout/exercise/:id` — pushing the
  ///     in-shell route from here rebuilds the shell branch and lands blank
  ///     (the root cause #399's symptom fix left open).
  ///  2. The back fallback lands on `/coach/athlete/:id` instead of the
  ///     athlete's `/workout` tab.
  /// Null for the athlete's own in-shell usage → behaviour unchanged.
  final String? coachAthleteId;

  /// 1-based RoutineDay.dayNumber to pre-select on first render. Out-of-range
  /// values are clamped to the valid day range by the build method's
  /// `selectedDayIndex.clamp(...)` so callers can pass any int safely.
  /// Used by the home `EmpezarEntrenamientoCard` to deep-link to today's day.
  final int? initialDayNumber;

  /// 0-based week index to pre-select on first render. Same clamping
  /// guarantees as [initialDayNumber].
  final int? initialWeekIndex;

  @override
  ConsumerState<RoutineDetailScreen> createState() =>
      _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends ConsumerState<RoutineDetailScreen> {
  late int selectedDayIndex;

  /// 0-based selected week index. Only used when routine.numWeeks > 1.
  late int selectedWeekIndex;

  @override
  void initState() {
    super.initState();
    // initialDayNumber is 1-based on the wire (matches RoutineDay.dayNumber);
    // local state is 0-based. The build method's clamp() guards against
    // out-of-range values once the routine resolves.
    selectedDayIndex =
        widget.initialDayNumber != null ? widget.initialDayNumber! - 1 : 0;
    selectedWeekIndex = widget.initialWeekIndex ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final routineAsync = ref.watch(routineByIdStreamProvider(widget.routineId));

    // Stack so the hero image can extend edge-to-edge from the top of the
    // safe area while the back button floats over it. Non-data states still
    // render the back button on top so the user can always escape.
    return Stack(
      children: [
        Positioned.fill(
          child: TreinoStateSwitcher(
            childKey: ValueKey(
              routineAsync.when(
                data: (routine) {
                  if (routine == null) return 'not-found';
                  if (routine.days.isEmpty) return 'empty';
                  return 'data';
                },
                loading: () => 'loading',
                error: (_, __) => 'error',
              ),
            ),
            child: routineAsync.when(
              data: (routine) {
                if (routine == null) {
                  return _NotFoundState(
                    label: AppL10n.of(context).routineDetailNotFound,
                  );
                }
                // `clamp(0, length - 1)` throws when length == 0 — empty-check
                // BEFORE clamping.
                if (routine.days.isEmpty) {
                  return _EmptyState(
                    message: AppL10n.of(context).routineDetailNoDaysConfigured,
                  );
                }
                final dayIndex = selectedDayIndex.clamp(
                  0,
                  routine.days.length - 1,
                );
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
                    // In the coach read-only context this screen is OUTSIDE the
                    // shell, so the exercise detail must be pushed on the
                    // top-level (out-of-shell) mirror — pushing the in-shell
                    // `/workout/exercise/:id` from here rebuilds the shell branch
                    // and lands blank (issue #410 Bug 1).
                    final base = widget.coachAthleteId != null
                        ? '/coach/athlete/${widget.coachAthleteId}'
                            '/plan/${widget.routineId}'
                            '/exercise/${slot.exerciseId}'
                        : '/workout/exercise/${slot.exerciseId}';
                    final target = ownerId != null && ownerId.isNotEmpty
                        ? '$base?ownerId=$ownerId&$nameParam'
                        : '$base?$nameParam';
                    context.push(target);
                  },
                );
              },
              loading: () => const _RoutineLoadingSkeleton(),
              error: (_, __) => _ErrorState(
                message: AppL10n.of(context).routineDetailLoadError,
                onRetry: () =>
                    ref.invalidate(routineByIdStreamProvider(widget.routineId)),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          child: _BackBar(
            fallbackRoute: widget.coachAthleteId != null
                ? '/coach/athlete/${widget.coachAthleteId}'
                : '/workout',
          ),
        ),
        // Edit affordance only for the owner of a user-created routine —
        // trainer-assigned plans and system templates render read-only.
        // Sits opposite the back button, same chip treatment for parity.
        Positioned(
          top: 0,
          right: 0,
          child: _EditBar(routineAsync: routineAsync),
        ),
      ],
    );
  }
}

/// Persistent top-left back button. Always visible so the user can never
/// dead-end on a deep-linked screen — even in loading, error, or not-found
/// states (REQ-RDT-016 strengthened). Now floats over the hero image with a
/// translucent chip so it stays legible on bright photos.
class _BackBar extends StatelessWidget {
  const _BackBar({required this.fallbackRoute});

  /// Where to land when there is nothing to pop (deep-link / OS state
  /// restoration). The athlete's own usage passes `/workout`; the coach
  /// read-only context passes `/coach/athlete/:id` so the PF doesn't get
  /// dumped on the athlete's Entrenar tab (issue #410 Bug 2).
  final String fallbackRoute;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8),
      child: Material(
        color: palette.scrimDark.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label: l10n.commonBack,
          child: IconButton(
            tooltip: l10n.commonBack,
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(fallbackRoute),
          ),
        ),
      ),
    );
  }
}

/// Top-right edit affordance. Renders ONLY when the current viewer is the
/// owner of a user-created routine — trainer-assigned plans, trainer
/// templates, and system routines stay read-only from the detail screen.
///
/// Tap navigates to `/workout/my-routine-editor` with the routine id as
/// extra, which reuses the SelfCreating edit path (`RoutineEditorScreen`
/// hydrates from Firestore). The editor is where the "Compartir en mi
/// perfil" toggle lives (routine visibility). Isolating the mutation
/// surface to the editor avoids duplicating the toggle in two places
/// (detail vs editor) that would then need to stay in sync.
class _EditBar extends ConsumerWidget {
  const _EditBar({required this.routineAsync});

  final AsyncValue<Routine?> routineAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = routineAsync.valueOrNull;
    if (routine == null) return const SizedBox.shrink();
    if (routine.source != RoutineSource.userCreated) {
      return const SizedBox.shrink();
    }
    final currentUid = ref.watch(currentUidProvider);
    if (currentUid == null || currentUid != routine.createdBy) {
      return const SizedBox.shrink();
    }

    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 12, top: 8),
      child: Material(
        color: palette.scrimDark.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Semantics(
          button: true,
          label: 'Editar rutina', // i18n: Fase W2
          child: IconButton(
            tooltip: 'Editar rutina', // i18n: Fase W2
            icon: Icon(Icons.edit, color: palette.textPrimary),
            onPressed: () =>
                context.push('/workout/my-routine-editor', extra: routine.id),
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
    final est = estimateRoutineDayMinutes(d, week: week);
    if (est.minutes == null) return '—';
    return est.authored ? '${est.minutes}' : '~${est.minutes}';
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
              if (s.isPresentInWeek(viewedWeek)) s,
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
          widgets.add(
            _SupersetBlock(
              items: items,
              onSlotTap: onSlotTap,
              viewedWeek: viewedWeek,
            ),
          );
          widgets.add(const SizedBox(height: 12));
          i = scan;
          continue;
        }
      }
      final slot = slots[i];
      widgets.add(
        _SlotRowWithLastWeight(
          slot: slot,
          index: i + 1,
          week: viewedWeek,
          onTap: () => onSlotTap(slot),
        ),
      );
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
    final exerciseWidgets = _buildExerciseList(
      viewedWeek,
      isPeriodized: isPeriodized,
    );
    if (isPeriodized && exerciseWidgets.isEmpty) {
      // All slots absent for this week → informational message (not a lock).
      return [_EmptyState(message: emptyWeekMessage)];
    }
    return exerciseWidgets;
  }

  /// Whether the start/repeat ACTION renders for the current viewer.
  ///
  /// Single source of truth. The action now lives OUTSIDE the scroll (#641),
  /// so the parent has to know up front whether to give it a slot in the
  /// [Column] at all — otherwise a read-only viewer gets an empty strip of
  /// chrome stealing height from the exercise list. Deciding it here, instead
  /// of letting each action widget return `SizedBox.shrink()` on its own, is
  /// what keeps the reserved space and the bar from ever disagreeing.
  ///
  /// The `userCreated` guard applies at EVERY plan length. It used to be gated
  /// behind `!isPeriodized`, inherited verbatim from the pre-#641 split where
  /// `_StartSessionCTABar` carried the check and `_PeriodizedCTABar` simply
  /// never had it. Nothing justified the asymmetry: a plan reaches the
  /// "RUTINAS PÚBLICAS" tab through `publicRoutinesByUserProvider`, which
  /// filters on `visibility` alone and has never looked at `numWeeks`, and the
  /// editor lets an athlete author >1 week AND share on profile at once. So the
  /// periodized case was not merely reachable — it was the LESS protected of
  /// the two, which is backwards: `planProgressProvider` is keyed
  /// `(uid: viewer, routineId: theirs)`, so a periodized start pollutes the
  /// viewer's plan progress on top of their session history.
  bool _startActionVisible(WidgetRef ref) {
    // Trainers coach — they don't train in-app, so the plan view is read-only.
    final role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );
    if (role == UserRole.trainer) return false;

    // Read-only view of someone else's public user-created routine (surfaced
    // from the "RUTINAS PÚBLICAS" tab of another user's public profile).
    // Starting it would log a session under the VIEWER's uid against a routine
    // they neither own nor can edit — history and plan progress accruing
    // against a plan whose author can rewrite or unshare it at any time.
    // Trainer templates are the legitimately public-and-startable kind and stay
    // untouched: this only ever fires on `userCreated`.
    if (routine.source == RoutineSource.userCreated) {
      final currentUid = ref.watch(currentUidProvider);
      if (currentUid != null && currentUid != routine.createdBy) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REQ-PERIOD-042 HARD INVARIANT: when numWeeks == 1, render the
    // single-week path untouched — no week selector, no locks, all days free.
    final isPeriodized = routine.numWeeks > 1;

    // For single-week plans the viewed week is always 0.
    final viewedWeek = isPeriodized ? selectedWeekIndex : 0;

    final l10n = AppL10n.of(context);

    final showStartAction = _startActionVisible(ref);

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
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
                  20,
                  0,
                  20,
                  // With the action pinned below, the Column already reserves
                  // the bottom chrome — inseting the scroll on top of it would
                  // double-count. Without it (read-only viewer, no bar) the
                  // scroll still has to clear the shell's floating nav bar
                  // itself.
                  showStartAction ? 0 : MediaQuery.paddingOf(context).bottom,
                ),
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
                    // ── Periodized: week selector above the day selector ────
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
                      _EmptyState(
                        message: l10n.routineDetailNoExercisesThisDay,
                      )
                    else
                      // REQ-WPRES-020: filter by presence when periodized.
                      // REQ-WPRES-028: zero present slots → show info message.
                      ..._buildPresenceFilteredSection(
                        viewedWeek,
                        isPeriodized,
                        emptyWeekMessage: l10n.routineDetailNoExercisesThisWeek,
                      ),
                    // Completion SIGNAL stays with the content while the
                    // ACTION is pinned below (#641). That split is what the
                    // periodized contract already asked for: completion only
                    // ever changes the signal and the action's LABEL, never
                    // the action's availability (AD-1/AD-2). Pinning the
                    // banner too would nail ~56px of terminal-state chrome to
                    // the bottom of a screen whose whole problem was vertical
                    // budget.
                    if (isPeriodized) ...[
                      const SizedBox(height: 20),
                      _PeriodizedCompletionSignal(
                        routine: routine,
                        day: day,
                        viewedWeek: viewedWeek,
                      ),
                    ],
                    // Community reputation — published trainer templates only.
                    // It sits at the end on purpose: whoever opened the
                    // template came to train, and the ratings are what they
                    // check before (or after) deciding.
                    if (routine.source == RoutineSource.trainerTemplate &&
                        routine.visibility == RoutineVisibility.public) ...[
                      const SizedBox(height: 20),
                      TemplateRatingsSection(routine: routine),
                    ],
                    const SizedBox(height: 18),
                  ]),
                ),
              ),
            ],
          ),
        ),
        // ── Pinned start action (#641) ──────────────────────────────────────
        // 5/5 usability participants failed to reach EMPEZAR while it lived at
        // the end of the exercise list, below a 320px hero and every slot of
        // the day. It is the ONLY action of this screen, so reaching it must
        // never depend on scrolling.
        //
        // Column + Expanded (not Stack + Positioned) on purpose: the scroll
        // viewport ends exactly where the bar begins, so the bar occupies
        // whatever the button naturally measures — including at large text
        // scale, where it grows. A Stack would need that height hardcoded or
        // measured over an extra frame, and either one silently clips the last
        // exercise as soon as the user bumps their font size. Same shape
        // AthleteDetailScreen already uses for its bottom actions.
        if (showStartAction)
          Padding(
            // Bottom inset: in-shell, Scaffold publishes the floating nav
            // bar's height through MediaQuery.padding.bottom (see
            // `_ShellScaffold`, `extendBody: true`), so this lifts the action
            // clear of it. In the out-of-shell coach context (#399/#410)
            // `_immersive`'s SafeArea already consumed that padding and the
            // same expression resolves to 0 — correct in BOTH mounts without
            // branching on which one we are in.
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            child: isPeriodized
                ? _PeriodizedStartAction(
                    routine: routine,
                    day: day,
                    viewedWeek: viewedWeek,
                  )
                : _StartSessionAction(routine: routine, day: day),
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
String _formatWeight(double kg) => '${formatWeightKg(kg)} kg';

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
          colors: [palette.accent.withValues(alpha: 0.85), palette.bg],
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
                    palette.scrimDark.withValues(alpha: 0.45),
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
      // A missing/blank profile is the same story as a failed read — we know a
      // PF assigned the plan, we just can't name them. Fall back to the generic
      // copy instead of rendering "Asignado por ?", which reads as a glitch.
      data: (profile) {
        final name = profile?.displayName;
        return (name == null || name.trim().isEmpty)
            ? l10n.coachAssignedByError
            : '${l10n.coachAssignedByPrefix}$name';
      },
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
    return Row(children: tiles.map<Widget>((t) => Expanded(child: t)).toList());
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

/// Completion SIGNAL for periodized plans (numWeeks > 1) — banner XOR chip,
/// at most one. Purely informational: it never gates, disables or hides the
/// action, which lives pinned at the bottom of the screen since #641
/// (periodized-plan-repeat, AD-1/AD-2).
///
/// Split out of the old `_PeriodizedCTABar` when the action was pinned. The
/// signal belongs WITH the content it describes; nailing a ~56px terminal-state
/// banner to the bottom chrome would eat the vertical budget that #641 exists
/// to recover. The contract is unchanged: completion only ever changes this
/// signal and the action's LABEL.
///
/// A failed progress fetch renders nothing here and, crucially, does not touch
/// the action (#497).
class _PeriodizedCompletionSignal extends ConsumerWidget {
  const _PeriodizedCompletionSignal({
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
    final progress = ref
        .watch(planProgressProvider((uid: uid, routineId: routine.id)))
        .valueOrNull;

    // null == progress unknown (still loading, or the fetch failed). No
    // signal — never a placeholder. Unlike the old inline version there is
    // nothing to reserve height for here: this widget sits in the scroll, so
    // it can appear when progress lands without shifting the action, which
    // now has its own fixed slot in the Column.
    if (progress == null) return const SizedBox.shrink();

    // Plan-scoped wins over day-scoped (banner XOR chip): "PLAN COMPLETADO"
    // stacked above "COMPLETADO" would say the same fact twice.
    if (progress.planComplete) return const _PlanCompleteBanner();
    if (progress.completed.contains((week: viewedWeek, day: day.dayNumber))) {
      return const _CompletedDayChip();
    }
    return const SizedBox.shrink();
  }
}

/// Pinned start/repeat ACTION for periodized plans (numWeeks > 1).
///
/// Unconditional by contract. Neither a completion state (AD-2) nor a failed
/// progress fetch (#497) removes, disables or hides it — plan progress only
/// decides the LABEL. Starting a workout needs the routine and the day the
/// parent already resolved, nothing else.
///
/// The earlier design let `error` return `SizedBox.shrink()` on the assumption
/// the failure was transient — it was not: [routineByIdProvider] cached the
/// AsyncError for the container's lifetime, so the screen's only control
/// vanished until the app restarted. Unknown progress degrades to "label
/// EMPEZAR", never to "no way to train".
///
/// "Unconditional" is scoped to PROGRESS, not to the viewer. Who may see this
/// at all — trainer role, or someone else's public user-created plan — is
/// decided by the parent (`_RoutineDetailContent._startActionVisible`) so the
/// pinned slot and its occupant can never disagree. Reading this widget alone
/// and concluding "always rendered" is precisely the mistake that let the
/// ownership guard skip periodized plans for as long as it did.
class _PeriodizedStartAction extends ConsumerWidget {
  const _PeriodizedStartAction({
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
    final uid = ref.watch(currentUidProvider) ?? '';
    final progress = ref
        .watch(planProgressProvider((uid: uid, routineId: routine.id)))
        .valueOrNull;

    // Startable or repeatable, the route composed is identical
    // (SCENARIO-REPEAT-004); only the label changes (AD-5). Unknown progress
    // falls back to EMPEZAR, never REPETIR.
    final isRepeat = progress != null &&
        progress.completed.contains((week: viewedWeek, day: day.dayNumber));

    return _StartActionButton(
      label: isRepeat
          ? AppL10n.of(context).routineDetailRepeat
          : AppL10n.of(context).routineDetailStart,
      onPressed: () {
        ref.read(analyticsServiceProvider).logRoutineStarted(
              routineId: routine.id,
              routineName: routine.name,
            );
        context.push(
          '/workout/session/${routine.id}/${day.dayNumber}?week=$viewedWeek',
        );
      },
    );
  }
}

/// The accent pill both start actions render. Extracted so the single-week and
/// periodized paths cannot drift in height — the pinned bar's footprint is
/// whatever this measures, and the scroll above it is sized by the Column from
/// exactly that.
class _StartActionButton extends StatelessWidget {
  const _StartActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 1.0,
            color: palette.bg,
          ),
        ),
      ),
    );
  }
}

/// Informational banner shown when every required (week, day) in the plan is
/// complete. Purely a SIGNAL — never withholds the action below it (AD-1/AD-2).
class _PlanCompleteBanner extends StatelessWidget {
  const _PlanCompleteBanner();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
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
            AppL10n.of(context).routineDetailPlanComplete,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: 1.2,
              color: palette.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip shown when the viewed (week, day) is already completed but the plan
/// as a whole is not. Purely a SIGNAL — never withholds the action below it
/// (AD-1/AD-2).
class _CompletedDayChip extends StatelessWidget {
  const _CompletedDayChip();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
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
            AppL10n.of(context).routineDetailCompleted,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 1.2,
              color: palette.accent,
            ),
          ),
        ],
      ),
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

/// Pinned start ACTION for single-week routines (numWeeks == 1).
///
/// Visibility for the current viewer — trainer role, or someone else's public
/// user-created routine — is decided by the parent
/// (`_RoutineDetailContent._startActionVisible`) rather than here, so the
/// pinned slot in the Column and its occupant can never disagree: a guard that
/// lived in this widget would shrink the button to nothing while the parent
/// still reserved the bar's height (#641).
class _StartSessionAction extends ConsumerWidget {
  const _StartSessionAction({required this.routine, required this.day});

  final Routine routine;
  final RoutineDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StartActionButton(
      label: AppL10n.of(context).routineDetailStart,
      onPressed: () {
        ref.read(analyticsServiceProvider).logRoutineStarted(
              routineId: routine.id,
              routineName: routine.name,
            );
        context.push('/workout/session/${routine.id}/${day.dayNumber}');
      },
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
    return TreinoShimmer(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 320,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.accent.withValues(alpha: 0.3), palette.bg],
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
      ),
    );
  }
}
