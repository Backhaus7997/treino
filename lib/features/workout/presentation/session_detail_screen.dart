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
import 'widgets/stat_tile.dart';
import 'workout_strings.dart';

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
                label: WorkoutStrings.detailStatDuration,
                value: session.durationMin.toString(),
              ),
              StatTile(
                label: WorkoutStrings.detailStatSets,
                value: setLogs.length.toString(),
              ),
              StatTile(
                label: WorkoutStrings.detailStatVolume,
                value: session.totalVolumeKg.toString(),
              ),
              const StatTile(
                label: WorkoutStrings.detailStatPrsToday,
                value: WorkoutStrings.statPrsTodayStub,
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Exercise blocks
          ...grouped.entries.map(
            (entry) => _ExerciseBlock(
              exerciseName: entry.key,
              sets: entry.value,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise block ────────────────────────────────────────────────────────────

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({required this.exerciseName, required this.sets});

  final String exerciseName;
  final List<SetLog> sets;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exerciseName,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: palette.textPrimary,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          ...sets.map((log) => _SetRow(log: log)),
        ],
      ),
    );
  }
}

// ── Set row ───────────────────────────────────────────────────────────────────

class _SetRow extends StatelessWidget {
  const _SetRow({required this.log});

  final SetLog log;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${log.setNumber}',
              style: TextStyle(color: palette.textMuted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${log.reps} reps',
              style: TextStyle(color: palette.textPrimary),
            ),
          ),
          Text(
            '${log.weightKg} kg',
            style: TextStyle(color: palette.textPrimary),
          ),
          const SizedBox(width: 8),
          const _PrBadgeStub(),
        ],
      ),
    );
  }
}

// ── PR badge stub ─────────────────────────────────────────────────────────────
// Placeholder widget — no params, no logic. Grep-friendly name for Etapa 5.

class _PrBadgeStub extends StatelessWidget {
  const _PrBadgeStub();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: palette.accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        WorkoutStrings.detailPrBadge,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: palette.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Not-found state ───────────────────────────────────────────────────────────

class _DetailNotFound extends StatelessWidget {
  const _DetailNotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(WorkoutStrings.notFoundTitle),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/workout'),
            child: const Text(WorkoutStrings.buttonBackToWorkout),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(WorkoutStrings.errorTitle),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: const Text(WorkoutStrings.buttonRetry),
          ),
        ],
      ),
    );
  }
}

// ── Time helper ───────────────────────────────────────────────────────────────

String _formatTime(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
