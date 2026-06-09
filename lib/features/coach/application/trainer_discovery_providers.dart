import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/trainer_public_profile_repository.dart';
import '../domain/discovery_filters.dart';
import '../domain/trainer_location.dart';
import '../domain/trainer_public_profile.dart';
import '../domain/trainer_specialty.dart';
import '../../../core/utils/geohash.dart';
import '../../../core/utils/haversine.dart';

// ── Repository interface (enables test overriding) ────────────────────────

/// Abstraction over [TrainerPublicProfileRepository] used by providers so
/// widget and unit tests can inject a fake without a real Firestore.
abstract interface class TrainerPublicProfileRepositoryInterface {
  /// DEPRECATED — usar [listByGeohashes] en lugar. Mantenido por backward
  /// compat con tests legacy hasta que se migren todos.
  Future<List<TrainerPublicProfile>> listByGeohashPrefix(
    String prefix5, {
    TrainerSpecialty? specialty,
  });

  Future<List<TrainerPublicProfile>> listByGeohashes(
    List<String> geohashes, {
    TrainerSpecialty? specialty,
  });

  Future<List<TrainerPublicProfile>> listVirtualOnly({
    TrainerSpecialty? specialty,
  });

  Future<List<TrainerPublicProfile>> listAll({TrainerSpecialty? specialty});

  Future<TrainerPublicProfile?> getById(String uid);
}

/// Provider for the [TrainerPublicProfileRepositoryInterface].
///
/// Override in tests with a fake implementation (see provider tests).
final trainerPublicProfileRepositoryProvider =
    Provider<TrainerPublicProfileRepositoryInterface>(
  (ref) => _RealRepoAdapter(
    TrainerPublicProfileRepository(firestore: ref.watch(firestoreProvider)),
  ),
);

/// Adapter that wraps the real [TrainerPublicProfileRepository] to satisfy
/// the [TrainerPublicProfileRepositoryInterface] contract.
class _RealRepoAdapter implements TrainerPublicProfileRepositoryInterface {
  _RealRepoAdapter(this._repo);
  final TrainerPublicProfileRepository _repo;

  @override
  Future<List<TrainerPublicProfile>> listByGeohashPrefix(
    String prefix5, {
    TrainerSpecialty? specialty,
  }) =>
      _repo.listByGeohashPrefix(prefix5, specialty: specialty);

  @override
  Future<List<TrainerPublicProfile>> listByGeohashes(
    List<String> geohashes, {
    TrainerSpecialty? specialty,
  }) =>
      _repo.listByGeohashes(geohashes, specialty: specialty);

  @override
  Future<List<TrainerPublicProfile>> listVirtualOnly({
    TrainerSpecialty? specialty,
  }) =>
      _repo.listVirtualOnly(specialty: specialty);

  @override
  Future<List<TrainerPublicProfile>> listAll({TrainerSpecialty? specialty}) =>
      _repo.listAll(specialty: specialty);

  @override
  Future<TrainerPublicProfile?> getById(String uid) => _repo.getById(uid);
}

// ── AthleteLocationNotifier ───────────────────────────────────────────────

/// States for athlete GPS location:
///   - `AsyncData(null)` = initial / permission denied / skipped
///   - `AsyncLoading`    = permission dialog showing / GPS acquiring
///   - `AsyncData(pos)`  = location granted and acquired
///   - `AsyncError`      = hardware/service error
///
/// Per design D7: NOT autoDispose — persists across list↔detail navigation.
/// Per design D8: rationale sheet must be shown BEFORE calling [requestPermission].
///
/// REQ-COACH-DISC-UI-011.
class AthleteLocationNotifier extends StateNotifier<AsyncValue<Position?>> {
  AthleteLocationNotifier() : super(const AsyncData(null));

  /// Whether the last permission check resulted in a denied state.
  bool _isPermissionDenied = false;

  bool get isPermissionDenied => _isPermissionDenied;

  /// True when we do NOT yet know the permission status (initial state).
  bool get isInitial =>
      state is AsyncData && state.value == null && !_isPermissionDenied;

  /// Requests OS permission then acquires position.
  ///
  /// Call this AFTER the rationale sheet was accepted by the user.
  Future<void> requestPermission() async {
    state = const AsyncLoading();
    _isPermissionDenied = false;
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _isPermissionDenied = true;
        state = const AsyncData(null);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      state = AsyncData(pos);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  // ── Test helpers ──────────────────────────────────────────────────────────

  /// Directly set a [Position] (for test overrides — never call in production).
  void setForTest(Position? pos) {
    _isPermissionDenied = false;
    state = AsyncData(pos);
  }

  /// Set denied state (for test overrides).
  void setDeniedForTest() {
    _isPermissionDenied = true;
    state = const AsyncData(null);
  }
}

/// Provider for the athlete's current GPS location.
///
/// Per D7: NOT autoDispose — scoped to the app session lifecycle.
final athleteLocationProvider =
    StateNotifierProvider<AthleteLocationNotifier, AsyncValue<Position?>>(
  (ref) => AthleteLocationNotifier(),
);

// ── selectedSpecialtyProvider ─────────────────────────────────────────────

/// Currently selected specialty filter, as a SET (multi-select).
/// Empty set = "Todos" (no filter, all match). Non-empty = OR-match: a PF
/// passes if their `trainerSpecialty` is in the set.
///
/// Migró de `TrainerSpecialty?` a `Set<TrainerSpecialty>` post-Fase 6
/// Etapa 3 polish — el user quería filtrar por varias categorías a la vez
/// (ej. "CrossFit OR Funcional"). Backward compat al nivel de UX: empty set
/// se mapea visualmente al chip "Todos" igual que antes el `null`.
///
/// Per D11: NOT autoDispose — maintains filter across list↔detail navigation.
final selectedSpecialtyProvider = StateProvider<Set<TrainerSpecialty>>(
  (ref) => const <TrainerSpecialty>{},
);

// ── mapModeProvider (private to feature) ─────────────────────────────────

/// Whether the user selected map view. Always false (stub) in this PR.
///
/// Per D24.
final mapModeProvider = StateProvider<bool>((ref) => false);

// ── selectedDistanceFilterProvider ────────────────────────────────────────

/// Filtro de distancia máxima desde el athlete (Fase 2b del Discovery map).
///
/// Default: `DistanceFilter.any` (sin restricción). Solo aplica cuando
/// `athleteLocationProvider` tiene una `Position` válida — sin location,
/// el filtro es no-op (no se descartan trainers).
///
/// NOT autoDispose — persiste entre navegaciones list↔detail, mismo patrón
/// que `selectedSpecialtyProvider`.
final selectedDistanceFilterProvider = StateProvider<DistanceFilter>(
  (ref) => DistanceFilter.any,
);

// ── selectedPriceFilterProvider ───────────────────────────────────────────

/// Filtro de rango de precio mensual del PF (Fase 2b del Discovery map).
///
/// Default: `PriceFilter.any` (sin restricción). Trainers sin
/// `trainerMonthlyRate` set se incluyen siempre (no se filtran out) — solo
/// se filtran los que tienen rate fuera del rango.
final selectedPriceFilterProvider = StateProvider<PriceFilter>(
  (ref) => PriceFilter.any,
);

// ── virtualOnlyFilterProvider ─────────────────────────────────────────────

/// Chip "Online" del discovery — Fase 6 Etapa 0 PR#2.
///
/// Default OFF: la lista trae presenciales del área del atleta UNION
/// virtuales (todos los PFs con `trainerOffersOnline: true`). Los híbridos
/// aparecen una sola vez (dedup por uid).
///
/// Cuando está ON:
///   - El query base pasa a `repo.listVirtualOnly()` — solo PFs con
///     `trainerOffersOnline: true`, ignorando el geohash del atleta.
///   - Distance filter se ignora (un virtual no tiene "distancia").
///   - Specialty + price filters siguen aplicando client-side.
///
/// Nombre interno del provider sigue siendo `virtualOnly` por backward
/// compat con el código del PR#2 — el label visible cambió a "Online".
///
/// Persiste como los otros filters (NOT autoDispose).
final virtualOnlyFilterProvider = StateProvider<bool>((ref) => false);

// ── trainerDiscoveryProvider ──────────────────────────────────────────────

/// Fetches and orders trainers for the discovery list.
///
/// Logic per D9:
///   - If athlete location is available (AsyncData with non-null position):
///       → geohash5 prefix query → haversine reorder ASC
///   - If no location (denied/initial):
///       → listAll ordered by displayNameLowercase
///   - Client-side specialty filter applied after fetch (D10).
///
/// autoDispose: re-fetches when user returns to the list (acceptable for MVP,
/// per design risk note 4).
///
/// REQ-COACH-DISC-UI-001..011.
final trainerDiscoveryProvider =
    FutureProvider.autoDispose<List<TrainerPublicProfile>>((ref) async {
  // Scoped watch: solo re-ejecutar cuando el Position cambia realmente, NO
  // cuando el AsyncValue pasa por AsyncLoading. Sin el `.select`, ir de
  // AsyncData(null) → AsyncLoading → AsyncData(pos) disparaba 2 refetches
  // — el primero wasteful (mismo `pos == null`, mismos datos). El select
  // colapsa eso a 1 sola transición real (null → pos).
  final pos = ref.watch(athleteLocationProvider.select((s) => s.valueOrNull));
  final selectedSpecialty = ref.watch(selectedSpecialtyProvider);
  final selectedDistance = ref.watch(selectedDistanceFilterProvider);
  final selectedPrice = ref.watch(selectedPriceFilterProvider);
  final virtualOnly = ref.watch(virtualOnlyFilterProvider);
  final repo = ref.watch(trainerPublicProfileRepositoryProvider);

  List<TrainerPublicProfile> trainers;

  if (virtualOnly) {
    // Filtro ON: solo virtuales (ignora geohash + distance filter).
    trainers = await repo.listVirtualOnly();
  } else if (pos != null) {
    // Filtro OFF + location disponible: UNION de presenciales del área
    // (los que tienen al menos una ubicación cerca del atleta) + virtuales
    // (los que ofrecen online, independiente de su ubicación). Dedup por
    // uid — un PF híbrido (locations + offersOnline) aparece UNA sola vez.
    //
    // Esto resuelve un bug UX donde los PFs virtuales puros (sin
    // trainerGeohashes) no aparecían sin tocar el filtro "Online".
    final athleteGeohash = geohash5(pos.latitude, pos.longitude);
    final nearby = await repo.listByGeohashes([athleteGeohash]);
    final virtuals = await repo.listVirtualOnly();
    final byUid = <String, TrainerPublicProfile>{};
    for (final t in nearby) {
      byUid[t.uid] = t;
    }
    for (final t in virtuals) {
      byUid.putIfAbsent(t.uid, () => t);
    }
    trainers = byUid.values.toList();
    // Fallback UX: si nadie matchea (ni geohash ni virtual), mostrar
    // todos. Haversine reorder igual ordena los que tienen ubicación.
    if (trainers.isEmpty) {
      trainers = await repo.listAll();
    }
  } else {
    // Sin location del atleta: listAll.
    trainers = await repo.listAll();
  }

  // Client-side specialty filter (D10) — multi-select OR semantics.
  // Empty set = sin filtro (match all). Non-empty = el trainer tiene que
  // tener trainerSpecialty != null Y estar en el set.
  if (selectedSpecialty.isNotEmpty) {
    trainers = trainers
        .where((t) =>
            t.trainerSpecialty != null &&
            selectedSpecialty.contains(t.trainerSpecialty))
        .toList();
  }

  // Distance filter — solo aplica cuando hay location del athlete y NO
  // estamos en modo virtual-only (los PFs virtuales no tienen ubicación
  // "cercana" que medir).
  final maxKm = selectedDistance.maxKm;
  if (pos != null && maxKm != null && !virtualOnly) {
    trainers = trainers.where((t) {
      final km = nearestDistanceKm(t, pos);
      if (km == null) {
        return false; // sin location no podemos saber la distancia
      }
      return km <= maxKm;
    }).toList();
  }

  // Price filter — siempre aplica. Trainers sin rate set se incluyen
  // (matches retorna true cuando rate es null).
  if (selectedPrice != PriceFilter.any) {
    trainers = trainers
        .where((t) => selectedPrice.matches(t.trainerMonthlyRate))
        .toList();
  }

  // Reorder by haversine ASC when location is available + NOT virtual-only.
  // Tiebreaker: displayName ASC.
  if (pos != null && !virtualOnly) {
    trainers.sort((a, b) {
      final da = nearestDistanceKm(a, pos) ?? double.maxFinite;
      final db = nearestDistanceKm(b, pos) ?? double.maxFinite;
      if (da != db) return da.compareTo(db);
      return (a.displayNameLowercase ?? a.uid)
          .compareTo(b.displayNameLowercase ?? b.uid);
    });
  }

  return trainers;
});

/// Devuelve las ubicaciones efectivas de un PF, fallback a los campos legacy
/// cuando el doc no tiene `trainerLocations` (PFs no migrados todavía o tests
/// con docs legacy). Es PUREZA — no toca network.
///
/// Si `trainerLocations` no está vacío → ese array.
/// Sino, si `trainerLatitude/Longitude/Geohash` legacy están seteados →
/// devuelve un `TrainerLocation` sintético de tipo `custom`.
/// Sino → lista vacía.
List<TrainerLocation> effectiveLocationsOf(TrainerPublicProfile t) {
  if (t.trainerLocations.isNotEmpty) return t.trainerLocations;
  if (t.trainerLatitude != null &&
      t.trainerLongitude != null &&
      t.trainerGeohash != null) {
    return [
      TrainerLocation(
        id: 'legacy',
        type: TrainerLocationType.custom,
        customLabel: 'Ubicación principal',
        lat: t.trainerLatitude!,
        lng: t.trainerLongitude!,
        geohash: t.trainerGeohash!,
      ),
    ];
  }
  return const [];
}

/// Distancia haversine en km a la ubicación MÁS CERCANA del PF. Null si el
/// PF no tiene ninguna ubicación con lat/lng.
double? nearestDistanceKm(TrainerPublicProfile t, Position pos) {
  final locations = effectiveLocationsOf(t);
  if (locations.isEmpty) return null;
  double? best;
  for (final loc in locations) {
    final km = haversineKm(pos.latitude, pos.longitude, loc.lat, loc.lng);
    if (best == null || km < best) best = km;
  }
  return best;
}

/// Devuelve la ubicación más cercana del PF al atleta. Null si no tiene
/// ubicaciones. Usada por `TrainerListTile` para mostrar el label correcto.
TrainerLocation? nearestLocationOf(TrainerPublicProfile t, Position pos) {
  final locations = effectiveLocationsOf(t);
  if (locations.isEmpty) return null;
  TrainerLocation? best;
  double? bestKm;
  for (final loc in locations) {
    final km = haversineKm(pos.latitude, pos.longitude, loc.lat, loc.lng);
    if (bestKm == null || km < bestKm) {
      bestKm = km;
      best = loc;
    }
  }
  return best;
}

// ── trainerByIdProvider ───────────────────────────────────────────────────

/// Fetches a single [TrainerPublicProfile] by uid.
///
/// Returns `null` if the document does not exist (not-found state per D12).
///
/// REQ-COACH-DISC-UI-012.
final trainerByIdProvider =
    FutureProvider.autoDispose.family<TrainerPublicProfile?, String>(
  (ref, uid) async {
    final repo = ref.watch(trainerPublicProfileRepositoryProvider);
    return repo.getById(uid);
  },
);
