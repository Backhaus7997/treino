import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../application/agenda_providers.dart';
import '../domain/appointment.dart';
import '../domain/wall_clock.dart';
import '../../../l10n/app_l10n.dart';
import 'agenda_formatters.dart';

/// Full-screen route for the athlete's agenda view — READ-ONLY.
///
/// The trainer now schedules all sessions; the athlete only views their own.
///
/// Reads:
/// - [appointmentsForAthleteStreamProvider] — athlete's confirmed appointments
///
/// SCENARIO-499: calendar renders with dots on days the athlete has sessions
/// SCENARIO-500: calendar renders even when athlete has no sessions
/// SCENARIO-506: past appointments drop off the upcoming list
/// SCENARIO-507: mixed list renders only upcoming sessions
/// SCENARIO-510: tapping a day opens a read-only day-sessions sheet
/// SCENARIO-511: screen renders (calendar always shown)
class AthleteAgendaScreen extends ConsumerStatefulWidget {
  const AthleteAgendaScreen({
    super.key,
    required this.trainerId,
    required this.athleteId,
  });

  final String trainerId;
  final String athleteId;

  @override
  ConsumerState<AthleteAgendaScreen> createState() =>
      _AthleteAgendaScreenState();
}

class _AthleteAgendaScreenState extends ConsumerState<AthleteAgendaScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);

    final appointmentsAsync =
        ref.watch(appointmentsForAthleteStreamProvider(widget.athleteId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.agendaScreenTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: palette.textPrimary,
          ),
        ),
      ),
      backgroundColor: palette.bg,
      body: appointmentsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
        error: (_, __) => _errorState(context, palette),
        data: (appointments) => _body(context, palette, appointments),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppPalette palette,
    List<Appointment> appointments,
  ) {
    // Only confirmed sessions matter for display purposes.
    final confirmed = appointments
        .where((a) => a.status == AppointmentStatus.confirmed)
        .toList();

    // Upcoming list: sessions that have NOT ended yet.
    // QA-COA-003: startsAt is wall-clock UTC (ADR-7); compare against wall-clock
    // "now" so sessions don't drop from "upcoming" 3h early in ART.
    final now = nowWall();
    final upcoming = confirmed
        .where((a) =>
            a.startsAt.add(Duration(minutes: a.durationMin)).isAfter(now))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ── Calendar ──────────────────────────────────────────────────────────
        _AgendaCalendar(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          appointments: confirmed,
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
            _openDaySheet(context, selected, confirmed);
          },
          onPageChanged: (focused) {
            setState(() => _focusedDay = focused);
          },
        ),

        const SizedBox(height: 24),

        // ── Upcoming sessions list ────────────────────────────────────────────
        if (upcoming.isNotEmpty) ...[
          Text(
            AppL10n.of(context).agendaUpcomingAppointmentsHeading,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          ...upcoming.map(
            (appt) => AppointmentTile(
              appointment: appt,
              now: now,
            ),
          ),
        ] else ...[
          _emptyState(context, palette),
        ],
      ],
    );
  }

  Widget _emptyState(BuildContext context, AppPalette palette) {
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            TreinoIcon.calendar,
            size: 40,
            color: palette.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.agendaNoUpcomingSessions,
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _openDaySheet(
    BuildContext context,
    DateTime day,
    List<Appointment> allConfirmed,
  ) {
    final normalizedDay = DateTime.utc(day.year, day.month, day.day);

    // Athlete's confirmed sessions on this day.
    final daySessions = allConfirmed.where((a) {
      final d = a.startsAt.toUtc();
      return d.year == normalizedDay.year &&
          d.month == normalizedDay.month &&
          d.day == normalizedDay.day;
    }).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DaySessionsSheet(
        day: day,
        sessions: daySessions,
      ),
    );
  }

  Widget _errorState(BuildContext context, AppPalette palette) => Center(
        child: Text(
          AppL10n.of(context).agendaGenericError,
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
        ),
      );
}

// ── Calendar widget ───────────────────────────────────────────────────────────

class _AgendaCalendar extends StatelessWidget {
  const _AgendaCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.appointments,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final List<Appointment> appointments;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(DateTime) onPageChanged;

  /// Whether the athlete has at least one confirmed session on [day].
  bool _hasSession(DateTime day) {
    return appointments.any((a) {
      final d = a.startsAt.toUtc();
      return d.year == day.year && d.month == day.month && d.day == day.day;
    });
  }

  /// Whether [day] is strictly before today (date-level, local TZ).
  bool _isDayPast(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(day.year, day.month, day.day).isBefore(today);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return TableCalendar<void>(
      firstDay: DateTime.utc(2026, 1, 1),
      lastDay: DateTime.utc(2027, 12, 31),
      focusedDay: focusedDay,
      selectedDayPredicate: (day) =>
          selectedDay != null && isSameDay(selectedDay, day),
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      calendarFormat: CalendarFormat.month,
      eventLoader: (day) =>
          (_hasSession(day) && !_isDayPast(day)) ? [null] : [],
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
            color: palette.textPrimary, fontWeight: FontWeight.w600),
        selectedTextStyle:
            GoogleFonts.barlow(color: palette.bg, fontWeight: FontWeight.w700),
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
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

// ── Read-only day-sessions bottom sheet ──────────────────────────────────────

/// Bottom sheet shown when the athlete taps a calendar day.
///
/// Lists the athlete's confirmed sessions for that day: time range + trainer
/// name. No booking or cancel controls. SCENARIO-510.
class _DaySessionsSheet extends ConsumerWidget {
  const _DaySessionsSheet({
    required this.day,
    required this.sessions,
  });

  final DateTime day;
  final List<Appointment> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sheet handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Date heading
          Text(
            AgendaFormatters.formatDate(
                DateTime(day.year, day.month, day.day, 12)),
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          if (sessions.isEmpty) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No tenés sesiones este día.',
                  style: GoogleFonts.barlow(
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ] else ...[
            ...sessions.map(
              (appt) => _SessionRow(appointment: appt),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Single session row inside the day sheet ───────────────────────────────────

class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerAsync =
        ref.watch(userPublicProfileProvider(appointment.trainerId));
    final trainerName = trainerAsync.valueOrNull?.displayName ?? 'Tu PF';

    final start = AgendaFormatters.formatTime(appointment.startsAt);
    final end = AgendaFormatters.formatTime(
      appointment.startsAt.add(Duration(minutes: appointment.durationMin)),
    );
    final range = '$start – $end · ${appointment.durationMin} min';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(TreinoIcon.clock, size: 18, color: palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  range,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trainerName,
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Appointment tile ──────────────────────────────────────────────────────────

/// Displays a single confirmed appointment in the upcoming list.
///
/// Read-only — no cancel control. SCENARIO-506 / 507.
class AppointmentTile extends ConsumerWidget {
  const AppointmentTile({
    super.key,
    required this.appointment,
    required this.now,
  });

  final Appointment appointment;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerAsync =
        ref.watch(userPublicProfileProvider(appointment.trainerId));
    final trainerName = trainerAsync.valueOrNull?.displayName ?? 'Tu PF';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(
            TreinoIcon.calendar,
            size: 20,
            color: palette.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AgendaFormatters.formatDate(appointment.startsAt),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AgendaFormatters.formatTime(appointment.startsAt)} · ${appointment.durationMin} min · $trainerName',
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
