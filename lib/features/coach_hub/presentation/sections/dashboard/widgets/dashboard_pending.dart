// Pendientes de HOY del Dashboard ("Hoy") — DashboardPendingSection.
//
// Extraído de `coach_hub_dashboard_screen.dart` (ADR-D2-05, extracción
// incremental) y rediseñado con el kit v2: TreinoSectionHeader (título +
// count real) + TreinoStateSwitcher (loading/empty/data/error) +
// TreinoListRow (skeleton) + TreinoEmptyState.
//
// ADR-D2-01 (dura): NO se agrega el feed rico de mensajes/fotos/dolor del
// mockup — es data inventada. Se rediseña SOLO lo real: solicitudes
// pendientes vía trainerLinksStreamProvider.
//
// Preserva las keys de test `pending_request_*`/`accept_*`/`decline_*` y
// los ElevatedButton/TextButton existentes (ya manejan su propio tap — NO
// se envuelven en TreinoTappable). Sigue el contrato de sección: sin
// Scaffold/SafeArea, AppPalette/AppL10n (ADR-CHW-005).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/widgets/empty_state/empty_state.dart';
import 'package:treino/features/coach_hub/presentation/widgets/list_row/list_row.dart';
import 'package:treino/features/coach_hub/presentation/widgets/section_header/section_header.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Pendientes de HOY — solicitudes pendientes REAL. REQ-HOY-06.
///
/// No existe key l10n para el título del mockup (l10n congelado, ADR-D2-03)
/// — se preserva el literal hardcodeado ya existente en el screen original.
class DashboardPendingSection extends ConsumerWidget {
  const DashboardPendingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final pending = linksAsync.valueOrNull
        ?.where((l) => l.status == TrainerLinkStatus.pending)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TreinoSectionHeader(
          title: 'Pendientes de HOY',
          count: pending?.length,
        ),
        const SizedBox(height: AppSpacing.s12),
        TreinoStateSwitcher(
          childKey: ValueKey(_stateKey(linksAsync, pending)),
          child: _PendingContent(linksAsync: linksAsync, pending: pending),
        ),
      ],
    );
  }

  /// Discrimina el estado actual para [TreinoStateSwitcher] — necesita keys
  /// distintas por estado o el cross-fade no anima el cambio.
  String _stateKey(
    AsyncValue<List<TrainerLink>> linksAsync,
    List<TrainerLink>? pending,
  ) {
    if (linksAsync.hasError) return 'error';
    if (pending == null) return 'loading';
    if (pending.isEmpty) return 'empty';
    return 'data';
  }
}

/// Contenido de la sección según el estado de [trainerLinksStreamProvider].
class _PendingContent extends ConsumerWidget {
  const _PendingContent({required this.linksAsync, required this.pending});

  final AsyncValue<List<TrainerLink>> linksAsync;
  final List<TrainerLink>? pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);

    if (linksAsync.hasError) {
      return _SectionError(
        message: l10n.coachHubSectionLoadError,
        onRetry: () => ref.invalidate(trainerLinksStreamProvider),
      );
    }

    final list = pending;
    if (list == null) {
      // Loading: columna de TreinoListRow skeleton (shimmer del kit).
      return const Column(
        children: [
          TreinoListRow(title: '', loading: true),
          SizedBox(height: AppSpacing.s8),
          TreinoListRow(title: '', loading: true),
        ],
      );
    }

    if (list.isEmpty) {
      // ADR-D2-03 (l10n congelado): no existe key dedicada para "sin
      // solicitudes pendientes" (esta sección no tenía empty state antes
      // del rediseño — mostraba SizedBox.shrink()). Se reusa
      // `dashboardAlertBannerAllClear` ("Todo al día"), ya usada en el
      // alert banner con el mismo significado ("nada pendiente de
      // revisar"), en vez de inventar un literal nuevo.
      return TreinoEmptyState(
        icon: TreinoIcon.emptyState,
        title: l10n.dashboardAlertBannerAllClear,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final link in list) ...[
          _PendingRequestTile(link: link),
          if (link != list.last) const SizedBox(height: AppSpacing.s8),
        ],
      ],
    );
  }
}

// ─── Section error (local — WU-05 extrae la versión compartida) ─────────────

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.s8),
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

// ─── Pending request tile (preserved) ────────────────────────────────────────

/// Tile de una solicitud pendiente. Keys preservadas:
/// `pending_request_*`/`accept_*`/`decline_*`.
class _PendingRequestTile extends ConsumerStatefulWidget {
  const _PendingRequestTile({required this.link});
  final TrainerLink link;

  @override
  ConsumerState<_PendingRequestTile> createState() =>
      _PendingRequestTileState();
}

class _PendingRequestTileState extends ConsumerState<_PendingRequestTile> {
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
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
          const SizedBox(width: AppSpacing.s12),
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
                const SizedBox(height: AppSpacing.hairline),
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
          const SizedBox(width: AppSpacing.s8),
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
              ),
              child: Text(l10n.coachHubActionReject),
            ),
            const SizedBox(width: AppSpacing.hairline),
            ElevatedButton(
              key: Key('accept_${widget.link.id}'),
              onPressed: _accept,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14),
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
