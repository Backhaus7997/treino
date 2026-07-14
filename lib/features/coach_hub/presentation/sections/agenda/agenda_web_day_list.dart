// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR1 — Ver turnos (read-only agenda viewer).
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/appointment.dart';
import '../../../../coach/presentation/agenda_formatters.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import 'agenda_web_helpers.dart';
import 'appointment_detail_dialog.dart';

// ─── AgendaWebDayList ─────────────────────────────────────────────────────────

/// Lista vertical de turnos del día seleccionado.
///
/// Reemplaza DayTimeline (hour-grid) con tarjetas simples (ADR-AGW-4).
/// Filtra: status==confirmed && mismo día. Ordena por startsAt asc.
class AgendaWebDayList extends ConsumerWidget {
  const AgendaWebDayList({
    super.key,
    required this.trainerId,
    required this.selectedDay,
    required this.rangeFrom,
    required this.rangeTo,
    this.fillHeight = false,
  });

  final String trainerId;
  final DateTime selectedDay;
  final DateTime rangeFrom;
  final DateTime rangeTo;

  /// true → ListView que llena el alto (panel desktop); false → Column
  /// shrink-wrap (dentro de la columna scrolleable del layout angosto).
  final bool fillHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final apptAsync = ref.watch(
      trainerAppointmentsStreamProvider(
        TrainerAppointmentsKey(
          trainerId: trainerId,
          fromDate: rangeFrom,
          toDate: rangeTo,
        ),
      ),
    );

    return apptAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Error al cargar los turnos.', // i18n
            style: TextStyle(color: palette.textMuted),
          ),
        ),
      ),
      data: (allAppts) {
        // Filtrar: confirmados del día seleccionado.
        final dayAppts = allAppts
            .where(
              (a) =>
                  a.status == AppointmentStatus.confirmed &&
                  a.startsAt.year == selectedDay.year &&
                  a.startsAt.month == selectedDay.month &&
                  a.startsAt.day == selectedDay.day,
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

        if (dayAppts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No hay sesiones este día.', // i18n
                style: TextStyle(color: palette.textMuted),
              ),
            ),
          );
        }

        final cards = <Widget>[
          for (final appt in dayAppts)
            AppointmentCard(appointment: appt, trainerId: trainerId),
        ];
        // Panel desktop: ListView que llena el alto y scrollea.
        // Layout angosto: Column shrink-wrap dentro del scroll de la página.
        if (fillHeight) {
          return ListView(children: cards);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cards,
        );
      },
    );
  }
}

// ─── AppointmentCard ──────────────────────────────────────────────────────────

/// Tarjeta de turno: hora, nombre del alumno, duración.
/// onTap abre [AppointmentDetailDialog] (ADR-AGW-3).
class AppointmentCard extends ConsumerWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.trainerId,
  });

  final Appointment appointment;
  final String trainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final appt = appointment;

    // Nombre del alumno: profile stream → fallback a athleteDisplayName → Alumno.
    final profileAsync = ref.watch(userPublicProfileProvider(appt.athleteId));
    final rawName =
        profileAsync.valueOrNull?.displayName ?? appt.athleteDisplayName;
    final athleteName = (isRawUid(rawName) || rawName.trim().isEmpty)
        ? 'Alumno'
        : rawName; // i18n

    final timeLabel = AgendaFormatters.formatTime(appt.startsAt);
    final durationLabel = '${appt.durationMin} min'; // i18n

    return GestureDetector(
      onTap: () => _openDetail(context, ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Text(
              timeLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                athleteName,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: palette.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              durationLabel,
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
            // "Cobrado" indicator (Slice 2a — Agenda→cobro bridge). // i18n
            if (appt.paymentId != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Cobrado', // i18n
                child: Icon(
                  TreinoIcon.money,
                  size: 14,
                  color: palette.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref) {
    final now = DateTime.now().toUtc();
    final isPast = appointment.startsAt.isBefore(now);
    showDialog<void>(
      context: context,
      builder: (_) => AppointmentDetailDialog(
        appointment: appointment,
        trainerId: trainerId,
        isPast: isPast,
      ),
    );
  }
}
