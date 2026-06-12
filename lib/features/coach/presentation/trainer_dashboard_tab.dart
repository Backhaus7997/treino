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
import '../application/trained_today_provider.dart';
import '../application/trainer_link_providers.dart';
import '../domain/appointment.dart';
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
        _PlaceholderCard(
          palette: palette,
          message: 'Próximamente.',
        ),
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
          _formatHeaderDate(DateTime.now()),
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
                firstName.isEmpty ? 'HOLA' : 'HOLA, ${firstName.toUpperCase()}',
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(TreinoIcon.bell, size: 22, color: palette.textPrimary),
        if (badgeCount > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
        _SectionHeader(label: 'SOLICITUDES PENDIENTES (${pending.length})'),
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

class _PendingRequestCard extends ConsumerWidget {
  const _PendingRequestCard({required this.link});
  final TrainerLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final name = profileAsync.valueOrNull?.displayName ?? 'Alumno';
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
                  onPressed: () =>
                      ref.read(trainerLinkRepositoryProvider).decline(link.id),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.highlight, width: 1),
                    foregroundColor: palette.highlight,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    'RECHAZAR',
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
                  onPressed: () async {
                    await ref
                        .read(trainerLinkRepositoryProvider)
                        .accept(link.id);
                    ref
                        .read(analyticsServiceProvider)
                        .logLinkAccepted(linkId: link.id);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    'ACEPTAR',
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
    final todayAppts =
        all.where((a) => _isSameLocalDay(a.startsAt, now)).toList();
    final pending = todayAppts
        .where((a) =>
            a.status == AppointmentStatus.confirmed && a.startsAt.isAfter(now))
        .length;
    final done = todayAppts
        .where((a) =>
            a.status == AppointmentStatus.confirmed && !a.startsAt.isAfter(now))
        .length;
    final cancelled =
        todayAppts.where((a) => a.status == AppointmentStatus.cancelled).length;

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
    final trainerId = ref.watch(currentUidProvider) ?? '';
    if (trainerId.isEmpty) {
      return _PlaceholderCard(
          palette: palette,
          message: 'Iniciá sesión para ver tus próximos turnos.');
    }
    final apptAsync = ref
        .watch(trainerAppointmentsStreamProvider(_appointmentsKey(trainerId)));

    return apptAsync.when(
      loading: () => _PlaceholderCard(
        palette: palette,
        message: 'Cargando…',
      ),
      error: (_, __) => _PlaceholderCard(
        palette: palette,
        message: 'No pudimos cargar tus próximos turnos.',
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
            message: 'No tenés turnos próximos confirmados.',
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
    final showName = _looksLikeUid(athleteName) ? 'Alumno' : athleteName;
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
                    '${_formatDateLabel(appointment.startsAt)} · ${appointment.durationMin} min',
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
    final todayAsync = ref.watch(trainedTodayProvider);

    if (todayAsync.isLoading && !todayAsync.hasValue) {
      return _PlaceholderCard(palette: palette, message: 'Cargando…');
    }
    if (todayAsync.hasError && !todayAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: 'No pudimos cargar la actividad de hoy.',
      );
    }

    final entries = todayAsync.valueOrNull ?? const [];
    if (entries.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: 'Nadie entrenó hoy todavía.',
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
    final showName =
        rawName.isEmpty || _looksLikeUid(rawName) ? 'Alumno' : rawName;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          label: 'PAGOS POR COBRAR',
          trailingLabel: '+ Cobro',
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
    final cobrosAsync = ref.watch(pagosPorCobrarProvider);

    if (cobrosAsync.isLoading && !cobrosAsync.hasValue) {
      return _PlaceholderCard(palette: palette, message: 'Cargando…');
    }
    if (cobrosAsync.hasError && !cobrosAsync.hasValue) {
      return _PlaceholderCard(
        palette: palette,
        message: 'No pudimos cargar los cobros.',
      );
    }

    final cobros = cobrosAsync.valueOrNull ?? const [];
    if (cobros.isEmpty) {
      return _PlaceholderCard(
        palette: palette,
        message: 'Sin cobros pendientes.',
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

  static String _cadenceLabel(BillingCadence c) => switch (c) {
        BillingCadence.mensual => 'Mensual',
        BillingCadence.semanal => 'Semanal',
        BillingCadence.porSesion => 'Por sesión',
        BillingCadence.suelto => 'Suelto',
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
    final profileAsync = ref.watch(userPublicProfileProvider(cobro.athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final showName =
        rawName.isEmpty || _looksLikeUid(rawName) ? 'Alumno' : rawName;
    final initials = _initials(showName);
    final trainerId = ref.watch(currentUidProvider) ?? '';

    Future<void> onCobrado() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: palette.bgCard,
          title: Text(
            '¿Marcar como cobrado?',
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
              child:
                  Text('Cancelar', style: TextStyle(color: palette.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Cobrado', style: TextStyle(color: palette.accent)),
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
            // Derive periodKey from concept cadence
            final now2 = DateTime.now().toUtc();
            final periodKey = cobro.cadence == BillingCadence.mensual
                ? '${now2.year}-${now2.month.toString().padLeft(2, '0')}'
                : '${now2.year}-W${_isoWeekNumber(now2).toString().padLeft(2, '0')}';
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
            for (final pid in cobro.pendingPaymentIds) {
              await repo.markPaid(pid, now);
            }
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cobro registrado.')),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Error al registrar el cobro. Intentá de nuevo.')),
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
                  '${cobro.concept} · ${_cadenceLabel(cobro.cadence)}',
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
                'Cobrado',
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
            'COBRO SUELTO',
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
            'ALUMNO',
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
              'No tenés alumnos activos.',
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
            'MONTO (ARS)',
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
              hintText: 'Ej: 5000',
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
            'CONCEPTO',
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
              hintText: 'Ej: Clase de verano',
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
                      'AGREGAR COBRO',
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
    final athleteId = _selectedAthleteId;
    final amountText = _amountController.text.trim();
    final concept = _conceptController.text.trim();

    if (athleteId == null || amountText.isEmpty || concept.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completá todos los campos.')),
      );
      return;
    }

    final amount = int.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un monto válido.')),
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
          const SnackBar(content: Text('Cobro suelto agregado.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al guardar. Intentá de nuevo.')),
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
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      hint: Text(
        'Seleccioná un alumno',
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
            ? 'Alumno (${link.athleteId.substring(0, 6)})'
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
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Invitar alumno — próximamente.'),
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
              '+ INVITAR ALUMNO',
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
              '+ ASIGNAR RUTINA',
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

const _kSpanishDays = <String>[
  '',
  'LUNES',
  'MARTES',
  'MIÉRCOLES',
  'JUEVES',
  'VIERNES',
  'SÁBADO',
  'DOMINGO',
];

const _kSpanishMonths = <String>[
  '',
  'ENERO',
  'FEBRERO',
  'MARZO',
  'ABRIL',
  'MAYO',
  'JUNIO',
  'JULIO',
  'AGOSTO',
  'SEPTIEMBRE',
  'OCTUBRE',
  'NOVIEMBRE',
  'DICIEMBRE',
];

String _formatHeaderDate(DateTime dt) {
  return '${_kSpanishDays[dt.weekday]} ${dt.day} ${_kSpanishMonths[dt.month]}';
}

String _formatTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _formatDateLabel(DateTime dt) {
  final now = DateTime.now().toUtc();
  final isToday = _isSameLocalDay(dt, now);
  final isTomorrow = _isSameLocalDay(dt, now.add(const Duration(days: 1)));
  if (isToday) return 'Hoy';
  if (isTomorrow) return 'Mañana';
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

/// ISO 8601 week number (Thursday-based). Used to derive semanal periodKey
/// when marking a payment as cobrado.
int _isoWeekNumber(DateTime date) {
  final thursday = date.subtract(Duration(days: date.weekday - 4));
  final jan4 = DateTime.utc(thursday.year, 1, 4);
  final week1Monday = jan4.subtract(Duration(days: jan4.weekday - 1));
  return ((thursday.difference(week1Monday).inDays) ~/ 7) + 1;
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
