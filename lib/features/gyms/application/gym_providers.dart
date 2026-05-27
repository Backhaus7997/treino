import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/gym_repository.dart';
import '../domain/gym.dart';

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
