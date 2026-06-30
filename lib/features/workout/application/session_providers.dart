import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/application/user_public_profile_providers.dart'
    show userPublicProfileRepositoryProvider;
import '../data/session_repository.dart';
import '../domain/session.dart';
import '../domain/session_status.dart';
import '../domain/set_log.dart';
import 'plan_progress.dart';
import 'routine_providers.dart' show routineByIdProvider;
import 'session_init.dart';
import 'session_notifier.dart';
import 'session_state.dart';

// ─── Dev A — providers de Etapa 1 ────────────────────────────────────────────

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(
    firestore: ref.watch(firestoreProvider),
    // Wired so finish() can recompute public workoutsCount/racha counters.
    // Without this the counters silently never update (bug: header showed 0).
    publicProfileRepository: ref.watch(userPublicProfileRepositoryProvider),
  ),
);

/// Fetches all sessions for [uid], ordered by startedAt descending.
/// Returns an empty list when [uid] is empty/invalid.
/// autoDispose: refresca al re-mountear (volver al tab Workout tras un
/// nuevo entreno) sin necesidad de invalidate manual desde el player.
final sessionsByUidProvider =
    FutureProvider.autoDispose.family<List<Session>, String>((ref, uid) async {
  if (uid.isEmpty) return const [];
  return ref.watch(sessionRepositoryProvider).listByUid(uid);
});

/// Fetches only [uid]'s FINISHED sessions completed today (UTC), ordered by
/// finishedAt descending. Bounded server-side query — used by the trainer
/// dashboard's "Entrenaron hoy" list to avoid a full-history read per athlete.
/// autoDispose: refreshes on re-mount, mirroring [sessionsByUidProvider].
final finishedTodayByUidProvider =
    FutureProvider.autoDispose.family<List<Session>, String>((ref, uid) async {
  if (uid.isEmpty) return const [];
  return ref.watch(sessionRepositoryProvider).listFinishedToday(uid);
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
final sessionNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<SessionNotifier, SessionState, SessionInit>(
  SessionNotifier.new,
);

/// Summary provider: fetches Session + SetLogs in parallel for a given
/// (uid, sessionId) pair. Returns null session when doc doesn't exist.
/// autoDispose so the load is re-triggered if the user navigates back and
/// returns. family key is a Dart record for explicit named fields (Design §2).
final sessionSummaryProvider = FutureProvider.autoDispose.family<
    ({Session? session, List<SetLog> setLogs}),
    ({String uid, String sessionId})>((ref, key) async {
  final repo = ref.read(sessionRepositoryProvider);
  final results = await Future.wait([
    repo.getById(uid: key.uid, sessionId: key.sessionId),
    repo.listSetLogs(uid: key.uid, sessionId: key.sessionId),
  ]);
  return (
    session: results[0] as Session?,
    setLogs: results[1] as List<SetLog>,
  );
});

// ─── Último peso por ejercicio (preview de rutina) ───────────────────────────

/// Cuántas sesiones recientes se escanean para derivar el último peso. Acota
/// las lecturas de Firestore; cubre de sobra el uso habitual (más reciente
/// primero).
const int _lastWeightSessionScan = 15;

/// Map `exerciseId → último peso usado (kg)`, derivado de las sesiones del
/// usuario (más reciente primero). Lo consume el badge "ÚLTIMO" del preview de
/// rutina. Indexado por ejercicio (no por rutina), así sobrevive cambios de
/// rutina y ejercicios repetidos (device feedback 2026-06-12).
///
/// Deriva del historial existente (no persiste un índice aparte) para que
/// funcione de inmediato con las sesiones ya guardadas. Si el volumen de
/// sesiones crece mucho, migrar a un doc índice `exerciseStats/{exerciseId}`
/// actualizado al finalizar la sesión.
final lastWeightByExerciseProvider =
    FutureProvider.autoDispose.family<Map<String, double>, String>(
  (ref, uid) async {
    if (uid.isEmpty) return const {};
    final sessions = await ref.watch(sessionsByUidProvider(uid).future);
    final repo = ref.read(sessionRepositoryProvider);

    final scanned = sessions.take(_lastWeightSessionScan).toList();
    // setLogs de cada sesión en paralelo, preservando el orden (más reciente
    // primero) que devuelve sessionsByUidProvider.
    final logsPerSession = await Future.wait(
      scanned.map((s) => repo.listSetLogs(uid: uid, sessionId: s.id)),
    );

    final result = <String, double>{};
    for (final logs in logsPerSession) {
      // Dentro de la sesión, el peso del último set (mayor setNumber) de cada
      // ejercicio.
      final lastSetPerExercise = <String, SetLog>{};
      for (final log in logs) {
        final existing = lastSetPerExercise[log.exerciseId];
        if (existing == null || log.setNumber > existing.setNumber) {
          lastSetPerExercise[log.exerciseId] = log;
        }
      }
      // La primera sesión (más reciente) que tiene el ejercicio define el valor.
      for (final entry in lastSetPerExercise.entries) {
        result.putIfAbsent(entry.key, () => entry.value.weightKg);
      }
    }
    return result;
  },
);

// ─── Coach cross-user set-log provider (REQ-SETLOGS-005) ─────────────────────

/// Fetches the setLogs for a given athlete's session, for the trainer's
/// read-only view. Keyed on a Dart record so named fields are explicit at
/// every call site. Returns `[]` immediately when either key field is empty,
/// without hitting Firestore. autoDispose: drops the cache when the expansion
/// tile closes.
final coachSessionSetLogsProvider = FutureProvider.autoDispose
    .family<List<SetLog>, ({String athleteUid, String sessionId})>(
        (ref, key) async {
  if (key.athleteUid.isEmpty || key.sessionId.isEmpty) {
    return const <SetLog>[];
  }
  return ref.read(sessionRepositoryProvider).listSetLogs(
        uid: key.athleteUid,
        sessionId: key.sessionId,
      );
});

// ─── Periodization (Model B) — plan progress provider ────────────────────────

/// Family key for [planProgressProvider].
///
/// Uses only String fields for structural equality via Dart's record ==.
/// - [uid]       the athlete's Firebase uid.
/// - [routineId] the routine being tracked.
///
/// dayNumbers and numWeeks are resolved inside the provider via
/// [routineByIdProvider] to avoid List<int> equality issues.
typedef PlanProgressKey = ({String uid, String routineId});

/// Derives the athlete's current progress in a periodized plan.
///
/// Reads [sessionsByUidProvider] (filtered by routineId + finished +
/// wasFullyCompleted) and [routineByIdProvider] (for dayNumbers + numWeeks),
/// then calls [derivePlanProgress].
///
/// autoDispose: refreshes automatically when the screen is re-mounted
/// (e.g. after returning from the player). family key is [PlanProgressKey].
final planProgressProvider = FutureProvider.autoDispose
    .family<PlanProgress, PlanProgressKey>((ref, key) async {
  final sessions = await ref.watch(sessionsByUidProvider(key.uid).future);
  final routine = await ref.watch(routineByIdProvider(key.routineId).future);
  if (routine == null) {
    return derivePlanProgress({}, const [], 1);
  }
  final dayNumbers = routine.days.map((d) => d.dayNumber).toList();
  final completed = sessions
      .where(
        (s) =>
            s.routineId == key.routineId &&
            s.status == SessionStatus.finished &&
            s.wasFullyCompleted,
      )
      .map((s) => (week: s.weekNumber, day: s.dayNumber))
      .toSet();

  // REQ-WPRES-022 (ADR-WPRES-10): compute the per-week required-day grid.
  // A (week, day) is required iff the day has ≥1 slot present in that week.
  // An absent day (zero present slots) is NOT in requiredPairs → auto-satisfied
  // by derivePlanProgress and the gating functions.
  // numWeeks==1 / all-empty-mask plans → every pair is included → back-compat.
  final requiredPairs = <CompletedKey>{};
  for (var w = 0; w < routine.numWeeks; w++) {
    for (final d in routine.days) {
      final hasPresent = d.slots.any((s) => s.isPresentInWeek(w));
      if (hasPresent) {
        requiredPairs.add((week: w, day: d.dayNumber));
      }
    }
  }

  return derivePlanProgress(
    completed,
    dayNumbers,
    routine.numWeeks,
    requiredPairs: requiredPairs,
  );
});

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
