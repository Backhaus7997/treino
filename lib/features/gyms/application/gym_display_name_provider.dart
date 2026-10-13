import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/gym.dart';
import '../domain/gym_display_name.dart';
import '../domain/gym_source.dart';
import 'gym_providers.dart';
import 'places_providers.dart';

/// Nombre a MOSTRAR de un gym — ÚNICA fuente para toda la UI.
///
/// - `null` / vacío / [kNoGymId] → `''` (el llamador oculta el subtítulo).
/// - Gym de Google Places → el `displayName` de Google pedido EN VIVO
///   (Place Details, máscara `displayName`). Los términos de Google Maps
///   Platform prohíben guardar su contenido, así que el nombre vive sólo en
///   la memoria de la sesión: este provider es `autoDispose` y se "fija"
///   (`keepAlive`) únicamente cuando Google contestó, de modo que un fallo de
///   red no queda cacheado toda la sesión.
/// - Si el pedido falla o viene vacío, cae al `gym.name` guardado (para un gym
///   nuevo es el marcador [kGymPlaceholderName]).
/// - Gyms sembrados / autogestionados → el `name` guardado.
final gymDisplayNameProvider =
    FutureProvider.autoDispose.family<String, String?>((ref, gymId) async {
  if (!hasRealGym(gymId)) return '';
  final gym = await ref.watch(gymByIdProvider(gymId!).future);
  if (gym == null) return '';

  if (gym.source == GymSource.googlePlaces) {
    try {
      final live = await ref
          .read(resolveGymPlaceServiceProvider)
          .fetchDisplayName(gym.id);
      if (live != null) {
        ref.keepAlive();
        return live;
      }
    } catch (_) {
      // Sin red / sin key / Google caído: se muestra el nombre guardado.
    }
  }
  return gymDisplayNameFromGym(gym);
});
