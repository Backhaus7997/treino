import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_day_detail_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAvailabilityRepository extends Fake
    implements AvailabilityRepository {}

class _FakeAppointmentRepository extends Fake
    implements AppointmentRepository {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

// Tuesday 2026-06-02 (weekday == 2 verified: 2026-06-01 is Monday=1)
final _kDay = DateTime.utc(2026, 6, 2);
final _kFrom = DateTime.utc(2026, 1, 1);
final _kTo = DateTime.utc(2027, 12, 31);

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

Appointment _makeAppointment({
  String athleteId = 'athlete-1',
  String athleteDisplayName = 'Athlete One',
  int hour = 9,
}) =>
    Appointment(
      id: 'trainer-1_${DateTime.utc(2026, 6, 2, hour, 0).millisecondsSinceEpoch}',
      trainerId: 'trainer-1',
      athleteId: athleteId,
      athleteDisplayName: athleteDisplayName,
      startsAt: DateTime.utc(2026, 6, 2, hour, 0),
      durationMin: 60,
      status: AppointmentStatus.confirmed,
    );

AvailabilityOverride _makeBlockOverride() => AvailabilityOverride.block(
      id: 'override-1',
      trainerId: 'trainer-1',
      date: _kDay, // must match the day the sheet is rendering
    );

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      ...overrides,
      availabilityRepositoryProvider
          .overrideWithValue(_FakeAvailabilityRepository()),
      appointmentRepositoryProvider
          .overrideWithValue(_FakeAppointmentRepository()),
      // Empty fake Firestore — _BookedSlotChip's stream emits a "doesn't
      // exist" snapshot, chip falls back to athleteDisplayName from fixture.
      firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    ),
  );
}

List<Override> _defaultOverrides({
  List<AvailabilityRule> rules = const [],
  List<AvailabilityOverride> overridesList = const [],
  List<Appointment> appointments = const [],
}) {
  return [
    availabilityRulesStreamProvider('trainer-1').overrideWith(
      (ref) => Stream.value(rules),
    ),
    overridesStreamProvider(OverridesKey(
      trainerId: 'trainer-1',
      fromDate: _kFrom,
      toDate: _kTo,
    )).overrideWith((ref) => Stream.value(overridesList)),
    trainerAppointmentsStreamProvider(TrainerAppointmentsKey(
      trainerId: 'trainer-1',
      fromDate: _kFrom,
      toDate: _kTo,
    )).overrideWith((ref) => Stream.value(appointments)),
  ];
}

Widget _sheet({
  List<AvailabilityRule> rules = const [],
  List<AvailabilityOverride> overridesList = const [],
  List<Appointment> appointments = const [],
}) {
  return _wrap(
    TrainerDayDetailSheet(
      trainerId: 'trainer-1',
      day: _kDay,
      rangeFrom: _kFrom,
      rangeTo: _kTo,
    ),
    overrides: _defaultOverrides(
      rules: rules,
      overridesList: overridesList,
      appointments: appointments,
    ),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ── SCENARIO-520: free slots shown as green chips ─────────────────────────
  group('SCENARIO-520 — Free slot chips', () {
    testWidgets(
      'SCENARIO-520: free slot for 09:00 shows time label (green chip)',
      (tester) async {
        final rule = _makeRule(dayOfWeek: DateTime.tuesday);
        await tester.pumpWidget(_sheet(rules: [rule]));
        await tester.pump(); // first frame
        await tester.pump(); // allow streams to emit

        // Free slot for the 09:00 window — formatted in local time
        // Since test env uses UTC, slot 09:00 UTC → local "09:00"
        // Use textContaining since time format is "HH:mm"
        final timeTexts = tester.widgetList<Text>(find.byType(Text));
        final hasSlotText = timeTexts.any((t) {
          final data = t.data ?? '';
          return RegExp(r'^\d{2}:\d{2}$').hasMatch(data);
        });
        expect(hasSlotText, isTrue,
            reason: 'Expected at least one HH:mm time chip to be rendered');
      },
    );
  });

  // ── SCENARIO-521: booked slots show athlete name ──────────────────────────
  group('SCENARIO-521 — Booked slot shows athlete name', () {
    testWidgets(
      'SCENARIO-521: booked slot chip shows athlete display name',
      (tester) async {
        final rule = _makeRule(dayOfWeek: DateTime.tuesday);
        final appt = _makeAppointment(
          athleteDisplayName: 'Juan Perez',
          hour: 9,
        );

        await tester.pumpWidget(_sheet(
          rules: [rule],
          appointments: [appt],
        ));
        await tester.pump();

        // Athlete name should appear in the booked chip
        expect(find.text('Juan Perez'), findsOneWidget);
      },
    );
  });

  // ── SCENARIO-522: booked slot tap → SessionDetailSheet with cancel ────────
  //
  // Behavior change: tapping a booked chip now opens the SessionDetailSheet
  // instead of an action menu. Cancel is still reachable via the sheet's
  // "CANCELAR RESERVA" button (when >24h ahead).
  group('SCENARIO-522 — Booked slot tap shows SessionDetailSheet', () {
    testWidgets(
      'SCENARIO-522: tapping booked chip opens SessionDetailSheet with time and CANCELAR RESERVA for >24h future',
      (tester) async {
        // Make appointment far in the future so cancel is available (>24h)
        final futureAppt = Appointment(
          id: 'trainer-1_99999999999999',
          trainerId: 'trainer-1',
          athleteId: 'athlete-1',
          athleteDisplayName: 'Athlete One',
          startsAt: DateTime.now().toUtc().add(const Duration(days: 30)),
          durationMin: 60,
          status: AppointmentStatus.confirmed,
        );

        await tester.pumpWidget(_wrap(
          TrainerDayDetailSheet(
            trainerId: 'trainer-1',
            day: DateTime.utc(
              futureAppt.startsAt.year,
              futureAppt.startsAt.month,
              futureAppt.startsAt.day,
            ),
            rangeFrom: _kFrom,
            rangeTo: _kTo,
          ),
          overrides: [
            availabilityRulesStreamProvider('trainer-1').overrideWith(
              (ref) => Stream.value([
                AvailabilityRule(
                  id: 'rule-future',
                  trainerId: 'trainer-1',
                  dayOfWeek: futureAppt.startsAt.weekday,
                  startHour: futureAppt.startsAt.hour,
                  startMinute: 0,
                  endHour: futureAppt.startsAt.hour + 2,
                  endMinute: 0,
                  slotDurationMin: 60,
                ),
              ]),
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
            )).overrideWith((ref) => Stream.value([futureAppt])),
            // Stub athlete note stream → no note
            athleteNoteProvider(
                    (trainerId: 'trainer-1', athleteId: 'athlete-1'))
                .overrideWith((ref) => Stream.value(null)),
            // Stub public profile → null (chip falls back to athleteDisplayName)
            userPublicProfileProvider('athlete-1').overrideWith((ref) async* {
              yield null;
            }),
          ],
        ));
        await tester.pump();

        // Find the athlete name chip and tap it
        expect(find.text('Athlete One'), findsOneWidget);
        await tester.tap(find.text('Athlete One'));
        await tester.pumpAndSettle();

        // The SessionDetailSheet should show the time range (HH:mm – HH:mm · N min)
        final timeTexts = tester.widgetList<Text>(find.byType(Text));
        final hasTimeRange = timeTexts.any((t) {
          final d = t.data ?? '';
          return RegExp(r'\d{2}:\d{2}\s*–\s*\d{2}:\d{2}').hasMatch(d);
        });
        expect(hasTimeRange, isTrue,
            reason: 'SessionDetailSheet should show a time range header');

        // The CANCELAR RESERVA button should be visible (>24h future)
        expect(find.text('CANCELAR RESERVA'), findsOneWidget);
      },
    );
  });

  // ── SCENARIO-524: blocked day shows blocked chip (gris) ───────────────────
  group('SCENARIO-524 — Blocked day shows blocked chip', () {
    testWidgets(
      'SCENARIO-524: blocked override renders slotBlockedLabel chip',
      (tester) async {
        final rule = _makeRule(dayOfWeek: DateTime.tuesday);
        final block = _makeBlockOverride();

        await tester.pumpWidget(_sheet(
          rules: [rule],
          overridesList: [block],
        ));
        await tester.pump();

        // Free slots should not show
        expect(find.text('09:00'), findsNothing);
        // Blocked chip should show
        expect(find.text('Bloqueado'), findsOneWidget);
      },
    );
  });

  // ── Empty state when no slots ─────────────────────────────────────────────
  group('Empty state — no rules, no overrides', () {
    testWidgets(
      'Empty state: "Sin turnos para este día." shown when no rules',
      (tester) async {
        await tester.pumpWidget(_sheet());
        await tester.pump();

        expect(find.text('Sin turnos para este día.'), findsOneWidget);
      },
    );
  });
}
