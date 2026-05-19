import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/post_workout_notifier.dart';
import '../application/session_providers.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';
import 'widgets/stat_tile.dart';
import 'workout_strings.dart';

class PostWorkoutSummaryScreen extends ConsumerWidget {
  const PostWorkoutSummaryScreen({super.key, required this.sessionId});

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
            error: (e, _) => _ErrorState(
              onRetry: () => ref.invalidate(
                sessionSummaryProvider((uid: uid, sessionId: sessionId)),
              ),
            ),
            data: (data) {
              final session = data.session;
              if (session == null) {
                return const _NotFoundState();
              }
              return _LoadedBody(
                session: session,
                setLogs: data.setLogs,
                onShare: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref
                        .read(postWorkoutNotifierProvider.notifier)
                        .shareWorkout(session);
                    if (!context.mounted) return;
                    messenger.showSnackBar(const SnackBar(
                      content: Text(WorkoutStrings.snackShareSuccess),
                    ));
                    context.go('/workout');
                  } catch (_) {
                    if (!context.mounted) return;
                    messenger.showSnackBar(const SnackBar(
                      content: Text(WorkoutStrings.snackShareError),
                    ));
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Loaded body ───────────────────────────────────────────────────────────────

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.session,
    required this.setLogs,
    required this.onShare,
  });

  final Session session;
  final List<SetLog> setLogs;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Close icon
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(TreinoIcon.close, color: palette.textPrimary),
              onPressed: () => context.go('/workout'),
            ),
          ),
          const SizedBox(height: 8),

          // Header
          Text(
            session.wasFullyCompleted
                ? WorkoutStrings.summaryHeaderCompleted
                : WorkoutStrings.summaryHeaderAbandoned,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w800,
              fontSize: 32,
              color: palette.accent,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            session.routineName,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 32),

          // 2×2 stat grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2,
            children: [
              StatTile(
                label: WorkoutStrings.statDuration,
                value: session.durationMin.toString(),
              ),
              StatTile(
                label: WorkoutStrings.statVolume,
                value: session.totalVolumeKg.toString(),
              ),
              StatTile(
                label: WorkoutStrings.statSets,
                value: setLogs.length.toString(),
              ),
              const StatTile(
                label: WorkoutStrings.statPrsToday,
                value: WorkoutStrings.statPrsTodayStub,
              ),
            ],
          ),
          const SizedBox(height: 32),

          // PRs section (stub)
          Text(
            WorkoutStrings.prsSectionTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: palette.textPrimary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            WorkoutStrings.prsPlaceholder,
            style: TextStyle(color: palette.textMuted),
          ),
          const SizedBox(height: 32),

          // Mood row — 5 emojis, visual only
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text('😞', style: TextStyle(fontSize: 28)),
              Text('😕', style: TextStyle(fontSize: 28)),
              Text('😐', style: TextStyle(fontSize: 28)),
              Text('🙂', style: TextStyle(fontSize: 28)),
              Text('😄', style: TextStyle(fontSize: 28)),
            ],
          ),
          const SizedBox(height: 40),

          // LISTO button (filled)
          FilledButton(
            onPressed: () => context.go('/workout'),
            child: const Text(WorkoutStrings.buttonDone),
          ),
          const SizedBox(height: 12),

          // COMPARTIR button (outlined)
          OutlinedButton(
            onPressed: onShare,
            child: const Text(WorkoutStrings.buttonShare),
          ),
        ],
      ),
    );
  }
}

// ── Not-found state ───────────────────────────────────────────────────────────

class _NotFoundState extends StatelessWidget {
  const _NotFoundState();

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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
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
