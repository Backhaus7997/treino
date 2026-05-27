import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/session_providers.dart' show currentUidProvider;
import '../application/agenda_providers.dart';
import '../application/trainer_link_providers.dart';
import '../domain/appointment.dart';
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      physics: const ClampingScrollPhysics(),
      children: [
        const _DashboardHeader(),
        const SizedBox(height: 18),
        const _SolicitudesPendientesSection(),
        const _ResumenDelDiaCard(),
        const SizedBox(height: 20),
        _SectionHeader(
          label: 'PRÓXIMAS SESIONES',
          trailingLabel: 'Agenda',
          trailingOnTap: () => context.go('/coach?tab=agenda'),
        ),
        const SizedBox(height: 8),
        const _ProximasSesionesList(),
        const SizedBox(height: 20),
        const _SectionHeader(
          label: 'ENTRENARON HOY',
          trailingLabel: 'Dejar feedback',
        ),
        const SizedBox(height: 8),
        _PlaceholderCard(
          palette: palette,
          message: 'Próximamente.',
        ),
        const SizedBox(height: 20),
        const _SectionHeader(
          label: 'ACTIVIDAD RECIENTE',
        ),
        const SizedBox(height: 8),
        _PlaceholderCard(
          palette: palette,
          message: 'Próximamente.',
        ),
        const SizedBox(height: 20),
        const _SectionHeader(
          label: 'PAGOS POR COBRAR',
          trailingLabel: 'Ver',
        ),
        const SizedBox(height: 8),
        _PlaceholderCard(
          palette: palette,
          message: 'Próximamente.',
        ),
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
                firstName.isEmpty
                    ? 'HOLA'
                    : 'HOLA, ${firstName.toUpperCase()}',
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
                  onPressed: () => ref
                      .read(trainerLinkRepositoryProvider)
                      .decline(link.id),
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
                  onPressed: () => ref
                      .read(trainerLinkRepositoryProvider)
                      .accept(link.id),
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
        : ref.watch(trainerAppointmentsStreamProvider(_appointmentsKey(trainerId)));

    final all = apptAsync.valueOrNull ?? const <Appointment>[];
    final now = DateTime.now().toUtc();
    final todayAppts = all.where((a) => _isSameLocalDay(a.startsAt, now)).toList();
    final pending = todayAppts
        .where((a) =>
            a.status == AppointmentStatus.confirmed && a.startsAt.isAfter(now))
        .length;
    final done = todayAppts
        .where((a) =>
            a.status == AppointmentStatus.confirmed && !a.startsAt.isAfter(now))
        .length;
    final cancelled = todayAppts
        .where((a) => a.status == AppointmentStatus.cancelled)
        .length;

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
            'RESUMEN DEL DÍA',
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
                label: 'PENDIENTES',
                color: palette.accent,
                palette: palette,
              ),
              _Divider(palette: palette),
              _StatColumn(
                value: '$done',
                label: 'COMPLETADAS',
                color: palette.textPrimary,
                palette: palette,
              ),
              _Divider(palette: palette),
              _StatColumn(
                value: '$cancelled',
                label: 'CANCELADAS',
                color: palette.highlight,
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
      return _PlaceholderCard(palette: palette, message: 'Iniciá sesión para ver tus próximos turnos.');
    }
    final apptAsync =
        ref.watch(trainerAppointmentsStreamProvider(_appointmentsKey(trainerId)));

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
    final athleteName = profileAsync.valueOrNull?.displayName ??
        appointment.athleteDisplayName;
    final showName = _looksLikeUid(athleteName) ? 'Alumno' : athleteName;
    final initials = _initials(showName);

    return InkWell(
      onTap: () => context.push('/coach/athlete/${appointment.athleteId}'),
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
                    _formatDateLabel(appointment.startsAt),
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
