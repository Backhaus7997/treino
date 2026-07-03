import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/payments/domain/payment.dart';

// TDD RED — REQ-VENC-10
// Tests that Payment.fromJson correctly round-trips the nullable dueAt field.
// These tests FAIL until dueAt is added to payment.dart and the freezed/json
// code is regenerated with build_runner.

void main() {
  group('Payment.dueAt — round-trip (REQ-VENC-10)', () {
    final baseJson = <String, Object?>{
      'id': 'pay-1',
      'trainerId': 'tA',
      'athleteId': 'aA',
      'amountArs': 5000,
      'concept': 'Mensual Julio 2026',
      'status': 'pending',
      'periodKey': '2026-07',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 1)),
    };

    // SCENARIO-VENC-10 grounding: non-null dueAt Timestamp → DateTime (UTC)
    test('fromJson parses a non-null dueAt Timestamp as UTC DateTime', () {
      final dueAtTs = Timestamp.fromDate(DateTime.utc(2026, 7, 31, 23, 59, 59));
      final json = {...baseJson, 'dueAt': dueAtTs};

      final payment = Payment.fromJson(json);

      expect(payment.dueAt, isNotNull);
      expect(
        payment.dueAt,
        equals(DateTime.utc(2026, 7, 31, 23, 59, 59)),
      );
    });

    // null dueAt: absent key → null without error
    test('fromJson tolerates absent dueAt key (null)', () {
      final payment = Payment.fromJson(Map.of(baseJson));

      expect(payment.dueAt, isNull);
    });

    // null dueAt: explicit null value → null without error
    test('fromJson tolerates explicit null dueAt (null)', () {
      final json = {...baseJson, 'dueAt': null};

      final payment = Payment.fromJson(json);

      expect(payment.dueAt, isNull);
    });

    // toJson round-trip: non-null dueAt → Timestamp back
    test('toJson round-trips non-null dueAt as Timestamp', () {
      final dueAt = DateTime.utc(2026, 7, 31, 23, 59, 59);
      final dueAtTs = Timestamp.fromDate(DateTime.utc(2026, 7, 31, 23, 59, 59));
      final json = {...baseJson, 'dueAt': dueAtTs};

      final payment = Payment.fromJson(json);
      final result = payment.toJson();

      expect(result['dueAt'], equals(Timestamp.fromDate(dueAt)));
    });

    // toJson round-trip: null dueAt → key absent or null
    test('toJson round-trips null dueAt as null', () {
      final payment = Payment.fromJson(Map.of(baseJson));
      final result = payment.toJson();

      expect(result['dueAt'], isNull);
    });
  });
}
