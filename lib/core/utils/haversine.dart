import 'dart:math' show asin, cos, pi, sin, sqrt;

/// Returns the great-circle distance in kilometres between two geographic
/// coordinates using the Haversine formula.
///
/// [lat1], [lon1] — origin in decimal degrees.
/// [lat2], [lon2] — destination in decimal degrees.
///
/// Returns 0.0 when both points are identical.
/// REQ-COACH-DISC-DATA-010.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * asin(sqrt(a));
  return earthRadiusKm * c;
}

double _toRad(double deg) => deg * pi / 180.0;
