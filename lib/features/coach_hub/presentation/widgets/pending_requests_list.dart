import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Solicitudes pendientes — solo aparece cuando hay al menos una.
///
/// Shared between the Coach Hub dashboard ("Pendientes de HOY" section) and
/// [SolicitudesScreen] (the `/solicitudes` route reached from the top-bar
/// bell). Extracted from `coach_hub_dashboard_screen.dart` (was
/// `_PendingRequestsList`/`_PendingRequestTile`, file-private) so both
/// consumers share identical accept/decline behavior. Keys preserved:
/// `pending_request_*`, `accept_*`, `decline_*`.
class PendingRequestsList extends ConsumerWidget {
  const PendingRequestsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return linksAsync.when(
      error: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: _SectionError(
          message: l10n.coachHubSectionLoadError,
          onRetry: () => ref.invalidate(trainerLinksStreamProvider),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      data: (links) {
        final pending =
            links.where((l) => l.status == TrainerLinkStatus.pending).toList();
        if (pending.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.coachHubDashboardPendingHeader(pending.length),
              style: GoogleFonts.barlowCondensed(
                color: palette.highlight,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ...pending.map(
              (link) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PendingRequestTile(link: link),
              ),
            ),
            const SizedBox(height: 18),
          ],
        );
      },
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: palette.accent),
              child: Text(l10n.coachRetryLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class PendingRequestTile extends ConsumerStatefulWidget {
  const PendingRequestTile({super.key, required this.link});
  final TrainerLink link;

  @override
  ConsumerState<PendingRequestTile> createState() => _PendingRequestTileState();
}

class _PendingRequestTileState extends ConsumerState<PendingRequestTile> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppL10n.of(context);
    final repo = ref.read(trainerLinkRepositoryProvider);
    try {
      await repo.accept(widget.link.id);
      ref
          .read(analyticsServiceProvider)
          .logLinkAccepted(linkId: widget.link.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.coachHubDashboardAcceptSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.coachHubDashboardAcceptError)),
      );
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppL10n.of(context);
    final repo = ref.read(trainerLinkRepositoryProvider);
    try {
      await repo.decline(widget.link.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.coachHubDashboardRejectSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.coachHubDashboardRejectError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final pubAsync =
        ref.watch(userPublicProfileProvider(widget.link.athleteId));
    final name = pubAsync.valueOrNull?.displayName ?? 'Atleta';
    final avatar = pubAsync.valueOrNull?.avatarUrl;

    return Container(
      key: Key('pending_request_${widget.link.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.highlight.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Semantics(
            image: true,
            label: l10n.a11yAvatarLabel(name),
            child: PostAvatar(
              authorDisplayName: name,
              authorAvatarUrl: avatar,
              size: 40,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.coachHubDashboardPendingContext,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            Semantics(
              label: l10n.commonProcessing,
              liveRegion: true,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.accent,
                ),
              ),
            )
          else ...[
            TextButton(
              key: Key('decline_${widget.link.id}'),
              onPressed: _decline,
              style: TextButton.styleFrom(
                foregroundColor: palette.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(l10n.coachHubActionReject),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              key: Key('accept_${widget.link.id}'),
              onPressed: _accept,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const StadiumBorder(),
              ),
              child: Text(l10n.coachHubActionAccept),
            ),
          ],
        ],
      ),
    );
  }
}
