import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/application/chat_providers.dart'
    show chatsForCurrentUserProvider;
import '../../coach/application/trainer_link_providers.dart'
    show trainerLinkRepositoryProvider;
import '../../coach/domain/trainer_link.dart';
import '../../coach/domain/trainer_link_status.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;

/// ¿Hay un vínculo PF↔alumno vigente entre el usuario actual y [otherUid]?
///
/// Mismo criterio que `ChatRepository._activeLinkIdBetween`, que es lo que
/// después sella el `linkId` en el chat que `chatCreateOk` valida: `active` y
/// `paused` cuentan (pausar es un hold temporal, no un corte). Se consulta de
/// los DOS lados porque el usuario puede ser el PF o el alumno.
///
/// Errores → `false`: si no se puede confirmar el vínculo, el botón queda
/// sujeto a las otras salidas (follow o perfil público) en vez de prometer un
/// chat que las rules podrían rebotar.
final _activeLinkWithProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, otherUid) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid == otherUid) return false;
  final repo = ref.watch(trainerLinkRepositoryProvider);
  const vigentes = {TrainerLinkStatus.active, TrainerLinkStatus.paused};
  final links = await Future.wait([
    repo.listForAthlete(uid, statuses: vigentes),
    repo.listForTrainer(uid, statuses: vigentes),
  ]);
  return links.expand((l) => l).any(
        (TrainerLink link) =>
            (link.trainerId == otherUid && link.athleteId == uid) ||
            (link.trainerId == uid && link.athleteId == otherUid),
      );
});

/// ¿Puedo abrir un chat con [targetUid] por algo que NO sea el follow ni el
/// perfil público?
///
/// Son las otras dos salidas de `chatCreateOk`, que el botón MENSAJE del
/// perfil ignoraba al principio (por eso el PF veía a su propio alumno con
/// MENSAJE gris y un chat ya abierto, #1476):
///
/// - **ya hay un chat** entre los dos: abrirlo es `getOrCreate`, que lo
///   devuelve tal cual, sin crear nada ni pasar por ninguna regla de creación;
/// - **hay un vínculo vigente** (ver [_activeLinkWithProvider]): la rama
///   `linkId` de `chatCreateOk`.
///
/// El chat se lee de `chatsForCurrentUserProvider`, el mismo stream que ya usa
/// la lista de chats y los badges, así que no abre ningún listener nuevo.
///
/// Mientras carga cualquiera de los dos devuelve `false`; el botón aparece
/// apenas llega el dato.
final chatViaRelationshipProvider =
    Provider.autoDispose.family<bool, String>((ref, targetUid) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid == targetUid) return false;

  final hasChat = ref
          .watch(chatsForCurrentUserProvider)
          .valueOrNull
          ?.any((chat) => chat.members.contains(targetUid)) ??
      false;
  if (hasChat) return true;

  return ref.watch(_activeLinkWithProvider(targetUid)).valueOrNull ?? false;
});
