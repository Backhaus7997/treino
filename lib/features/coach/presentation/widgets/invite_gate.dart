import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../profile/application/user_providers.dart';
import '../../../profile/domain/user_role.dart';
import '../../application/pending_invite_providers.dart';
import '../../data/pending_invite_store.dart';
import '../../application/trainer_link_providers.dart';
import '../../domain/invite_outcome.dart';
import '../../domain/trainer_link.dart';
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
  /// La invitación YA resuelta, como `'uid:trainerId'`.
  ///
  /// Antes era sólo el uid, y se marcaba en `build` —o sea, al INTENTAR, no al
  /// lograr—. Si en ese instante la invitación no estaba capturada todavía, el
  /// gate se rendía y quedaba marcado igual: no reintentaba nunca. Ahora se
  /// marca recién cuando hubo algo real que resolver, y lleva el trainerId
  /// para que una invitación NUEVA de la misma cuenta vuelva a disparar.
  String? _resueltaPara;

  /// Evita que dos frames seguidos lancen dos resoluciones en paralelo.
  bool _resolviendo = false;

  @override
  void initState() {
    super.initState();
    // Una invitación puede llegar con la home YA montada: es el caso normal
    // cuando el botón de `/abrir/alumno` abre la app que ya estaba corriendo.
    // Sin esto, nadie despierta al gate.
    PendingInviteStore.revision.addListener(_alCambiarLaInvitacion);
  }

  @override
  void dispose() {
    PendingInviteStore.revision.removeListener(_alCambiarLaInvitacion);
    super.dispose();
  }

  void _alCambiarLaInvitacion() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(
      userProfileProvider.select((a) => a.valueOrNull),
    );
    final uid = perfil?.uid;
    // Se OBSERVA el store, no se lee: mientras `SharedPreferences` no resolvió
    // vale `null`, y rendirse en ese estado no puede ser definitivo. Cuando
    // resuelve, este watch vuelve a construir y el intento se repite.
    final store = ref.watch(pendingInviteStoreProvider);

    if (uid != null && store != null && !_resolviendo) {
      _resolviendo = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _resolver(uid, perfil!.role, store),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _resolver(
    String uid,
    UserRole role,
    PendingInviteStore store,
  ) async {
    try {
      await _resolverInterno(uid, role, store);
    } finally {
      _resolviendo = false;
    }
  }

  Future<void> _resolverInterno(
    String uid,
    UserRole role,
    PendingInviteStore store,
  ) async {
    final trainerId = await store.leer();
    if (trainerId == null || !mounted) return;

    // El latch recién acá: hubo una invitación de verdad que resolver.
    final clave = '$uid:$trainerId';
    if (clave == _resueltaPara) return;
    _resueltaPara = clave;

    final InviteOutcome outcome;
    if (role == UserRole.trainer) {
      // Un PF también puede tocar un link a propósito. No intentamos
      // vincularlo: preservamos el motivo para confirmar que el link sí llegó.
      outcome = resolveTrainerInvite(
        inviteTrainerId: trainerId,
        trainerId: uid,
      );
    } else {
      final TrainerLink? vinculo;
      try {
        // El provider se queda en `AsyncLoading` mientras no llegue el
        // servidor, a propósito: un `AsyncData(null)` significa "no tenés
        // vínculo", nunca "no pudimos preguntar". Pero esto corre adentro de un
        // handler, así que acota la espera acá.
        vinculo = await ref
            .read(currentAthleteLinkAnyStatusProvider.future)
            .timeout(kEsperaDelServidorDeVinculo);
      } on TimeoutException {
        // Resolver con `null` haría que `resolveInvite` le mande una solicitud
        // a un PF con el que el alumno quizás YA está vinculado. Soltamos el
        // latch y dejamos la invitación guardada: el próximo arranque
        // reintenta.
        _resueltaPara = null;
        return;
      }
      if (!mounted) return;
      outcome = resolveInvite(
        inviteTrainerId: trainerId,
        athleteId: uid,
        vinculoActual: vinculo,
      );
    }

    // Se limpia SIEMPRE, haya terminado en vínculo o no. Una invitación que el
    // alumno ya vio y canceló no puede volver a aparecer en el próximo
    // arranque, y una que no aplica tampoco tiene nada que esperar.
    //
    // El PF que abre su propio link YA NO cae acá en silencio: es
    // `InviteLinkPropio` y le muestra "el link funciona, compartilo". Lo que
    // queda en `InviteNoAplica` es sólo la invitación sin PF — una entrada que
    // nadie pidió a propósito y sobre la que no hay nada honesto que decir.
    await store.limpiar();
    if (!mounted || outcome is InviteNoAplica) return;

    await showInviteDialog(context, outcome);
  }
}
