import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
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
  group('gymBrandsProvider', () {
    test('groups gymsProvider results by brandId (multi-branch chain)',
        () async {
      final container = ProviderContainer(
        overrides: [
          gymsProvider.overrideWith((ref) async => [
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
              ]),
        ],
      );
      addTearDown(container.dispose);

      final brands = await container.read(gymBrandsProvider.future);

      expect(brands, hasLength(1));
      expect(brands.single.brandId, 'sportclub');
      expect(brands.single.branchCount, 2);
    });

    test('falls back to gym id as brand key when brandId is null (old docs)',
        () async {
      final container = ProviderContainer(
        overrides: [
          gymsProvider.overrideWith((ref) async => [
                _gym(id: 'megatlon-recoleta', name: 'Megatlon Recoleta'),
              ]),
        ],
      );
      addTearDown(container.dispose);

      final brands = await container.read(gymBrandsProvider.future);

      expect(brands, hasLength(1));
      expect(brands.single.brandId, 'megatlon-recoleta');
      expect(brands.single.singleBranchGymId, 'megatlon-recoleta');
    });

    test('propagates gymsProvider error', () async {
      final container = ProviderContainer(
        overrides: [
          gymsProvider.overrideWith((ref) async => throw Exception('boom')),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(gymBrandsProvider.future),
        throwsException,
      );
    });
  });

  group('branchesForBrandProvider', () {
    test('returns only the sucursales for the given brandId', () async {
      final container = ProviderContainer(
        overrides: [
          gymsProvider.overrideWith((ref) async => [
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
                _gym(
                  id: 'megatlon-recoleta',
                  name: 'Megatlon Recoleta',
                  brandId: 'megatlon-recoleta',
                  brandName: 'Megatlon',
                ),
              ]),
        ],
      );
      addTearDown(container.dispose);

      final branches =
          await container.read(branchesForBrandProvider('sportclub').future);

      expect(
          branches.map((g) => g.id), ['sportclub-belgrano', 'sportclub-pilar']);
    });

    test('returns empty list for unknown brandId', () async {
      final container = ProviderContainer(
        overrides: [
          gymsProvider.overrideWith((ref) async => [
                _gym(
                  id: 'megatlon-recoleta',
                  name: 'Megatlon Recoleta',
                  brandId: 'megatlon-recoleta',
                  brandName: 'Megatlon',
                ),
              ]),
        ],
      );
      addTearDown(container.dispose);

      final branches = await container
          .read(branchesForBrandProvider('does-not-exist').future);

      expect(branches, isEmpty);
    });
  });
}
