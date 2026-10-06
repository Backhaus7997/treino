import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show userProfileProvider;
import '../domain/gym.dart';
import 'gym_providers.dart' show gymRepositoryProvider;

/// `gyms/{id}` en vivo. `autoDispose` para soltar el listener de Firestore
/// apenas nadie lo mira (sin keepAlive ni timers).
final gymStreamByIdProvider =
    StreamProvider.autoDispose.family<Gym?, String>((ref, id) {
  return ref.watch(gymRepositoryProvider).watchById(id);
});

/// El atleta/entrenador descartó la card «nombrá tu gimnasio» en esta sesión.
/// Vive lo que vive el `ProviderScope`: no se persiste a propósito, así que
/// vuelve a aparecer en la próxima apertura de la app si el gym sigue sin
/// nombre.
final gymNamePromptDismissedProvider = StateProvider<bool>((ref) => false);

/// El gym vinculado del usuario (`users/{uid}.gymId`) SOLO si está marcado
/// `nameNeeded`; `AsyncData(null)` si no hay gym, es el sentinel `no-gym`,
/// no existe o ya tiene nombre.
///
/// Cargando y error se propagan tal cual: el consumidor los trata como «no
/// mostrar». Un aviso opcional nunca debe bloquear ni ensuciar la pantalla
/// por un dato que todavía no llegó.
final gymNamePromptGymProvider = Provider.autoDispose<AsyncValue<Gym?>>((ref) {
  final gymId = ref.watch(
    userProfileProvider.select((async) => async.whenData((p) => p?.gymId)),
  );
  return gymId.when(
    loading: () => const AsyncLoading<Gym?>(),
    error: (e, st) => AsyncError<Gym?>(e, st),
    data: (id) {
      if (id == null || id.isEmpty || id == kNoGymId) {
        return const AsyncData<Gym?>(null);
      }
      return ref
          .watch(gymStreamByIdProvider(id))
          .whenData((gym) => gym != null && gym.nameNeeded ? gym : null);
    },
  );
});
