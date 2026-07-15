// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_hero.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_kpi_strip.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/coach_hub/application/inactivos_provider.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Dashboard ────────────────────────────────────────────────────────────────

/// Coach Hub web dashboard — "Hoy" landing screen.
///
/// Adaptive two-column layout (>=900px wide) or single-column stack.
/// Section contract: ConsumerWidget, no Scaffold/SafeArea, AppPalette,
/// TreinoIcon, showDialog, AppL10n (ADR-CHW-005).
///
/// PR1: alert banner (placeholder) + welcome card + KPI strip + two column
/// stubs. Old student-list widgets preserved below for now (PR3 removes).
class CoachHubDashboardScreen extends ConsumerWidget {
  const CoachHubDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Align.topCenter en vez de Center: centra horizontalmente pero pega
    // el content al top. Con Center puro, cuando el viewport es alto y el
    // content es corto (poca data en dev), sobraba mucho espacio en blanco
    // arriba y abajo.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        // maxWidth 1600 evita que el content se estire en 4K/5K pero
        // aprovecha bien viewports 1440-1920 sin dejar mucho espacio muerto
        // a los lados. Antes era 1280 (conservador para 720p/1080p) y en
        // monitores Retina/4K quedaba pegado a la izquierda con mucho aire
        // en la derecha.
        constraints: const BoxConstraints(maxWidth: 1600),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Finite-height guard mirrors agenda_web_screen.dart:107-108.
            final wide =
                constraints.maxWidth >= 900 && constraints.maxHeight.isFinite;

            final content = _DashboardContent(wide: wide);

            if (wide) {
              return SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: content,
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: content,
            );
          },
        ),
      ),
    );
  }
}

// ── Dashboard Content ─────────────────────────────────────────────────────────

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DashboardAlertBanner(),
        const SizedBox(height: AppSpacing.s18),
        const DashboardWelcomeCard(),
        const SizedBox(height: AppSpacing.s18),
        const DashboardKpiStrip(),
        const SizedBox(height: 20),
        if (wide) ...[
          const _TwoColumnLayout(
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PendingTodaySection(),
              ],
            ),
            right: _RightColumn(),
          ),
        ] else ...[
          const _PendingTodaySection(),
          const SizedBox(height: 16),
          const _RightColumn(),
        ],
      ],
    );
  }
}

// ── Two-column layout ──────────────────────────────────────────────────────────

class _TwoColumnLayout extends StatelessWidget {
  const _TwoColumnLayout({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 55, child: left),
          const SizedBox(width: 20),
          Expanded(flex: 45, child: right),
        ],
      ),
    );
  }
}

// ── Right column ──────────────────────────────────────────────────────────────

/// Right column container: Próximas sesiones + Vencimientos 7d + Inactivos.
/// REQ-HOY-07, REQ-HOY-08, REQ-HOY-09.
class _RightColumn extends StatelessWidget {
  const _RightColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProximasSesiones(),
        SizedBox(height: 16),
        _Vencimientos7d(),
        SizedBox(height: 16),
        _InactivosSection(),
      ],
    );
  }
}

// ── Próximas sesiones (REAL) ──────────────────────────────────────────────────

/// Shows next 4 confirmed future appointments. REQ-HOY-07.
class _ProximasSesiones extends ConsumerWidget {
  const _ProximasSesiones();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final uid = ref.watch(currentUidProvider) ?? '';
    final now = DateTime.now().toUtc();
    // La key de un provider .family DEBE ser estable entre builds. Usar
    // DateTime.now() con precisión de microsegundos genera una key distinta en
    // cada build → nueva instancia del family → AsyncLoading→data → rebuild →
    // otra key nueva → loop infinito → pumpAndSettle nunca estabiliza (rompía
    // TODOS los tests del dashboard en CI). Truncamos al día (estable dentro
    // del día UTC); el filtro fino usa `now` más abajo en el .when(data:).
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    // Ventana de 30 días desde el arranque de hoy. Key estable → sin loop.
    final windowEnd = todayStart.add(const Duration(days: 30));
    final appointmentsAsync = ref.watch(
      trainerAppointmentsStreamProvider(
        TrainerAppointmentsKey(
          trainerId: uid,
          fromDate: todayStart,
          toDate: windowEnd,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dashboardProximasSesionesSectionLabel,
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          appointmentsAsync.when(
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accent,
                  ),
                ),
              ),
            ),
            error: (_, __) => Text(
              l10n.dashboardProximasSesionesEmpty,
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
            data: (appointments) {
              final upcoming = appointments
                  .where(
                    (a) =>
                        a.status == AppointmentStatus.confirmed &&
                        a.startsAt.isAfter(now),
                  )
                  .toList()
                ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

              final rows = upcoming.take(4).toList();

              if (rows.isEmpty) {
                return Text(
                  l10n.dashboardProximasSesionesEmpty,
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                );
              }

              return Column(
                children: rows
                    .map((a) => _SesionRow(appointment: a, palette: palette))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SesionRow extends StatelessWidget {
  const _SesionRow({required this.appointment, required this.palette});
  final Appointment appointment;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final local = appointment.startsAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';

    // La lista de próximas sesiones abarca hasta 30 días. Cuando la sesión no
    // es hoy, prefijamos el día ("mañana · 09:00" / "14/7 · 09:00") para que el
    // orden no se lea salteado — mostrar solo HH:mm confundía sesiones de días
    // distintos (se ordenan por fecha completa, no solo por hora).
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(local.year, local.month, local.day);
    final daysAhead = sessionDay.difference(today).inDays;
    final String label;
    if (daysAhead <= 0) {
      label = time;
    } else if (daysAhead == 1) {
      label = '${l10n.dashboardProximaSesionManana} · $time';
    } else {
      label = '${local.day}/${local.month} · $time';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(
                color: palette.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              appointment.athleteDisplayName,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vencimientos 7 días (REAL) ────────────────────────────────────────────────

/// Shows vencidos from pagosBucketsProvider + "Ver todos" link. REQ-HOY-08.
class _Vencimientos7d extends ConsumerWidget {
  const _Vencimientos7d();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final bucketsAsync = ref.watch(pagosBucketsProvider);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dashboardVencimientosTitle,
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          bucketsAsync.when(
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accent,
                  ),
                ),
              ),
            ),
            error: (_, __) => Text(
              l10n.dashboardVencimientosEmpty,
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
            data: (buckets) {
              final vencidos = buckets.vencidos;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (vencidos.isEmpty)
                    Text(
                      l10n.dashboardVencimientosEmpty,
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    )
                  else
                    ...vencidos.map(
                      (p) => _VencimientoRow(payment: p, palette: palette),
                    ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => context.go('/pagos'),
                    child: Text(
                      l10n.dashboardVencimientosVerTodos,
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _VencimientoRow extends ConsumerWidget {
  const _VencimientoRow({required this.payment, required this.palette});
  final Payment payment;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysOverdue = DateTime.now()
        .toUtc()
        .difference(
          payment.createdAt.toUtc(),
        )
        .inDays;

    // Payment sólo trae athleteId → resolvemos el nombre del alumno.
    final name = ref
            .watch(userPublicProfileProvider(payment.athleteId))
            .valueOrNull
            ?.displayName ??
        '…';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '+$daysOverdue d',
              style: TextStyle(
                color: palette.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Alumnos inactivos (REAL — driven by inactivosProvider) ──────────────────

/// Alumnos inactivos — REQ-HOY-09.
///
/// Watches [inactivosProvider] for the list of inactive athlete IDs.
/// Resolves each athlete's display name via [userPublicProfileProvider]
/// (same per-id pattern used in _VencimientoRow).
///
/// Loading: renders the section header without a spinner (avoids perpetual
/// pumpAndSettle hang in CI). Empty state: "Sin alumnos inactivos".
class _InactivosSection extends ConsumerWidget {
  const _InactivosSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final inactivosAsync = ref.watch(inactivosProvider);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dashboardInactivosTitle,
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          // Resolve data when available; show nothing extra while loading
          // to avoid a perpetual spinner that would hang pumpAndSettle.
          inactivosAsync.when(
            loading: () => Text(
              '…',
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
            error: (_, __) => _SectionError(message: l10n.coachRetryLabel),
            data: (result) {
              final ids = result.inactiveAthleteIds;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ids.isEmpty)
                    Text(
                      l10n.dashboardInactivosEmpty,
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    )
                  else
                    ...ids.map(
                      (id) => _InactivoRow(athleteId: id, palette: palette),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Single row in the inactivos list — resolves athlete name via
/// [userPublicProfileProvider] (same pattern as _VencimientoRow).
class _InactivoRow extends ConsumerWidget {
  const _InactivoRow({required this.athleteId, required this.palette});
  final String athleteId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref
            .watch(userPublicProfileProvider(athleteId))
            .valueOrNull
            ?.displayName ??
        '…';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(TreinoIcon.tabProfile, size: 14, color: palette.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending today section (preserved solicitudes) ─────────────────────────────

/// Pendientes de HOY — solicitudes pendientes REAL. REQ-HOY-06.
///
/// Preserves _PendingRequestsList/_PendingRequestTile unchanged from original.
class _PendingTodaySection extends ConsumerWidget {
  const _PendingTodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pendientes de HOY', // i18n key in PR3 tasks.md (7.1)
          style: GoogleFonts.barlowCondensed(
            color: palette.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        const _PendingRequestsList(),
      ],
    );
  }
}

// ─── Section helpers (error) ──────────────────────────────────────────────────

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

// ─── Pending requests section ────────────────────────────────────────────────

/// Solicitudes pendientes — solo aparece cuando hay al menos una.
/// Keys preserved: pending_request_*, accept_*, decline_*.
class _PendingRequestsList extends ConsumerWidget {
  const _PendingRequestsList();

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
                child: _PendingRequestTile(link: link),
              ),
            ),
            const SizedBox(height: 18),
          ],
        );
      },
    );
  }
}

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
