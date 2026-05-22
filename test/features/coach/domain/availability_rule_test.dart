import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';

void main() {
  group('AvailabilityRule JSON round-trip', () {
    test(
      'SCENARIO-478: round-trip preserves all fields and slotDurationMin in [30, 60, 90, 120]',
      () {
        for (final dur in const [30, 60, 90, 120]) {
          final rule = AvailabilityRule(
            id: 'r1',
            trainerId: 'tA',
            dayOfWeek: 1,
            startHour: 9,
            startMinute: 0,
            endHour: 11,
            endMinute: 0,
            slotDurationMin: dur,
          );
          final decoded = AvailabilityRule.fromJson(rule.toJson());
          expect(decoded, equals(rule));
          expect(decoded.slotDurationMin, dur);
          expect(const [30, 60, 90, 120].contains(decoded.slotDurationMin),
              isTrue);
        }
      },
    );

    test('full record with all fields round-trips cleanly', () {
      final rule = AvailabilityRule(
        id: 'r-mon-am',
        trainerId: 'trainer-1',
        dayOfWeek: 1,
        startHour: 7,
        startMinute: 30,
        endHour: 9,
        endMinute: 45,
        slotDurationMin: 60,
      );
      final decoded = AvailabilityRule.fromJson(rule.toJson());
      expect(decoded, equals(rule));
      expect(decoded.startMinute, 30);
      expect(decoded.endMinute, 45);
    });
  });

  group('AvailabilityRule slotDurationMin validation', () {
    test(
      'SCENARIO-479: deserialization with slotDurationMin: 45 throws AssertionError or ArgumentError',
      () {
        final invalid = <String, dynamic>{
          'id': 'r1',
          'trainerId': 'tA',
          'dayOfWeek': 1,
          'startHour': 9,
          'startMinute': 0,
          'endHour': 11,
          'endMinute': 0,
          'slotDurationMin': 45,
        };
        expect(
          () => AvailabilityRule.fromJson(invalid),
          throwsA(
            anyOf(isA<AssertionError>(), isA<ArgumentError>()),
          ),
        );
      },
    );

    test(
      'constructor with slotDurationMin: 15 also rejects (covers any 30 < x boundary)',
      () {
        expect(
          () => AvailabilityRule(
            id: 'r-bad',
            trainerId: 'tA',
            dayOfWeek: 1,
            startHour: 9,
            startMinute: 0,
            endHour: 11,
            endMinute: 0,
            slotDurationMin: 15,
          ),
          throwsA(
            anyOf(isA<AssertionError>(), isA<ArgumentError>()),
          ),
        );
      },
    );
  });
}
