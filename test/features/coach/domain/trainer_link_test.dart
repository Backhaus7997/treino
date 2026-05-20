import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';

void main() {
  group('TrainerLinkStatusX wire encoding', () {
    test('toJson encodes pending/active/paused/terminated lowercase', () {
      expect(TrainerLinkStatusX(TrainerLinkStatus.pending).toJson(), 'pending');
      expect(TrainerLinkStatusX(TrainerLinkStatus.active).toJson(), 'active');
      expect(TrainerLinkStatusX(TrainerLinkStatus.paused).toJson(), 'paused');
      expect(TrainerLinkStatusX(TrainerLinkStatus.terminated).toJson(),
          'terminated');
    });

    test('fromJson decodes valid wire values', () {
      expect(TrainerLinkStatusX.fromJson('pending'), TrainerLinkStatus.pending);
      expect(TrainerLinkStatusX.fromJson('active'), TrainerLinkStatus.active);
      expect(TrainerLinkStatusX.fromJson('paused'), TrainerLinkStatus.paused);
      expect(TrainerLinkStatusX.fromJson('terminated'),
          TrainerLinkStatus.terminated);
    });

    test('fromJson throws ArgumentError on unknown value', () {
      expect(() => TrainerLinkStatusX.fromJson('unknown'),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('TrainerLink JSON round-trip', () {
    test('full record with all fields', () {
      final link = TrainerLink(
        id: 'link-001',
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
        status: TrainerLinkStatus.active,
        requestedAt: DateTime.utc(2026, 5, 20, 10, 0),
        acceptedAt: DateTime.utc(2026, 5, 20, 12, 0),
        terminatedAt: null,
        terminationReason: null,
      );
      final decoded = TrainerLink.fromJson(link.toJson());
      expect(decoded, equals(link));
    });

    test('minimal pending record (no acceptedAt/terminatedAt)', () {
      final link = TrainerLink(
        id: 'link-002',
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
        status: TrainerLinkStatus.pending,
        requestedAt: DateTime.utc(2026, 5, 20, 10, 0),
      );
      final decoded = TrainerLink.fromJson(link.toJson());
      expect(decoded.acceptedAt, isNull);
      expect(decoded.terminatedAt, isNull);
      expect(decoded.terminationReason, isNull);
      expect(decoded, equals(link));
    });

    test('terminated record with reason', () {
      final link = TrainerLink(
        id: 'link-003',
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
        status: TrainerLinkStatus.terminated,
        requestedAt: DateTime.utc(2026, 5, 20, 10, 0),
        terminatedAt: DateTime.utc(2026, 5, 20, 14, 0),
        terminationReason: 'declined',
      );
      final decoded = TrainerLink.fromJson(link.toJson());
      expect(decoded.terminationReason, 'declined');
    });

    test('fromJson with Firestore Timestamps deserializes correctly', () {
      final rawMap = <String, dynamic>{
        'id': 'link-004',
        'trainerId': 'trainer-1',
        'athleteId': 'athlete-1',
        'status': 'active',
        'requestedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20, 10, 0)),
        'acceptedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20, 12, 0)),
      };
      final decoded = TrainerLink.fromJson(rawMap);
      expect(decoded.id, 'link-004');
      expect(decoded.status, TrainerLinkStatus.active);
      expect(decoded.requestedAt, DateTime.utc(2026, 5, 20, 10, 0));
    });
  });
}
