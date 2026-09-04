import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../profile/application/user_providers.dart';
import '../../../profile/domain/user_role.dart';
import '../../application/pending_invite_providers.dart';
import '../../application/trainer_link_providers.dart';
import '../../domain/invite_outcome.dart';
import 'invite_dialog.dart';

/// Widget invisible que aplica una invitación pendiente, una vez, apenas hay
/// sesión.
///
/// ─── Por qué acá y no en el router ─────────────────────────────────────────
///
/// Mismo criterio que [OnboardingGate], y por la misma cicatriz: `authRedirect`
/// ya carga siete gates entre dos roles y produjo #429, #499 y #615. Una
/// invitación no es precondición de nada — el peor caso acá es que el diálogo
/// no aparezca y el alumno se vincule a mano, que es exactamente lo que pasa
/// hoy. Ponerlo detrás de un redirect bloqueante sería el mismo error de
/// categoría que hizo el #429.
///
/// ─── Por qué un widget y no una llamada desde una pantalla ────────────────
///
/// El mini-onboarding de PLANTILLAS es una función que dispara UNA pantalla,
/// porque está anclado a esa pantalla. Una invitación no: llega por un link,
/// puede sobrevivir a un login, y tiene que dispararse en la pantalla en la que
/// el alumno aterrice. Es el problema de [OnboardingGate], no el del
/// mini-onboarding.
class InviteGate extends ConsumerStatefulWidget {
  const InviteGate({super.key});

  @override
  ConsumerState<InviteGate> createState() => _InviteGateState();
}

class _InviteGateState extends ConsumerState<InviteGate> {
  /// El uid para el que esta instancia ya resolvió la invitación.
  ///
  /// Latch de instancia, igual que en [OnboardingGate] y por lo mismo:
  /// `userProfileProvider` es un stream y re-emite. Sin esto, el diálogo se
  /// apila sobre sí mismo entre que se cierra y llega el snapshot siguiente.
  ///
  /// Va por cuenta y no por `bool` para que un segundo alumno que entre en el
  /// mismo teléfono reciba su propia invitación.
  String? _resueltaPara;

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(
      userProfileProvider.select((a) => a.valueOrNull),
    );
    final uid = perfil?.uid;

    // Sólo alumnos. Un PF no se vincula con otro PF, y el repositorio lo
    // rechaza igual.
    if (uid != null && perfil?.role == UserRole.athlete && uid != _resueltaPara) {
      _resueltaPara = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolver(uid));
    }
    return const SizedBox.shrink();
  }

  Future<void> _resolver(String uid) async {
    final store = ref.read(pendingInviteStoreProvider);
    if (store == null) return; // prefs sin resolver: no hay nada que aplicar
    final trainerId = await store.leer();
    if (trainerId == null || !mounted) return;

    final vinculo =
        await ref.read(currentAthleteLinkAnyStatusProvider.future);
    if (!mounted) return;

    final outcome = resolveInvite(
      inviteTrainerId: trainerId,
      athleteId: uid,
      vinculoActual: vinculo,
    );

    // Se limpia SIEMPRE, haya terminado en vínculo o no. Una invitación que el
    // alumno ya vio y canceló no puede volver a aparecer en el próximo
    // arranque; y una que no aplica —el PF abriendo su propio link— tampoco
    // tiene nada que esperar.
    await store.limpiar();
    if (!mounted || outcome is InviteNoAplica) return;

    await showInviteDialog(context, outcome);
  }
}
