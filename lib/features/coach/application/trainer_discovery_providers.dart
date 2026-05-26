import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/trainer_public_profile_repository.dart';
import '../domain/discovery_filters.dart';
import '../domain/trainer_public_profile.dart';
import '../domain/trainer_specialty.dart';
import '../../../core/utils/geohash.dart';
import '../../../core/utils/haversine.dart';

// ── Repository interface (enables test overriding) ────────────────────────

/// Abstraction over [TrainerPublicProfileRepository] used by providers so
/// widget and unit tests can inject a fake without a real Firestore.
abstract interface class TrainerPublicProfileRepositoryInterface {
  Future<List<TrainerPublicProfile>> listByGeohashPrefix(
    String prefix5, {
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

/// Currently selected specialty filter. `null` means "Todos".
///
/// Per D11: NOT autoDispose — maintains filter across list↔detail navigation.
final selectedSpecialtyProvider = StateProvider<TrainerSpecialty?>(
  (ref) => null,
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
  final repo = ref.watch(trainerPublicProfileRepositoryProvider);

  List<TrainerPublicProfile> trainers;

  if (pos != null) {
    final prefix = geohash5(pos.latitude, pos.longitude);
    trainers = await repo.listByGeohashPrefix(prefix);
    // Fallback UX: si el geohash cell del atleta no tiene trainers,
    // mostrar todos (haversine reorder igual aplica). Mejor que dejar el
    // empty state cuando hay PFs disponibles en otras ciudades.
    if (trainers.isEmpty) {
      trainers = await repo.listAll();
    }
  } else {
    trainers = await repo.listAll();
  }

  // Client-side specialty filter (D10)
  if (selectedSpecialty != null) {
    trainers =
        trainers.where((t) => t.trainerSpecialty == selectedSpecialty).toList();
  }

  // Fase 2b: distance filter — solo aplica cuando hay location del athlete.
  // Si pos == null, el filtro es no-op (no descarta nada).
  final maxKm = selectedDistance.maxKm;
  if (pos != null && maxKm != null) {
    trainers = trainers.where((t) {
      if (t.trainerLatitude == null || t.trainerLongitude == null) {
        return false; // sin location no podemos saber la distancia
      }
      final km = haversineKm(
        pos.latitude,
        pos.longitude,
        t.trainerLatitude!,
        t.trainerLongitude!,
      );
      return km <= maxKm;
    }).toList();
  }

  // Fase 2b: price filter — siempre aplica. Trainers sin rate set se
  // incluyen (matches retorna true cuando rate es null).
  if (selectedPrice != PriceFilter.any) {
    trainers = trainers
        .where((t) => selectedPrice.matches(t.trainerMonthlyRate))
        .toList();
  }

  // Reorder by haversine ASC when location is available (D9)
  if (pos != null) {
    trainers.sort((a, b) {
      final da = _distanceOrMax(a, pos);
      final db = _distanceOrMax(b, pos);
      if (da != db) return da.compareTo(db);
      // Tiebreaker: displayName ASC (D9)
      return (a.displayNameLowercase ?? a.uid)
          .compareTo(b.displayNameLowercase ?? b.uid);
    });
  }

  return trainers;
});

double _distanceOrMax(TrainerPublicProfile t, Position pos) {
  if (t.trainerLatitude == null || t.trainerLongitude == null) {
    return double.maxFinite;
  }
  return haversineKm(
      pos.latitude, pos.longitude, t.trainerLatitude!, t.trainerLongitude!);
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
