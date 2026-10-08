import 'package:cloud_functions/cloud_functions.dart';

import '../domain/moderation_stats.dart';
import '../domain/pending_queue.dart';
import '../domain/pending_report.dart';

/// La cola de revision de reportes, del lado del cliente.
///
/// Habla con los tres callables de `functions/src/moderation/report-review.ts`.
/// NO lee `reports` ni `report_reviews` directo: las dos estan cerradas con
/// `allow read: if false` para TODO cliente, moderador incluido. El moderador
/// lee por el Admin SDK, del otro lado del callable, y el claim `moderator` se
/// verifica ahi.
///
/// Que las reglas sigan cerradas no es un detalle: un moderador que pudiera
/// leer `reports` desde el cliente convertiria la coleccion en un canal de
/// acoso nuevo si alguna vez se le otorgara el claim a quien no corresponde.
class ModerationQueueService {
  ModerationQueueService({required FirebaseFunctions functions})
      : _functions = functions;

  final FirebaseFunctions _functions;

  /// Los pendientes, mas viejos primero.
  ///
  /// Devuelve tambien `reachedScanCap`. El servidor escanea hasta un tope y
  /// avisa cuando lo alcanzo: descartar ese dato haria que la pantalla diga
  /// "no hay reportes esperando" cuando la verdad es "dejamos de buscar", y
  /// los reportes de mas atras quedarian invisibles en cada refresco.
  ///
  /// Es exactamente la mentira que el flag existe para evitar, asi que viaja
  /// hasta la UI.
  Future<PendingQueue> listPending({int limit = 50}) async {
    final res = await _functions
        .httpsCallable('listPendingReports')
        .call<Map<String, dynamic>>({'limit': limit});

    final crudos = res.data['reports'];
    return PendingQueue(
      reportes: crudos is! List
          ? const []
          : crudos
              .whereType<Map<Object?, Object?>>()
              .map(PendingReport.fromMap)
              .toList(),
      incompleta: res.data['reachedScanCap'] == true,
    );
  }

  /// Marca un reporte como MIRADO. Idempotente: el servidor estampa una sola
  /// vez y no reabre un reporte ya resuelto.
  Future<void> markViewed(String reportId) async {
    await _functions
        .httpsCallable('markReportViewed')
        .call<Map<String, dynamic>>({'reportId': reportId});
  }

  /// Cierra un reporte. [status] es `actioned` o `dismissed`.
  Future<void> resolve({
    required String reportId,
    required String status,
    required String action,
    String? note,
  }) async {
    await _functions.httpsCallable('resolveReport').call<Map<String, dynamic>>({
      'reportId': reportId,
      'status': status,
      'action': action,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  Future<ModerationStats> stats() async {
    final res = await _functions
        .httpsCallable('moderationStats')
        .call<Map<String, dynamic>>(const <String, dynamic>{});
    return ModerationStats.fromMap(res.data);
  }
}
