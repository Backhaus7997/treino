import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/gym_repository.dart';
import '../domain/gym.dart';
import '../domain/gym_brand.dart';

final gymRepositoryProvider = Provider<GymRepository>(
  (ref) => GymRepository(firestore: ref.watch(firestoreProvider)),
);

/// Catálogo completo de gyms — lectura eager, ~20 docs.
final gymsProvider = FutureProvider<List<Gym>>((ref) async {
  return ref.watch(gymRepositoryProvider).listAll();
});

/// Single-gym lookup. Lo consumen widgets que muestran el nombre del gym
/// asociado a una `TrainerLocation` con `type == gym` y `gymId` setteado.
final gymByIdProvider = FutureProvider.family<Gym?, String>(
  (ref, id) async {
    return ref.watch(gymRepositoryProvider).getById(id);
  },
);

/// Step 1 del picker de dos niveles: agrupa el catálogo (`gymsProvider`) por
/// marca. Deriva del mismo `AsyncValue` que ya cachea Riverpod — no hace un
/// fetch propio. Ver `GymBrand.groupFrom` para la lógica de agrupación.
final gymBrandsProvider =
    FutureProvider.autoDispose<List<GymBrand>>((ref) async {
  final gyms = await ref.watch(gymsProvider.future);
  return GymBrand.groupFrom(gyms);
});

/// Step 2 del picker: sucursales de una marca específica. `family` por
/// `brandId` — filtra el mismo catálogo ya cacheado por `gymsProvider`.
final branchesForBrandProvider =
    FutureProvider.autoDispose.family<List<Gym>, String>((ref, brandId) async {
  final gyms = await ref.watch(gymsProvider.future);
  return gyms.where((g) => (g.brandId ?? g.id) == brandId).toList(
        growable: false,
      );
});

/// Query de búsqueda compartido entre step 1 (marcas) y step 2 (sucursales)
/// del picker de dos niveles. `autoDispose`: se destruye al salir del picker.
final gymBrandSearchQueryProvider = StateProvider.autoDispose<String>(
  (_) => '',
);
