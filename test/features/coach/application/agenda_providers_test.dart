import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;

void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(fakeFirestore),
      ],
    );
  }

  group('availabilityRulesStreamProvider', () {
    // ─── SCENARIO: provider returns a stream ─────────────────────────────
    test(
      'SCENARIO: returns a stream of rules for the given trainerId',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);

        // Seed one rule directly into the fake Firestore.
        final rule = AvailabilityRule(
          id: 'r1',
          trainerId: 'tA',
          dayOfWeek: 1,
          startHour: 9,
          startMinute: 0,
          endHour: 11,
          endMinute: 0,
          slotDurationMin: 60,
        );
        await fakeFirestore
            .collection('coach_availability_rules')
            .doc(rule.id)
            .set(rule.toJson());

        final stream =
            container.read(availabilityRulesStreamProvider('tA'));
        expect(stream, isA<AsyncValue<List<AvailabilityRule>>>());

        // Wait for first emission.
        final result = await container
            .read(availabilityRulesStreamProvider('tA').future);
        expect(result, hasLength(1));
        expect(result.first.id, equals('r1'));
      },
    );
  });

  group('availabilityRulesStreamProvider family key stability', () {
    // ─── SCENARIO: family keys are stable ────────────────────────────────
    test(
      'SCENARIO: two calls with same trainerId return same provider instance',
      () {
        final container = makeContainer();
        addTearDown(container.dispose);

        final p1 = availabilityRulesStreamProvider('tA');
        final p2 = availabilityRulesStreamProvider('tA');
        expect(p1, equals(p2));
      },
    );

    test(
      'SCENARIO: two calls with different trainerIds return different instances',
      () {
        final p1 = availabilityRulesStreamProvider('tA');
        final p2 = availabilityRulesStreamProvider('tB');
        expect(p1, isNot(equals(p2)));
      },
    );
  });

  group('appointmentsForAthleteStreamProvider', () {
    // ─── SCENARIO: streams confirmed appointments for athlete ─────────────
    test(
      'SCENARIO: streams confirmed appointments for athleteId',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);

        final appt = Appointment.create(
          trainerId: 'tA',
          athleteId: 'aA',
          athleteDisplayName: 'Ana',
          startsAt: DateTime.utc(2026, 7, 1, 10, 0),
          durationMin: 60,
        );
        await fakeFirestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        final result = await container
            .read(appointmentsForAthleteStreamProvider('aA').future);
        expect(result, hasLength(1));
        expect(result.first.athleteId, equals('aA'));
        expect(result.first.status, equals(AppointmentStatus.confirmed));
      },
    );
  });
}
