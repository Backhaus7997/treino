import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/moderation/moderation_guard.dart';
import '../../../../core/telemetry/non_fatal.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../gyms/application/places_providers.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../../gyms/presentation/gym_name_dialog.dart';
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
/// `ProfileSetupNotifier.submit()`, que lo manda en su parcial y hace el
/// dual-write de `gymName` leyendo ese `gyms/{placeId}`.
///
/// Un gym NUEVO se nombra acá, pero el nombre queda en el draft
/// (`pendingGymName`) y el doc compartido se CREA en el submit, antes del
/// update de `users/{uid}`: crearlo al elegir dejaba el nombre de alguien que
/// después elegía otro gimnasio o abandonaba el alta (#1338).
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

  Future<void> _onGymIdSelected(
    BuildContext context,
    WidgetRef ref,
    String? gymId,
  ) async {
    final notifier = ref.read(profileSetupNotifierProvider.notifier);
    if (gymId == null || gymId == kNoGymId) {
      notifier.updateGymId(kNoGymId);
      return;
    }

    // Todo lo que se usa después del await se toma ANTES: leer `ref` o
    // `context` con la operación en vuelo tiraba "Cannot use ref after the
    // widget was disposed" cuando la pantalla se desmontaba en el medio, y el
    // gimnasio nunca llegaba al draft.
    final resolver = ref.read(resolveGymPlaceServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);

    try {
      var result = await resolver.call(placeId: gymId, name: null);
      if (result.needsName && !result.existsUnnamed) {
        // Gym nuevo: lo nombra quien lo crea. Un gym que ya existe sin
        // nombre de usuario NO se nombra acá: la regla de Firestore sólo deja
        // a quien ya está vinculado (`users/{uid}.gymId`), y en el alta ese
        // doc todavía no existe. Queda en el draft y lo nombra su primer
        // usuario vinculado desde el perfil.
        if (!context.mounted) return;
        final typed = await showGymNameDialog(context);
        if (typed == null) return;
        // El nombre se valida acá (feedback inmediato) pero se ESCRIBE en el
        // submit: el gym compartido no puede quedar con el nombre de alguien
        // que después elige otro o abandona el alta (#1338).
        ModerationGuard.ensure(typed, campo: 'gym.name');
        notifier.updateGymId(gymId, pendingName: typed.trim());
        return;
      }
      notifier.updateGymId(result.gymId);
    } on ModerationBlockedException {
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.moderationBlockedMessage)),
        );
      }
    } catch (e, st) {
      // Antes esto no avisaba a nadie: ni al usuario, que tocaba el gimnasio
      // y no pasaba nada, ni a Crashlytics. Por eso el bug de `bornAtOk` se
      // vio como «el gimnasio no se deja elegir» y no como lo que era.
      unawaited(reportNonFatal(
        e,
        st,
        reason: 'Step3Gym: no se pudo resolver el gimnasio elegido en el alta',
      ));
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.profileSetupGymSelectError)),
        );
      }
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
          onGymIdSelected: (gymId) => _onGymIdSelected(context, ref, gymId),
        ),
      ),
    );
  }
}
