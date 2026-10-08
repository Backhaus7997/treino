import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;

/// Lo que el backend PUBLICÓ sobre los alumnos del PF que quedaron fuera de su
/// cupo.
///
/// No es un `Set<String>` pelado porque un set vacío tiene dos lecturas
/// incompatibles y la pantalla las tiene que decir distinto:
///
/// - **publicada y vacía** → el backend miró y no hay ninguno afuera. Se puede
///   afirmar «el cupo no explica lo que te rebotó».
/// - **sin publicar** → el backend nunca escribió el campo para este PF, así
///   que NO SE SABE. Afirmar cualquiera de las dos cosas es inventar.
///
/// La segunda no es un caso de laboratorio: `blockedAthleteIds` sólo aparece
/// después de que `syncTrainerEntitlements` corre sobre ese PF (cambio de
/// `subscription`, escritura en sus `trainer_links`, o el barrido). Un PF cuyo
/// padrón y suscripción no se movieron desde el deploy todavía no tiene el
/// campo — y colapsar eso en «ninguno» es exactamente la afirmación sin
/// prueba que esta pantalla existe para no hacer.
@immutable
class BlockedAthletes {
  const BlockedAthletes.published(this.ids) : isPublished = true;

  const BlockedAthletes._unpublished()
      : ids = const <String>{},
        isPublished = false;

  /// El backend todavía no dijo nada sobre este PF. [ids] va vacío porque no
  /// hay nada que mostrar, NO porque se sepa que no hay ninguno.
  static const unpublished = BlockedAthletes._unpublished();

  /// Los atletas sin ningún vínculo vivo `entitled`. Vacío y [isPublished]
  /// significa «ninguno», vacío y no publicado significa «no sé».
  final Set<String> ids;

  /// `true` si `users/{uid}.blockedAthleteIds` existe en el doc del PF.
  final bool isPublished;

  /// Igualdad POR VALOR, y no es cosmética.
  ///
  /// El editor de rutinas observa este provider mientras está abierto, y la CF
  /// reescribe `users/{trainerId}` sin condición: `linkLoadReconcile` la
  /// dispara en CADA escritura de `trainer_links`, con los mismos valores si
  /// nada cambió. Con un `Set` crudo cada snapshot produce una instancia nueva,
  /// `AsyncData(a) != AsyncData(b)` siempre, y el árbol más pesado del Coach
  /// Hub se reconstruye porque un alumno ajeno aceptó un vínculo. Con esta
  /// igualdad, el `.distinct()` de abajo corta esas emisiones.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockedAthletes &&
          other.isPublished == isPublished &&
          setEquals(other.ids, ids);

  @override
  int get hashCode => Object.hash(isPublished, Object.hashAllUnordered(ids));
}

/// Los alumnos del PF actual que quedaron fuera del cupo de su plan, leídos de
/// `users/{uid}.blockedAthleteIds` (paywall Fase 7).
///
/// ## Por qué se lee ESE campo y no se derivan de los `trainer_links`
///
/// Un mismo alumno puede tener más de un vínculo vivo con el mismo PF
/// (`trainer_link_repository.dart` crea con id autogenerado y no impide el
/// duplicado). Filtrar los links por `entitlement == blocked` contaría como
/// bloqueado a un alumno que todavía tiene otro vínculo `entitled` — y ese
/// alumno NO está frenado: cualquiera de sus vínculos vivos alcanza.
///
/// `blockedAthleteIds` lo escribe una Cloud Function que ya resolvió esa
/// desambiguación por ATLETA, y su contrato es exactamente «los atletas sin
/// ningún vínculo vivo entitled»
/// (`functions/src/subscriptions/select-blocked-links.ts`). Es la única fuente
/// que no puede contradecirse con la carga ponderada.
///
/// ## Por qué un read crudo y no un campo de `UserProfile`
///
/// `blockedAthleteIds` es CF-write-only: las reglas pinean el campo contra
/// cualquier escritura del cliente. Meterlo en el modelo que el cliente
/// TAMBIÉN escribe invitaría a mandarlo de vuelta en un `update` y a comerse
/// una denegación por un campo que nadie quiso tocar.
///
/// Lo puede leer el propio PF: el `allow read` de `users/{uid}` es owner-only,
/// así que este stream sólo funciona sobre el doc propio — que es todo lo que
/// necesita esta pantalla.
///
/// ## Los tres estados, y por qué son tres
///
/// `loading` mientras no llegó nada, `error` si el read falla, y un
/// [BlockedAthletes] que a su vez distingue «publicado» de «sin publicar». Un
/// `Set` vacío NO alcanza para las cuatro situaciones, y el consumidor que las
/// confunde afirma cosas que no sabe: la pantalla diría «no fue por el cupo de
/// tu plan» y el evento de analytics saldría con `athlete_entitlement:
/// entitled`, que según su propio contrato significa «esto no es cobro, es una
/// regla rota» y manda al on-call al lado equivocado.
///
/// El error NO se traga como conjunto vacío por esa misma razón: sin app de
/// Firebase inicializada (`flutter test`) o con el read denegado, este provider
/// queda en `AsyncError` y la pantalla dibuja «NO PUDIMOS CARGAR TU CUPO», que
/// es el estado honesto. Un test que quiera ejercitar la rama con alumnos
/// afuera overridea este provider directo.
final blockedAthletesProvider =
    StreamProvider.autoDispose<BlockedAthletes>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) {
    return Stream.value(BlockedAthletes.unpublished);
  }

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(uid)
      .snapshots()
      // Misma guarda que `UserRepository.watch`, por la misma razón: con la
      // cache local fría la PRIMERA snapshot llega con `exists == false` antes
      // de que el servidor confirme. Sin este filtro, el PF que abre el
      // navegador nuevo y viene rebotado de un guardado lee «tu cuenta no
      // tiene publicada la lista» durante el round-trip.
      .where((snap) => snap.exists || !snap.metadata.isFromCache)
      .map((snap) {
    final raw = snap.data()?['blockedAthleteIds'];
    // Campo ausente ≠ lista vacía. Un `List` vacío es el backend diciendo
    // «ninguno»; que no esté el campo es el backend sin haber hablado.
    if (raw is! List) return BlockedAthletes.unpublished;
    return BlockedAthletes.published(raw.whereType<String>().toSet());
  }).distinct();
});
