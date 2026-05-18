import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/session_repository.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';
import 'session_init.dart';
import 'session_notifier.dart';
import 'session_state.dart';

// ─── Dev A — providers de Etapa 1 (NO modificar) ─────────────────────────────

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(firestore: ref.watch(firestoreProvider)),
);

/// Fetches all sessions for [uid], ordered by startedAt descending.
/// Returns an empty list when [uid] is empty/invalid.
final sessionsByUidProvider =
    FutureProvider.family<List<Session>, String>((ref, uid) async {
  if (uid.isEmpty) return const [];
  return ref.watch(sessionRepositoryProvider).listByUid(uid);
});

/// Returns the currently active session for [uid], or null if none.
final activeSessionProvider =
    FutureProvider.family<Session?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  return ref.watch(sessionRepositoryProvider).getActive(uid);
});

// ─── Etapa 2 — nuevos providers para el player ───────────────────────────────

/// UID del usuario autenticado, o null si no hay sesión.
/// Público porque tanto el notifier como activeSessionForUidProvider lo usan.
final currentUidProvider = Provider<String?>((ref) {
  final user = ref.watch(authStateChangesProvider).valueOrNull;
  return user?.uid;
});

/// Notifier de sesión activa. autoDispose cancela el timer al salir del player.
/// Orden: `.autoDispose.family` (no `.family.autoDispose`). Diseño §4.
final sessionNotifierProvider =
    AsyncNotifierProvider.autoDispose.family<SessionNotifier, SessionState,
        SessionInit>(
  SessionNotifier.new,
);

/// Chequeo de sesión activa al abrir /home (Decision 12).
/// Retorna el record (session + setLogs) si hay una sesión activa, o null.
/// autoDispose: se re-evalúa en cada mount de HomeScreen.
final activeSessionForUidProvider =
    FutureProvider.autoDispose<({Session session, List<SetLog> setLogs})?>(
  (ref) async {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return null;
    final repo = ref.read(sessionRepositoryProvider);
    // Adaptación al contrato real de Etapa 1: getActive + listSetLogs.
    final session = await repo.getActive(uid);
    if (session == null) return null;
    final setLogs = await repo.listSetLogs(uid: uid, sessionId: session.id);
    return (session: session, setLogs: setLogs);
  },
);
