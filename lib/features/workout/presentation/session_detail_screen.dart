import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/session_providers.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';
import 'utils/date_helpers.dart';
import 'widgets/session_exercise_block.dart';
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
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Loaded body ───────────────────────────────────────────────────────────────

class _DetailLoaded extends StatelessWidget {
  const _DetailLoaded({required this.session, required this.setLogs});

  final Session session;
  final List<SetLog> setLogs;

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

          // Header: date + time + routineName
          Text(
            formatSessionDate(session.startedAt),
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
            _formatTime(session.startedAt),
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
          const SizedBox(height: 24),

          // 4-stat grid 2×2
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2,
            children: [
              StatTile(
                label: l10n.workoutDetailStatDuration,
                value: session.durationMin.toString(),
              ),
              StatTile(
                label: l10n.workoutDetailStatSets,
                value: setLogs.length.toString(),
              ),
              StatTile(
                label: l10n.workoutDetailStatVolume,
                value: session.totalVolumeKg.toString(),
              ),
              StatTile(
                label: l10n.workoutDetailStatPrsToday,
                value: l10n.workoutStatPrsTodayStub,
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Exercise blocks — or empty state when no sets were logged.
          if (grouped.isEmpty)
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
            ...grouped.entries.map(
              (entry) => SessionExerciseBlock(
                exerciseName: entry.key,
                sets: entry.value,
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
