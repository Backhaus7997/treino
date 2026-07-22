import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/agenda_exceptions.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/wall_clock.dart';

/// QA-COA-003 regression: `Appointment.startsAt` is wall-clock UTC (ADR-7), so
/// every comparison against it must use a wall-clock "now", NOT a real UTC
/// instant (`DateTime.now().toUtc()`, which is +3h in Argentina, UTC-3).
///
/// Unlike the far-future 2030 dates in appointment_repository_test.dart — whose
/// multi-year margins mask a 3h shift — these tests use NEAR dates with an
/// INJECTED wall-clock clock, so a regression back to real-UTC comparison would
/// visibly flip the outcome.
void main() {
  late FakeFirebaseFirestore firestore;
  late AppointmentRepository repo;

  const trainerId = 'trainer1';
  const athleteId = 'athlete1';
  const athleteDisplayName = 'Ana Pérez';
  const durationMin = 60;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = AppointmentRepository(firestore: firestore);
  });

  Appointment confirmedAt(DateTime startsAt, {required String id}) => Appointment(
        id: id,
        trainerId: trainerId,
        athleteId: athleteId,
        athleteDisplayName: athleteDisplayName,
        startsAt: startsAt,
        durationMin: durationMin,
        status: AppointmentStatus.confirmed,
      );

  Future<void> seed(Appointment appt) =>
      firestore.collection('appointments').doc(appt.id).set(appt.toJson());

  group('nowWall()', () {
    test('re-labels the given calendar fields (down to the minute) as UTC', () {
      expect(
        nowWall(now: DateTime.utc(2026, 7, 20, 15, 30, 45)),
        DateTime.utc(2026, 7, 20, 15, 30),
      );
    });
  });

  group('cancel() — wall-clock 24h gate', () {
    test(
      '(a) a session ~25 REAL hours away CAN be cancelled '
      '(startsAt = wall-clock tomorrow 10:00, now = wall-clock today 09:00). '
      'The old real-UTC compare made this 22h in ART and wrongly threw.',
      () async {
        final now = DateTime.utc(2026, 7, 20, 9, 0); // wall-clock today 09:00
        final startsAt = DateTime.utc(2026, 7, 21, 10, 0); // tomorrow 10:00 (25h)
        final appt = confirmedAt(startsAt, id: 'appt-25h');
        await seed(appt);

        // Must NOT throw CancellationTooLateException.
        await repo.cancel(appointment: appt, actorUid: trainerId, now: now);

        final snap =
            await firestore.collection('appointments').doc(appt.id).get();
        expect(snap.data()!['status'], 'cancelled');
      },
    );

    test(
      'a session ~1 hour away is correctly rejected (<24h) with '
      'CancellationTooLateException',
      () async {
        final now = DateTime.utc(2026, 7, 20, 9, 0);
        final startsAt = DateTime.utc(2026, 7, 20, 10, 0); // +1h
        final appt = confirmedAt(startsAt, id: 'appt-1h');
        await seed(appt);

        await expectLater(
          repo.cancel(appointment: appt, actorUid: trainerId, now: now),
          throwsA(isA<CancellationTooLateException>()),
        );
      },
    );

    test(
      'the gate boundary is measured in wall-clock hours: a session exactly 24h '
      'away is cancellable, 23h59m is not',
      () async {
        final now = DateTime.utc(2026, 7, 20, 9, 0);

        final at24h = confirmedAt(DateTime.utc(2026, 7, 21, 9, 0), id: 'at-24h');
        await seed(at24h);
        await repo.cancel(appointment: at24h, actorUid: trainerId, now: now);
        expect(
          (await firestore.collection('appointments').doc(at24h.id).get())
              .data()!['status'],
          'cancelled',
        );

        final at23h59 =
            confirmedAt(DateTime.utc(2026, 7, 21, 8, 59), id: 'at-23h59');
        await seed(at23h59);
        await expectLater(
          repo.cancel(appointment: at23h59, actorUid: trainerId, now: now),
          throwsA(isA<CancellationTooLateException>()),
        );
      },
    );
  });

  group('upcoming semantics — wall-clock', () {
    test(
      '(b) a session starting in ~1 hour is still in the future vs wall-clock '
      'now, so the "upcoming" filter keeps it. Under the old real-UTC now it '
      'was dropped ~3h early in ART.',
      () {
        final now = nowWall(now: DateTime.utc(2026, 7, 20, 9, 0));
        final startsAt = DateTime.utc(2026, 7, 20, 10, 0); // +1h

        // The dashboard/agenda "upcoming" predicate.
        expect(startsAt.isAfter(now), isTrue);
        // And still upcoming by the "not ended yet" (startsAt + duration) rule.
        expect(
          startsAt.add(const Duration(minutes: durationMin)).isAfter(now),
          isTrue,
        );
      },
    );
  });

  group('book() — wall-clock horizon + past guard', () {
    test('rejects a startsAt in the past with BookingInThePastException',
        () async {
      final now = DateTime.utc(2026, 7, 20, 9, 0);
      final past = DateTime.utc(2026, 7, 20, 8, 0); // 1h ago

      await expectLater(
        repo.book(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: past,
          durationMin: durationMin,
          now: now,
        ),
        throwsA(isA<BookingInThePastException>()),
      );
      expect((await firestore.collection('appointments').get()).docs, isEmpty);
    });

    test('accepts a startsAt ~25h ahead (future, inside the 28-day horizon)',
        () async {
      final now = DateTime.utc(2026, 7, 20, 9, 0);
      final soon = DateTime.utc(2026, 7, 21, 10, 0);

      final appt = await repo.book(
        trainerId: trainerId,
        athleteId: athleteId,
        athleteDisplayName: athleteDisplayName,
        startsAt: soon,
        durationMin: durationMin,
        now: now,
      );

      expect(appt.status, AppointmentStatus.confirmed);
      expect(appt.startsAt, soon);
    });
  });
}
