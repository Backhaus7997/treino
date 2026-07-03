// Task 1.11 RED / 1.12 GREEN — gym-selection-v2 Phase 1.
//
// nearbyLocationProvider is the HYBRID location pattern (design AD-1/AD-9
// item 4): silent checkPermission() first (never a surprise OS dialog on
// screen-open), exposes a not-granted state the UI reads to render an
// inline opt-in affordance, and a separate escalation method
// (requestPermission()) invoked ONLY on explicit user tap — never here.
//
// CRITICAL: `Geolocator.checkPermission()` HANGS FOREVER under
// `testWidgets` (confirmed gotcha — see
// test/features/profile_setup/presentation/gym_search_box_test.dart:264-305).
// This provider therefore MUST expose `setForTest`/`setDeniedForTest` test
// seams (mirrors `AthleteLocationNotifier` in
// trainer_discovery_providers.dart) — every test below drives state via
// those seams and NEVER lets the real Geolocator plugin channel fire.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/features/gyms/application/places_providers.dart';

void main() {
  final position = Position(
    latitude: -34.5598,
    longitude: -58.4615,
    timestamp: DateTime(2026, 7, 3),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  group('nearbyLocationProvider — initial state', () {
    test(
        'initial state is AsyncData(null) with no permission-denied flag — '
        'no silent check runs on construction/read alone', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Reading the provider/notifier must not itself trigger
      // checkSilently() (that is a UI-driven call on screen-open) — this
      // would hang under testWidgets if it touched the real Geolocator
      // plugin channel. Reaching this assertion without hanging proves it.
      final notifier = container.read(nearbyLocationProvider.notifier);
      final state = container.read(nearbyLocationProvider);

      expect(state, isA<AsyncData<Position?>>());
      expect(state.value, isNull);
      expect(notifier.isPermissionDenied, isFalse);
    });
  });

  group('nearbyLocationProvider — test seams', () {
    test('setForTest(position) transitions to granted-with-position', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(nearbyLocationProvider.notifier).setForTest(position);

      final state = container.read(nearbyLocationProvider);
      expect(state.hasValue, isTrue);
      expect(state.value, position);
    });

    test('setDeniedForTest() transitions to not-granted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(nearbyLocationProvider.notifier).setDeniedForTest();

      final notifier = container.read(nearbyLocationProvider.notifier);
      final state = container.read(nearbyLocationProvider);
      expect(state.hasValue, isTrue);
      expect(state.value, isNull);
      expect(notifier.isPermissionDenied, isTrue);
    });

    test('setForTest after setDeniedForTest clears the denied flag', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(nearbyLocationProvider.notifier);
      notifier.setDeniedForTest();
      expect(notifier.isPermissionDenied, isTrue);

      notifier.setForTest(position);
      expect(notifier.isPermissionDenied, isFalse);
      expect(container.read(nearbyLocationProvider).value, position);
    });

    test('no real Geolocator call occurs when only test seams are used', () {
      // Constructing the container and driving state exclusively via
      // setForTest/setDeniedForTest must never touch the platform channel —
      // if it did, this test would hang (the confirmed testWidgets gotcha)
      // rather than complete instantly under plain `test()`.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(nearbyLocationProvider.notifier);
      notifier.setDeniedForTest();
      notifier.setForTest(position);
      notifier.setDeniedForTest();

      // Reaching this line without hanging/throwing proves no plugin
      // channel invocation occurred.
      expect(container.read(nearbyLocationProvider).value, isNull);
    });
  });
}
