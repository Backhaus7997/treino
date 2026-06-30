// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR1 — Ver turnos (read-only agenda viewer).
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/appointment.dart';
import 'agenda_web_helpers.dart';

// ─── AgendaWebCalendar ────────────────────────────────────────────────────────

/// Calendario semanal/mensual con dots en días con turnos confirmados.
///
/// Port de _TrainerCalendar (trainer_agenda_tab.dart:191-341) adaptado al
/// idioma web. Sin AppL10n — strings hardcodeadas en español (C-6).
/// Dots: solo días confirmados Y no pasados (igual que mobile).
class AgendaWebCalendar extends ConsumerWidget {
  const AgendaWebCalendar({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.trainerId,
    required this.rangeFrom,
    required this.rangeTo,
    required this.calendarFormat,
    required this.onFormatChanged,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final String trainerId;
  final DateTime rangeFrom;
  final DateTime rangeTo;
  final CalendarFormat calendarFormat;
  final void Function(CalendarFormat) onFormatChanged;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(DateTime) onPageChanged;

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
    final appointments = apptAsync.valueOrNull ?? const <Appointment>[];

    // Días con turnos confirmados (sin pasados).
    final bookedDays = <DateTime>{};
    for (final appt in appointments) {
      if (appt.status == AppointmentStatus.confirmed &&
          !isDayPast(appt.startsAt)) {
        final d = appt.startsAt;
        bookedDays.add(DateTime(d.year, d.month, d.day));
      }
    }

    bool hasActivity(DateTime day) =>
        bookedDays.contains(DateTime(day.year, day.month, day.day));

    return TableCalendar<dynamic>(
      locale: 'es', // i18n
      firstDay: DateTime.utc(2026, 1, 1),
      lastDay: DateTime.utc(2027, 12, 31),
      focusedDay: focusedDay,
      selectedDayPredicate: (d) =>
          selectedDay != null && isSameDay(selectedDay, d),
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      calendarFormat: calendarFormat,
      onFormatChanged: onFormatChanged,
      availableCalendarFormats: const {
        CalendarFormat.month: 'Mes', // i18n
        CalendarFormat.week: 'Semana', // i18n
      },
      eventLoader: (day) => (hasActivity(day) && !isDayPast(day)) ? [null] : [],
      calendarBuilders: CalendarBuilders<dynamic>(
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return null;
          return Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.highlight,
              ),
            ),
          );
        },
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        todayDecoration: BoxDecoration(
          color: palette.accent.withAlpha(60),
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
        ),
        markerDecoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
        ),
        defaultTextStyle: GoogleFonts.barlow(color: palette.textPrimary),
        weekendTextStyle: GoogleFonts.barlow(color: palette.textMuted),
        outsideTextStyle: GoogleFonts.barlow(color: palette.textMuted),
        todayTextStyle: GoogleFonts.barlow(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        selectedTextStyle: GoogleFonts.barlow(
          color: palette.bg,
          fontWeight: FontWeight.w700,
        ),
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: true,
        formatButtonShowsNext: true,
        titleCentered: false,
        formatButtonPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        formatButtonTextStyle: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.5,
          color: palette.accent,
        ),
        formatButtonDecoration: BoxDecoration(
          border: Border.all(color: palette.accent),
          borderRadius: BorderRadius.circular(9999),
        ),
        titleTextStyle: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: palette.textPrimary,
        ),
        leftChevronIcon: Icon(TreinoIcon.back, color: palette.textPrimary),
        rightChevronIcon: Icon(TreinoIcon.forward, color: palette.textPrimary),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: GoogleFonts.barlowCondensed(
          color: palette.textMuted,
          fontSize: 12,
        ),
        weekendStyle: GoogleFonts.barlowCondensed(
          color: palette.textMuted,
          fontSize: 12,
        ),
      ),
    );
  }
}
