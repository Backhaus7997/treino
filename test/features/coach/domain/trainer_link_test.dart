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

  // ── sharedWithTrainer field ────────────────────────────────────────────────
  //
  // Privacy gate retrofit. The field MUST round-trip through fromJson/toJson
  // (SCENARIO-464) and MUST default to false when the key is absent from a
  // legacy document (SCENARIO-465).
  //
  // REQ-COACH-LINK-001 (field contract) and REQ-COACH-LINK-002 (default).

  // ── pausedAt field (REQ-CHLM-005) ────────────────────────────────────────────
  //
  // pausedAt is an additive nullable DateTime — legacy docs without the key
  // MUST deserialize cleanly with pausedAt == null.

  group('pausedAt field', () {
    test(
      'SCEN-CHLM-006: fromJson without pausedAt key → pausedAt == null',
      () {
        final legacyMap = <String, dynamic>{
          'id': 'link-paused-001',
          'trainerId': 'trainer-1',
          'athleteId': 'athlete-1',
          'status': 'active',
          'requestedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20, 10, 0)),
          'acceptedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20, 12, 0)),
          // no 'pausedAt' key — legacy doc
        };
        final decoded = TrainerLink.fromJson(legacyMap);
        expect(decoded.pausedAt, isNull);
      },
    );

    test(
      'pausedAt round-trips through fromJson/toJson when set',
      () {
        final pausedAt = DateTime.utc(2026, 6, 1, 9, 0);
        final rawMap = <String, dynamic>{
          'id': 'link-paused-002',
          'trainerId': 'trainer-1',
          'athleteId': 'athlete-1',
          'status': 'paused',
          'requestedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20, 10, 0)),
          'acceptedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20, 12, 0)),
          'pausedAt': Timestamp.fromDate(pausedAt),
        };
        final decoded = TrainerLink.fromJson(rawMap);
        expect(decoded.pausedAt, pausedAt);
      },
    );
  });

  group('sharedWithTrainer field', () {
    test(
      'SCENARIO-464: round-trip preserves sharedWithTrainer: true and other fields',
      () {
        final link = TrainerLink(
          id: 'link-shared-001',
          trainerId: 'trainer-1',
          athleteId: 'athlete-1',
          status: TrainerLinkStatus.active,
          requestedAt: DateTime.utc(2026, 5, 20, 10, 0),
          acceptedAt: DateTime.utc(2026, 5, 20, 12, 0),
          sharedWithTrainer: true,
        );
        final decoded = TrainerLink.fromJson(link.toJson());
        expect(decoded.sharedWithTrainer, isTrue);
        expect(decoded, equals(link));
      },
    );

    test(
      'SCENARIO-465: fromJson defaults sharedWithTrainer to false when key absent',
      () {
        final legacyMap = <String, dynamic>{
          'id': 'link-legacy-001',
          'trainerId': 'trainer-1',
          'athleteId': 'athlete-1',
          'status': 'active',
          'requestedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20, 10, 0)),
          'acceptedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20, 12, 0)),
        };
        final decoded = TrainerLink.fromJson(legacyMap);
        expect(decoded.sharedWithTrainer, isFalse);
      },
    );
  });
}
