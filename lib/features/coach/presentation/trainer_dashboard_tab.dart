import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../l10n/app_l10n.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../payments/application/pagos_por_cobrar_provider.dart';
import '../../payments/application/payment_providers.dart';
import '../../payments/domain/athlete_billing.dart';
import '../../payments/domain/payment.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/agenda_providers.dart';
import '../application/dashboard_day_counts.dart';
import '../application/recent_activity_provider.dart';
import '../application/trained_today_provider.dart';
import '../application/trainer_link_providers.dart';
import '../domain/appointment.dart';

// Re-export so the mobile test (trainer_dashboard_day_counts_test.dart) that
// imports dashboardDayCounts/DashboardDayCounts from this file keeps compiling
// without modification.
export '../application/dashboard_day_counts.dart'
    show dashboardDayCounts, DashboardDayCounts;
import 'widgets/appointment_detail_sheet.dart';
import '../domain/trainer_link.dart';
import '../domain/trainer_link_status.dart';

/// Trainer "Hoy" / Dashboard sub-tab — matches docs/app-trainer/screens/dashboard.
///
/// Sections wired to real data:
///   - Header (greeting + date + avatar)
///   - Resumen del día (counts derived from today's appointments)
///   - Próximas sesiones (next 3 confirmed appointments from now)
///   - CTAs: Asignar rutina, Invitar alumno (stub for now)
///
/// Sections shown visually with placeholder until backing data exists:
///   - Entrenaron hoy (needs sessions provider scoped to trainer's athletes)
///   - Actividad reciente (same)
///   - Pagos por cobrar (no payments module yet)
class TrainerDashboardTab extends ConsumerWidget {
  const TrainerDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    return ListView(
      // Explicit padding overrides the ambient MediaQuery inset, so the
      // floating bar's height must be added back — otherwise the last row
      // (CTA buttons) can never scroll out from behind the translucent bar.
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 24 + MediaQuery.paddingOf(context).bottom),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const _DashboardHeader(),
        const SizedBox(height: 18),
        const _SolicitudesPendientesSection(),
        const _ResumenDelDiaCard(),
        const SizedBox(height: 20),
        _SectionHeader(
          label: AppL10n.of(context).dashboardProximasSesionesSectionLabel,
          trailingLabel: AppL10n.of(context).dashboardAgendaTrailingLabel,
          trailingOnTap: () => context.go('/coach?tab=agenda'),
        ),
        const SizedBox(height: 8),
        const _ProximasSesionesList(),
        const SizedBox(height: 20),
        _SectionHeader(
          label: AppL10n.of(context).dashboardEntrenaronHoySectionLabel,
          trailingLabel: AppL10n.of(context).dashboardDejarFeedbackLabel,
        ),
        const SizedBox(height: 8),
        const _EntrenaronHoyList(),
        const SizedBox(height: 20),
        _SectionHeader(
          label: AppL10n.of(context).dashboardActividadRecienteSectionLabel,
        ),
        const SizedBox(height: 8),
        const _ActividadRecienteList(),
        const SizedBox(height: 20),
        _PagosPorCobrarSection(palette: palette),
        const SizedBox(height: 20),
        const _BottomActions(),
      ],
    );
  }
}

// ── Header (greeting + date + bell + avatar) ─────────────────────────────────

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    final name = profileAsync.valueOrNull?.displayName ?? '';
    final firstName = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    final initials = _initials(name);
    final pendingCount = (linksAsync.valueOrNull ?? const [])
        .where((l) => l.status == TrainerLinkStatus.pending)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatHeaderDate(AppL10n.of(context), DateTime.now()),
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                firstName.isEmpty
                    ? AppL10n.of(context).dashboardHolaSinNombre
                    : AppL10n.of(context)
                        .dashboardHolaConNombre(firstName.toUpperCase()),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 28,
                  letterSpacing: 0.5,
                  color: palette.textPrimary,
                ),
              ),
            ),
            _BellWithBadge(badgeCount: pendingCount, palette: palette),
            const SizedBox(width: 12),
            _AvatarInitials(
              initials: initials.isEmpty ? '·' : initials,
              palette: palette,
            ),
          ],
        ),
      ],
    );
  }
}

class _BellWithBadge extends StatelessWidget {
  const _BellWithBadge({required this.badgeCount, required this.palette});
  final int badgeCount;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Semantics(
      label: l10n.homePendingRequestsA11y(badgeCount),
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(TreinoIcon.bell, size: 22, color: palette.textPrimary),
            if (badgeCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(color: palette.bg, width: 1),
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      color: palette.bg,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials({required this.initials, required this.palette});
  final String initials;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.bgCard,
        border: Border.all(color: palette.accent, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.5,
          color: palette.accent,
        ),
      ),
    );
  }
}

// ── Solicitudes pendientes (only when count > 0) ──────────────────────────────

class _SolicitudesPendientesSection extends ConsumerWidget {
  const _SolicitudesPendientesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final pending = (linksAsync.valueOrNull ?? const <TrainerLink>[])
        .where((l) => l.status == TrainerLinkStatus.pending)
        .toList();
    if (pending.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
            label: AppL10n.of(context)
                .dashboardSolicitudesPendientesTitle(pending.length)),
        const SizedBox(height: 8),
        for (final link in pending) ...[
          _PendingRequestCard(link: link),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class _PendingRequestCard extends ConsumerStatefulWidget {
  const _PendingRequestCard({required this.link});
  final TrainerLink link;

  @override
  ConsumerState<_PendingRequestCard> createState() =>
      _PendingRequestCardState();
}

class _PendingRequestCardState extends ConsumerState<_PendingRequestCard> {
  // Guards against double-submit: a fast double-tap before the stream rebuilds
  // and removes this card would otherwise fire accept/decline (and analytics)
  // twice. Stays true on success — the card is about to disappear; only resets
  // on error so the trainer can retry.
  bool _busy = false;

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(trainerLinkRepositoryProvider).decline(widget.link.id);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(trainerLinkRepositoryProvider).accept(widget.link.id);
      ref
          .read(analyticsServiceProvider)
          .logLinkAccepted(linkId: widget.link.id);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final profileAsync =
        ref.watch(userPublicProfileProvider(widget.link.athleteId));
    final name =
        profileAsync.valueOrNull?.displayName ?? l10n.dashboardAlumnoFallback;
    final initials = _initials(name);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AvatarInitials(initials: initials, palette: palette),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _decline,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.highlight, width: 1),
                    foregroundColor: palette.highlight,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    l10n.dashboardRechazarLabel,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    l10n.dashboardAceptarLabel,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Resumen del día (3 stat columns) ──────────────────────────────────────────

class _ResumenDelDiaCard extends ConsumerWidget {
  const _ResumenDelDiaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerId = ref.watch(currentUidProvider) ?? '';
    final apptAsync = trainerId.isEmpty
        ? const AsyncValue<List<Appointment>>.data(<Appointment>[])
        : ref.watch(
            trainerAppointmentsStreamProvider(_appointmentsKey(trainerId)));

    final all = apptAsync.valueOrNull ?? const <Appointment>[];
    final now = DateTime.now().toUtc();
    final counts = dashboardDayCounts(all, now);
    final pending = counts.pending;
    final done = counts.done;
    final cancelled = counts.cancelled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppL10n.of(context).dashboardResumenDelDiaTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatColumn(
                value: '$pending',
                label: AppL10n.of(context).dashboardStatPendientes,
                color: palette.accent,
                palette: palette,
              ),
              _Divider(palette: palette),
              _StatColumn(
                value: '$done',
                label: AppL10n.of(context).dashboardStatCompletadas,
                color: palette.textPrimary,
                palette: palette,
              ),
              _Divider(palette: palette),
              _StatColumn(
                value: '$cancelled',
                label: AppL10n.of(context).dashboardStatCanceladas,
                color: palette.danger,
                palette: palette,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.value,
    required this.label,
    required this.color,
    required this.palette,
  });

  final String value;
  final String label;
  final Color color;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 28,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: palette.border,
    );
  }
}

// ── Section header with optional trailing link ────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    this.trailingLabel,
    this.trailingOnTap,
  });

  final String label;
  final String? trailingLabel;
  final VoidCallback? trailingOnTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
        ),
        if (trailingLabel != null)
          GestureDetector(
            onTap: trailingOnTap,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text(
                  trailingLabel!,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: trailingOnTap == null
                        ? palette.textMuted
                        : palette.accent,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  TreinoIcon.forward,
                  size: 14,
                  color: trailingOnTap == null
                      ? palette.textMuted
                      : palette.accent,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Próximas sesiones list ────────────────────────────────────────────────────

class _ProximasSesionesList extends ConsumerWidget {
  const _ProximasSesionesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerId = ref.watch(currentUidProvider) ?? '';
    if (trainerId.isEmpty) {
      return _PlaceholderCard(
          palette: palette, message: l10n.dashboardIniciaSesion);
    }
    final apptAsync = ref
        .watch(trainerAppointmentsStreamProvider(_appointmentsKey(trainerId)));

    return apptAsync.when(
      loading: () => _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardCargando,
      ),
      error: (_, __) => _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardErrorTurnos,
      ),
      data: (all) {
        final now = DateTime.now().toUtc();
        final upcoming = all
            .where((a) =>
                a.status == AppointmentStatus.confirmed &&
                a.startsAt.isAfter(now))
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        final next3 = upcoming.take(3).toList();

        if (next3.isEmpty) {
          return _PlaceholderCard(
            palette: palette,
            message: l10n.dashboardSinTurnosProximos,
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border, width: 1),
          ),
          child: Column(
            children: [
              for (int i = 0; i < next3.length; i++) ...[
                if (i > 0)
                  Divider(
                    color: palette.border,
                    height: 1,
                    thickness: 1,
                    indent: 14,
                    endIndent: 14,
                  ),
                _ProximaSesionRow(appointment: next3[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ProximaSesionRow extends ConsumerWidget {
  const _ProximaSesionRow({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync =
        ref.watch(userPublicProfileProvider(appointment.athleteId));
    final athleteName =
        profileAsync.valueOrNull?.displayName ?? appointment.athleteDisplayName;
    final showName = _looksLikeUid(athleteName)
        ? AppL10n.of(context).dashboardAlumnoFallback
        : athleteName;
    final initials = _initials(showName);

    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        backgroundColor: AppPalette.of(context).bgCard,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => AppointmentDetailSheet(
          appointment: appointment,
          trainerId: ref.watch(currentUidProvider) ?? '',
        ),
      ),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                _formatTime(appointment.startsAt),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: palette.accent,
                ),
              ),
            ),
            _AvatarInitials(initials: initials, palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showName,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDateLabel(AppL10n.of(context), appointment.startsAt)} · ${appointment.durationMin} min',
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: palette.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(TreinoIcon.forward, size: 18, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Entrenaron hoy list ───────────────────────────────────────────────────────

class _EntrenaronHoyList extends ConsumerWidget {
  const _EntrenaronHoyList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final todayAsync = ref.watch(trainedTodayProvider);

    if (todayAsync.isLoading && !todayAsync.hasValue) {
      return _PlaceholderCard(
          palette: palette, message: l10n.dashboardCargando);
    }
    if (todayAsync.hasError && !todayAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardErrorActividad,
      );
    }

    final entries = todayAsync.valueOrNull ?? const [];
    if (entries.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardNadieEntreno,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                color: palette.border,
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
              ),
            _EntrenaronHoyRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class _EntrenaronHoyRow extends ConsumerWidget {
  const _EntrenaronHoyRow({required this.entry});
  final TrainedTodayEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(entry.athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final showName = rawName.isEmpty || _looksLikeUid(rawName)
        ? AppL10n.of(context).dashboardAlumnoFallback
        : rawName;
    final initials = _initials(showName);
    final session = entry.session;

    return InkWell(
      onTap: () => context.push('/coach/athlete/${entry.athleteId}'),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _AvatarInitials(initials: initials, palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showName,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${session.routineName} · ${_formatTime(session.finishedAt!)}',
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: palette.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${session.totalVolumeKg.toStringAsFixed(0)} kg',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Actividad reciente ────────────────────────────────────────────────────────

class _ActividadRecienteList extends ConsumerWidget {
  const _ActividadRecienteList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final activityAsync = ref.watch(recentActivityProvider);

    if (activityAsync.isLoading && !activityAsync.hasValue) {
      return _PlaceholderCard(
          palette: palette, message: l10n.dashboardCargando);
    }
    if (activityAsync.hasError && !activityAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardErrorActividad,
      );
    }

    final entries = activityAsync.valueOrNull ?? const [];
    if (entries.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardSinActividadReciente,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        children: [
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                color: palette.border,
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
              ),
            _ActividadRecienteRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class _ActividadRecienteRow extends ConsumerWidget {
  const _ActividadRecienteRow({required this.entry});
  final RecentActivityEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(entry.athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final showName = rawName.isEmpty || _looksLikeUid(rawName)
        ? AppL10n.of(context).dashboardAlumnoFallback
        : rawName;
    final initials = _initials(showName);
    final session = entry.session;

    return InkWell(
      onTap: () => context.push('/coach/athlete/${entry.athleteId}'),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _AvatarInitials(initials: initials, palette: palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showName,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Date (not time-of-day) — differentiates this rolling feed
                    // from the "Entrenaron hoy" today snapshot above.
                    '${session.routineName} · ${_formatArtDate(session.finishedAt!)}',
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: palette.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${session.totalVolumeKg.toStringAsFixed(0)} kg',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats a UTC instant as its ART calendar date, `d/M` (e.g. "15/7").
String _formatArtDate(DateTime finishedAt) {
  final art = toArgentina(finishedAt.toUtc());
  return '${art.day}/${art.month}';
}

// ── Pagos por cobrar section ──────────────────────────────────────────────────

class _PagosPorCobrarSection extends ConsumerWidget {
  const _PagosPorCobrarSection({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainerId = ref.watch(currentUidProvider);

    void openAddSueltoSheet() {
      if (trainerId == null) return;
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        backgroundColor: palette.bgCard,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _AddSueltoSheet(
          trainerId: trainerId,
        ),
      );
    }

    final l10n = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: l10n.dashboardPagosPorCobrarTitle,
          trailingLabel: l10n.dashboardCobroTrailingLabel,
          trailingOnTap: openAddSueltoSheet,
        ),
        const SizedBox(height: 8),
        const _PagosPorCobrarList(),
      ],
    );
  }
}

class _PagosPorCobrarList extends ConsumerWidget {
  const _PagosPorCobrarList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final cobrosAsync = ref.watch(pagosPorCobrarProvider);

    if (cobrosAsync.isLoading && !cobrosAsync.hasValue) {
      return _PlaceholderCard(
          palette: palette, message: l10n.dashboardCargando);
    }
    if (cobrosAsync.hasError && !cobrosAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardErrorCobros,
      );
    }

    final cobros = cobrosAsync.valueOrNull ?? const [];
    if (cobros.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: l10n.dashboardSinCobros,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        children: [
          for (int i = 0; i < cobros.length; i++) ...[
            if (i > 0)
              Divider(
                color: palette.border,
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
              ),
            _CobroPendienteRow(cobro: cobros[i]),
          ],
        ],
      ),
    );
  }
}

class _CobroPendienteRow extends ConsumerWidget {
  const _CobroPendienteRow({required this.cobro});
  final CobroPendiente cobro;

  static String _cadenceLabel(AppL10n l10n, BillingCadence c) => switch (c) {
        BillingCadence.mensual => l10n.dashboardCadenceMensual,
        BillingCadence.semanal => l10n.dashboardCadenceSemanal,
        BillingCadence.porSesion => l10n.dashboardCadencePorSesion,
        BillingCadence.suelto => l10n.dashboardCadenceSuelto,
      };

  static String _formatAmount(int amount) {
    // Thousands separator for ARS amounts
    final s = amount.toString();
    final buffer = StringBuffer();
    int offset = s.length % 3;
    if (offset > 0) buffer.write(s.substring(0, offset));
    for (int i = offset; i < s.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(cobro.athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final showName = rawName.isEmpty || _looksLikeUid(rawName)
        ? l10n.dashboardAlumnoFallback
        : rawName;
    final initials = _initials(showName);
    final trainerId = ref.watch(currentUidProvider) ?? '';

    Future<void> onCobrado() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: palette.bgCard,
          title: Text(
            l10n.dashboardMarcarCobradoTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: palette.textPrimary,
            ),
          ),
          content: Text(
            '${cobro.concept} — \$${_formatAmount(cobro.amountArs)}',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: palette.textMuted,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.dashboardCancelarLabel,
                  style: TextStyle(color: palette.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.dashboardCobradoLabel,
                  style: TextStyle(color: palette.accent)),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;

      final repo = ref.read(paymentRepositoryProvider);
      final now = DateTime.now().toUtc();

      try {
        switch (cobro.cadence) {
          case BillingCadence.mensual:
          case BillingCadence.semanal:
            // Derive periodKey in ART: the bucket identity is a calendar
            // concept and MUST match the CF (createdAt/paidAt below stay UTC).
            final now2 = argentinaNow();
            final periodKey = cobro.cadence == BillingCadence.mensual
                ? '${now2.year}-${now2.month.toString().padLeft(2, '0')}'
                : isoWeekPeriodKey(now2);
            await repo.add(Payment(
              id: '',
              trainerId: trainerId,
              athleteId: cobro.athleteId,
              amountArs: cobro.amountArs,
              concept: cobro.concept,
              status: PaymentStatus.paid,
              periodKey: periodKey,
              createdAt: now,
              paidAt: now,
            ));

          case BillingCadence.porSesion:
            await repo.add(Payment(
              id: '',
              trainerId: trainerId,
              athleteId: cobro.athleteId,
              amountArs: cobro.amountArs,
              concept: cobro.concept,
              status: PaymentStatus.paid,
              createdAt: now,
              paidAt: now,
            ));

          case BillingCadence.suelto:
            // Flip all pending one-off charges atomically: a mid-loop failure
            // (network drop / concurrently deleted doc) must not leave the
            // athlete in a half-paid state.
            await repo.markManyPaid(cobro.pendingPaymentIds, now);
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.dashboardCobroRegistrado)),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.dashboardCobroError)),
          );
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _AvatarInitials(initials: initials, palette: palette),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  showName,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: palette.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${cobro.concept} · ${_cadenceLabel(l10n, cobro.cadence)}',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\$${_formatAmount(cobro.amountArs)}',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onCobrado,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                l10n.dashboardCobradoLabel,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: palette.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Add suelto charge sheet ───────────────────────────────────────────────────

class _AddSueltoSheet extends ConsumerStatefulWidget {
  const _AddSueltoSheet({required this.trainerId});
  final String trainerId;

  @override
  ConsumerState<_AddSueltoSheet> createState() => _AddSueltoSheetState();
}

class _AddSueltoSheetState extends ConsumerState<_AddSueltoSheet> {
  String? _selectedAthleteId;
  final _amountController = TextEditingController();
  final _conceptController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _conceptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final activeLinks = (linksAsync.valueOrNull ?? const [])
        .where((l) => l.status == TrainerLinkStatus.active)
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dashboardCobroSueltoTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          // Athlete picker
          Text(
            l10n.dashboardAlumnoLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (activeLinks.isEmpty)
            Text(
              l10n.dashboardSinAlumnosActivos,
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
              ),
            )
          else
            _AthleteDropdown(
              links: activeLinks,
              selectedId: _selectedAthleteId,
              palette: palette,
              onChanged: (id) => setState(() => _selectedAthleteId = id),
            ),
          const SizedBox(height: 14),
          Text(
            l10n.dashboardMontoArsLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: palette.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: l10n.dashboardMontoHint,
              hintStyle: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
              filled: true,
              fillColor: palette.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.dashboardConceptoLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _conceptController,
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: palette.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: l10n.dashboardConceptoHint,
              hintStyle: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
              filled: true,
              fillColor: palette.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving || activeLinks.isEmpty ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                disabledBackgroundColor: palette.border,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: palette.bg,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      l10n.dashboardAgregarCobroLabel,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = AppL10n.of(context);
    final athleteId = _selectedAthleteId;
    final amountText = _amountController.text.trim();
    final concept = _conceptController.text.trim();

    if (athleteId == null || amountText.isEmpty || concept.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dashboardCompletaCampos)),
      );
      return;
    }

    final amount = int.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dashboardMontoInvalido)),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now().toUtc();
      await ref.read(paymentRepositoryProvider).add(Payment(
            id: '',
            trainerId: widget.trainerId,
            athleteId: athleteId,
            amountArs: amount,
            concept: concept,
            status: PaymentStatus.pending,
            createdAt: now,
          ));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.dashboardCobroSueltoAgregado)),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.dashboardGuardarError)),
        );
      }
    }
  }
}

/// Dropdown widget to pick an active athlete by name.
class _AthleteDropdown extends ConsumerWidget {
  const _AthleteDropdown({
    required this.links,
    required this.selectedId,
    required this.palette,
    required this.onChanged,
  });

  final List<TrainerLink> links;
  final String? selectedId;
  final AppPalette palette;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      hint: Text(
        l10n.dashboardSeleccionaAlumnoHint,
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
      ),
      dropdownColor: palette.bgCard,
      style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
      decoration: InputDecoration(
        filled: true,
        fillColor: palette.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
      items: links.map((link) {
        final profileAsync =
            ref.watch(userPublicProfileProvider(link.athleteId));
        final rawName = profileAsync.valueOrNull?.displayName ?? '';
        final showName = rawName.isEmpty || _looksLikeUid(rawName)
            ? '${l10n.dashboardAlumnoFallback} (${link.athleteId.substring(0, 6)})'
            : rawName;
        return DropdownMenuItem<String>(
          value: link.athleteId,
          child: Text(showName),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

// ── Placeholder card (for sections not yet wired) ─────────────────────────────

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.palette, required this.message});
  final AppPalette palette;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Text(
        message,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

// ── Bottom actions (Invitar / Asignar) ────────────────────────────────────────

class _BottomActions extends StatelessWidget {
  const _BottomActions();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.dashboardInvitarProximamente),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: palette.border, width: 1),
              foregroundColor: palette.textPrimary,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9999),
              ),
            ),
            child: Text(
              l10n.dashboardInvitarAlumnoLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () => context.go('/coach?tab=alumnos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.bg,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9999),
              ),
            ),
            child: Text(
              l10n.dashboardAsignarRutinaLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _weekdayName(AppL10n l10n, int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return l10n.dashboardWeekday1;
    case DateTime.tuesday:
      return l10n.dashboardWeekday2;
    case DateTime.wednesday:
      return l10n.dashboardWeekday3;
    case DateTime.thursday:
      return l10n.dashboardWeekday4;
    case DateTime.friday:
      return l10n.dashboardWeekday5;
    case DateTime.saturday:
      return l10n.dashboardWeekday6;
    default:
      return l10n.dashboardWeekday7;
  }
}

String _monthName(AppL10n l10n, int month) {
  switch (month) {
    case 1:
      return l10n.dashboardMonth1;
    case 2:
      return l10n.dashboardMonth2;
    case 3:
      return l10n.dashboardMonth3;
    case 4:
      return l10n.dashboardMonth4;
    case 5:
      return l10n.dashboardMonth5;
    case 6:
      return l10n.dashboardMonth6;
    case 7:
      return l10n.dashboardMonth7;
    case 8:
      return l10n.dashboardMonth8;
    case 9:
      return l10n.dashboardMonth9;
    case 10:
      return l10n.dashboardMonth10;
    case 11:
      return l10n.dashboardMonth11;
    default:
      return l10n.dashboardMonth12;
  }
}

String _formatHeaderDate(AppL10n l10n, DateTime dt) {
  return '${_weekdayName(l10n, dt.weekday)} ${dt.day} ${_monthName(l10n, dt.month)}';
}

String _formatTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _formatDateLabel(AppL10n l10n, DateTime dt) {
  final now = DateTime.now().toUtc();
  final isToday = _isSameLocalDay(dt, now);
  final isTomorrow = _isSameLocalDay(dt, now.add(const Duration(days: 1)));
  if (isToday) return l10n.dashboardDateToday;
  if (isTomorrow) return l10n.dashboardDateTomorrow;
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  return '$dd/$mm';
}

bool _isSameLocalDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _initials(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '·';
  final parts = clean.split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  if (parts[0].length >= 2) {
    return parts[0].substring(0, 2).toUpperCase();
  }
  return parts[0].toUpperCase();
}

/// Heuristic to detect a UID stored in athleteDisplayName from pre-backfill
/// bookings — used as last-resort fallback in the row to avoid displaying
/// the raw UID. The proper fix is the live Firestore stream (see
/// trainer_day_detail_sheet.dart).
bool _looksLikeUid(String s) {
  if (s.length < 20) return false;
  // Firebase UIDs are 28-char alphanumeric. If it contains no spaces and is
  // long + mostly alphanumeric, treat as UID.
  if (s.contains(' ')) return false;
  final alphaNumeric = RegExp(r'^[a-zA-Z0-9]+$');
  return alphaNumeric.hasMatch(s);
}

TrainerAppointmentsKey _appointmentsKey(String trainerId) {
  final now = DateTime.now().toUtc();
  final from = DateTime.utc(now.year, now.month - 1 < 1 ? 1 : now.month - 1, 1);
  final to = DateTime.utc(now.year + 1, now.month, 1);
  return TrainerAppointmentsKey(
    trainerId: trainerId,
    fromDate: from,
    toDate: to,
  );
}
