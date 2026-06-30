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

  // Neighbor expansion — fixes trainer discovery dropping nearby trainers
  // across geohash cell boundaries (3×3 grid query).
  group('geohashNeighbors', () {
    test('NEIGHBORS-001: returns the 8 surrounding cells for Buenos Aires', () {
      // Buenos Aires geohash5 '69y7p'. Expected adjacency per the standard
      // geohash algorithm (no prefix carry needed for this interior cell):
      //   N=69y7r S=69y6z E=69ye0 W=69y7n
      //   NE=69ye2 NW=69y7q SE=69ydb SW=69y6y
      final ba = geohash5(-34.6037, -58.3816);
      expect(ba, equals('69y7p'));

      final neighbors = geohashNeighbors(ba);
      expect(
        neighbors,
        containsAll(<String>[
          '69y7r', '69y6z', '69ye0', '69y7n', // N S E W
          '69ye2', '69y7q', '69ydb', '69y6y', // NE NW SE SW
        ]),
      );
    });

    test('NEIGHBORS-002: returns exactly 8 distinct cells, none equal to self',
        () {
      final neighbors = geohashNeighbors('69y7p');
      expect(neighbors.length, equals(8));
      expect(neighbors.toSet().length, equals(8));
      expect(neighbors, isNot(contains('69y7p')));
    });

    test('NEIGHBORS-003: every neighbor preserves the 5-char precision', () {
      for (final n in geohashNeighbors('gcpvj')) {
        expect(n.length, equals(5));
      }
    });

    test('NEIGHBORS-004: handles prefix carry at a cell border', () {
      // The eastern neighbor of '69y7p' is '69ye0', which requires a carry
      // into the parent prefix (last char 'p' is on the east border). This
      // exercises the recursive _adjacent path, not just a same-prefix flip.
      expect(geohashNeighbors('69y7p'), contains('69ye0'));
    });
  });

  group('geohashNeighbors5x5', () {
    test('NEIGHBORS5X5-001: returns exactly 24 distinct cells, none equal to self',
        () {
      final ring = geohashNeighbors5x5('69y7p');
      expect(ring.length, equals(24));
      expect(ring.toSet().length, equals(24));
      expect(ring, isNot(contains('69y7p')));
    });

    test('NEIGHBORS5X5-002: with the center cell stays within Firestore\'s 30-value limit',
        () {
      // Caller builds [center, ...neighbors5x5] → must be <= 30 for the
      // `array-contains-any` query. 5×5 = 25 cells, the safe maximum.
      final cells = ['69y7p', ...geohashNeighbors5x5('69y7p')];
      expect(cells.length, equals(25));
      expect(cells.length, lessThanOrEqualTo(30));
    });

    test('NEIGHBORS5X5-003: is a superset of the 3×3 ring (contains all 8 immediate neighbors)',
        () {
      final ring5 = geohashNeighbors5x5('69y7p').toSet();
      expect(ring5, containsAll(geohashNeighbors('69y7p')));
    });

    test('NEIGHBORS5X5-004: every cell preserves the 5-char precision', () {
      for (final c in geohashNeighbors5x5('gcpvj')) {
        expect(c.length, equals(5));
      }
    });
  });
}
