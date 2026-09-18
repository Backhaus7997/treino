import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/moderation_queue_service.dart';
import '../domain/moderation_stats.dart';
import '../domain/pending_queue.dart';

/// Los callables de moderacion viven en `southamerica-east1`, igual que el
/// resto de las functions del repo.
final moderationFunctionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: 'southamerica-east1'),
);

final moderationQueueServiceProvider = Provider<ModerationQueueService>(
  (ref) => ModerationQueueService(
    functions: ref.watch(moderationFunctionsProvider),
  ),
);

/// El claim `moderator` del ID token del usuario.
///
/// Se pide con `refresh: true` A PROPOSITO. Los custom claims viajan DENTRO
/// del ID token, que dura hasta una hora: sin forzar el refresco, alguien a
/// quien se le acaba de otorgar el claim con `scripts/grant_moderator.js`
/// tendria que esperar hasta 60 minutos o cerrar sesion para que la cola le
/// aparezca. Cuesta una llamada de red por sesion.
///
/// El mismo mecanismo al reves: REVOCAR el claim tampoco corta la sesion en
/// curso hasta que el token expire. Para eso hace falta ademas
/// `firebase auth:revoke-refresh-tokens`, y esta escrito en el script.
final moderatorClaimProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authStateChangesProvider).valueOrNull;
  if (user == null) return false;
  final token = await user.getIdTokenResult(true);
  return token.claims?['moderator'] == true;
});

/// `true` sólo cuando el claim esta CONFIRMADO.
///
/// Mientras carga o si falla devuelve `false`, y eso es deliberado: acá
/// colapsar "no sé" con "no" es lo correcto. Un ítem de moderación que
/// parpadea mientras resuelve el token es peor que uno que aparece medio
/// segundo tarde, y un error de red no puede abrir una superficie de staff.
final isModeratorProvider = Provider<bool>(
  (ref) => ref.watch(moderatorClaimProvider).valueOrNull ?? false,
);

/// Los reportes pendientes. Se refresca con `ref.invalidate`.
final pendingReportsProvider = FutureProvider<PendingQueue>((ref) {
  if (!ref.watch(isModeratorProvider)) {
    return Future.value(
      const PendingQueue(reportes: [], incompleta: false),
    );
  }
  return ref.watch(moderationQueueServiceProvider).listPending();
});

final moderationStatsProvider = FutureProvider<ModerationStats?>((ref) {
  if (!ref.watch(isModeratorProvider)) return Future.value(null);
  return ref.watch(moderationQueueServiceProvider).stats();
});
