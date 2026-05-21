import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/check_in/domain/check_in.dart';

void main() {
  group('CheckIn.dateKey', () {
    test('SCENARIO-326-datekey: formats standard date with zero-padding', () {
      expect(
        CheckIn.dateKey(DateTime(2026, 5, 15)),
        equals('2026-05-15'),
      );
    });

    test('pads single-digit month and day', () {
      expect(
        CheckIn.dateKey(DateTime(2026, 1, 3)),
        equals('2026-01-03'),
      );
    });

    test('pads year to 4 digits for small years', () {
      expect(
        CheckIn.dateKey(DateTime(99, 5, 15)),
        equals('0099-05-15'),
      );
    });
  });

  group('CheckIn fromJson/toJson', () {
    test(
        'SCENARIO-326: roundtrip with all fields present including gymId/gymName',
        () {
      final now = DateTime.utc(2026, 5, 15, 10, 0, 0);
      final ts = Timestamp.fromDate(now);

      final json = <String, Object?>{
        'uid': 'user1',
        'date': '2026-05-15',
        'checkedInAt': ts,
        'gymId': 'smart-fit-palermo',
        'gymName': 'Smart Fit · Palermo',
      };

      final checkIn = CheckIn.fromJson(json);
      expect(checkIn.uid, equals('user1'));
      expect(checkIn.date, equals('2026-05-15'));
      expect(checkIn.gymId, equals('smart-fit-palermo'));
      expect(checkIn.gymName, equals('Smart Fit · Palermo'));
    });

    test('SCENARIO-326: gymId and gymName may be null without error', () {
      final ts = Timestamp.fromDate(DateTime.utc(2026, 5, 15));
      final json = <String, Object?>{
        'uid': 'user1',
        'date': '2026-05-15',
        'checkedInAt': ts,
        'gymId': null,
        'gymName': null,
      };

      final checkIn = CheckIn.fromJson(json);
      expect(checkIn.gymId, isNull);
      expect(checkIn.gymName, isNull);
    });

    test('toJson roundtrip preserves all fields', () {
      final now = DateTime.utc(2026, 5, 15, 10, 0, 0);
      final checkIn = CheckIn(
        uid: 'user1',
        date: '2026-05-15',
        checkedInAt: now,
        gymId: 'gym1',
        gymName: 'Gym Name',
      );

      final json = checkIn.toJson();
      final deserialized = CheckIn.fromJson(json);
      expect(deserialized.uid, equals(checkIn.uid));
      expect(deserialized.date, equals(checkIn.date));
      expect(deserialized.gymId, equals(checkIn.gymId));
      expect(deserialized.gymName, equals(checkIn.gymName));
    });
  });
}
