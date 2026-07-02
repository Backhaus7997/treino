// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/dashboard_day_counts.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/chat/application/chat_providers.dart'
    show totalUnreadCountProvider;
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_kpi_row.dart'
    show KpiTile;
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtArs;
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
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
        const _AlertBanner(),
        const SizedBox(height: 16),
        const _WelcomeCard(),
        const SizedBox(height: 16),
        const _KpiStrip(),
        const SizedBox(height: 20),
        if (wide) ...[
          const _TwoColumnLayout(
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PendingTodaySection(),
              ],
            ),
            right: _PlaceholderCard(
              title: 'Próximas sesiones',
              hint: 'Las sesiones de hoy aparecerán aquí (PR2).',
            ),
          ),
        ] else ...[
          const _PendingTodaySection(),
          const SizedBox(height: 16),
          const _PlaceholderCard(
            title: 'Próximas sesiones',
            hint: 'Las sesiones de hoy aparecerán aquí (PR2).',
          ),
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

// ── Alert banner (PLACEHOLDER) ────────────────────────────────────────────────

/// Alert banner — V1 placeholder (no real notification aggregation). REQ-HOY-03.
class _AlertBanner extends StatelessWidget {
  const _AlertBanner();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(TreinoIcon.bell, size: 16, color: palette.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.dashboardAlertBannerPlaceholder,
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Welcome card ──────────────────────────────────────────────────────────────

/// Welcome card — greeting + summary + quick actions + adherencia ring.
/// REQ-HOY-04.
class _WelcomeCard extends ConsumerWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // Name from userProfileProvider.
    final profileAsync = ref.watch(userProfileProvider);
    final displayName = profileAsync.valueOrNull?.displayName ?? '';
    final firstName = displayName.trim().split(RegExp(r'\s+')).first;

    // Unread message count.
    final unread = ref.watch(totalUnreadCountProvider);

    // Pending solicitudes count (para revisar).
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final pendingCount = linksAsync.valueOrNull
            ?.where((l) => l.status == TrainerLinkStatus.pending)
            .length ??
        0;

    // Sesiones hoy count via trainerAppointmentsStreamProvider + dashboardDayCounts.
    final uid = ref.watch(currentUidProvider) ?? '';
    final now = DateTime.now().toUtc();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final appointmentsAsync = ref.watch(
      trainerAppointmentsStreamProvider(
        TrainerAppointmentsKey(
          trainerId: uid,
          fromDate: todayStart,
          toDate: todayEnd,
        ),
      ),
    );
    final sessionCounts = dashboardDayCounts(
      appointmentsAsync.valueOrNull ?? [],
      now,
    );

    // Vencidos count from pagosBucketsProvider.
    final bucketsAsync = ref.watch(pagosBucketsProvider);
    final vencidosCount = bucketsAsync.valueOrNull?.vencidos.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          Text(
            l10n.dashboardGreeting(firstName.toUpperCase()),
            style: GoogleFonts.barlowCondensed(
              color: palette.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          // Summary line
          Text(
            l10n.dashboardSummaryLine(
              sessionCounts.pending,
              pendingCount,
              vencidosCount,
            ),
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // Quick actions row + adherencia ring
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickAction(
                      label: l10n.dashboardQuickActionNuevoAlumno,
                      onTap: () => context.go('/alumnos'),
                    ),
                    _QuickAction(
                      label: l10n.dashboardQuickActionCrearRutina,
                      onTap: () => context.go('/biblioteca'),
                    ),
                    _QuickAction(
                      label: l10n.dashboardQuickActionMensajes(unread),
                      onTap: () => context.go('/mensajes'),
                    ),
                    _QuickAction(
                      label: l10n.dashboardQuickActionImportarPlan,
                      onTap: () => context.push('/upload-plan'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Adherencia ring placeholder
              _AdherenceRingPlaceholder(l10n: l10n, palette: palette),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single quick action chip/button.
class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Adherencia ring — V1 placeholder (no aggregate provider). REQ-HOY-04B.
class _AdherenceRingPlaceholder extends StatelessWidget {
  const _AdherenceRingPlaceholder({
    required this.l10n,
    required this.palette,
  });
  final AppL10n l10n;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: 0,
            strokeWidth: 6,
            backgroundColor: palette.border,
            color: palette.accent.withValues(alpha: 0.3),
          ),
          Text(
            l10n.dashboardAdherenceRingPlaceholder,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── KPI strip ─────────────────────────────────────────────────────────────────

/// 4-tile KPI strip: Alumnos activos / Ingreso del mes / Adherencia / Por cobrar.
/// REQ-HOY-05.
class _KpiStrip extends ConsumerWidget {
  const _KpiStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final bucketsAsync = ref.watch(pagosBucketsProvider);

    // Alumnos activos.
    final activeCount = linksAsync.valueOrNull
            ?.where((l) => l.status == TrainerLinkStatus.active)
            .length ??
        0;

    // Ingreso del mes + Por cobrar from pagosBuckets.
    int ingresoMes = 0;
    int porCobrarTotal = 0;
    int vencidosCount = 0;
    bucketsAsync.whenData((buckets) {
      final now = DateTime.now().toUtc();
      final monthStart = DateTime.utc(now.year, now.month, 1);
      for (final p in buckets.pagados) {
        final ref = (p.paidAt ?? p.createdAt).toUtc();
        if (!ref.isBefore(monthStart)) {
          ingresoMes += p.amountArs;
        }
      }
      porCobrarTotal = buckets.vencidos.fold(0, (sum, p) => sum + p.amountArs);
      vencidosCount = buckets.vencidos.length;
    });

    final isLoading = linksAsync.isLoading || bucketsAsync.isLoading;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          KpiTile(
            label: l10n.dashboardKpiAlumnosActivos,
            value: isLoading ? '…' : activeCount.toString(),
          ),
          const SizedBox(width: 12),
          KpiTile(
            label: l10n.dashboardKpiIngresoMes,
            value: bucketsAsync.isLoading ? '…' : fmtArs(ingresoMes),
          ),
          const SizedBox(width: 12),
          KpiTile(
            label: l10n.dashboardKpiAdherencia,
            value: l10n.dashboardAdherenceRingPlaceholder,
          ),
          const SizedBox(width: 12),
          KpiTile(
            label: l10n.dashboardKpiPorCobrar(vencidosCount),
            value: bucketsAsync.isLoading ? '…' : fmtArs(porCobrarTotal),
          ),
        ],
      ),
    );
  }
}

// ── Placeholder card ──────────────────────────────────────────────────────────

/// Shared placeholder card for gaps (PR2/PR3 will replace).
class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
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
            title,
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.dashboardPlaceholderSoon,
            style: TextStyle(color: palette.textMuted, fontSize: 13),
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
