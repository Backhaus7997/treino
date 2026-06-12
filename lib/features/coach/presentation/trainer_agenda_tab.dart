import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/agenda_providers.dart';
import '../domain/appointment.dart';
import 'widgets/day_timeline.dart';
import 'widgets/new_session_sheet.dart';

/// Trainer-side AGENDA sub-tab inside TrainerCoachView.
///
/// Trainer can:
/// - See their availability rules summary + navigate to availability editor
/// - View a monthly calendar with dots on days that have bookings
/// - See the selected day's sessions inline as a [DayTimeline] below the calendar
/// - Tap a block in the timeline → [SessionDetailSheet]
/// - Tap empty area in the timeline → [NewSessionSheet] prefilled with that time
///
/// SCENARIO-512: replaces _SubTabPlaceholder at index 2 of TabBarView
/// SCENARIO-513: empty state when no rules configured (calendar + timeline still shown)
/// SCENARIO-514: calendar with booking dots when rules exist
/// SCENARIO-515: tap on day → updates [DayTimeline] (inline, no bottom sheet)
/// SCENARIO-516: booked slot shows athlete name
class TrainerAgendaTab extends ConsumerStatefulWidget {
  const TrainerAgendaTab({super.key, required this.trainerId});

  final String trainerId;

  @override
  ConsumerState<TrainerAgendaTab> createState() => _TrainerAgendaTabState();
}

class _TrainerAgendaTabState extends ConsumerState<TrainerAgendaTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Default to the compact WEEK view so the day timeline below gets most of
  // the screen. The trainer can expand to month with the header toggle.
  CalendarFormat _calendarFormat = CalendarFormat.week;

  // Rolling 12-month window for overrides + appointments stream.
  late DateTime _rangeFrom;
  late DateTime _rangeTo;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _rangeFrom =
        DateTime.utc(now.year, now.month - 1 < 1 ? 1 : now.month - 1, 1);
    _rangeTo = DateTime.utc(now.year + 1, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final selectedDay = _selectedDay ?? DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Fixed header area (non-scrolling) ─────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Nueva sesión CTA ────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openNewSessionSheet(context),
                  icon: const Icon(TreinoIcon.plus, size: 16),
                  label: Text(
                    'NUEVA SESIÓN',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.8,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Calendar ────────────────────────────────────────────────────
              _TrainerCalendar(
                focusedDay: _focusedDay,
                selectedDay: _selectedDay,
                trainerId: widget.trainerId,
                rangeFrom: _rangeFrom,
                rangeTo: _rangeTo,
                calendarFormat: _calendarFormat,
                onFormatChanged: (f) => setState(() => _calendarFormat = f),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
                onPageChanged: (focused) =>
                    setState(() => _focusedDay = focused),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // ── Timeline (scrollable, fills remaining space) ─────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: DayTimeline(
              trainerId: widget.trainerId,
              day: selectedDay,
              rangeFrom: _rangeFrom,
              rangeTo: _rangeTo,
            ),
          ),
        ),
      ],
    );
  }

  void _openNewSessionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const NewSessionSheet(),
    );
  }
}

// ── Calendar widget ───────────────────────────────────────────────────────────

/// Whether [day] is strictly before today (date-level, local TZ).
bool _isDayPast(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTime(day.year, day.month, day.day).isBefore(today);
}

class _TrainerCalendar extends ConsumerWidget {
  const _TrainerCalendar({
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

    // Days that have confirmed bookings — used for dots.
    final bookedDays = <DateTime>{};
    for (final appt in appointments) {
      if (appt.status == AppointmentStatus.confirmed) {
        // startsAt is a wall-clock UTC value per ADR-7; no toLocal() needed
        // (would shift the calendar dot to the wrong day in AR TZ).
        final d = appt.startsAt;
        bookedDays.add(DateTime(d.year, d.month, d.day));
      }
    }

    // A day is marked when it has at least one confirmed session.
    bool hasActivity(DateTime day) =>
        bookedDays.contains(DateTime(day.year, day.month, day.day));

    return TableCalendar<dynamic>(
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
        CalendarFormat.month: 'Mes',
        CalendarFormat.week: 'Semana',
      },
      // No dots on past days — availability there is moot and a dot reads as
      // "bookable". Today keeps its dot.
      eventLoader: (day) =>
          (hasActivity(day) && !_isDayPast(day)) ? [null] : [],
      calendarBuilders: CalendarBuilders<dynamic>(
        // Magenta dot on days with ≥1 session (matches the reserved colour).
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
