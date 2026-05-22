import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/agenda_exceptions.dart';
import 'package:treino/features/coach/domain/appointment.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AppointmentRepository repo;

  const trainerId = 'trainer1';
  const athleteId = 'athlete1';
  const athleteDisplayName = 'Ana Pérez';
  const durationMin = 60;

  // ADR-7: minute-precision DateTime.
  final startsAt = DateTime.utc(2026, 7, 1, 10, 0, 0);
  final startsAtMs = startsAt.millisecondsSinceEpoch;
  final expectedDocId = '${trainerId}_$startsAtMs';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = AppointmentRepository(firestore: firestore);
  });

  group('book()', () {
    // ─── SCENARIO-489: book NEW slot ──────────────────────────────────────
    test(
      'SCENARIO-489: book new slot (doc absent) → returns confirmed Appointment with deterministic ID',
      () async {
        final appt = await repo.book(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: startsAt,
          durationMin: durationMin,
        );

        expect(appt.id, equals(expectedDocId));
        expect(appt.status, equals(AppointmentStatus.confirmed));
        expect(appt.trainerId, equals(trainerId));
        expect(appt.athleteId, equals(athleteId));
        expect(appt.startsAt, equals(startsAt));

        // Verify persisted in Firestore.
        final snap = await firestore
            .collection('appointments')
            .doc(expectedDocId)
            .get();
        expect(snap.exists, isTrue);
        expect(snap.data()!['status'], equals('confirmed'));
        expect(snap.data()!['athleteId'], equals(athleteId));
      },
    );

    // ─── SCENARIO-490: book when slot already confirmed ───────────────────
    test(
      'SCENARIO-490: book when doc exists status=confirmed → throws SlotAlreadyTakenException',
      () async {
        // Pre-seed a confirmed appointment at the doc ID.
        final existing = Appointment.create(
          trainerId: trainerId,
          athleteId: 'otherAthlete',
          athleteDisplayName: 'Other',
          startsAt: startsAt,
          durationMin: durationMin,
        );
        await firestore
            .collection('appointments')
            .doc(expectedDocId)
            .set(existing.toJson());

        expect(
          () => repo.book(
            trainerId: trainerId,
            athleteId: athleteId,
            athleteDisplayName: athleteDisplayName,
            startsAt: startsAt,
            durationMin: durationMin,
          ),
          throwsA(isA<SlotAlreadyTakenException>()),
        );
      },
    );

    // ─── SCENARIO-491-amended: ADR-1 flip cancelled → confirmed ──────────
    test(
      'SCENARIO-491-amended: book when doc exists status=cancelled → flips to confirmed, preserves cancellationLog',
      () async {
        // Pre-seed a cancelled appointment with an existing cancellation log.
        final cancelledAppt = Appointment(
          id: expectedDocId,
          trainerId: trainerId,
          athleteId: 'oldAthlete',
          athleteDisplayName: 'Old Athlete',
          startsAt: startsAt,
          durationMin: durationMin,
          status: AppointmentStatus.cancelled,
          cancelledAt: DateTime.utc(2026, 6, 28),
          cancelledBy: 'oldAthlete',
          cancellationLog: const [
            CancellationEntry(byUid: 'oldAthlete', atMs: 1751068800000),
          ],
        );
        await firestore
            .collection('appointments')
            .doc(expectedDocId)
            .set(cancelledAppt.toJson());

        final appt = await repo.book(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: startsAt,
          durationMin: durationMin,
        );

        expect(appt.status, equals(AppointmentStatus.confirmed));
        expect(appt.athleteId, equals(athleteId));
        expect(appt.cancelledAt, isNull);
        expect(appt.cancelledBy, isNull);

        // cancellationLog MUST be preserved (ADR-1 audit trail).
        final snap = await firestore
            .collection('appointments')
            .doc(expectedDocId)
            .get();
        final log = snap.data()!['cancellationLog'] as List<dynamic>;
        expect(log, hasLength(1));
        expect((log.first as Map<String, dynamic>)['byUid'], 'oldAthlete');
      },
    );

    // ─── SCENARIO-496: deterministic doc ID assertion ─────────────────────
    test(
      'SCENARIO-496: book asserts doc ID is exactly trainerId_startsAtMs',
      () async {
        final appt = await repo.book(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: startsAt,
          durationMin: durationMin,
        );

        expect(appt.id, equals('${trainerId}_${startsAt.millisecondsSinceEpoch}'));

        // Verify the document exists at that exact ID.
        final snap = await firestore
            .collection('appointments')
            .doc(appt.id)
            .get();
        expect(snap.exists, isTrue);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // cancel(), watchForAthlete(), watchForTrainer()
  // ─────────────────────────────────────────────────────────────────────────

  group('cancel()', () {
    Appointment makeConfirmedAppt({
      required DateTime startsAt,
      String id = '',
    }) {
      final appt = Appointment.create(
        trainerId: trainerId,
        athleteId: athleteId,
        athleteDisplayName: athleteDisplayName,
        startsAt: startsAt,
        durationMin: durationMin,
      );
      return id.isEmpty ? appt : appt.copyWith(id: id);
    }

    // ─── SCENARIO-492: cancellation succeeds when >24h ahead ─────────────
    test(
      'SCENARIO-492: cancel succeeds when >24h ahead → status=cancelled, cancelledAt/By set, appends to log',
      () async {
        // startsAt is in the far future — always >24h away.
        final future = DateTime.utc(2030, 1, 1, 10, 0);
        final appt = makeConfirmedAppt(startsAt: future);
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await repo.cancel(
          appointment: appt,
          actorUid: athleteId,
          reason: 'changed plans',
        );

        final snap = await firestore
            .collection('appointments')
            .doc(appt.id)
            .get();
        expect(snap.data()!['status'], equals('cancelled'));
        expect(snap.data()!['cancelledBy'], equals(athleteId));
        // cancellationLog should have one entry.
        final log = snap.data()!['cancellationLog'] as List<dynamic>;
        expect(log, hasLength(1));
        expect((log.first as Map<String, dynamic>)['byUid'], equals(athleteId));
        expect(
          (log.first as Map<String, dynamic>)['reason'],
          equals('changed plans'),
        );
      },
    );

    // ─── SCENARIO-493: CancellationTooLateException when <24h ahead ──────
    test(
      'SCENARIO-493: cancel throws CancellationTooLateException when <24h ahead',
      () async {
        // startsAt is 1 hour from now.
        final soon = DateTime.now().toUtc().add(const Duration(hours: 1));
        final soonMinutePrecision = DateTime.utc(
          soon.year,
          soon.month,
          soon.day,
          soon.hour,
          soon.minute,
        );
        final appt = makeConfirmedAppt(startsAt: soonMinutePrecision);
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        expect(
          () => repo.cancel(appointment: appt, actorUid: athleteId),
          throwsA(isA<CancellationTooLateException>()),
        );
      },
    );
  });

  group('watchForAthlete()', () {
    // ─── SCENARIO-494: streams confirmed appointments for athleteId ───────
    test(
      'SCENARIO-494: watchForAthlete streams confirmed appointments for athleteId',
      () async {
        final appt1 = Appointment.create(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: DateTime.utc(2026, 7, 1, 10, 0),
          durationMin: durationMin,
        );
        final appt2 = Appointment.create(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: DateTime.utc(2026, 7, 2, 10, 0),
          durationMin: durationMin,
        );
        // Different athlete — should NOT appear.
        final apptOther = Appointment.create(
          trainerId: trainerId,
          athleteId: 'otherAthlete',
          athleteDisplayName: 'Other',
          startsAt: DateTime.utc(2026, 7, 3, 10, 0),
          durationMin: durationMin,
        );

        await firestore
            .collection('appointments')
            .doc(appt1.id)
            .set(appt1.toJson());
        await firestore
            .collection('appointments')
            .doc(appt2.id)
            .set(appt2.toJson());
        await firestore
            .collection('appointments')
            .doc(apptOther.id)
            .set(apptOther.toJson());

        final results = await repo.watchForAthlete(athleteId).first;
        expect(results, hasLength(2));
        expect(results.map((a) => a.athleteId).toSet(), equals({athleteId}));
        expect(results.every((a) => a.status == AppointmentStatus.confirmed),
            isTrue);
      },
    );
  });

  group('watchForTrainer()', () {
    // ─── SCENARIO-495: streams confirmed appointments for trainerId in date range ─
    test(
      'SCENARIO-495: watchForTrainer streams confirmed appointments for trainerId in date range',
      () async {
        final apptInRange = Appointment.create(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: DateTime.utc(2026, 7, 5, 10, 0),
          durationMin: durationMin,
        );
        // Outside range — should NOT appear.
        final apptOutside = Appointment.create(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: DateTime.utc(2026, 8, 1, 10, 0),
          durationMin: durationMin,
        );

        await firestore
            .collection('appointments')
            .doc(apptInRange.id)
            .set(apptInRange.toJson());
        await firestore
            .collection('appointments')
            .doc(apptOutside.id)
            .set(apptOutside.toJson());

        final results = await repo
            .watchForTrainer(
              trainerId,
              fromDate: DateTime.utc(2026, 7, 1),
              toDate: DateTime.utc(2026, 7, 31),
            )
            .first;

        expect(results, hasLength(1));
        expect(results.single.id, equals(apptInRange.id));
        expect(results.single.trainerId, equals(trainerId));
      },
    );
  });
}
