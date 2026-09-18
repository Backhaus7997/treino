import 'package:cloud_functions/cloud_functions.dart';

import '../domain/moderation_stats.dart';
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
  Future<List<PendingReport>> listPending({int limit = 50}) async {
    final res = await _functions
        .httpsCallable('listPendingReports')
        .call<Map<String, dynamic>>({'limit': limit});

    final crudos = res.data['reports'];
    if (crudos is! List) return const [];
    return crudos
        .whereType<Map<Object?, Object?>>()
        .map(PendingReport.fromMap)
        .toList();
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
