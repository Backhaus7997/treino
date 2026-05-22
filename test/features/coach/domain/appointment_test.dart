import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/appointment.dart';

void main() {
  group('Appointment JSON round-trip', () {
    test(
      'SCENARIO-482: round-trip preserves all fields and status confirmed',
      () {
        final appt = Appointment(
          id: 'tA_1748000000000',
          trainerId: 'tA',
          athleteId: 'aB',
          athleteDisplayName: 'Juan Perez',
          startsAt: DateTime.fromMillisecondsSinceEpoch(
            1748000000000,
            isUtc: true,
          ),
          durationMin: 60,
          status: AppointmentStatus.confirmed,
        );
        final decoded = Appointment.fromJson(appt.toJson());
        expect(decoded, equals(appt));
        expect(decoded.status, AppointmentStatus.confirmed);
        expect(decoded.id, 'tA_1748000000000');
      },
    );

    test('round-trip with status cancelled and cancellation metadata', () {
      final cancelledAt = DateTime.utc(2026, 5, 22, 10);
      final appt = Appointment(
        id: 'tA_1748000000000',
        trainerId: 'tA',
        athleteId: 'aB',
        athleteDisplayName: 'Juan Perez',
        startsAt: DateTime.fromMillisecondsSinceEpoch(
          1748000000000,
          isUtc: true,
        ),
        durationMin: 60,
        status: AppointmentStatus.cancelled,
        cancelledAt: cancelledAt,
        cancelledBy: 'aB',
        cancellationLog: const [
          CancellationEntry(
            byUid: 'aB',
            reason: 'athlete-cancel',
            atMs: 1747999000000,
          ),
        ],
      );
      final decoded = Appointment.fromJson(appt.toJson());
      expect(decoded.status, AppointmentStatus.cancelled);
      expect(decoded.cancelledAt, cancelledAt);
      expect(decoded.cancelledBy, 'aB');
      expect(decoded.cancellationLog, hasLength(1));
      expect(decoded.cancellationLog.single.byUid, 'aB');
    });
  });

  group('AppointmentStatus wire encoding', () {
    test('SCENARIO-483: AppointmentStatus.cancelled serialises to "cancelled"',
        () {
      final raw = const Appointment(
        id: 'tA_1',
        trainerId: 'tA',
        athleteId: 'aB',
        athleteDisplayName: 'Juan',
        durationMin: 60,
        status: AppointmentStatus.cancelled,
      ).copyWith(startsAt: DateTime.utc(2026, 6, 1, 9));
      final encoded = raw.toJson();
      expect(encoded['status'], 'cancelled');
    });

    test('AppointmentStatus.confirmed serialises to "confirmed"', () {
      final raw = Appointment(
        id: 'tA_1',
        trainerId: 'tA',
        athleteId: 'aB',
        athleteDisplayName: 'Juan',
        startsAt: DateTime.utc(2026, 6, 1, 9),
        durationMin: 60,
        status: AppointmentStatus.confirmed,
      );
      expect(raw.toJson()['status'], 'confirmed');
    });
  });

  group('Appointment deterministic id', () {
    test('SCENARIO-484: id matches pattern "{trainerId}_{startsAtMs}"', () {
      final startsAt = DateTime.fromMillisecondsSinceEpoch(
        1748000000000,
        isUtc: true,
      );
      final appt = Appointment.create(
        trainerId: 'tA',
        athleteId: 'aB',
        athleteDisplayName: 'Juan',
        startsAt: startsAt,
        durationMin: 60,
      );
      expect(appt.id, 'tA_1748000000000');
      expect(appt.trainerId, 'tA');
      expect(appt.startsAt.millisecondsSinceEpoch, 1748000000000);
    });

    test('Appointment.create asserts minute precision on startsAt (ADR-7)', () {
      expect(
        () => Appointment.create(
          trainerId: 'tA',
          athleteId: 'aB',
          athleteDisplayName: 'Juan',
          // 30 seconds — violates ADR-7 minute precision.
          startsAt: DateTime.utc(2026, 6, 1, 9, 0, 30),
          durationMin: 60,
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });
  });

  group('Appointment.fromJson accepts Firestore Timestamps', () {
    test('startsAt and cancelledAt decode from Timestamp', () {
      final raw = <String, dynamic>{
        'id': 'tA_1',
        'trainerId': 'tA',
        'athleteId': 'aB',
        'athleteDisplayName': 'Juan',
        'startsAt': Timestamp.fromDate(DateTime.utc(2026, 6, 1, 9)),
        'durationMin': 60,
        'status': 'cancelled',
        'cancelledAt': Timestamp.fromDate(DateTime.utc(2026, 5, 30, 10)),
        'cancelledBy': 'aB',
        'cancellationLog': const <Map<String, dynamic>>[],
      };
      final decoded = Appointment.fromJson(raw);
      expect(decoded.startsAt, DateTime.utc(2026, 6, 1, 9));
      expect(decoded.cancelledAt, DateTime.utc(2026, 5, 30, 10));
    });
  });
}
