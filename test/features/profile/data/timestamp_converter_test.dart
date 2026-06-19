import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/timestamp_converter.dart';

void main() {
  const converter = TimestampConverter();

  group('TimestampConverter', () {
    final dt = DateTime.utc(2026, 5, 11, 13, 30);
    final ts = Timestamp.fromDate(dt);

    test('toJson returns a Timestamp instance', () {
      expect(converter.toJson(dt), isA<Timestamp>());
    });

    test('fromJson returns a DateTime', () {
      expect(converter.fromJson(ts), isA<DateTime>());
    });

    test('roundtrip fromJson(toJson(dt)) == dt at millisecond precision', () {
      final roundtripped = converter.fromJson(converter.toJson(dt));
      expect(roundtripped, equals(dt));
    });

    test('fromJson known epoch → expected DateTime', () {
      final epoch = Timestamp.fromMillisecondsSinceEpoch(1715432400000);
      final result = converter.fromJson(epoch);
      expect(
        result.millisecondsSinceEpoch,
        equals(1715432400000),
      );
    });
  });

  group('TimestampMapConverter', () {
    const mapConverter = TimestampMapConverter();

    final dt1 = DateTime.utc(2026, 5, 11, 13, 30, 0, 500);
    final dt2 = DateTime.utc(2026, 6, 1, 8, 0);

    test('toJson values are Timestamp instances', () {
      final result = mapConverter.toJson({'uid-a': dt1, 'uid-b': dt2});
      expect(result['uid-a'], isA<Timestamp>());
      expect(result['uid-b'], isA<Timestamp>());
    });

    test('fromJson returns UTC DateTimes', () {
      final json = {
        'uid-a': Timestamp.fromDate(dt1),
      };
      final result = mapConverter.fromJson(json);
      expect(result['uid-a']!.isUtc, isTrue);
    });

    test('roundtrip preserves milliseconds', () {
      final original = {'uid-x': dt1};
      final roundtripped = mapConverter.fromJson(mapConverter.toJson(original));
      expect(roundtripped['uid-x'], equals(dt1));
    });

    test('empty map round-trips to empty map', () {
      final result = mapConverter.fromJson(mapConverter.toJson({}));
      expect(result, isEmpty);
    });

    test('multi-key map decoded correctly', () {
      final json = <String, Object?>{
        'uid-a': Timestamp.fromDate(dt1),
        'uid-b': Timestamp.fromDate(dt2),
      };
      final result = mapConverter.fromJson(json);
      expect(result.length, 2);
      expect(result['uid-a'], equals(dt1));
      expect(result['uid-b'], equals(dt2));
    });

    test('non-null both sides contract — toJson then fromJson is identity', () {
      final original = {'uid-a': dt1, 'uid-b': dt2};
      final json = mapConverter.toJson(original);
      final back = mapConverter.fromJson(json);
      expect(back, equals(original));
    });
  });
}
