import 'package:freezed_annotation/freezed_annotation.dart';

import 'gym.dart';

part 'gym_brand.freezed.dart';

/// Pure grouping view model — NOT persisted to Firestore (no `fromJson`).
///
/// Groups the flat `gyms/` catalog (each doc = one sucursal) into brands for
/// the two-step picker (step 1: brands, step 2: branches within a brand).
///
/// `branchCount == 1` signals the picker should SKIP step 2 and resolve
/// [singleBranchGymId] directly — that's the case for independent gyms
/// (single-location, brandId maps to their own doc id).
@freezed
class GymBrand with _$GymBrand {
  const factory GymBrand({
    required String brandId,
    required String brandName,
    required int branchCount,
    String? singleBranchGymId,
  }) = _GymBrand;

  const GymBrand._();

  /// Groups [gyms] by `(brandId ?? id)` — old docs seeded before this
  /// migration have a null `brandId` and fall back to their own doc id,
  /// which also makes them single-branch brands (`branchCount == 1`).
  static List<GymBrand> groupFrom(List<Gym> gyms) {
    final byBrandId = <String, List<Gym>>{};
    for (final gym in gyms) {
      final key = gym.brandId ?? gym.id;
      byBrandId.putIfAbsent(key, () => []).add(gym);
    }

    return byBrandId.entries.map((entry) {
      final branches = entry.value;
      final first = branches.first;
      return GymBrand(
        brandId: entry.key,
        brandName: first.brandName ?? first.name,
        branchCount: branches.length,
        singleBranchGymId: branches.length == 1 ? branches.single.id : null,
      );
    }).toList(growable: false);
  }
}
