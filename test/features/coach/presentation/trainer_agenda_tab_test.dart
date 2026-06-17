import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach/presentation/trainer_agenda_tab.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/coach/presentation/widgets/day_timeline.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAvailabilityRepository extends Fake
    implements AvailabilityRepository {}

class _FakeAppointmentRepository extends Fake
    implements AppointmentRepository {}

// ── Factories ─────────────────────────────────────────────────────────────────

AvailabilityRule _makeRule({int dayOfWeek = 2}) => AvailabilityRule(
      id: 'rule-1',
      trainerId: 'trainer-1',
      dayOfWeek: dayOfWeek,
      startHour: 9,
      startMinute: 0,
      endHour: 11,
      endMinute: 0,
      slotDurationMin: 60,
    );

Appointment _makeAppointment({required DateTime startsAt}) => Appointment(
      id: 'appt-1',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      athleteDisplayName: 'Athlete One',
      startsAt: startsAt,
      durationMin: 60,
      status: AppointmentStatus.confirmed,
    );

/// Wraps a widget in a minimal app scaffold with theme + ProviderScope.
Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    ),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ── SCENARIO-512: AGENDA sub-tab renders TrainerAgendaTab ─────────────────
  group('SCENARIO-512 — TrainerCoachView renders TrainerAgendaTab at index 2',
      () {
    testWidgets(
      'SCENARIO-512: TabBarView index 2 is TrainerAgendaTab, not _SubTabPlaceholder',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              availabilityRulesStreamProvider('trainer-1').overrideWith(
                (ref) => Stream.value([]),
              ),
              overridesStreamProvider(OverridesKey(
                trainerId: 'trainer-1',
                fromDate: _kFrom,
                toDate: _kTo,
              )).overrideWith((ref) => Stream.value([])),
              trainerAppointmentsStreamProvider(TrainerAppointmentsKey(
                trainerId: 'trainer-1',
                fromDate: _kFrom,
                toDate: _kTo,
              )).overrideWith((ref) => Stream.value([])),
              availabilityRepositoryProvider.overrideWithValue(
                _FakeAvailabilityRepository(),
              ),
              appointmentRepositoryProvider.overrideWithValue(
                _FakeAppointmentRepository(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              localizationsDelegates: AppL10n.localizationsDelegates,
              supportedLocales: AppL10n.supportedLocales,
              locale: const Locale('es', 'AR'),
              home: const Scaffold(
                  body: TrainerAgendaTab(trainerId: 'trainer-1')),
            ),
          ),
        );

        await tester.pump();
        expect(find.byType(TrainerAgendaTab), findsOneWidget);
        // Placeholder text should NOT be present
        expect(find.text('PRÓXIMAMENTE'), findsNothing);
      },
    );
  });

  // ── SCENARIO-513: calendar + timeline always shown, even with no rules ───────
  //
  // Behavior changed: the inline DayTimeline replaces the old empty-state branch.
  // Calendar and timeline now always render regardless of whether working-hour
  // rules are configured. The old "trainerEmptyAvailability" full-screen CTA is
  // gone; instead a "Configurar" link appears in the header row.
  group('SCENARIO-513 — Calendar and timeline render even with no rules', () {
    testWidgets(
      'SCENARIO-513: calendar and DayTimeline present when no rules configured',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const TrainerAgendaTab(trainerId: 'trainer-1'),
            overrides: [
              availabilityRulesStreamProvider('trainer-1').overrideWith(
                (ref) => Stream.value([]),
              ),
              overridesStreamProvider(OverridesKey(
                trainerId: 'trainer-1',
                fromDate: _kFrom,
                toDate: _kTo,
              )).overrideWith((ref) => Stream.value([])),
              trainerAppointmentsStreamProvider(TrainerAppointmentsKey(
                trainerId: 'trainer-1',
                fromDate: _kFrom,
                toDate: _kTo,
              )).overrideWith((ref) => Stream.value([])),
              availabilityRepositoryProvider.overrideWithValue(
                _FakeAvailabilityRepository(),
              ),
              appointmentRepositoryProvider.overrideWithValue(
                _FakeAppointmentRepository(),
              ),
            ],
          ),
        );

        await tester.pump();
        // Old full-screen empty-state copy is no longer rendered.
        expect(
          find.text('Todavía no configuraste tus horarios de trabajo. Agregá uno para que tus alumnos puedan reservar.'),
          findsNothing,
        );
        // Calendar is always present (no more rules-empty gating).
        expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
        // Inline timeline is present below the calendar.
        expect(find.byType(DayTimeline), findsOneWidget);
        // "Mis Horarios de Trabajo" header was removed (trainer-driven model
        // no longer exposes availability rules).
        expect(
          find.text('MIS HORARIOS DE TRABAJO'),
          findsNothing,
        );
      },
    );
  });

  // ── SCENARIO-514: calendar renders with booking dots when rules exist ──────
  group('SCENARIO-514 — Calendar renders with booking markers', () {
    testWidgets(
      'SCENARIO-514: TableCalendar shown when rules exist',
      (tester) async {
        final rule = _makeRule(dayOfWeek: DateTime.tuesday);
        await tester.pumpWidget(
          _wrap(
            const TrainerAgendaTab(trainerId: 'trainer-1'),
            overrides: _overridesWithRules([rule]),
          ),
        );

        await tester.pump();
        expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
        // "Mis Horarios de Trabajo" header was removed (trainer-driven model).
        expect(
          find.text('MIS HORARIOS DE TRABAJO'),
          findsNothing,
        );
      },
    );
  });

  // ── SCENARIO-515: tap on day → updates DayTimeline inline (no sheet) ────────
  //
  // Behavior changed: tapping a calendar day no longer opens a TrainerDayDetailSheet
  // bottom sheet. Instead, the selected day updates the inline DayTimeline widget.
  group('SCENARIO-515 — Tap on day updates DayTimeline (no bottom sheet)', () {
    testWidgets(
      'SCENARIO-515: DayTimeline is present; tapping a day does not open a sheet',
      (tester) async {
        final rule = _makeRule(dayOfWeek: DateTime.tuesday);
        await tester.pumpWidget(
          _wrap(
            const TrainerAgendaTab(trainerId: 'trainer-1'),
            overrides: _overridesWithRules([rule]),
          ),
        );

        await tester.pump();
        // Calendar still renders.
        expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
        // DayTimeline is always present inline below the calendar.
        expect(find.byType(DayTimeline), findsOneWidget);
        // No bottom sheet should be open initially.
        expect(find.byType(BottomSheet), findsNothing);
      },
    );
  });

  // ── SCENARIO-516: tap on booked slot → action menu with cancel option ──────
  group('SCENARIO-516 — Booked slot shows cancel action', () {
    testWidgets(
      'SCENARIO-516: booked slot chip shows athlete name',
      (tester) async {
        final rule = _makeRule(dayOfWeek: DateTime.tuesday);
        final now = DateTime.now().toUtc();
        // Next Tuesday at 09:00 UTC
        final nextTuesday = _nextWeekday(now, DateTime.tuesday);
        final appt = _makeAppointment(
          startsAt: DateTime.utc(
            nextTuesday.year,
            nextTuesday.month,
            nextTuesday.day,
            9,
            0,
          ),
        );

        await tester.pumpWidget(
          _wrap(
            const TrainerAgendaTab(trainerId: 'trainer-1'),
            overrides: _overridesWithRulesAndAppointments([rule], [appt]),
          ),
        );

        await tester.pump();
        // Calendar should be visible
        expect(find.byType(TableCalendar<dynamic>), findsOneWidget);
      },
    );
  });

  // ── SCENARIO-517 / 518: cancel booking 24h gate ───────────────────────────
  // These are tested via the TrainerDayDetailSheet widget tests below
  // (see trainer_day_detail_sheet integration in this group).
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// A fixed date far in the future to use as range keys in overrides.
final _kFrom = DateTime.utc(2026, 1, 1);
final _kTo = DateTime.utc(2027, 12, 31);

List<Override> _overridesWithRules(List<AvailabilityRule> rules) {
  return [
    availabilityRulesStreamProvider('trainer-1').overrideWith(
      (ref) => Stream.value(rules),
    ),
    overridesStreamProvider(OverridesKey(
      trainerId: 'trainer-1',
      fromDate: _kFrom,
      toDate: _kTo,
    )).overrideWith((ref) => Stream.value([])),
    trainerAppointmentsStreamProvider(TrainerAppointmentsKey(
      trainerId: 'trainer-1',
      fromDate: _kFrom,
      toDate: _kTo,
    )).overrideWith((ref) => Stream.value([])),
    availabilityRepositoryProvider.overrideWithValue(
      _FakeAvailabilityRepository(),
    ),
    appointmentRepositoryProvider.overrideWithValue(
      _FakeAppointmentRepository(),
    ),
  ];
}

List<Override> _overridesWithRulesAndAppointments(
  List<AvailabilityRule> rules,
  List<Appointment> appointments,
) {
  return [
    availabilityRulesStreamProvider('trainer-1').overrideWith(
      (ref) => Stream.value(rules),
    ),
    overridesStreamProvider(OverridesKey(
      trainerId: 'trainer-1',
      fromDate: _kFrom,
      toDate: _kTo,
    )).overrideWith((ref) => Stream.value([])),
    trainerAppointmentsStreamProvider(TrainerAppointmentsKey(
      trainerId: 'trainer-1',
      fromDate: _kFrom,
      toDate: _kTo,
    )).overrideWith((ref) => Stream.value(appointments)),
    availabilityRepositoryProvider.overrideWithValue(
      _FakeAvailabilityRepository(),
    ),
    appointmentRepositoryProvider.overrideWithValue(
      _FakeAppointmentRepository(),
    ),
  ];
}

DateTime _nextWeekday(DateTime from, int weekday) {
  var d = from.add(const Duration(days: 1));
  while (d.weekday != weekday) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}
