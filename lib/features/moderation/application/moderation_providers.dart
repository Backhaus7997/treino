import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/block_repository.dart';
import '../data/report_repository.dart';

final blockRepositoryProvider = Provider<BlockRepository>(
  (ref) => BlockRepository(firestore: ref.watch(firestoreProvider)),
);

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(firestore: ref.watch(firestoreProvider)),
);

/// UIDs que [uid] bloqueó, en vivo.
///
/// Family keyed by `String` uid — mismo criterio que `followingProvider`
/// (ver el dartdoc de clase en `follow_providers.dart`): Riverpod compara
/// keys por igualdad y una `List` la compararía por identidad.
final blockedUidsProvider =
    StreamProvider.family.autoDispose<List<String>, String>((ref, uid) {
  return ref.watch(blockRepositoryProvider).watchBlockedUids(uid);
});

/// La lista de bloqueados para quien la MUESTRA («Usuarios bloqueados»): sin
/// red y con la caché fría termina en `AsyncError` (`unavailable`) en vez de
/// publicar un `[]` que la pantalla dibujaría como «No bloqueaste a nadie».
///
/// Es aparte de [blockedUidsProvider] a propósito: ése lo leen el feed, el chat
/// y [myBlockedUidsProvider], que ante el frío asumen «sin bloqueos». Ver
/// [BlockRepository.watchBlockedUidsConfirmed].
final blockedUidsConfirmedProvider =
    StreamProvider.family.autoDispose<List<String>, String>((ref, uid) {
  return ref.watch(blockRepositoryProvider).watchBlockedUidsConfirmed(uid);
});

/// Conveniencia: UIDs que el usuario ACTUAL bloqueó, o `[]` si no hay sesión
/// o mientras el stream no emitió el primer valor.
///
/// Envuelve [blockedUidsProvider] con [currentUidProvider] para que los call
/// sites (feed, public profile) no repitan el chequeo de sesión nula en cada
/// uno. Devolver `[]` en frío es a propósito — mismo criterio que
/// `pendingFollowRequestCountProvider`: mientras carga o ante error se asume
/// "sin bloqueos" en vez de tapar contenido de más.
final myBlockedUidsProvider = Provider.autoDispose<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const [];
  return ref.watch(blockedUidsProvider(uid)).valueOrNull ?? const [];
});
