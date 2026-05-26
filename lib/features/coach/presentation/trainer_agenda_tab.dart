import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../application/agenda_providers.dart';
import '../domain/appointment.dart';
import '../domain/availability_rule.dart';
import 'agenda_strings.dart';
import 'widgets/trainer_day_detail_sheet.dart';

/// Trainer-side AGENDA sub-tab inside TrainerCoachView.
///
/// Trainer can:
/// - See their availability rules summary + navigate to availability editor
/// - View a monthly calendar with dots on days that have bookings
/// - Tap any day to see a detail sheet showing all slots (free/booked/blocked)
///
/// SCENARIO-512: replaces _SubTabPlaceholder at index 2 of TabBarView
/// SCENARIO-513: empty state when no rules configured
/// SCENARIO-514: calendar with booking dots when rules exist
/// SCENARIO-515: tap on day → TrainerDayDetailSheet
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
    final rulesAsync =
        ref.watch(availabilityRulesStreamProvider(widget.trainerId));

    return rulesAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: palette.accent)),
      error: (_, __) => Center(
        child: Text(
          AgendaStrings.genericError,
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
        ),
      ),
      data: (rules) => _body(context, palette, rules),
    );
  }

  Widget _body(
    BuildContext context,
    AppPalette palette,
    List<AvailabilityRule> rules,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        // ── Header row ────────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text(
                AgendaStrings.myWorkingHoursHeading,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
            ),
            if (rules.isNotEmpty)
              TextButton(
                onPressed: () => context.push(
                    '/coach/availability-editor?trainerId=${widget.trainerId}'),
                child: Text(
                  'Editar',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: palette.accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Empty state ────────────────────────────────────────────────────────
        if (rules.isEmpty) ...[
          const SizedBox(height: 32),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                AgendaStrings.trainerEmptyAvailability,
                style: GoogleFonts.barlow(
                  fontSize: 15,
                  color: palette.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton(
              onPressed: () => context.push(
                  '/coach/availability-editor?trainerId=${widget.trainerId}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                minimumSize: const Size(200, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: Text(
                AgendaStrings.configureHoursCta,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ] else ...[
          // ── Calendar ─────────────────────────────────────────────────────────
          _TrainerCalendar(
            focusedDay: _focusedDay,
            selectedDay: _selectedDay,
            trainerId: widget.trainerId,
            rules: rules,
            rangeFrom: _rangeFrom,
            rangeTo: _rangeTo,
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
              _openDaySheet(context, selected);
            },
            onPageChanged: (focused) => setState(() => _focusedDay = focused),
          ),
        ],
      ],
    );
  }

  void _openDaySheet(BuildContext context, DateTime day) {
    final normalized = DateTime.utc(day.year, day.month, day.day);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TrainerDayDetailSheet(
        trainerId: widget.trainerId,
        day: normalized,
        rangeFrom: _rangeFrom,
        rangeTo: _rangeTo,
      ),
    );
  }
}

// ── Calendar widget ───────────────────────────────────────────────────────────

class _TrainerCalendar extends ConsumerWidget {
  const _TrainerCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.trainerId,
    required this.rules,
    required this.rangeFrom,
    required this.rangeTo,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final String trainerId;
  final List<AvailabilityRule> rules;
  final DateTime rangeFrom;
  final DateTime rangeTo;
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
        final d = appt.startsAt.toLocal();
        bookedDays.add(DateTime(d.year, d.month, d.day));
      }
    }

    // Days that have rules (day-of-week based).
    final ruleDays = rules.map((r) => r.dayOfWeek).toSet();

    bool hasActivity(DateTime day) =>
        ruleDays.contains(day.weekday) ||
        bookedDays.contains(
          DateTime(day.year, day.month, day.day),
        );

    return TableCalendar<dynamic>(
      firstDay: DateTime.utc(2026, 1, 1),
      lastDay: DateTime.utc(2027, 12, 31),
      focusedDay: focusedDay,
      selectedDayPredicate: (d) =>
          selectedDay != null && isSameDay(selectedDay, d),
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      calendarFormat: CalendarFormat.month,
      eventLoader: (day) => hasActivity(day) ? [null] : [],
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
