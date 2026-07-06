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
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/payments/domain/payment.dart';
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
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
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

// ── Alert banner (REAL — composes vencidos + solicitudes + inactivos) ────────

/// Alert banner — REQ-HOY-03.
///
/// Watches three signals:
/// - [pagosBucketsProvider].vencidos count
/// - [trainerLinksStreamProvider] pending solicitudes
/// - [inactivosProvider].inactiveCount
///
/// Shows "Todo al día" when all are 0; otherwise renders a composed line.
class _AlertBanner extends ConsumerWidget {
  const _AlertBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final bucketsAsync = ref.watch(pagosBucketsProvider);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final inactivosAsync = ref.watch(inactivosProvider);

    final vencidosCount = bucketsAsync.valueOrNull?.vencidos.length ?? 0;
    final solicitudesCount = linksAsync.valueOrNull
            ?.where((l) => l.status == TrainerLinkStatus.pending)
            .length ??
        0;
    final inactivosCount = inactivosAsync.valueOrNull?.inactiveCount ?? 0;

    final allClear =
        vencidosCount == 0 && solicitudesCount == 0 && inactivosCount == 0;

    final text = allClear
        ? l10n.dashboardAlertBannerAllClear
        : l10n.dashboardAlertBannerSummary(
            vencidosCount,
            solicitudesCount,
            inactivosCount,
          );

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
              text,
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
              // Adherencia ring — real aggregate (PR2).
              const _AdherenceRing(),
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

/// Adherencia ring — real aggregate from [aggregateAdherenceProvider]. REQ-HOY-04B.
///
/// Shows "{pct}%" when data is available; "--" when null (no athlete has a plan).
/// Loading state degrades gracefully to "--" (not a perpetual spinner) so
/// [pumpAndSettle] does not hang in CI.
class _AdherenceRing extends ConsumerWidget {
  const _AdherenceRing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    // valueOrNull: resolves to null while loading → shows "--" (no spinner hang).
    final adherence = ref.watch(aggregateAdherenceProvider).valueOrNull;

    final String label;
    final double ringValue;
    if (adherence == null) {
      label = l10n.dashboardAdherenceRingPlaceholder; // "--"
      ringValue = 0;
    } else {
      label = l10n.dashboardAdherenceValue(adherence.round());
      // Clamp ring value to [0, 1] for CircularProgressIndicator.
      ringValue = (adherence / 100).clamp(0.0, 1.0);
    }

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: ringValue,
            strokeWidth: 6,
            backgroundColor: palette.border,
            color: adherence == null
                ? palette.accent.withValues(alpha: 0.3)
                : palette.accent,
          ),
          Text(
            label,
            style: TextStyle(
              color:
                  adherence == null ? palette.textMuted : palette.textPrimary,
              fontSize: 14,
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

    // Adherencia aggregate — valueOrNull degrades to null (no spinner hang).
    final adherenceAsync = ref.watch(aggregateAdherenceProvider);
    final adherenceValue = adherenceAsync.valueOrNull;
    final adherenceLabel = adherenceValue == null
        ? l10n.dashboardAdherenceRingPlaceholder // "--"
        : l10n.dashboardAdherenceValue(adherenceValue.round());

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
            value: adherenceLabel,
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
    final local = appointment.startsAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '$hh:$mm',
              style: TextStyle(
                color: palette.accent,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
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
/// Watches [inactivosProvider] for the list of inactive athlete IDs and the
/// total sharing count. Resolves each athlete's display name via
/// [userPublicProfileProvider] (same per-id pattern used in _VencimientoRow).
///
/// Loading: renders the section header without a spinner (avoids perpetual
/// pumpAndSettle hang in CI). Empty state: "Sin alumnos inactivos".
/// Disclaimer: "N de M con datos compartidos" always shown when totalSharingCount > 0.
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
                  if (result.totalSharingCount > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      l10n.dashboardInactivosSharingNote(
                        result.totalSharingCount,
                        result.totalSharingCount,
                      ),
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
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
