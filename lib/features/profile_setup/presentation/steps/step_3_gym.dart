import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../widgets/gym_search_box.dart';

/// Step 3: single Google Places search box (Text Search, AD-12) +
/// `kNoGymId` ("OTRO/SIN GYM") option. Mockup: `profile-setup-2.png`.
///
/// Replaces the retired two-step brand→sucursal picker (`GymBrand`,
/// `gymBrandsProvider`, `branchesForBrandProvider`) per spec gym-catalog
/// "Athlete gym selection is a single debounced search".
///
/// Tocar un gimnasio lo RESUELVE en el acto (`ResolveGymPlaceService`: LEE
/// `gyms/{placeId}`) y lo deja en el draft. El `gymId` del usuario lo persiste
/// `ProfileSetupNotifier.submit()`, que lo manda en su parcial.
///
/// Tocar un gimnasio sólo lo deja en el draft (no resuelve ni escribe nada).
/// El submit crea `gyms/{placeId}` con un marcador como nombre si no existe y
/// el nombre de Google se muestra en vivo, sin guardarse (política de Places,
/// #1338). Nadie nombra el gym.
///
/// Este paso NO escribe `users/{uid}`, y no es un detalle. Hasta sep-2026
/// escribía `{'gymId': ...}` ahí (vía `selectGymActionProvider`), apoyado en
/// que "`users/{uid}` no necesita existir todavía, porque es un
/// `set(merge: true)`". Era falso: sobre un doc inexistente ese merge se
/// evalúa como CREATE, y la regla de create exige `uid` y `role`, que el
/// parcial no trae. Andaba sólo porque el alta siempre creaba el doc antes.
/// Cuando dejó de crearlo (`bornAtOk` de firestore.rules denegaba el
/// `bornAt: null` que manda `toJson()`), este paso empezó a fallar en
/// silencio y el onboarding quedó con una sola salida: «OTRO GYM / SIN GYM».
/// Y una sesión restaurada sin doc (ver el doc de `submit()`) llega acá
/// igual, con o sin ese bug. Sin la escritura, el paso no depende de que el
/// doc exista, y el gimnasio se guarda recién en el submit, junto con el
/// resto del alta.
///
/// ASIMETRÍA con `ProfileGymScreen` (issue #814): allá el usuario ya tiene su
/// doc completo, y GUARDAR —vía `selectGymActionProvider`— es el único punto
/// de persistencia. Acá ese punto es el `submit()` del alta.
///
/// Either way, `profileSetupNotifierProvider`'s draft is kept in sync
/// (`updateGymId`) so `submit()`'s `draft.gymId` read and the search box's
/// `selected` highlight stay consistent.
class Step3Gym extends ConsumerWidget {
  const Step3Gym({super.key});

  /// Sólo deja el gym en el draft. El doc compartido `gyms/{placeId}` se crea
  /// en el submit: crearlo al tocar dejaba docs huérfanos en un catálogo que
  /// lee todo el mundo si el usuario cambiaba de gym o abandonaba el alta.
  void _onGymIdSelected(WidgetRef ref, String? gymId) {
    final notifier = ref.read(profileSetupNotifierProvider.notifier);
    notifier.updateGymId(
      gymId == null || gymId == kNoGymId ? kNoGymId : gymId,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedGymId = ref.watch(
      profileSetupNotifierProvider.select(
        (ProfileSetupState s) => s.draft.gymId,
      ),
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: GymSearchBox(
          selectedGymId: selectedGymId,
          onGymIdSelected: (gymId) => _onGymIdSelected(ref, gymId),
        ),
      ),
    );
  }
}
