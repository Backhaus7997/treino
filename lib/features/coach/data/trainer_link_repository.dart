import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, Timestamp;

import '../domain/trainer_link.dart';
import '../domain/trainer_link_status.dart';

class TrainerLinkRepository {
  TrainerLinkRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _links =>
      _firestore.collection('trainer_links');

  // ─── request ────────────────────────────────────────────────────────────
  //
  // Solo el atleta inicia el request (convención producto: el cliente busca
  // al PF, no al revés). Crea el doc con `status: pending`, `requestedAt: now`.

  Future<TrainerLink> request({
    required String trainerId,
    required String athleteId,
  }) async {
    if (trainerId == athleteId) {
      throw ArgumentError.value(
          athleteId, 'athleteId', 'trainerId y athleteId no pueden coincidir');
    }
    final ref = _links.doc();
    final link = TrainerLink(
      id: ref.id,
      trainerId: trainerId,
      athleteId: athleteId,
      status: TrainerLinkStatus.pending,
      requestedAt: DateTime.now(),
    );
    await ref.set(link.toJson());
    return link;
  }

  // ─── decline ────────────────────────────────────────────────────────────
  //
  // Transición pending → terminated con razón 'declined'. Lo usa el PF
  // cuando rechaza una solicitud entrante.

  Future<void> decline(String linkId) async {
    final docRef = _links.doc(linkId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Vínculo $linkId no existe');
    }
    final current = _fromDoc(snap);
    if (current == null) {
      throw StateError('Vínculo $linkId no se pudo deserializar');
    }
    if (current.status != TrainerLinkStatus.pending) {
      throw StateError(
        'decline solo se permite sobre status=pending (actual: ${current.status.toJson()})',
      );
    }
    await docRef.update({
      'status': TrainerLinkStatusX(TrainerLinkStatus.terminated).toJson(),
      'terminatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
      'terminationReason': 'declined',
    });
  }

  // ─── cancel ─────────────────────────────────────────────────────────────
  //
  // Transición pending → terminated cuando el atleta cancela su propia
  // solicitud antes de que el PF responda. Diferenciado de `decline`
  // (que es la rechazo desde el PF) — termina con razón distinta para
  // analytics.

  Future<void> cancel(String linkId) async {
    final docRef = _links.doc(linkId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Vínculo $linkId no existe');
    }
    final current = _fromDoc(snap);
    if (current == null) {
      throw StateError('Vínculo $linkId no se pudo deserializar');
    }
    if (current.status != TrainerLinkStatus.pending) {
      throw StateError(
        'cancel solo se permite sobre status=pending (actual: ${current.status.toJson()})',
      );
    }
    await docRef.update({
      'status': TrainerLinkStatusX(TrainerLinkStatus.terminated).toJson(),
      'terminatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
      'terminationReason': 'cancelled-by-athlete',
    });
  }

  // ─── terminate ──────────────────────────────────────────────────────────
  //
  // Transición active/paused → terminated. Cualquier member puede terminar.

  Future<void> terminate(String linkId, {String? reason}) async {
    final docRef = _links.doc(linkId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Vínculo $linkId no existe');
    }
    final current = _fromDoc(snap);
    if (current == null) {
      throw StateError('Vínculo $linkId no se pudo deserializar');
    }
    if (current.status != TrainerLinkStatus.active &&
        current.status != TrainerLinkStatus.paused) {
      throw StateError(
        'terminate solo se permite sobre status=active|paused '
        '(actual: ${current.status.toJson()})',
      );
    }
    await docRef.update({
      'status': TrainerLinkStatusX(TrainerLinkStatus.terminated).toJson(),
      'terminatedAt': Timestamp.fromDate(DateTime.now().toUtc()),
      if (reason != null) 'terminationReason': reason,
    });
  }

  // ─── pause ──────────────────────────────────────────────────────────────
  //
  // Transición active → paused. Setea pausedAt: now. Preserva acceptedAt.
  // Lanza StateError si el doc no existe o el status actual != active.

  Future<void> pause(String linkId) async {
    final docRef = _links.doc(linkId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Vínculo $linkId no existe');
    }
    final current = _fromDoc(snap);
    if (current == null) {
      throw StateError('Vínculo $linkId no se pudo deserializar');
    }
    if (current.status != TrainerLinkStatus.active) {
      throw StateError(
        'pause solo se permite sobre status=active (actual: ${current.status.toJson()})',
      );
    }
    await docRef.update({
      'status': TrainerLinkStatusX(TrainerLinkStatus.paused).toJson(),
      'pausedAt': Timestamp.fromDate(DateTime.now().toUtc()),
    });
  }

  // ─── resume: MOVIDO AL SERVIDOR ──────────────────────────────────────────
  //
  // La transición paused → active vive ahora en la CF `resumeTrainerLink`
  // (paywall Fase 7, PR4), igual que `accept`. Son las DOS transiciones que
  // suben el peso ponderado, y desde el cliente el límite era inaplicable.
  // El helper del server limpia `pausedAt` y preserva `acceptedAt`, igual que
  // hacía este método. Usá `TrainerLinkPromotionService.resume`.

  // ─── listForTrainer ─────────────────────────────────────────────────────

  Future<List<TrainerLink>> listForTrainer(
    String trainerId, {
    Set<TrainerLinkStatus>? statuses,
  }) async {
    final query = _links
        .where('trainerId', isEqualTo: trainerId)
        .orderBy('requestedAt', descending: true);
    final snap = await query.get();
    final links = snap.docs.map(_fromDoc).whereType<TrainerLink>().toList();
    if (statuses == null) return links;
    return links.where((l) => statuses.contains(l.status)).toList();
  }

  // ─── setSharedWithTrainer ───────────────────────────────────────────────
  //
  // Privacy gate. Solo el atleta puede flippear este flag (validado por
  // Firestore rules — Shape 1). Single-field update sin `updatedAt` para
  // mantener la convención del resto de los update methods de este repo.
  // REQ-COACH-LINK-003..006.

  Future<void> setSharedWithTrainer(String linkId, bool value) {
    return _links.doc(linkId).update({'sharedWithTrainer': value});
  }

  // ─── listForAthlete ─────────────────────────────────────────────────────

  Future<List<TrainerLink>> listForAthlete(
    String athleteId, {
    Set<TrainerLinkStatus>? statuses,
  }) async {
    final query = _links
        .where('athleteId', isEqualTo: athleteId)
        .orderBy('requestedAt', descending: true);
    final snap = await query.get();
    final links = snap.docs.map(_fromDoc).whereType<TrainerLink>().toList();
    if (statuses == null) return links;
    return links.where((l) => statuses.contains(l.status)).toList();
  }

  // ─── watchForAthlete ────────────────────────────────────────────────────
  //
  // Espejo de [watchForTrainer] para el lado del atleta, y la razón por la que
  // existe es que [listForAthlete] no alcanza.
  //
  // Un `.get()` servido desde la caché local fría no devuelve un error:
  // devuelve una lista VACÍA. Quien pregunta no tiene forma de distinguir "no
  // tenés vínculo" de "todavía no sé", y como el `.get()` es una sola
  // resolución, esa confusión queda pegada hasta que el usuario sale de la
  // pantalla y vuelve. El lado del PF nunca lo vio porque siempre fue stream:
  // le llega una segunda snapshot y se repara solo.

  Stream<List<TrainerLink>> watchForAthlete(
    String athleteId, {
    Set<TrainerLinkStatus>? statuses,
  }) {
    final query = _links
        .where('athleteId', isEqualTo: athleteId)
        .orderBy('requestedAt', descending: true);
    return query
        .snapshots()
        .map((snap) {
          final links =
              snap.docs.map(_fromDoc).whereType<TrainerLink>().toList();
          final filtrados = statuses == null
              ? links
              : links.where((l) => statuses.contains(l.status)).toList();
          return (filtrados, snap.metadata.isFromCache);
        })
        // Misma guarda que `user_repository.dart`,
        // `athlete_entitlement_provider.dart` y `blocked_athletes_providers.dart`:
        // un resultado VACÍO servido desde la caché no es "no hay vínculos", es
        // "todavía no sé", y lo descartamos esperando al servidor.
        //
        // La guarda va DESPUÉS del filtro por estado, no antes, y la diferencia
        // no es cosmética. Una snapshot con documentos NO prueba que el estado
        // pedido esté ausente: la caché puede tener un vínculo `terminated`
        // viejo mientras el `active` nuevo —creado desde el dispositivo del
        // PF— existe sólo en el servidor. Con la guarda antes del filtro, esa
        // snapshot pasaba por "tiene datos", el filtro la dejaba vacía, y el
        // provider publicaba `null` sin confirmación del servidor. O sea, el
        // bug original entrando por otra puerta.
        //
        // (La versión anterior de este comentario afirmaba que un filtro vacío
        // sobre datos reales "ya es un hecho y no una ignorancia". Es falso
        // cuando la caché está incompleta, que es exactamente el caso que
        // importa. Lo encontró Codex en el PR #1109.)
        .where((par) => par.$1.isNotEmpty || !par.$2)
        .map((par) => par.$1);
  }

  // ─── watchForTrainer ────────────────────────────────────────────────────
  //
  // Real-time stream para que el dashboard del PF refleje requests y
  // terminations sin reload manual.

  Stream<List<TrainerLink>> watchForTrainer(
    String trainerId, {
    Set<TrainerLinkStatus>? statuses,
  }) {
    final query = _links
        .where('trainerId', isEqualTo: trainerId)
        .orderBy('requestedAt', descending: true);
    return query.snapshots().map((snap) {
      final links = snap.docs.map(_fromDoc).whereType<TrainerLink>().toList();
      if (statuses == null) return links;
      return links.where((l) => statuses.contains(l.status)).toList();
    });
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  TrainerLink? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return TrainerLink.fromJson({...data, 'id': snap.id});
  }
}
