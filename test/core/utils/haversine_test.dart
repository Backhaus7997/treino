import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/haversine.dart';

void main() {
  // SCENARIO-420: haversineKm reference distance Buenos Aires → Santiago.
  // SCENARIO-421: haversineKm returns 0.0 for identical coordinates.
  group('haversineKm', () {
    test('SCENARIO-421: identical coordinates return 0.0', () {
      expect(haversineKm(-34.6037, -58.3816, -34.6037, -58.3816), equals(0.0));
      expect(haversineKm(0.0, 0.0, 0.0, 0.0), equals(0.0));
    });

    test('SCENARIO-420: Buenos Aires → Santiago ≈ 1139 km (±10 km tolerance)',
        () {
      // Buenos Aires: -34.6037, -58.3816
      // Santiago de Chile: -33.4489, -70.6693
      // Expected ≈ 1138.9 km
      final dist = haversineKm(-34.6037, -58.3816, -33.4489, -70.6693);
      expect(dist, greaterThan(1129.0));
      expect(dist, lessThan(1149.0));
    });

    test('Buenos Aires → La Plata ≈ 53 km (±3 km tolerance)', () {
      // Buenos Aires: -34.6037, -58.3816
      // La Plata: -34.9205, -57.9536
      // Expected ≈ 52.6 km
      final dist = haversineKm(-34.6037, -58.3816, -34.9205, -57.9536);
      expect(dist, greaterThan(49.0));
      expect(dist, lessThan(56.0));
    });

    test('is commutative (distance A→B == B→A)', () {
      final ab = haversineKm(-34.6037, -58.3816, -33.4489, -70.6693);
      final ba = haversineKm(-33.4489, -70.6693, -34.6037, -58.3816);
      expect((ab - ba).abs(), lessThan(0.001));
    });

    test('result is always non-negative', () {
      expect(haversineKm(10.0, 20.0, -10.0, -20.0), greaterThanOrEqualTo(0.0));
    });
  });
}
