import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

void main() {
  group('Session', () {
    test(
        'SCENARIO-234: Session default values and JSON round-trip with finishedAt null',
        () {
      final startedAt = DateTime.utc(2026, 5, 18, 10, 0, 0);

      final session = Session(
        id: 'session-001',
        uid: 'user-abc',
        routineId: 'routine-ppl',
        routineName: 'Push Pull Legs',
        startedAt: startedAt,
        finishedAt: null,
        status: SessionStatus.active,
      );

      final json = session.toJson();
      final decoded = Session.fromJson(json);

      expect(decoded.id, equals('session-001'));
      expect(decoded.uid, equals('user-abc'));
      expect(decoded.routineId, equals('routine-ppl'));
      expect(decoded.routineName, equals('Push Pull Legs'));
      expect(decoded.startedAt, equals(startedAt));
      expect(decoded.finishedAt, isNull);
      expect(decoded.totalVolumeKg, equals(0.0));
      expect(decoded.durationMin, equals(0));
      expect(decoded.status, equals(SessionStatus.active));
      expect(decoded, equals(session));
    });

    test('SCENARIO-239: Session.finishedAt is null when status is active', () {
      final session = Session(
        id: 'session-002',
        uid: 'user-xyz',
        routineId: 'routine-full-body',
        routineName: 'Full Body',
        startedAt: DateTime.utc(2026, 5, 18, 9, 0, 0),
        status: SessionStatus.active,
      );

      expect(session.finishedAt, isNull);
      expect(session.status, equals(SessionStatus.active));
    });

    test('SCENARIO-234b: finished Session round-trip preserves all fields', () {
      final startedAt = DateTime.utc(2026, 5, 18, 9, 0, 0);
      final finishedAt = DateTime.utc(2026, 5, 18, 9, 45, 0);

      final session = Session(
        id: 'session-003',
        uid: 'user-abc',
        routineId: 'routine-ppl',
        routineName: 'Push Pull Legs',
        startedAt: startedAt,
        finishedAt: finishedAt,
        totalVolumeKg: 1250.5,
        durationMin: 45,
        status: SessionStatus.finished,
      );

      final json = session.toJson();
      final decoded = Session.fromJson(json);

      expect(decoded.finishedAt, equals(finishedAt));
      expect(decoded.totalVolumeKg, equals(1250.5));
      expect(decoded.durationMin, equals(45));
      expect(decoded.status, equals(SessionStatus.finished));
      expect(decoded, equals(session));
    });

    test('SCENARIO-234c: status serializes to wire value in JSON', () {
      final session = Session(
        id: 'session-004',
        uid: 'user-abc',
        routineId: 'r1',
        routineName: 'Test',
        startedAt: DateTime.utc(2026, 5, 18, 8, 0, 0),
        status: SessionStatus.active,
      );

      final json = session.toJson();

      // Wire representation must be lowercase string
      expect(json['status'], equals('active'));
    });

    test(
        'SCENARIO-234d: fromJson with Timestamp objects deserializes correctly',
        () {
      final startedAt = DateTime.utc(2026, 5, 18, 10, 0, 0);
      final rawMap = <String, dynamic>{
        'id': 'session-005',
        'uid': 'user-abc',
        'routineId': 'routine-ppl',
        'routineName': 'Push Pull Legs',
        'startedAt': Timestamp.fromDate(startedAt),
        'finishedAt': null,
        'totalVolumeKg': 0.0,
        'durationMin': 0,
        'status': 'active',
      };

      final decoded = Session.fromJson(rawMap);

      expect(decoded.id, equals('session-005'));
      expect(decoded.startedAt, equals(startedAt));
      expect(decoded.finishedAt, isNull);
    });
  });
}
