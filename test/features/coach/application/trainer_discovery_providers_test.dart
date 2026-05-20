import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

Position _makePosition({double lat = -34.6, double lon = -58.4}) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime(2024),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

TrainerPublicProfile _trainer({
  required String uid,
  String? displayName,
  TrainerSpecialty? specialty,
  double? lat,
  double? lon,
  String? geohash,
  int? rate,
}) =>
    TrainerPublicProfile(
      uid: uid,
      displayName: displayName ?? uid,
      displayNameLowercase: (displayName ?? uid).toLowerCase(),
      trainerSpecialty: specialty,
      trainerLatitude: lat,
      trainerLongitude: lon,
      trainerGeohash: geohash,
      trainerHourlyRate: rate,
    );

// ── Fake GeolocatorPlatform stub ──────────────────────────────────────────
// Widget tests override athleteLocationProvider directly — no geolocator
// invoked. These provider unit tests also use direct provider overrides.

// ──────────────────────────────────────────────────────────────────────────
// T22 / T23: AthleteLocationNotifier state machine
// ──────────────────────────────────────────────────────────────────────────

void main() {
  group('AthleteLocationNotifier — T22/T23', () {
    test('initial state is AsyncData(null) — permission not yet requested',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(athleteLocationProvider);
      // Initial state: AsyncData(null) means location not available yet
      expect(state, isA<AsyncData<Position?>>());
      expect(state.value, isNull);
    });

    test('can be overridden with a granted position', () async {
      final pos = _makePosition();
      final container = ProviderContainer(overrides: [
        athleteLocationProvider.overrideWith(
          (ref) => AthleteLocationNotifier()..setForTest(pos),
        ),
      ]);
      addTearDown(container.dispose);

      // Wait for any async initialization
      await container.pump();

      final state = container.read(athleteLocationProvider);
      expect(state.value, pos);
    });

    test('denied state is AsyncData(null) with isPermissionDenied true',
        () async {
      final container = ProviderContainer(overrides: [
        athleteLocationProvider.overrideWith(
          (ref) => AthleteLocationNotifier()..setDeniedForTest(),
        ),
      ]);
      addTearDown(container.dispose);

      await container.pump();

      final notifier = container.read(athleteLocationProvider.notifier);
      expect(notifier.isPermissionDenied, isTrue);
      expect(container.read(athleteLocationProvider).value, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T24 / T25: trainerDiscoveryProvider
  // ──────────────────────────────────────────────────────────────────────────

  group('trainerDiscoveryProvider — T24/T25', () {
    test('SCENARIO: falls back to listAll when location is null', () async {
      final trainer1 = _trainer(uid: 'a', displayName: 'Alpha');
      final trainer2 = _trainer(uid: 'b', displayName: 'Beta');

      final container = ProviderContainer(overrides: [
        athleteLocationProvider.overrideWith(
          (_) => AthleteLocationNotifier()..setForTest(null),
        ),
        selectedSpecialtyProvider.overrideWith((_) => null),
        trainerPublicProfileRepositoryProvider.overrideWith(
          (_) => _FakeTrainerRepo(all: [trainer1, trainer2]),
        ),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(trainerDiscoveryProvider.future);
      expect(result.length, 2);
      // No location → no distance reorder, just as returned by repo
    });

    test('SCENARIO: with location reorders by haversine distance ASC',
        () async {
      // trainer near BA (-34.6, -58.4), trainer far away (-33.0, -60.0)
      final near = _trainer(
          uid: 'near',
          displayName: 'Near',
          lat: -34.6,
          lon: -58.4,
          geohash: 'd2h4j');
      final far = _trainer(
          uid: 'far',
          displayName: 'Far',
          lat: -33.0,
          lon: -60.0,
          geohash: 'd2h00');

      final pos = _makePosition(lat: -34.6, lon: -58.4);

      final container = ProviderContainer(overrides: [
        athleteLocationProvider.overrideWith(
          (_) => AthleteLocationNotifier()..setForTest(pos),
        ),
        selectedSpecialtyProvider.overrideWith((_) => null),
        trainerPublicProfileRepositoryProvider.overrideWith(
          (_) => _FakeTrainerRepo(geohash: [near, far]),
        ),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(trainerDiscoveryProvider.future);
      expect(result.first.uid, 'near');
      expect(result.last.uid, 'far');
    });

    test('SCENARIO-431: specialty filter reduces list client-side', () async {
      final t1 = _trainer(
          uid: 'a', specialty: TrainerSpecialty.crossfit, displayName: 'A');
      final t2 = _trainer(
          uid: 'b', specialty: TrainerSpecialty.yoga, displayName: 'B');

      final container = ProviderContainer(overrides: [
        athleteLocationProvider.overrideWith(
          (_) => AthleteLocationNotifier()..setForTest(null),
        ),
        selectedSpecialtyProvider
            .overrideWith((_) => TrainerSpecialty.crossfit),
        trainerPublicProfileRepositoryProvider.overrideWith(
          (_) => _FakeTrainerRepo(all: [t1, t2]),
        ),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(trainerDiscoveryProvider.future);
      expect(result.length, 1);
      expect(result.first.uid, 'a');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T24 / T25: trainerByIdProvider
  // ──────────────────────────────────────────────────────────────────────────

  group('trainerByIdProvider — T24/T25', () {
    test('returns trainer profile when exists', () async {
      final trainer = _trainer(uid: 'x', displayName: 'Xavier');

      final container = ProviderContainer(overrides: [
        trainerPublicProfileRepositoryProvider.overrideWith(
          (_) => _FakeTrainerRepo(byId: {'x': trainer}),
        ),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(trainerByIdProvider('x').future);
      expect(result, isNotNull);
      expect(result!.uid, 'x');
    });

    test('returns null when trainer doc does not exist', () async {
      final container = ProviderContainer(overrides: [
        trainerPublicProfileRepositoryProvider.overrideWith(
          (_) => _FakeTrainerRepo(),
        ),
      ]);
      addTearDown(container.dispose);

      final result = await container.read(trainerByIdProvider('ghost').future);
      expect(result, isNull);
    });
  });
}

// ── Fake repository ────────────────────────────────────────────────────────

class _FakeTrainerRepo implements TrainerPublicProfileRepositoryInterface {
  _FakeTrainerRepo({
    List<TrainerPublicProfile>? all,
    List<TrainerPublicProfile>? geohash,
    Map<String, TrainerPublicProfile>? byId,
  })  : _all = all ?? const [],
        _geohash = geohash ?? const [],
        _byId = byId ?? const {};

  final List<TrainerPublicProfile> _all;
  final List<TrainerPublicProfile> _geohash;
  final Map<String, TrainerPublicProfile> _byId;

  @override
  Future<List<TrainerPublicProfile>> listAll(
      {TrainerSpecialty? specialty}) async {
    var r = _all;
    if (specialty != null) {
      r = r.where((t) => t.trainerSpecialty == specialty).toList();
    }
    return r;
  }

  @override
  Future<List<TrainerPublicProfile>> listByGeohashPrefix(
    String prefix5, {
    TrainerSpecialty? specialty,
  }) async {
    var r = _geohash;
    if (specialty != null) {
      r = r.where((t) => t.trainerSpecialty == specialty).toList();
    }
    return r;
  }

  @override
  Future<TrainerPublicProfile?> getById(String uid) async => _byId[uid];
}
