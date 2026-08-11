import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/exercise_feedback_providers.dart'
    show coachSessionFeedbackProvider;
import '../application/session_providers.dart';
import '../domain/exercise_feedback.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';
import 'utils/date_helpers.dart';
import 'widgets/session_exercise_block.dart';
import 'widgets/session_stats_card.dart';
import 'widgets/stat_tile.dart';
import '../../../l10n/app_l10n.dart';

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider) ?? '';
    final summaryAsync = ref.watch(
      sessionSummaryProvider((uid: uid, sessionId: sessionId)),
    );

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: TreinoStateSwitcher(
            childKey: ValueKey(summaryAsync.when(
              loading: () => 'loading',
              error: (_, __) => 'error',
              data: (data) => data.session == null ? 'notfound' : 'data',
            )),
            child: summaryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _DetailError(
                onRetry: () => ref.invalidate(
                  sessionSummaryProvider((uid: uid, sessionId: sessionId)),
                ),
              ),
              data: (data) {
                final session = data.session;
                if (session == null) {
                  return const _DetailNotFound();
                }
                return _DetailLoaded(
                  session: session,
                  setLogs: data.setLogs,
                  feedback: ref
                          .watch(coachSessionFeedbackProvider(
                              (athleteUid: uid, sessionId: sessionId)))
                          .valueOrNull ??
                      const <ExerciseFeedback>[],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Loaded body ───────────────────────────────────────────────────────────────

class _DetailLoaded extends StatelessWidget {
  const _DetailLoaded({
    required this.session,
    required this.setLogs,
    this.feedback = const <ExerciseFeedback>[],
  });

  final Session session;
  final List<SetLog> setLogs;

  /// The athlete's own per-exercise feedback for this session (issue #628),
  /// shown back to them so a report they left mid-session is not write-only.
  final List<ExerciseFeedback> feedback;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Group setLogs by exerciseName preserving first-appearance order.
    // Map literal {} creates a LinkedHashMap in Dart — insertion order preserved.
    final grouped = <String, List<SetLog>>{};
    for (final log in setLogs) {
      grouped.putIfAbsent(log.exerciseName, () => []).add(log);
    }
    // Indexado para el stagger de abajo — lista eager (no builder), así que
    // TreinoFadeSlideIn es seguro (docs/design-system.md).
    final groupedList = grouped.entries.toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back button — top-left
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(TreinoIcon.back, color: palette.textPrimary),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/workout'),
            ),
          ),
          const SizedBox(height: 8),

          // Header: date + time + routineName. startedAt is a real instant
          // (UTC via TimestampConverter) — convert to the viewer's local time
          // before formatting, or it reads +3h in Argentina (#380).
          TreinoFadeSlideIn(
            child: Column(
              children: [
                Text(
                  formatSessionDate(session.startedAt.toLocal()),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(session.startedAt.toLocal()),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  session.routineName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    color: palette.textPrimary,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4 stats agrupadas en una tarjeta 2×2.
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: SessionStatsCard(
              tiles: [
                StatTile(
                  icon: TreinoIcon.clock,
                  label: l10n.workoutDetailStatDurationMin,
                  value: session.durationMin.toString(),
                ),
                StatTile(
                  icon: TreinoIcon.statSets,
                  label: l10n.workoutDetailStatSets,
                  value: setLogs.length.toString(),
                ),
                StatTile(
                  icon: TreinoIcon.dumbbell,
                  label: l10n.workoutDetailStatVolumeKg,
                  value: formatVolumeKg(session.totalVolumeKg),
                ),
                StatTile(
                  icon: TreinoIcon.statPr,
                  label: l10n.workoutDetailStatPrsToday,
                  value: l10n.workoutStatPrsTodayStub,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Exercise blocks — or empty state when no sets were logged.
          if (groupedList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                l10n.sessionDetailNoSets,
                textAlign: TextAlign.center,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: palette.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else
            ...groupedList.asMap().entries.map(
                  (indexed) => TreinoFadeSlideIn(
                    delay: AppMotion.stagger(indexed.key + 2),
                    child: SessionExerciseBlock(
                      exerciseName: indexed.value.key,
                      sets: indexed.value.value,
                      // The athlete's own report, shown back to them (#628).
                      // Grouping here is by exerciseName (that is what the
                      // grouped list is keyed on), so match on the same field.
                      feedback: feedback
                          .where((f) => f.exerciseName == indexed.value.key)
                          .toList(),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Not-found state ───────────────────────────────────────────────────────────

class _DetailNotFound extends StatelessWidget {
  const _DetailNotFound();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.workoutNotFoundTitle),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/workout'),
            child: Text(l10n.workoutButtonBackToWorkout),
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.workoutErrorTitle),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: Text(l10n.workoutButtonRetry),
          ),
        ],
      ),
    );
  }
}

// ── Time helper ───────────────────────────────────────────────────────────────

String _formatTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
