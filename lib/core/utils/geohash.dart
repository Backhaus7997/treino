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
