/// Pure-Dart geohash encoding — 5-character precision (~4.9km × 4.9km cell).
///
/// Uses the standard geohash base32 alphabet:
///   '0123456789bcdefghjkmnpqrstuvwxyz'
///
/// Algorithm:
///   1. Interleave 25 bits: bit 0 = longitude, bit 1 = latitude, repeating.
///   2. Group into five 5-bit chunks.
///   3. Map each chunk to the base32 alphabet.
///
/// REQ-COACH-DISC-DATA-011.
const _kBase32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Encodes [lat] / [lon] as a 5-character geohash string.
///
/// [lat] must be in the range [-90, 90].
/// [lon] must be in the range [-180, 180].
String geohash5(double lat, double lon) {
  double minLat = -90.0, maxLat = 90.0;
  double minLon = -180.0, maxLon = 180.0;

  final bits = List<int>.filled(25, 0);
  bool isLon = true; // geohash alternates: longitude first, then latitude

  for (var i = 0; i < 25; i++) {
    if (isLon) {
      final mid = (minLon + maxLon) / 2;
      if (lon >= mid) {
        bits[i] = 1;
        minLon = mid;
      } else {
        bits[i] = 0;
        maxLon = mid;
      }
    } else {
      final mid = (minLat + maxLat) / 2;
      if (lat >= mid) {
        bits[i] = 1;
        minLat = mid;
      } else {
        bits[i] = 0;
        maxLat = mid;
      }
    }
    isLon = !isLon;
  }

  final buffer = StringBuffer();
  for (var i = 0; i < 25; i += 5) {
    final val = bits[i] * 16 +
        bits[i + 1] * 8 +
        bits[i + 2] * 4 +
        bits[i + 3] * 2 +
        bits[i + 4];
    buffer.write(_kBase32[val]);
  }
  return buffer.toString();
}

// ── Neighbor expansion ─────────────────────────────────────────────────────
//
// Standard geohash adjacency tables (Gustavo Niemeyer's reference algorithm).
// `_kNeighbors[dir][parity]` maps each base32 char to the char of the adjacent
// cell in direction `dir`; `_kBorders[dir][parity]` lists the chars that sit on
// that border (requiring a carry into the parent prefix). `parity` is 0 for an
// even-length hash and 1 for odd.

const _kNeighbors = <String, List<String>>{
  'n': ['p0r21436x8zb9dcf5h7kjnmqesgutwvy', 'bc01fg45238967deuvhjyznpkmstqrwx'],
  's': ['14365h7k9dcfesgujnmqp0r2twvyx8zb', '238967debc01fg45kmstqrwxuvhjyznp'],
  'e': ['bc01fg45238967deuvhjyznpkmstqrwx', 'p0r21436x8zb9dcf5h7kjnmqesgutwvy'],
  'w': ['238967debc01fg45kmstqrwxuvhjyznp', '14365h7k9dcfesgujnmqp0r2twvyx8zb'],
};

const _kBorders = <String, List<String>>{
  'n': ['prxz', 'bcfguvyz'],
  's': ['028b', '0145hjnp'],
  'e': ['bcfguvyz', 'prxz'],
  'w': ['0145hjnp', '028b'],
};

/// Returns the geohash cell adjacent to [geohash] in cardinal direction [dir]
/// (`'n'`, `'s'`, `'e'`, `'w'`). Preserves the input length.
String _adjacent(String geohash, String dir) {
  final source = geohash.toLowerCase();
  final lastCh = source[source.length - 1];
  var parent = source.substring(0, source.length - 1);
  final type = source.length % 2; // 0 = even, 1 = odd
  if (_kBorders[dir]![type].contains(lastCh) && parent.isNotEmpty) {
    parent = _adjacent(parent, dir);
  }
  return parent + _kBase32[_kNeighbors[dir]![type].indexOf(lastCh)];
}

/// Returns the 8 geohash cells surrounding [geohash] (4 cardinal + 4 diagonal),
/// each at the same precision as the input.
///
/// Used to widen a geohash proximity query so trainers in cells adjacent to the
/// athlete's own cell are not dropped at cell boundaries. Combine with the
/// athlete's own cell to build a 3×3 grid (9 cells total), which stays within
/// Firestore's `array-contains-any` 30-value limit.
List<String> geohashNeighbors(String geohash) {
  final n = _adjacent(geohash, 'n');
  final s = _adjacent(geohash, 's');
  return [
    n,
    s,
    _adjacent(geohash, 'e'),
    _adjacent(geohash, 'w'),
    _adjacent(n, 'e'),
    _adjacent(n, 'w'),
    _adjacent(s, 'e'),
    _adjacent(s, 'w'),
  ];
}

/// Returns the 24 geohash cells forming the two rings around [geohash] (a 5×5
/// block minus the center), each at the same precision as the input.
///
/// Widens [geohashNeighbors] (3×3 / 8 cells, ~15km) to a 5×5 grid (~25km) so a
/// trainer up to ~2 cells from the athlete is not dropped at the proximity
/// stage — the 3×3 grid silently missed a trainer only ~9.8km away that landed
/// in a cell just beyond the immediate ring. Combine with the athlete's own
/// cell for 25 values total, still within Firestore's `array-contains-any`
/// 30-value limit. A 7×7 block (49 cells) would EXCEED that limit and require a
/// different query strategy.
List<String> geohashNeighbors5x5(String geohash) {
  // Ring 2 = the neighbors of every ring-1 cell. Unioning the neighbors of the
  // 3×3 block extends coverage exactly one ring further out (to 5×5); the Set
  // dedupes the interior cells the expansion revisits.
  final ring1 = geohashNeighbors(geohash);
  final grid = <String>{...ring1};
  for (final cell in ring1) {
    grid.addAll(geohashNeighbors(cell));
  }
  grid.remove(geohash); // center is prepended by the caller, as with geohashNeighbors
  return grid.toList();
}
