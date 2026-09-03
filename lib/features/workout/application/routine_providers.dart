import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/network_timeouts.dart';
import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/domain/experience_level.dart';
import '../data/routine_repository.dart';
import '../domain/routine.dart';

final routineRepositoryProvider = Provider<RoutineRepository>(
  (ref) => RoutineRepository(firestore: ref.watch(firestoreProvider)),
);

/// Eager-loads the system template catalogue (~6 docs). Auth-gated:
/// returns an empty list when unauthenticated, mirroring [exercisesProvider].
/// Uses [RoutineRepository.listSystemTemplates] (REQ-USR-015, ADR-USR-05) —
/// only `source == 'system'` routines; athlete-created routines are isolated
/// in [userCreatedRoutinesProvider].
final routinesProvider = FutureProvider<List<Routine>>((ref) async {
  final user = await ref.watch(authStateChangesProvider.future);
  if (user == null) return const [];
  return ref.watch(routineRepositoryProvider).listSystemTemplates();
});

/// Community-published trainer templates (`trainer-template` +
/// `visibility == 'public'`). Auth-gated like [routinesProvider]; a failure
/// here is enrichment-only for the PLANTILLAS grid (see
/// `communityTemplatesProvider`).
///
/// `autoDispose` on purpose (unlike [routinesProvider], whose system
/// catalogue is effectively immutable): the community catalogue changes
/// whenever ANY trainer publishes or unpublishes. Kept alive while
/// `/workout` is mounted by PlantillasTab, it re-queries when the athlete
/// comes back to the Entrenar tab instead of freezing for the whole
/// session.
final publishedTemplatesProvider =
    FutureProvider.autoDispose<List<Routine>>((ref) async {
  final user = await ref.watch(authStateChangesProvider.future);
  if (user == null) return const [];
  return ref.watch(routineRepositoryProvider).listPublishedTemplates();
});

/// Live stream of the trainer's own templates (assignedBy == trainerId,
/// source == trainer-template). Powers the template library section of
/// `TrainerWorkoutView`.
final trainerTemplatesStreamProvider =
    StreamProvider.autoDispose.family<List<Routine>, String>((ref, trainerId) {
  return ref.read(routineRepositoryProvider).watchTemplatesBy(trainerId);
});

/// Single-doc fetch. Hits Firestore directly via `getById` so it works for
/// BOTH public catalog plantillas AND private trainer-assigned plans
/// (which are not in [routinesProvider] because [listSystemTemplates] filters
/// by `source == 'system'` and `visibility == 'public'`).
///
/// One-shot Future: callers that read the routine once (session finish/update,
/// insights radars via `.future`) rely on this NOT holding an open stream.
/// Screens that must AUTO-REFRESH after an edit use [routineByIdStreamProvider]
/// instead.
///
/// Caches SUCCESS, never caches FAILURE (#497) — see [_cacheOnlyOnSuccess].
final routineByIdProvider = FutureProvider.autoDispose.family<Routine?, String>(
  (ref, id) async {
    return _cacheOnlyOnSuccess(
      ref,
      () => ref.watch(routineRepositoryProvider).getById(id),
    );
  },
);

/// Live single-doc stream via `watchById`, for screens that must re-render when
/// the routine changes (routine detail: an edit must show immediately instead
/// of a stale cached value — issue #401). `autoDispose` so the Firestore
/// listener is torn down when the detail screen leaves. Separate from
/// [routineByIdProvider] on purpose: the one-shot Future callers must not be
/// switched to a stream (they read via `.future` and would leak open listeners).
final routineByIdStreamProvider =
    StreamProvider.autoDispose.family<Routine?, String>(
  (ref, id) {
    return ref.watch(routineRepositoryProvider).watchById(id);
  },
);

/// Routine lookup for callers that treat the routine as OPTIONAL enrichment:
/// resolves to `null` when it is not visible (deleted, or access revoked)
/// instead of throwing. Transient backend failures still propagate — see
/// [RoutineRepository.getByIdIfVisible] for the full contract and why the
/// distinction matters.
///
/// The insights radars use this for their muscle-group slot fallback: they
/// resolve the routine of every scanned session, so one stale session pointing
/// at a routine that is gone must degrade that session's custom-exercise
/// mapping, not fail the whole chart.
///
/// Caches SUCCESS (including the `null` "not visible" answer), never caches
/// the transient failures it rethrows (#497) — see [_cacheOnlyOnSuccess].
final visibleRoutineByIdProvider =
    FutureProvider.autoDispose.family<Routine?, String>(
  (ref, id) async {
    return _cacheOnlyOnSuccess(
      ref,
      () => ref.watch(routineRepositoryProvider).getByIdIfVisible(id),
    );
  },
);

/// Runs [fetch] under a cache policy of "keep the answer, drop the failure".
///
/// Both single-doc providers above are read one-shot from many places (session
/// start/resume, `planProgressProvider`, the insights radars) and MUST keep
/// caching their result: making them plainly `autoDispose` would re-hit
/// Firestore on every mount of every consumer.
///
/// But a NON-autoDispose provider caches its `AsyncError` just as durably as
/// its data, and nothing ever invalidated these (#497). One timeout in a gym
/// with bad signal, or a `permission-denied` on a trainer-template that was
/// just un-shared, and every consumer stayed broken until the app restarted —
/// "empezar/continuar sesión" included. The screens' own retry buttons could
/// not fix it either: `ref.invalidate` on a WRAPPER (`planProgressProvider`)
/// does NOT cascade to its dependencies. Same family as #376.
///
/// So: [Ref.keepAlive] is taken on entry and released ONLY when the fetch
/// throws. On success the link is held and the element behaves exactly as the
/// old non-autoDispose provider did. Taking the link BEFORE the first await
/// also means an in-flight fetch is never disposed mid-air by a consumer that
/// unmounted while waiting.
/// ⚠️ El `keepAlive` se toma ANTES del await y solo se suelta si el fetch TIRA.
/// Un fetch que no resuelve NI tira no es éxito ni fracaso: dejaba el elemento
/// clavado en `AsyncLoading` por el resto de la vida del proceso, y cada lector
/// posterior de `.future` esperaba para siempre. Ni el botón de reintento de la
/// pantalla lo destrababa, porque nunca había un error del que volver.
///
/// Por eso el fetch va ACOTADO: un stall se convierte en `TimeoutException`, y
/// con eso el `catch` de abajo corre, el link se cierra, el elemento se descarta
/// y la próxima lectura arranca un fetch nuevo. Es la mitad estructural del
/// spinner eterno al retomar — ver `core/utils/network_timeouts.dart`.
Future<Routine?> _cacheOnlyOnSuccess(
  Ref<AsyncValue<Routine?>> ref,
  Future<Routine?> Function() fetch,
) async {
  final link = ref.keepAlive();
  try {
    return await fetch().timeout(ref.read(firestoreReadTimeoutProvider));
  } catch (_) {
    link.close();
    rethrow;
  }
}

/// Currently selected level filter for the Plantillas section.
/// `null` means "Todas" (no filter applied).
final routinesLevelFilterProvider =
    StateProvider<ExperienceLevel?>((ref) => null);

/// Derived view of [routinesProvider] filtered by [routinesLevelFilterProvider].
/// Returns an [AsyncValue] so the UI keeps a unified loading/error contract.
/// When the filter is `null`, the full list is returned unchanged.
///
/// [AsyncValue.whenData] preserves loading and error states automatically
/// — only the data branch runs the transform.
final filteredRoutinesProvider = Provider<AsyncValue<List<Routine>>>((ref) {
  final routines = ref.watch(routinesProvider);
  final filter = ref.watch(routinesLevelFilterProvider);
  return routines.whenData((list) {
    if (filter == null) return list;
    return list.where((r) => r.level == filter).toList();
  });
});

/// Drops the cached single-doc answers for [routineId] after a WRITE to it.
///
/// [routineByIdProvider] and [visibleRoutineByIdProvider] hold a
/// [Ref.keepAlive] link for as long as the fetch succeeded (see
/// [_cacheOnlyOnSuccess]), so their `autoDispose` never fires and nothing
/// re-reads Firestore on its own. That is the point for READS — but it means
/// an EDIT is invisible to every one-shot consumer until the process dies.
///
/// The bug that forced this (#: "agrego un ejercicio y al EMPEZAR no está"):
/// `RoutineDetailScreen` watches [routineByIdStreamProvider], so the added
/// exercise appeared there immediately, while `SessionNotifier._buildFresh`
/// reads [routineByIdProvider] and built the session from the PRE-edit copy.
/// Same routine, two sources of truth, and only an app restart reconciled them.
///
/// Every write path that mutates an EXISTING routine doc must call this right
/// after the write resolves — edits, archives, deletes, publish/unpublish. The
/// stream-backed LISTS heal themselves from the Firestore snapshot, which is
/// what makes the omission so easy to miss: the grid updates, the single-doc
/// readers do not.
///
/// Creates are the one exception: nothing can be cached under an id that did
/// not exist yet. `assignTemplateToAthlete` counts as a create — it writes a
/// NEW athlete-owned doc via `createAssigned` and never touches the template.
///
/// Rating aggregates (`ratingAvg`/`ratingsCount`) are written server-side on
/// the parent doc and are therefore NOT covered here; a cached copy can show a
/// stale average until the container is rebuilt.
///
/// Takes the [ProviderContainer] and not a `WidgetRef` ON PURPOSE: the editor
/// captures it BEFORE the save's async gap, so a back gesture that disposes the
/// screen mid-write still drops the stale cache. A `WidgetRef` touched after
/// unmount throws, and the branch that swallowed the invalidation would be
/// exactly the one that leaves a pre-edit routine cached for the whole process.
void invalidateRoutineById(ProviderContainer container, String routineId) {
  container.invalidate(routineByIdProvider(routineId));
  container.invalidate(visibleRoutineByIdProvider(routineId));
}
