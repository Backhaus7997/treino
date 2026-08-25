import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentSnapshot,
        FirebaseFirestore,
        QuerySnapshot;

import '../domain/check_in.dart';

/// Acceso a `users/{uid}/wellbeingCheckIns/{checkInId}` — el registro subjetivo
/// del usuario.
///
/// Owner-only por reglas de Firestore: nadie más que el dueño lee o escribe.
/// Es el dato más sensible que guarda la app, así que NO se propaga a
/// `userPublicProfiles` ni se comparte con el PF — y, a diferencia de
/// `sessions`/`setLogs`, tampoco lo abre `session_shares`. Compartirlo, si
/// algún día se quiere, necesita su propio opt-in explícito y su propio issue.
///
/// El path NO es `users/{uid}/checkIns`: ese quedó reservado para el check-in
/// de presencia en el gym (ver el dartdoc de [CheckIn]).
class CheckInRepository {
  CheckInRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> _collection(String uid) =>
      _firestore.collection('users').doc(uid).collection('wellbeingCheckIns');

  // ─── save ───────────────────────────────────────────────────────────────

  /// Guarda un check-in y devuelve el id del documento.
  ///
  /// Si [CheckIn.id] viene cargado, ACTUALIZA ese documento — es el camino de
  /// "editar lo que ya registré". Si viene en `null`, CREA uno nuevo con
  /// [checkInDocId]: dos registros del mismo día conviven en vez de pisarse.
  ///
  /// Esa es la diferencia con la slice 1, donde el id era la fecha y el
  /// segundo entreno del día borraba el primero sin decir nada.
  Future<String> save(String uid, CheckIn checkIn) async {
    final id = checkIn.id ?? checkInDocId(checkIn.date, checkIn.recordedAt);
    await _collection(uid).doc(id).set(checkIn.toJson());
    return id;
  }

  // ─── getForDate ─────────────────────────────────────────────────────────

  /// Todos los check-ins de [date] (`YYYY-MM-DD`), del más viejo al más nuevo.
  ///
  /// Lista vacía si ese día no tiene registro. Consulta por el CAMPO `date` y
  /// no por prefijo del id: es una igualdad simple, que Firestore resuelve con
  /// el índice de campo único que crea solo.
  Future<List<CheckIn>> getForDate(String uid, String date) async {
    final snap = await _collection(uid).where('date', isEqualTo: date).get();
    return _fromQuery(snap);
  }

  // ─── getRange ───────────────────────────────────────────────────────────

  /// Check-ins entre [fromDate] y [toDate] inclusive (`YYYY-MM-DD`), del más
  /// viejo al más nuevo. Es la lectura que alimenta la curva de tendencia.
  ///
  /// El rango va sobre `date` —la fecha LOCAL a la que el usuario imputa el
  /// registro— y no sobre `recordedAt`: cerca de medianoche los dos caen en
  /// días distintos, y el eje de la curva es el día del usuario.
  ///
  /// Sigue siendo un solo campo, así que tampoco necesita índice compuesto.
  Future<List<CheckIn>> getRange(
    String uid, {
    required String fromDate,
    required String toDate,
  }) async {
    final snap = await _collection(uid)
        .where('date', isGreaterThanOrEqualTo: fromDate)
        .where('date', isLessThanOrEqualTo: toDate)
        .get();
    return _fromQuery(snap);
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  /// Decodifica y ordena en el cliente por `(date, recordedAt)`.
  ///
  /// El orden no se le pide a Firestore a propósito: un `orderBy('recordedAt')`
  /// junto al rango sobre `date` exigiría un índice compuesto, y son como mucho
  /// unas decenas de documentos por consulta.
  List<CheckIn> _fromQuery(QuerySnapshot<Map<String, Object?>> snap) {
    final out = <CheckIn>[];
    for (final doc in snap.docs) {
      final parsed = _fromDoc(doc);
      if (parsed != null) out.add(parsed);
    }
    out.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.recordedAt.compareTo(b.recordedAt);
    });
    return out;
  }

  CheckIn? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      // El id arranca con la fecha, así que sirve de fallback para un doc que
      // no la haya persistido en el body (mismo patrón defensivo que
      // MeasurementRepository._fromDoc). Lo que traiga `data` manda.
      return CheckIn.fromJson({
        'date': snap.id.split('_').first,
        ...data,
      }).copyWith(id: snap.id);
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
