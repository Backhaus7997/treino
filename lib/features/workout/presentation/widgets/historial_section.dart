import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/session_providers.dart';
import '../../domain/session.dart';
import '../../domain/session_status.dart';
import '../utils/date_helpers.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Displays the list of finished workout sessions for the current user.
/// Replaces the private `_HistorialSection` placeholder in WorkoutScreen.
///
/// No constructor parameters — consumes [currentUidProvider] and
/// [sessionsByUidProvider] from Riverpod.
class HistorialSection extends ConsumerStatefulWidget {
  const HistorialSection({super.key});

  @override
  ConsumerState<HistorialSection> createState() => _HistorialSectionState();
}

class _HistorialSectionState extends ConsumerState<HistorialSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';

    final sessionsAsync = ref.watch(sessionsByUidProvider(uid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.workoutHistorialHeading,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        sessionsAsync.when(
          loading: () => const _ListLoadingState(),
          error: (_, __) => _ListErrorState(
            onRetry: () => ref.invalidate(sessionsByUidProvider(uid)),
          ),
          data: (all) {
            final completed = all
                .where((s) =>
                    s.status == SessionStatus.finished && s.wasFullyCompleted)
                .toList();
            if (completed.isEmpty) {
              return const _ListEmptyState();
            }

            const limit = 5; // historialCollapsedLimit
            final overflow = completed.length > limit;
            final visible = (overflow && !_expanded)
                ? completed.take(limit).toList()
                : completed;
            final hidden = completed.length - limit;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visible.length,
                  itemBuilder: (context, i) =>
                      _HistorialCard(session: visible[i]),
                ),
                if (overflow)
                  _ExpandToggle(
                    expanded: _expanded,
                    hiddenCount: hidden,
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
              ],
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
            AppL10n.of(context).workoutHistorialErrorMessage,
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
            AppL10n.of(context).workoutHistorialEmptyMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/workout'),
            child: Text(AppL10n.of(context).workoutHistorialEmptyCta),
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
            const _CompletedIcon(),
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
              '${session.totalVolumeKg}${AppL10n.of(context).workoutHistorialCardKgSuffix}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${session.durationMin}${AppL10n.of(context).workoutHistorialCardMinSuffix}',
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
  const _CompletedIcon();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Icon(TreinoIcon.checkCircleFill, color: palette.accent, size: 20);
  }
}

// ── Expand / collapse toggle ──────────────────────────────────────────────────

class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({
    required this.expanded,
    required this.hiddenCount,
    required this.onTap,
  });

  final bool expanded;
  final int hiddenCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final label = expanded
        ? l10n.workoutHistorialShowLess
        : l10n.workoutHistorialShowMore(hiddenCount);
    final icon = expanded ? TreinoIcon.chevronUp : TreinoIcon.chevronDown;

    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: palette.accent, size: 18),
        label: Text(label, style: TextStyle(color: palette.accent)),
      ),
    );
  }
}
