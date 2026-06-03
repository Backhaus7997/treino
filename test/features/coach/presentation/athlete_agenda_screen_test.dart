import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach/presentation/agenda_strings.dart';
import 'package:treino/features/coach/presentation/athlete_agenda_screen.dart';
import 'package:treino/features/coach/presentation/widgets/day_slots_sheet.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';

// ─── Factories ────────────────────────────────────────────────────────────────

TrainerLink _makeLink({
  TrainerLinkStatus status = TrainerLinkStatus.active,
  String trainerId = 'trainer-1',
  String athleteId = 'athlete-1',
}) =>
    TrainerLink(
      id: 'link-1',
      trainerId: trainerId,
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 5, 18, 10, 0),
      acceptedAt: status == TrainerLinkStatus.active
          ? DateTime.utc(2026, 5, 18, 12, 0)
          : null,
      sharedWithTrainer: false,
    );

Appointment _makeAppointment({
  required DateTime startsAt,
  AppointmentStatus status = AppointmentStatus.confirmed,
  String id = 'appt-1',
}) =>
    Appointment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      athleteDisplayName: 'Athlete One',
      startsAt: startsAt,
      durationMin: 60,
      status: status,
    );

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

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // NOTE: SCENARIO-497 / 498 (VER AGENDA button visibility in AthleteCoachView)
  // were drafted here but moved out — they belong in athlete_coach_view_test.dart
  // because they test the entry-point button inside _LinkStateCard, not the
  // agenda screen itself.

  // ── SCENARIO-511: Calendar always renders (read-only screen has no empty state) ──

  group('SCENARIO-511 — Calendar renders (no empty state)', () {
    testWidgets(
      'SCENARIO-511: calendar shown even when athlete has no appointments',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentAthleteLinkProvider
                  .overrideWith((ref) async => _makeLink()),
              appointmentsForAthleteStreamProvider('athlete-1').overrideWith(
                (ref) => Stream.value([]),
              ),
              userPublicProfileProvider('trainer-1')
                  .overrideWith((ref) => Stream.value(null)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const AthleteAgendaScreen(
                trainerId: 'trainer-1',
                athleteId: 'athlete-1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The read-only screen always shows the calendar.
        expect(find.byType(TableCalendar<void>), findsOneWidget);
        // The old "trainer has no availability" empty state is no longer shown.
        expect(find.text(AgendaStrings.emptyAvailability), findsNothing);
      },
    );
  });

  // ── SCENARIO-499 / 500: Calendar renders when rules exist ────────────────────
  //
  // NOTE: The calendar no longer uses availabilityRulesStreamProvider for dot
  // logic. Dots now reflect the athlete's own confirmed sessions. The test
  // verifies the calendar always renders; dot behaviour is covered separately.

  group('SCENARIO-499 / SCENARIO-500 — Calendar renders', () {
    testWidgets(
      'SCENARIO-499 / 500: calendar renders with or without appointments',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentAthleteLinkProvider
                  .overrideWith((ref) async => _makeLink()),
              appointmentsForAthleteStreamProvider('athlete-1').overrideWith(
                (ref) => Stream.value([]),
              ),
              userPublicProfileProvider('trainer-1')
                  .overrideWith((ref) => Stream.value(null)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const AthleteAgendaScreen(
                trainerId: 'trainer-1',
                athleteId: 'athlete-1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Calendar is shown
        expect(find.byType(TableCalendar<void>), findsOneWidget);
        // Old availability-empty-state not shown
        expect(find.text(AgendaStrings.emptyAvailability), findsNothing);
      },
    );
  });

  // ── SCENARIO-506 / 507: Past appointments drop off the upcoming list ──────────
  //
  // A session drops off the moment it ends (startsAt + durationMin < now).

  group('SCENARIO-506 / 507 — Past appointments drop off the list', () {
    testWidgets(
      'SCENARIO-506: past-only → no tiles and the heading is hidden',
      (tester) async {
        // Use a tall viewport so the lazy ListView builds all appointment tiles.
        tester.view.physicalSize = const Size(800, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final now = DateTime.now().toUtc();

        // Round to minute precision (ADR-7)
        DateTime rnd(DateTime d) =>
            DateTime.utc(d.year, d.month, d.day, d.hour, d.minute);

        // All three sessions already ended (days ago).
        final appointments = [
          _makeAppointment(
              startsAt: rnd(now.subtract(const Duration(days: 3))), id: 'a1'),
          _makeAppointment(
              startsAt: rnd(now.subtract(const Duration(days: 5))), id: 'a2'),
          _makeAppointment(
              startsAt: rnd(now.subtract(const Duration(days: 7))), id: 'a3'),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentAthleteLinkProvider
                  .overrideWith((ref) async => _makeLink()),
              appointmentsForAthleteStreamProvider('athlete-1').overrideWith(
                (ref) => Stream.value(appointments),
              ),
              userPublicProfileProvider('trainer-1')
                  .overrideWith((ref) => Stream.value(null)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const AthleteAgendaScreen(
                trainerId: 'trainer-1',
                athleteId: 'athlete-1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No upcoming sessions → no tiles, and the heading is hidden.
        expect(find.byType(AppointmentTile), findsNothing);
        expect(
          find.text(AgendaStrings.upcomingAppointmentsHeading),
          findsNothing,
        );
      },
    );

    testWidgets(
      'SCENARIO-507: mixed list renders only upcoming sessions',
      (tester) async {
        // Use a tall viewport so the lazy ListView builds all appointment tiles.
        tester.view.physicalSize = const Size(800, 8000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final now = DateTime.now().toUtc();
        DateTime rnd(DateTime d) =>
            DateTime.utc(d.year, d.month, d.day, d.hour, d.minute);

        // 5 past (ended) + 3 future appointments.
        final appointments = [
          for (var i = 1; i <= 5; i++)
            _makeAppointment(
                startsAt: rnd(now.subtract(Duration(days: i))), id: 'past$i'),
          for (var i = 1; i <= 3; i++)
            _makeAppointment(
                startsAt: rnd(now.add(Duration(days: i))), id: 'future$i'),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentAthleteLinkProvider
                  .overrideWith((ref) async => _makeLink()),
              appointmentsForAthleteStreamProvider('athlete-1').overrideWith(
                (ref) => Stream.value(appointments),
              ),
              userPublicProfileProvider('trainer-1')
                  .overrideWith((ref) => Stream.value(null)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const AthleteAgendaScreen(
                trainerId: 'trainer-1',
                athleteId: 'athlete-1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Only the 3 future sessions render; the 5 past ones drop off.
        expect(find.byType(AppointmentTile), findsNWidgets(3));
        expect(
          find.text(AgendaStrings.upcomingAppointmentsHeading),
          findsOneWidget,
        );
      },
    );
  });

  // ── SCENARIO-510: Tapping a day opens read-only day-sessions sheet ───────────

  group('SCENARIO-510 — Read-only day sheet', () {
    testWidgets(
      'SCENARIO-510: tapping a day opens sheet with no book or cancel buttons',
      (tester) async {
        final now = DateTime.now().toUtc();
        // A future session 7 days from now so it is in the current calendar view.
        final futureDay = now.add(const Duration(days: 7));
        final sessionStart = DateTime.utc(
          futureDay.year,
          futureDay.month,
          futureDay.day,
          10,
          0,
        );
        final appt = _makeAppointment(startsAt: sessionStart, id: 'sheet-1');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentAthleteLinkProvider
                  .overrideWith((ref) async => _makeLink()),
              appointmentsForAthleteStreamProvider('athlete-1').overrideWith(
                (ref) => Stream.value([appt]),
              ),
              userPublicProfileProvider('trainer-1')
                  .overrideWith((ref) => Stream.value(null)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const AthleteAgendaScreen(
                trainerId: 'trainer-1',
                athleteId: 'athlete-1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the cell for that specific day — find it by its day number text.
        final dayFinder = find.text(futureDay.day.toString());
        await tester.tap(dayFinder.first);
        await tester.pumpAndSettle();

        // Sheet is open — no book button, no cancel button.
        expect(find.text(AgendaStrings.bookingConfirmCta), findsNothing);
        expect(find.text(AgendaStrings.cancellationConfirmCta), findsNothing);
        expect(find.byIcon(Icons.cancel_outlined), findsNothing);
        // The read-only "no sessions" copy is NOT shown (we have a session).
        expect(find.text('No tenés sesiones este día.'), findsNothing);
      },
    );

    testWidgets(
      'SCENARIO-510b: tapping a day with no sessions shows empty copy',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentAthleteLinkProvider
                  .overrideWith((ref) async => _makeLink()),
              appointmentsForAthleteStreamProvider('athlete-1').overrideWith(
                (ref) => Stream.value([]),
              ),
              userPublicProfileProvider('trainer-1')
                  .overrideWith((ref) => Stream.value(null)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const AthleteAgendaScreen(
                trainerId: 'trainer-1',
                athleteId: 'athlete-1',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap any day number visible in the calendar.
        final dayFinder = find.text('15');
        await tester.tap(dayFinder.first);
        await tester.pumpAndSettle();

        // Sheet shows the no-sessions empty copy.
        expect(find.text('No tenés sesiones este día.'), findsOneWidget);
        expect(find.text(AgendaStrings.bookingConfirmCta), findsNothing);
        expect(find.byIcon(Icons.cancel_outlined), findsNothing);
      },
    );
  });

  // ── SCENARIO-501 / 502: DaySlotsSheet (direct widget test — NOT via athlete screen) ──
  //
  // DaySlotsSheet is kept for its own tests and the trainer flow.
  // These tests are still valid because they test DaySlotsSheet directly.

  group('SCENARIO-501 / 502 — DaySlotsSheet (direct)', () {
    testWidgets(
      'SCENARIO-501: sheet lists free slot chips',
      (tester) async {
        // Use local time so AgendaStrings.formatTime (which calls toLocal())
        // displays the expected "09:00" / "10:00" regardless of machine timezone.
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final slot1 =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0);
        final slot2 =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 0);

        await tester.pumpWidget(
          ProviderScope(
            overrides: const [],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: DaySlotsSheet(
                  slots: [slot1, slot2],
                  existingBookings: const [],
                  onBookSlot: (_) async {},
                  onCancelAppointment: (_) async {},
                  now: DateTime.now().toUtc(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('09:00'), findsOneWidget);
        expect(find.text('10:00'), findsOneWidget);
      },
    );

    testWidgets(
      'SCENARIO-502: sheet shows empty-state when no slots',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: const [],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: DaySlotsSheet(
                  slots: const [],
                  existingBookings: const [],
                  onBookSlot: (_) async {},
                  onCancelAppointment: (_) async {},
                  now: DateTime.now().toUtc(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(AgendaStrings.emptyAvailability), findsOneWidget);
      },
    );
  });

  // ── SCENARIO-503 / 504: Booking flow (DaySlotsSheet direct) ─────────────────

  group('SCENARIO-503 / 504 — Booking flow (DaySlotsSheet direct)', () {
    testWidgets(
      'SCENARIO-503: tapping slot chip shows confirmation dialog',
      (tester) async {
        // Use local time so AgendaStrings.formatTime displays "09:00".
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final slot =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0);

        var bookCalled = false;
        await tester.pumpWidget(
          ProviderScope(
            overrides: const [],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: DaySlotsSheet(
                  slots: [slot],
                  existingBookings: const [],
                  onBookSlot: (s) async {
                    bookCalled = true;
                  },
                  onCancelAppointment: (_) async {},
                  now: DateTime.now().toUtc(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the slot chip
        await tester.tap(find.text('09:00'));
        await tester.pumpAndSettle();

        // Confirmation dialog title should appear
        expect(find.text(AgendaStrings.bookingConfirmTitle), findsOneWidget);
        // Book not called yet (confirmation pending)
        expect(bookCalled, isFalse);
      },
    );

    testWidgets(
      'SCENARIO-504: confirming dialog calls onBookSlot',
      (tester) async {
        // Use local time so AgendaStrings.formatTime displays "09:00".
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final slot =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0);

        DateTime? bookedSlot;
        await tester.pumpWidget(
          ProviderScope(
            overrides: const [],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: DaySlotsSheet(
                  slots: [slot],
                  existingBookings: const [],
                  onBookSlot: (s) async {
                    bookedSlot = s;
                  },
                  onCancelAppointment: (_) async {},
                  now: DateTime.now().toUtc(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('09:00'));
        await tester.pumpAndSettle();

        // Confirm in dialog
        await tester.tap(find.widgetWithText(
            ElevatedButton, AgendaStrings.bookingConfirmCta));
        await tester.pumpAndSettle();

        expect(bookedSlot, equals(slot));
      },
    );
  });

  // ── SCENARIO-508b — Own bookings highlighted in DaySlotsSheet (direct) ───────

  group('SCENARIO-508b — Own bookings highlighted in DaySlotsSheet (direct)',
      () {
    testWidgets(
      'SCENARIO-508b: athlete own bookings shown with distinct style',
      (tester) async {
        // Use local time so AgendaStrings.formatTime displays "09:00".
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final slot =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0);

        final ownBooking = _makeAppointment(
          startsAt: slot,
          id: 'own-booking',
          status: AppointmentStatus.confirmed,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: const [],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: DaySlotsSheet(
                  slots: const [],
                  existingBookings: [ownBooking],
                  onBookSlot: (_) async {},
                  onCancelAppointment: (_) async {},
                  now: DateTime.now().toUtc(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Own booking tile uses 'RESERVADO' label
        expect(find.text('RESERVADO'), findsOneWidget);
        // And displays the time
        expect(find.text('09:00'), findsOneWidget);
      },
    );
  });
}
