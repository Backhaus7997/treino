import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/geohash.dart';

void main() {
  // SCENARIO-422: geohash5 returns 5-char string for known reference points.
  // Reference values computed via standard geohash algorithm with
  // base32 alphabet '0123456789bcdefghjkmnpqrstuvwxyz'.
  group('geohash5', () {
    test('SCENARIO-422: Buenos Aires returns 5-char geohash with known prefix',
        () {
      // Buenos Aires: lat=-34.6037, lon=-58.3816 → expected '69y7p'
      final result = geohash5(-34.6037, -58.3816);
      expect(result.length, equals(5));
      expect(result, equals('69y7p'));
    });

    test('result is always exactly 5 characters', () {
      expect(geohash5(0.0, 0.0).length, equals(5));
      expect(geohash5(51.5074, -0.1278).length, equals(5));
      expect(geohash5(-33.4489, -70.6693).length, equals(5));
    });

    test('London returns known geohash', () {
      // London: lat=51.5074, lon=-0.1278 → expected 'gcpvj'
      expect(geohash5(51.5074, -0.1278), equals('gcpvj'));
    });

    test('origin (0.0, 0.0) returns known geohash', () {
      // (0.0, 0.0) → expected 's0000'
      expect(geohash5(0.0, 0.0), equals('s0000'));
    });

    test('nearby points share common prefix', () {
      // Points very close to Buenos Aires should share the same 5-char prefix
      // or at least the first 4 chars (geohash spatial locality property).
      final ba = geohash5(-34.6037, -58.3816);
      final baNearby = geohash5(-34.6038, -58.3817);
      // Same first 4 chars at minimum for sub-100m offset
      expect(ba.substring(0, 4), equals(baNearby.substring(0, 4)));
    });

    test('only uses geohash base32 alphabet characters', () {
      const alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';
      for (final coords in [
        (-34.6037, -58.3816),
        (51.5074, -0.1278),
        (0.0, 0.0),
        (90.0, 180.0),
        (-90.0, -180.0),
      ]) {
        final h = geohash5(coords.$1, coords.$2);
        for (final ch in h.split('')) {
          expect(alphabet.contains(ch), isTrue,
              reason: 'Character "$ch" not in base32 alphabet');
        }
      }
    });
  });
}
