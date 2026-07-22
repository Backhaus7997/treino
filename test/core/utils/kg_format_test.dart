import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/kg_format.dart';

void main() {
  group('formatWeightKg', () {
    test('null → empty string (empty editor field)', () {
      expect(formatWeightKg(null), '');
    });

    test('0 renders as plain 0', () {
      expect(formatWeightKg(0), '0');
    });

    test('whole numbers drop the decimal', () {
      expect(formatWeightKg(20.0), '20');
      expect(formatWeightKg(60.0), '60');
      expect(formatWeightKg(100.0), '100');
    });

    test('fractional values keep their decimals as typed', () {
      expect(formatWeightKg(17.5), '17.5');
      expect(formatWeightKg(17.25), '17.25');
      expect(formatWeightKg(0.5), '0.5');
    });

    test('never compacts, even at the top of the plausible range', () {
      expect(formatWeightKg(227.5), '227.5');
      expect(formatWeightKg(500.0), '500');
    });
  });

  group('formatVolumeKg — full number below 10 000', () {
    test('0 (bodyweight-only session) renders as 0, not 0.0', () {
      expect(formatVolumeKg(0), '0');
    });

    test('small fractional volume keeps one decimal', () {
      expect(formatVolumeKg(3.2), '3.2');
    });

    test('whole volumes drop the decimal', () {
      expect(formatVolumeKg(600.0), '600');
      expect(formatVolumeKg(1800.0), '1800');
      expect(formatVolumeKg(3880.0), '3880');
    });

    test('fractional volumes round to one decimal', () {
      expect(formatVolumeKg(987.5), '987.5');
      expect(formatVolumeKg(999.9), '999.9');
      expect(formatVolumeKg(1234.5), '1234.5');
      expect(formatVolumeKg(3880.75), '3880.8');
    });

    test('exactly 1000 stays full — compaction starts at 10 000', () {
      expect(formatVolumeKg(1000.0), '1000');
    });

    test('just below the threshold stays full', () {
      expect(formatVolumeKg(9999.0), '9999');
      expect(formatVolumeKg(9999.5), '9999.5');
    });
  });

  group('formatVolumeKg — compact from 10 000', () {
    test('exactly 10 000 compacts and drops the redundant .0', () {
      expect(formatVolumeKg(10000.0), '10k');
    });

    test('whole thousands drop the redundant .0', () {
      expect(formatVolumeKg(12000.0), '12k');
      expect(formatVolumeKg(100000.0), '100k');
    });

    test('floors — a headline never inflates', () {
      // 20 770 rounds to 20.8k; flooring keeps it honest at 20.7k.
      expect(formatVolumeKg(20770.0), '20.7k');
      expect(formatVolumeKg(34580.0), '34.5k');
      expect(formatVolumeKg(49480.0), '49.4k');
      // 10 099 must not round up to 10.1k.
      expect(formatVolumeKg(10099.0), '10k');
      expect(formatVolumeKg(99999.0), '99.9k');
    });

    test('one decimal survives when meaningful', () {
      expect(formatVolumeKg(10100.0), '10.1k');
      expect(formatVolumeKg(13900.0), '13.9k');
    });

    test('well above 100k keeps the same floored rule', () {
      expect(formatVolumeKg(123456.0), '123.4k');
    });
  });
}
