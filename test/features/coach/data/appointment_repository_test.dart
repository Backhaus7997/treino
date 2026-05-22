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
}
