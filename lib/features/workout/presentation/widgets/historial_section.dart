import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/session_providers.dart';
import '../../domain/session.dart';
import '../../domain/session_status.dart';
import '../utils/date_helpers.dart';
import '../workout_strings.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Displays the list of finished workout sessions for the current user.
/// Replaces the private `_HistorialSection` placeholder in WorkoutScreen.
///
/// No constructor parameters — consumes [currentUidProvider] and
/// [sessionsByUidProvider] from Riverpod.
class HistorialSection extends ConsumerWidget {
  const HistorialSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';

    final sessionsAsync = ref.watch(sessionsByUidProvider(uid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          WorkoutStrings.historialHeading,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        sessionsAsync.when(
          loading: () => const _ListLoadingState(),
          error: (_, __) => _ListErrorState(
            onRetry: () => ref.invalidate(sessionsByUidProvider(uid)),
          ),
          data: (all) {
            final finished =
                all.where((s) => s.status == SessionStatus.finished).toList();
            if (finished.isEmpty) {
              return const _ListEmptyState();
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: finished.length,
              itemBuilder: (context, i) => _HistorialCard(session: finished[i]),
            );
          },
        ),
      ],
    );
  }
}

// ── Loading state ─────────────────────────────────────────────────────────────

class _ListLoadingState extends StatelessWidget {
  const _ListLoadingState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ListErrorState extends StatelessWidget {
  const _ListErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            WorkoutStrings.historialErrorMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: const Text(WorkoutStrings.historialErrorRetry),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _ListEmptyState extends StatelessWidget {
  const _ListEmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            WorkoutStrings.historialEmptyMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/workout'),
            child: const Text(WorkoutStrings.historialEmptyCta),
          ),
        ],
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _HistorialCard extends StatelessWidget {
  const _HistorialCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final formattedDate = formatSessionDate(session.startedAt);

    return GestureDetector(
      onTap: () => context.push('/workout/historial/${session.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _CompletedIcon(wasFullyCompleted: session.wasFullyCompleted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.routineName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formattedDate,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${session.totalVolumeKg}${WorkoutStrings.historialCardKgSuffix}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${session.durationMin}${WorkoutStrings.historialCardMinSuffix}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Completed indicator icon ──────────────────────────────────────────────────

class _CompletedIcon extends StatelessWidget {
  const _CompletedIcon({required this.wasFullyCompleted});

  final bool wasFullyCompleted;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (wasFullyCompleted) {
      return Icon(TreinoIcon.checkCircleFill, color: palette.accent, size: 20);
    }
    return Icon(
      TreinoIcon.checkCircleEmpty,
      color: palette.textMuted,
      size: 20,
    );
  }
}
