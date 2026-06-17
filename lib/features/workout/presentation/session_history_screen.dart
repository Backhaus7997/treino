import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/session_providers.dart';
import '../domain/session.dart';
import '../domain/session_status.dart';
import 'utils/date_helpers.dart';

/// Full, uncapped list of finished workout sessions for the current user.
///
/// Top-level (outside the ShellRoute) destination reached from the "Ver todo"
/// affordance in [HistorialSection]. Owns its own Scaffold + [AppBackground]
/// and back button, matching [SessionDetailScreen]. The inline section on the
/// WORKOUT tab caps at 5 entries; this screen is the first-class entry point
/// to past sessions so history is no longer buried under everything else.
class SessionHistoryScreen extends ConsumerWidget {
  const SessionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final sessionsAsync = ref.watch(sessionsByUidProvider(uid));

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: l10n.commonBack,
                      icon: Icon(TreinoIcon.back,
                          size: 20, color: palette.textPrimary),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/workout'),
                    ),
                    const SizedBox(width: 6),
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.workoutHistorialFullTitle,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          letterSpacing: 1.0,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: sessionsAsync.when(
                  loading: () => Center(
                    child: CircularProgressIndicator(color: palette.accent),
                  ),
                  error: (_, __) => _ErrorState(
                    onRetry: () =>
                        ref.invalidate(sessionsByUidProvider(uid)),
                  ),
                  data: (all) {
                    final completed = all
                        .where((s) =>
                            s.status == SessionStatus.finished &&
                            s.wasFullyCompleted)
                        .toList();
                    if (completed.isEmpty) {
                      return const _EmptyState();
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: completed.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: palette.textMuted.withValues(alpha: 0.12),
                      ),
                      itemBuilder: (_, i) =>
                          _HistoryCard(session: completed[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final l10n = AppL10n.of(context);
    final formattedDate = formatSessionDate(session.startedAt);

    return InkWell(
      onTap: () => context.push('/workout/historial/${session.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(TreinoIcon.checkCircleFill,
                  color: palette.accent, size: 20),
            ),
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
              '${session.totalVolumeKg}${l10n.workoutHistorialCardKgSuffix}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${session.durationMin}${l10n.workoutHistorialCardMinSuffix}',
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppL10n.of(context).workoutHistorialEmptyMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go('/workout'),
              child: Text(AppL10n.of(context).workoutHistorialEmptyCta),
            ),
          ],
        ),
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
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppL10n.of(context).workoutHistorialErrorMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: Text(AppL10n.of(context).workoutHistorialErrorRetry),
            ),
          ],
        ),
      ),
    );
  }
}
