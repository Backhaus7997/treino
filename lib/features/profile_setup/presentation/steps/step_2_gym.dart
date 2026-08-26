import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/auth_providers.dart'
    show firebaseAuthProvider;
import '../../../gyms/application/places_providers.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../widgets/gym_search_box.dart';

/// Step 2: single Google Places search box (Text Search, AD-12) +
/// `kNoGymId` ("OTRO/SIN GYM") option. Mockup: `profile-setup-2.png`.
///
/// Replaces the retired two-step brand→sucursal picker (`GymBrand`,
/// `gymBrandsProvider`, `branchesForBrandProvider`) per spec gym-catalog
/// "Athlete gym selection is a single debounced search".
///
/// Selecting a Google Places suggestion resolves it immediately via
/// `selectGymActionProvider` (server-side `resolveGymPlace` upsert of
/// `gyms/{placeId}` + `UserRepository.update({'gymId': ...})`, which
/// dual-writes `gymName`) — NOT deferred to `ProfileSetupNotifier.submit()`.
/// This guarantees the `gyms/{placeId}` doc exists before submit reads it,
/// since `submit()` only writes the raw `gymId` string and never calls
/// `resolveGymPlace` itself. `users/{uid}` doesn't need to exist yet:
/// `UserRepository.update` uses `set(..., merge: true)`, so this "early"
/// write during onboarding is safe and later merges cleanly with
/// `createIfAbsent` + the final `submit()` write.
///
/// `kNoGymId` needs no resolution — it updates the local draft only.
///
/// ASIMETRÍA DELIBERADA con `ProfileGymScreen` (issue #814): ahí el tap es
/// draft-only y GUARDAR es el único punto de persistencia, porque tocar un
/// gimnasio le pisaba al atleta un `gymId` YA EXISTENTE —el que alimenta sus
/// rankings y su feed por gimnasio— sin confirmación. Acá no hay nada que
/// pisar: el alta todavía no tiene `gymId`, el paso no se abandona sin
/// pasar por `submit()`, y la escritura temprana existe por una dependencia
/// real —`submit()` escribe el `gymId` crudo y NUNCA resuelve el Place, así
/// que `gyms/{placeId}` tiene que existir antes o el dual-write de
/// `gymName` queda vacío—. Diferir esto exigiría mover el resolve adentro de
/// `ProfileSetupNotifier.submit()`, que es otro cambio de contrato, no la
/// corrección de #814. Si alguien lo unifica algún día, que empiece por ahí.
///
/// Either way, `profileSetupNotifierProvider`'s draft is kept in sync
/// (`updateGymId`) so `submit()`'s `draft.gymId` read and the search box's
/// `selected` highlight stay consistent.
class Step2Gym extends ConsumerWidget {
  const Step2Gym({super.key});

  Future<void> _onGymIdSelected(WidgetRef ref, String? gymId) async {
    final notifier = ref.read(profileSetupNotifierProvider.notifier);
    if (gymId == null || gymId == kNoGymId) {
      notifier.updateGymId(kNoGymId);
      return;
    }

    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;

    // `select` devuelve el resultado en vez de dejarlo solo en el estado del
    // provider: leer `ref` DESPUÉS del await tiraba "Cannot use ref after the
    // widget was disposed" cuando la pantalla se desmontaba con la operación
    // en vuelo, y el gimnasio nunca se aplicaba al draft — el onboarding
    // quedaba trabado en este paso sin decir por qué.
    final ok = await ref
        .read(selectGymActionProvider.notifier)
        .select(uid: uid, placeId: gymId);
    if (ok) {
      notifier.updateGymId(gymId);
    }
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
