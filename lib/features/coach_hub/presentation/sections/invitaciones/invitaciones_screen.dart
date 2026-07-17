// InvitacionesScreen — bandeja de Solicitudes del Coach Hub web (WU-04,
// Fase 4). Reemplaza `ProximamenteScreen` en `/invitaciones`.
//
// Sigue el patrón de `alumnos_screen.dart` (screen de sección Riverpod, sin
// Scaffold — ADR-CHW-005): TreinoSectionHeader + TreinoFilterChips (3 tabs
// con badges de conteo) entran con `TreinoFadeSlideIn` staggered; la lista
// queda fuera del stagger, su cross-fade lo resuelve TreinoStateSwitcher
// sobre `trainerLinksStreamProvider.when` (plan-fase4.md §3).
//
// Acciones (solo tab Pendientes, ADR-F4-02): aceptar/rechazar abren un
// `TreinoDialog` de confirmación; al confirmar, `_SolicitudTile` cablea
// `trainerLinkRepositoryProvider.accept/decline` con un `busy` local
// (patrón `_PendingRequestTile` de `dashboard_pending.dart`) + snackbar con
// las keys l10n existentes (ADR-F4-05, l10n congelado).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/application/trainer_link_providers.dart';
import '../../../../coach/domain/trainer_link.dart';
import '../../../../coach/domain/trainer_link_status.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import '../../../../../l10n/app_l10n.dart';
import '../../widgets/coach_hub_widgets.dart';
import 'solicitudes_providers.dart';
import 'widgets/solicitud_card.dart';

/// Bandeja de Solicitudes (`/invitaciones`) — WU-04.
class InvitacionesScreen extends ConsumerWidget {
  const InvitacionesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final tab = ref.watch(solicitudTabProvider);
    final pendingCount = ref.watch(invitacionesPendingCountProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s20,
        vertical: AppSpacing.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: TreinoSectionHeader(
              title: 'Solicitudes', // i18n: Fase W1
              count: pendingCount,
            ),
          ),
          const SizedBox(height: AppSpacing.s18),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: _TabChips(
              tab: tab,
              counts: _countsByTab(linksAsync.valueOrNull),
            ),
          ),
          const SizedBox(height: AppSpacing.s14),
          TreinoStateSwitcher(
            childKey:
                ValueKey('invitaciones_${_stateKeyOf(linksAsync)}_${tab.name}'),
            child: linksAsync.when(
              loading: () => const _LoadingList(),
              error: (e, _) => _ErrorSection(onRetry: () {
                ref.invalidate(trainerLinksStreamProvider);
              }),
              data: (links) {
                final filtered = [
                  for (final l in links)
                    if (matchesSolicitudTab(l, tab)) l,
                ];
                if (filtered.isEmpty) return _EmptyForTab(tab: tab);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final link in filtered) ...[
                      _SolicitudTile(link: link),
                      if (link != filtered.last)
                        const SizedBox(height: AppSpacing.s8),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuenta las solicitudes por tab sobre la lista completa (no filtrada) —
/// mismo criterio que los badges de `_FiltroChips` en `alumnos_screen.dart`.
Map<SolicitudTab, int> _countsByTab(List<TrainerLink>? links) {
  final list = links ?? const <TrainerLink>[];
  return {
    for (final t in SolicitudTab.values)
      t: list.where((l) => matchesSolicitudTab(l, t)).length,
  };
}

String _stateKeyOf(AsyncValue<Object?> value) {
  if (value.hasError) return 'error';
  if (value.isLoading && !value.hasValue) return 'loading';
  return 'data';
}

/// Chips de tab (Pendientes/Aceptadas/Rechazadas) con badges de conteo real
/// (ADR-F4-02) — single-select, default Pendientes.
class _TabChips extends ConsumerWidget {
  const _TabChips({required this.tab, required this.counts});

  final SolicitudTab tab;
  final Map<SolicitudTab, int> counts;

  static const _labels = {
    SolicitudTab.pendientes: 'Pendientes', // i18n: Fase W1
    SolicitudTab.aceptadas: 'Aceptadas', // i18n: Fase W1
    SolicitudTab.rechazadas: 'Rechazadas', // i18n: Fase W1
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabByLabel = {for (final e in _labels.entries) e.value: e.key};

    return TreinoFilterChips(
      options: _labels.values.toList(),
      selected: {_labels[tab]!},
      badgeCounts: {
        for (final e in _labels.entries) e.value: counts[e.key] ?? 0,
      },
      onChanged: (newSelected) {
        // Single-select: un tap que vacía la selección (chip activo
        // desmarcado) es un no-op — siempre necesitamos un tab activo.
        if (newSelected.isEmpty) return;
        final t = tabByLabel[newSelected.first];
        if (t != null) ref.read(solicitudTabProvider.notifier).state = t;
      },
    );
  }
}

/// Skeleton de carga — columna de `TreinoListRow(loading: true)`.
class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        TreinoListRow(title: '', loading: true),
        SizedBox(height: AppSpacing.s8),
        TreinoListRow(title: '', loading: true),
        SizedBox(height: AppSpacing.s8),
        TreinoListRow(title: '', loading: true),
      ],
    );
  }
}

/// Error al cargar `trainerLinksStreamProvider` + retry.
class _ErrorSection extends StatelessWidget {
  const _ErrorSection({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Padding(
      key: const Key('invitaciones_error'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.coachHubSectionLoadError,
            style: TextStyle(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.s8),
            TextButton(
              key: const Key('invitaciones_retry'),
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

/// Estado vacío honesto por tab (plan-fase4.md §3) — sin CTA (no hay a dónde
/// mandar al PF a "crear" una solicitud, la origina el alumno).
class _EmptyForTab extends StatelessWidget {
  const _EmptyForTab({required this.tab});

  final SolicitudTab tab;

  String get _title => switch (tab) {
        SolicitudTab.pendientes =>
          'No tenés solicitudes pendientes.', // i18n: Fase W1
        SolicitudTab.aceptadas =>
          'Todavía no aceptaste ninguna solicitud.', // i18n: Fase W1
        SolicitudTab.rechazadas =>
          'No rechazaste ninguna solicitud.', // i18n: Fase W1
      };

  @override
  Widget build(BuildContext context) {
    return TreinoEmptyState(icon: TreinoIcon.emptyState, title: _title);
  }
}

/// Una fila de la bandeja: resuelve el perfil del atleta y cablea las
/// acciones de [SolicitudCard] (solo si `status == pending`) a
/// `trainerLinkRepositoryProvider.accept/decline` con confirmación previa
/// (`TreinoDialog`) + `busy` local + snackbar (patrón `_PendingRequestTile`).
class _SolicitudTile extends ConsumerStatefulWidget {
  const _SolicitudTile({required this.link});

  final TrainerLink link;

  @override
  ConsumerState<_SolicitudTile> createState() => _SolicitudTileState();
}

class _SolicitudTileState extends ConsumerState<_SolicitudTile> {
  bool _busy = false;

  bool get _isPending => widget.link.status == TrainerLinkStatus.pending;

  Future<void> _accept(String name) async {
    final l10n = AppL10n.of(context);
    final confirmed = await _confirmSolicitud(
      context,
      title: 'Aceptar solicitud', // i18n: Fase W1
      body: 'Vas a aceptar la solicitud de $name. '
          'Se va a convertir en tu alumno.', // i18n: Fase W1
      confirmLabel: l10n.coachHubActionAccept,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final repo = ref.read(trainerLinkRepositoryProvider);
    try {
      await repo.accept(widget.link.id);
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

  Future<void> _decline(String name) async {
    final l10n = AppL10n.of(context);
    final confirmed = await _confirmSolicitud(
      context,
      title: 'Rechazar solicitud', // i18n: Fase W1
      body: 'Vas a rechazar la solicitud de $name.', // i18n: Fase W1
      confirmLabel: l10n.coachHubActionReject,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
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
    final l10n = AppL10n.of(context);
    final profileAsync =
        ref.watch(userPublicProfileProvider(widget.link.athleteId));
    final name = profileAsync.valueOrNull?.displayName ??
        l10n.coachHubAlumnosNameFallback;
    final avatarUrl = profileAsync.valueOrNull?.avatarUrl;

    return SolicitudCard(
      id: widget.link.id,
      displayName: name,
      avatarUrl: avatarUrl,
      requestedAt: widget.link.requestedAt,
      status: widget.link.status,
      busy: _busy,
      onAccept: _isPending ? () => _accept(name) : null,
      onDecline: _isPending ? () => _decline(name) : null,
    );
  }
}

/// Diálogo de confirmación — kit v2 (`showTreinoDialog`/`TreinoDialog`),
/// mismo patrón que `_confirmAction` en `alumnos_screen.dart`.
Future<bool> _confirmSolicitud(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final l10n = AppL10n.of(context);
  final result = await showTreinoDialog<bool>(
    context,
    builder: (ctx) => TreinoDialog(
      title: title,
      body: Text(body),
      primaryLabel: confirmLabel,
      onPrimaryTap: () => Navigator.of(ctx).pop(true),
      secondaryLabel: l10n.coachHubActionCancel,
      onSecondaryTap: () => Navigator.of(ctx).pop(false),
    ),
  );
  return result ?? false;
}
