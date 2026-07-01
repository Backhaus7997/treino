import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_brand.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';

Gym _gym({
  required String id,
  required String name,
  String? brandId,
  String? brandName,
  String? branchName,
}) =>
    Gym(
      id: id,
      name: name,
      lat: 0,
      lng: 0,
      geohash: 'x',
      source: GymSource.seed,
      createdAt: DateTime.utc(2026, 1, 1),
      brandId: brandId,
      brandName: brandName,
      branchName: branchName,
    );

void main() {
  group('GymBrand.groupFrom', () {
    test('groups multi-branch chain by brandId, counts branches', () {
      final gyms = [
        _gym(
          id: 'sportclub-belgrano',
          name: 'SportClub - Belgrano',
          brandId: 'sportclub',
          brandName: 'SportClub',
          branchName: 'Belgrano',
        ),
        _gym(
          id: 'sportclub-pilar',
          name: 'SportClub - Pilar',
          brandId: 'sportclub',
          brandName: 'SportClub',
          branchName: 'Pilar',
        ),
      ];

      final brands = GymBrand.groupFrom(gyms);

      expect(brands, hasLength(1));
      expect(brands.single.brandId, 'sportclub');
      expect(brands.single.brandName, 'SportClub');
      expect(brands.single.branchCount, 2);
      expect(brands.single.singleBranchGymId, isNull);
    });

    test('single-branch brand sets singleBranchGymId (step 2 skip signal)', () {
      final gyms = [
        _gym(
          id: 'sieger-gym-cba',
          name: 'Sieger Gym',
          brandId: 'sieger-gym-cba',
          brandName: 'Sieger Gym',
          branchName: null,
        ),
      ];

      final brands = GymBrand.groupFrom(gyms);

      expect(brands, hasLength(1));
      expect(brands.single.branchCount, 1);
      expect(brands.single.singleBranchGymId, 'sieger-gym-cba');
    });

    test('null brandId falls back to grouping by gym id (old docs)', () {
      final gyms = [
        _gym(id: 'megatlon-belgrano', name: 'Megatlon Belgrano'),
      ];

      final brands = GymBrand.groupFrom(gyms);

      expect(brands, hasLength(1));
      expect(brands.single.brandId, 'megatlon-belgrano');
      expect(brands.single.brandName, 'Megatlon Belgrano');
      expect(brands.single.singleBranchGymId, 'megatlon-belgrano');
    });
  });
}
