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
}
