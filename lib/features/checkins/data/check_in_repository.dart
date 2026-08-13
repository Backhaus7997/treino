import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/check_in.dart';

/// Acceso a `users/{uid}/checkIns/{date}` — el registro subjetivo del usuario.
///
/// Owner-only por reglas de Firestore: nadie más que el dueño lee o escribe.
/// Es el dato más sensible que guarda la app, así que NO se propaga a
/// `userPublicProfiles` ni se comparte con el PF. Compartirlo, si algún día se
/// quiere, necesita su propio opt-in explícito y su propio issue.
class CheckInRepository {
  CheckInRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> _collection(String uid) =>
      _firestore.collection('users').doc(uid).collection('checkIns');

  // ─── save ───────────────────────────────────────────────────────────────

  /// Guarda el check-in de un día. El id del documento es [CheckIn.date], así
  /// que un segundo registro para la misma fecha PISA al anterior — es el
  /// dedup natural que ya documentan las reglas ("one doc per day per user"),
  /// no un accidente.
  Future<void> save(String uid, CheckIn checkIn) async {
    await _collection(uid).doc(checkIn.date).set(checkIn.toJson());
  }

  // ─── getByDate ──────────────────────────────────────────────────────────

  /// Lee el check-in de [date] (`YYYY-MM-DD`). `null` si ese día no tiene
  /// registro, o si el doc existe pero no parsea — un doc malformado no puede
  /// romper la pantalla que lo consulta.
  Future<CheckIn?> getByDate(String uid, String date) async {
    final snap = await _collection(uid).doc(date).get();
    return _fromDoc(snap);
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  CheckIn? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      // El id ES la fecha: se inyecta para que un doc viejo que no persistió
      // `date` en el body decodifique igual (mismo patrón que
      // MeasurementRepository._fromDoc).
      return CheckIn.fromJson({...data, 'date': snap.id});
    } catch (e, st) {
      developer.log(
        'CheckInRepository: skipped unparseable check-in ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
