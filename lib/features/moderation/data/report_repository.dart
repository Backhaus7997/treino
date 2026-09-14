import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, FirebaseFirestore;

import '../domain/content_report.dart';
import '../domain/report_reason.dart';
import '../domain/report_target_kind.dart';

/// Acceso a `reports/{targetKind}_{targetId}_{reporterUid}`.
///
/// Sólo `report()` — no hay `get`/`watch`: el `read` está cerrado a todo
/// cliente (design.md → "reports — el id previene el doble reporte"), así
/// que este repositorio no expone ningún método de lectura a propósito. Un
/// método `watch`/`get` que Firestore rechaza en runtime es peor que no
/// tenerlo: invita a un call site a asumir que puede leer sus propios
/// reportes.
class ReportRepository {
  ReportRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _reports =>
      _firestore.collection('reports');

  /// Crea (o pisa, si ya existía) el reporte de [reporterUid] sobre
  /// [targetId].
  ///
  /// `set()` y no `set(..., merge: false)` con un chequeo previo de
  /// existencia: el id ya hace idempotente el doble reporte —mismo motivo,
  /// mismo target, mismo reporter pisa el mismo doc— así que no hace falta un
  /// `get()` extra antes de escribir, a diferencia de `BlockRepository.block`
  /// (que sí necesita devolver la arista existente).
  Future<void> report({
    required String reporterUid,
    required ReportTargetKind targetKind,
    required String targetId,
    required String targetOwnerUid,
    required ReportReason reason,
    String? detail,
  }) async {
    final id = ContentReport.idFor(targetKind, targetId, reporterUid);
    final report = ContentReport(
      id: id,
      reporterUid: reporterUid,
      targetKind: targetKind,
      targetId: targetId,
      targetOwnerUid: targetOwnerUid,
      reason: reason,
      detail: detail,
      createdAt: DateTime.now().toUtc(),
    );
    await _reports.doc(id).set(report.toJson());
  }
}
