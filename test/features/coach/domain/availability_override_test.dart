import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/availability_override.dart';

void main() {
  group('AvailabilityOverride.block', () {
    test(
      'SCENARIO-480: block-type round-trips with type=block and no time fields',
      () {
        final ov = AvailabilityOverride.block(
          id: 'ov-block-001',
          trainerId: 'tA',
          date: DateTime.utc(2026, 6, 1),
        );
        final decoded = AvailabilityOverride.fromJson(ov.toJson());
        expect(decoded, equals(ov));
        // Discriminator preserved
        expect(
          decoded.when(
            block: (_, __, ___) => 'block',
            extra: (_, __, ___, ____, _____, ______, _______, ________) =>
                'extra',
          ),
          'block',
        );
      },
    );

    test('block-type fromJson accepts Firestore Timestamp for date', () {
      final rawMap = <String, dynamic>{
        'id': 'ov-block-002',
        'trainerId': 'tA',
        'date': Timestamp.fromDate(DateTime.utc(2026, 6, 1)),
        'type': 'block',
      };
      final decoded = AvailabilityOverride.fromJson(rawMap);
      expect(decoded.id, 'ov-block-002');
      expect(decoded.date, DateTime.utc(2026, 6, 1));
      expect(
        decoded.when(
          block: (_, __, ___) => 'block',
          extra: (_, __, ___, ____, _____, ______, _______, ________) =>
              'extra',
        ),
        'block',
      );
    });
  });

  group('AvailabilityOverride.extra', () {
    test(
      'SCENARIO-481: extra-type round-trips with all time fields preserved',
      () {
        final ov = AvailabilityOverride.extra(
          id: 'ov-extra-001',
          trainerId: 'tA',
          date: DateTime.utc(2026, 6, 15),
          startHour: 10,
          startMinute: 0,
          endHour: 12,
          endMinute: 0,
          slotDurationMin: 60,
        );
        final decoded = AvailabilityOverride.fromJson(ov.toJson());
        expect(decoded, equals(ov));
        decoded.when(
          block: (_, __, ___) => fail('expected extra'),
          extra: (id, trainerId, date, sh, sm, eh, em, dur) {
            expect(sh, 10);
            expect(sm, 0);
            expect(eh, 12);
            expect(em, 0);
            expect(dur, 60);
            return 'ok';
          },
        );
      },
    );

    test(
      'extra-type with slotDurationMin: 45 throws on construction',
      () {
        expect(
          () => AvailabilityOverride.extra(
            id: 'ov-extra-bad',
            trainerId: 'tA',
            date: DateTime.utc(2026, 6, 15),
            startHour: 10,
            startMinute: 0,
            endHour: 12,
            endMinute: 0,
            slotDurationMin: 45,
          ),
          throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
        );
      },
    );
  });
}
