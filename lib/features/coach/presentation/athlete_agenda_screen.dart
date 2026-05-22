import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/agenda_providers.dart';
import '../domain/agenda_exceptions.dart';
import '../domain/appointment.dart';
import '../domain/availability_rule.dart';
import 'agenda_strings.dart';
import 'widgets/day_slots_sheet.dart';

/// Full-screen route for the athlete's agenda view.
///
/// Reads:
/// - [availabilityRulesStreamProvider] — trainer's rules
/// - [appointmentsForAthleteStreamProvider] — athlete's booked appointments
/// - [freeSlotsProvider] — derived free slots per selected day
///
/// SCENARIO-499: calendar renders with dots on days with free slots
/// SCENARIO-500: no dots when no rules
/// SCENARIO-501-507: day sheet + booking + cancellation flows
/// SCENARIO-511: empty state when no rules
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
    final palette = AppPalette.of(context);

    final rulesAsync =
        ref.watch(availabilityRulesStreamProvider(widget.trainerId));
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
          AgendaStrings.agendaScreenTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: palette.textPrimary,
          ),
        ),
      ),
      backgroundColor: palette.bg,
      body: rulesAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
        error: (_, __) => _errorState(context, palette),
        data: (rules) => _body(context, palette, rules, appointmentsAsync),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppPalette palette,
    List<AvailabilityRule> rules,
    AsyncValue<List<Appointment>> appointmentsAsync,
  ) {
    // REQ-COACH-AGENDA-018 / SCENARIO-511: empty state when no rules
    if (rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            AgendaStrings.emptyAvailability,
            style: GoogleFonts.barlow(
              fontSize: 15,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final appointments = appointmentsAsync.valueOrNull ?? const [];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ── Calendar ──────────────────────────────────────────────────────────
        _AgendaCalendar(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          trainerId: widget.trainerId,
          rules: rules,
          appointments: appointments,
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
            _openDaySheet(context, selected, appointments);
          },
          onPageChanged: (focused) {
            setState(() => _focusedDay = focused);
          },
        ),

        const SizedBox(height: 24),

        // ── Appointments list ─────────────────────────────────────────────────
        if (appointments.isNotEmpty) ...[
          Text(
            AgendaStrings.upcomingAppointmentsHeading,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          ...appointments.map(
            (appt) => AppointmentTile(
              appointment: appt,
              now: DateTime.now().toUtc(),
              onCancel: _canCancel(appt)
                  ? () => _onCancelAppointment(context, appt)
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  bool _canCancel(Appointment appt) =>
      appt.startsAt.difference(DateTime.now().toUtc()) >
      const Duration(hours: 24);

  void _openDaySheet(
    BuildContext context,
    DateTime day,
    List<Appointment> allAppointments,
  ) {
    final now = DateTime.now().toUtc();
    final normalizedDay = DateTime.utc(day.year, day.month, day.day);

    // Free slots for this day from the derived provider
    final fromDate = normalizedDay;
    final toDate = normalizedDay.add(const Duration(days: 1));
    final key = FreeSlotsKey(
      trainerId: widget.trainerId,
      forDate: normalizedDay,
      fromDate: fromDate,
      toDate: toDate,
    );
    final slots = ref.read(freeSlotsProvider(key));

    // Athlete's own bookings on this day
    final dayBookings = allAppointments.where((a) {
      final d = a.startsAt.toUtc();
      return d.year == normalizedDay.year &&
          d.month == normalizedDay.month &&
          d.day == normalizedDay.day &&
          a.status == AppointmentStatus.confirmed;
    }).toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DaySlotsSheet(
        slots: slots,
        existingBookings: dayBookings,
        now: now,
        onBookSlot: (slot) => _onBook(context, slot),
        onCancelAppointment: (appt) => _onCancelAppointment(context, appt),
      ),
    );
  }

  Future<void> _onBook(BuildContext context, DateTime slot) async {
    final repo = ref.read(appointmentRepositoryProvider);
    try {
      await repo.book(
        trainerId: widget.trainerId,
        athleteId: widget.athleteId,
        athleteDisplayName: widget.athleteId, // caller sets display name
        startsAt: slot,
        durationMin: 60,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close sheet
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AgendaStrings.bookingSuccess)),
      );
    } on SlotAlreadyTakenException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AgendaStrings.bookingRaceError)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AgendaStrings.genericError)),
      );
    }
  }

  Future<void> _onCancelAppointment(
      BuildContext context, Appointment appt) async {
    final repo = ref.read(appointmentRepositoryProvider);
    try {
      await repo.cancel(
        appointment: appt,
        actorUid: widget.athleteId,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close sheet if open
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AgendaStrings.cancellationSuccess)),
      );
    } on CancellationTooLateException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AgendaStrings.cancellationTooLate)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AgendaStrings.genericError)),
      );
    }
  }

  Widget _errorState(BuildContext context, AppPalette palette) => Center(
        child: Text(
          AgendaStrings.genericError,
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
        ),
      );
}

// ── Calendar widget ───────────────────────────────────────────────────────────

class _AgendaCalendar extends ConsumerWidget {
  const _AgendaCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.trainerId,
    required this.rules,
    required this.appointments,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final String trainerId;
  final List<AvailabilityRule> rules;
  final List<Appointment> appointments;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(DateTime) onPageChanged;

  /// Days of week (ISO 1=Mon) that have rules.
  Set<int> get _ruleDays => rules.map((r) => r.dayOfWeek).toSet();

  bool _hasSlots(DateTime day) => _ruleDays.contains(day.weekday);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      eventLoader: (day) => _hasSlots(day) ? [null] : [],
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

// ── Appointment tile ──────────────────────────────────────────────────────────

/// Displays a single appointment in the list below the calendar.
///
/// Shows a cancel button (icon) only when [startsAt] is >24h from [now].
/// SCENARIO-508 / 509.
class AppointmentTile extends StatelessWidget {
  const AppointmentTile({
    super.key,
    required this.appointment,
    required this.now,
    required this.onCancel,
  });

  final Appointment appointment;
  final DateTime now;
  final VoidCallback? onCancel;

  bool get _canCancel =>
      appointment.startsAt.difference(now) > const Duration(hours: 24);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isCancelled = appointment.status == AppointmentStatus.cancelled;

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
            color: isCancelled ? palette.textMuted : palette.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AgendaStrings.formatDate(appointment.startsAt),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color:
                        isCancelled ? palette.textMuted : palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AgendaStrings.formatTime(appointment.startsAt),
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isCancelled)
            Text(
              'Cancelado',
              style: GoogleFonts.barlow(
                fontSize: 12,
                color: palette.textMuted,
              ),
            )
          else if (_canCancel && onCancel != null)
            IconButton(
              icon: Icon(Icons.cancel_outlined,
                  color: palette.highlight, size: 20),
              onPressed: onCancel,
              tooltip: AgendaStrings.cancellationConfirmCta,
            ),
        ],
      ),
    );
  }
}

// ── Test-only widget for SCENARIO-505 ────────────────────────────────────────

/// @visibleForTesting — rendered only in tests to trigger booking race error.
class AthleteAgendaScreenTest extends ConsumerWidget {
  const AthleteAgendaScreenTest({
    super.key,
    required this.trainerId,
    required this.athleteId,
    required this.raceSlot,
  });

  final String trainerId;
  final String athleteId;
  final DateTime raceSlot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.bg,
      body: Center(
        child: ElevatedButton(
          key: const Key('trigger-race-booking'),
          onPressed: () async {
            final repo = ref.read(appointmentRepositoryProvider);
            try {
              await repo.book(
                trainerId: trainerId,
                athleteId: athleteId,
                athleteDisplayName: 'Athlete',
                startsAt: raceSlot,
                durationMin: 60,
              );
            } on SlotAlreadyTakenException {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(AgendaStrings.bookingRaceError),
                ),
              );
            }
          },
          child: const Text('trigger'),
        ),
      ),
    );
  }
}
