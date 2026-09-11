// ignore: unused_import — Timestamp is used by the generated content_report.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'report_reason.dart';
import 'report_target_kind.dart';

part 'content_report.freezed.dart';
part 'content_report.g.dart';

/// Un reporte de contenido o de perfil.
///
/// Stored at `reports/{targetKind}_{targetId}_{reporterUid}` — mismo truco
/// que `posts/{postId}/reactions/{reactorUid}`: el uid de quien escribe es
/// PARTE del id, así que falsificar el `reporterUid` de otro es imposible y
/// reportar dos veces lo mismo es idempotente (pisa el mismo doc), sin
/// ningún contador. Ver `openspec/changes/moderacion-reporte-y-bloqueo/design.md`.
///
/// El `read` está cerrado a todo cliente — los reportes se revisan por
/// consola de Firestore, nunca desde la app.
@freezed
class ContentReport with _$ContentReport {
  const factory ContentReport({
    required String id,
    required String reporterUid,
    required ReportTargetKind targetKind,
    required String targetId,

    /// Uid del dueño del contenido reportado (autor del post/mensaje/review,
    /// o el propio perfil cuando `targetKind == profile`). No participa del
    /// id — sólo viaja como dato para que la revisión en consola no tenga que
    /// resolverlo a mano.
    required String targetOwnerUid,
    required ReportReason reason,

    /// Detalle libre opcional, ≤ 1000 caracteres (lo valida el sheet y,
    /// server-side, las reglas de Firestore).
    String? detail,
    @TimestampConverter() required DateTime createdAt,
  }) = _ContentReport;

  factory ContentReport.fromJson(Map<String, Object?> json) =>
      _$ContentReportFromJson(json);

  /// Doc id determinístico: `'{targetKind}_{targetId}_{reporterUid}'`.
  static String idFor(
    ReportTargetKind targetKind,
    String targetId,
    String reporterUid,
  ) =>
      '${targetKind.toJson()}_${targetId}_$reporterUid';
}
