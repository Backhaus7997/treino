import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show trainerLinkRepositoryProvider;
import '../../coach/domain/trainer_link.dart';
import '../../coach/domain/trainer_link_status.dart';
import '../../feed/application/follow_providers.dart'
    show followRepositoryProvider;
import '../../moderation/application/moderation_providers.dart'
    show blockedUidsProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'chat_providers.dart' show chatsForCurrentUserProvider;

/// Por qué [ChatContact.uid] es alcanzable. Ordena la sección y elige la
/// etiqueta de la fila.
enum ChatContactReason {
  /// Vínculo vigente y el otro es el PF.
  coach,

  /// Vínculo vigente y el otro es el alumno.
  athlete,

  /// Lo sigo con la arista aceptada.
  following,
}

/// Alguien a quien el usuario actual le puede abrir un chat y que todavía no
/// tiene uno en la lista.
class ChatContact {
  const ChatContact({required this.uid, required this.reason});

  final String uid;
  final ChatContactReason reason;

  @override
  bool operator ==(Object other) =>
      other is ChatContact && other.uid == uid && other.reason == reason;

  @override
  int get hashCode => Object.hash(uid, reason);

  @override
  String toString() => 'ChatContact($uid, ${reason.name})';
}

/// Estados de vínculo que habilitan el chat. Espeja la rama `linkId` de
/// `chatCreateOk` en `firestore.rules` (`status in ['active', 'paused']`) y
/// `ChatRepository._activeLinkIdBetween`, que es lo que sella el `linkId`.
const chatEnablingLinkStatuses = {
  TrainerLinkStatus.active,
  TrainerLinkStatus.paused,
};

/// Lista de contactos a partir de las fuentes ya resueltas. Pura, para que
/// el criterio se pueda testear sin Firestore.
///
/// El criterio es EXACTAMENTE el de `chatCreateOk` en `firestore.rules`, en
/// sus dos ramas que no dependen de una superficie de discovery:
///
/// - **Rama `linkId`**: hay un `trainer_links` con [selfUid] y el otro como
///   `trainerId`/`athleteId` y estado en [chatEnablingLinkStatuses].
/// - **Rama social**: `followAccepted(me, other)`, o sea que la arista
///   `follows/{yo}_{otro}` está aceptada: a quien SIGO ([followingUids]). Con
///   perfil privado eso ya implica que me aceptó; una solicitud pendiente no
///   llega en esa lista.
///
/// Quedan afuera a propósito dos cosas que las rules también habilitan:
/// - un perfil PÚBLICO que no sigo: se le escribe desde su perfil (botón
///   MENSAJE), pero listarlos sería listar a toda la red;
/// - la pre-consulta (`kind == 'inquiry'`): habilita a TODO PF publicado, así
///   que es el discovery de la tab Coach (AGENTS.md §5), no una lista de
///   contactos.
///
/// Se excluyen:
/// - [blockedUids]: `chatCreateOk` y `senderMayPost` exigen `notBlocked`.
///   Del lado inverso (el otro me bloqueó) no hace falta nada: no puedo leer
///   sus bloqueos, pero `removeFollowEdgesOnBlock` borra las dos aristas.
/// - [chatPartnerUids]: ya hay un chat en la lista (o en Archivados); se
///   muestra el chat.
List<ChatContact> chatContactsFrom({
  required String selfUid,
  required Iterable<TrainerLink> links,
  required Iterable<String> followingUids,
  required Iterable<String> blockedUids,
  required Iterable<String> chatPartnerUids,
}) {
  final excluded = {selfUid, ...blockedUids, ...chatPartnerUids};
  final seen = <String>{};
  final coaches = <ChatContact>[];
  final athletes = <ChatContact>[];
  final following = <ChatContact>[];

  for (final link in links) {
    if (!chatEnablingLinkStatuses.contains(link.status)) continue;
    final ChatContactReason reason;
    final String other;
    if (link.athleteId == selfUid) {
      other = link.trainerId;
      reason = ChatContactReason.coach;
    } else if (link.trainerId == selfUid) {
      other = link.athleteId;
      reason = ChatContactReason.athlete;
    } else {
      continue;
    }
    if (excluded.contains(other) || !seen.add(other)) continue;
    (reason == ChatContactReason.coach ? coaches : athletes)
        .add(ChatContact(uid: other, reason: reason));
  }
  for (final uid in followingUids) {
    if (excluded.contains(uid) || !seen.add(uid)) continue;
    following.add(ChatContact(uid: uid, reason: ChatContactReason.following));
  }
  return [...coaches, ...athletes, ...following];
}

/// Vínculos vigentes donde el usuario actual es el alumno, en vivo.
final chatContactLinksAsAthleteProvider =
    StreamProvider.autoDispose<List<TrainerLink>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(trainerLinkRepositoryProvider)
      .watchForAthlete(uid, statuses: chatEnablingLinkStatuses);
});

/// Vínculos vigentes donde el usuario actual es el PF, en vivo.
final chatContactLinksAsTrainerProvider =
    StreamProvider.autoDispose<List<TrainerLink>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(trainerLinkRepositoryProvider)
      .watchForTrainer(uid, statuses: chatEnablingLinkStatuses);
});

/// A quiénes sigue el usuario actual con la arista aceptada, en vivo.
final chatContactFollowingProvider =
    StreamProvider.autoDispose<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(followRepositoryProvider).watchFollowingOf(uid);
});

/// Contactos a los que el usuario actual le puede escribir y que no tienen
/// chat en la lista. Ver [chatContactsFrom] para el criterio.
///
/// Reactivo: cada fuente es un stream, así que seguir a alguien (o que acepte
/// la solicitud) o un vínculo que se activa agrega al contacto, y un unfollow,
/// un bloqueo o un vínculo terminado lo saca, sin recargar la pantalla.
///
/// Mientras CUALQUIER fuente carga devuelve loading, y si alguna falla,
/// error: una fuente que todavía no llegó no es "no tenés contactos" (ver la
/// memoria del repo sobre guardas que devuelven vacío). Los bloqueos son la
/// excepción a medias: si fallan se asume "sin bloqueos", mismo criterio que
/// `myBlockedUidsProvider`, porque el peor caso es una fila cuyo primer
/// mensaje rebota, no un chat prometido a quien no corresponde.
final chatContactsProvider =
    Provider.autoDispose<AsyncValue<List<ChatContact>>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const AsyncData([]);

  final asAthlete = ref.watch(chatContactLinksAsAthleteProvider);
  final asTrainer = ref.watch(chatContactLinksAsTrainerProvider);
  final following = ref.watch(chatContactFollowingProvider);
  final chats = ref.watch(chatsForCurrentUserProvider);
  final blocked = ref.watch(blockedUidsProvider(uid));

  final sources = <AsyncValue<Object?>>[asAthlete, asTrainer, following, chats];
  for (final source in sources) {
    if (source.hasError) {
      return AsyncError(source.error!, source.stackTrace ?? StackTrace.empty);
    }
  }
  if (sources.any((s) => !s.hasValue) || blocked.isLoading) {
    return const AsyncLoading();
  }

  return AsyncData(
    chatContactsFrom(
      selfUid: uid,
      links: [...asAthlete.requireValue, ...asTrainer.requireValue],
      followingUids: following.requireValue,
      blockedUids: blocked.valueOrNull ?? const [],
      // Un chat eliminado no cuenta como "ya tiene chat": la persona vuelve a
      // aparecer acá, y tocarla reabre ese chat sin el historial borrado.
      chatPartnerUids: chats.requireValue
          .where((c) => !c.isHiddenFor(uid))
          .expand((c) => c.members),
    ),
  );
});
