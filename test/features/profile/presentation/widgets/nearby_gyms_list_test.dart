// gym-selection-v2 Phase 2 tasks 2.8/2.10 — NearbyGymsList states + tap
// selection. All providers overridden — NEVER a real Geolocator call
// (confirmed hang gotcha under testWidgets, see nearbyLocationProvider doc).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/geohash.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/gyms/domain/nearby_gym.dart';
import 'package:treino/features/profile/presentation/widgets/nearby_gyms_list.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockResolveGymPlaceService extends Mock
    implements ResolveGymPlaceService {}

/// Deterministic test position: Buenos Aires-ish coordinates, arbitrary.
const _lat = -34.5638;
const _lng = -58.4531;
final _bucket = geohash5(_lat, _lng);
final _position = Position(
  latitude: _lat,
  longitude: _lng,
  timestamp: DateTime(2025),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

NearbyGym _gym(String id, {double lat = _lat, double lng = _lng}) => NearbyGym(
      placeId: id,
      name: 'Gym $id',
      address: 'Address $id',
      lat: lat,
      lng: lng,
    );

/// Fake notifier — starts already in a controlled state via `setForTest`/
/// `setDeniedForTest`, seams `NearbyLocationNotifier` exposes explicitly for
/// tests (never touches Geolocator).
class _FakeNearbyLocationNotifier extends NearbyLocationNotifier {
  _FakeNearbyLocationNotifier({required bool granted}) {
    if (granted) {
      setForTest(_position);
    } else {
      setDeniedForTest();
    }
  }

  int checkSilentlyCallCount = 0;

  @override
  Future<void> checkSilently() async {
    checkSilentlyCallCount++;
    // No-op — state already set by the constructor for this fake.
  }
}

Widget _wrap({
  required List<Override> overrides,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: NearbyGymsList(
              uid: 'test-uid',
              currentGymId: null,
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  group('location not-granted', () {
    testWidgets('shows the "Activar ubicación" affordance', (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: false);
      await tester.pumpWidget(_wrap(overrides: [
        nearbyLocationProvider.overrideWith((ref) => fake),
      ]));
      await tester.pumpAndSettle();

      expect(
        find.text('Activar ubicación para ver gyms cercanos'),
        findsOneWidget,
      );
      expect(fake.checkSilentlyCallCount, 1);
    });
  });

  group('fetch states (location granted)', () {
    testWidgets('shows a CircularProgressIndicator while fetching',
        (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      final completer = Completer<List<NearbyGym>>();

      await tester.pumpWidget(_wrap(overrides: [
        nearbyLocationProvider.overrideWith((ref) => fake),
        nearbyGymsProvider(_bucket).overrideWith((ref) => completer.future),
      ]));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(const []);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'fetch error shows a retry affordance that invalidates '
        'nearbyGymsProvider(bucket)', (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      var attempt = 0;

      await tester.pumpWidget(_wrap(overrides: [
        nearbyLocationProvider.overrideWith((ref) => fake),
        nearbyGymsProvider(_bucket).overrideWith((ref) async {
          attempt++;
          if (attempt == 1) throw Exception('network error');
          return [_gym('ok-1')];
        }),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar los gyms cercanos.'), findsOneWidget);
      final retryFinder = find.text('Reintentar');
      expect(retryFinder, findsOneWidget);

      await tester.tap(retryFinder);
      await tester.pumpAndSettle();

      expect(find.text('Gym ok-1'), findsOneWidget);
    });

    testWidgets('empty (0 after dedup) hides the section with no error text',
        (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);

      await tester.pumpWidget(_wrap(overrides: [
        nearbyLocationProvider.overrideWith((ref) => fake),
        nearbyGymsProvider(_bucket).overrideWith((ref) async => const []),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('No pudimos'), findsNothing);
      expect(find.byType(NearbyGymsList), findsOneWidget);
    });

    testWidgets(
        'data shows up to 8 rows with "a X km" labels, current gym absent',
        (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      // 9 gyms so we can prove the cap; one shares placeId with currentGymId
      // (dedup case verified separately below).
      final gyms = List.generate(9, (i) => _gym('gym-$i'));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          nearbyLocationProvider.overrideWith((ref) => fake),
          nearbyGymsProvider(_bucket).overrideWith((ref) async => gyms),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: NearbyGymsList(uid: 'test-uid', currentGymId: null),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Only 8 of the 9 rows are visible initially (AD-4 cap).
      for (var i = 0; i < 8; i++) {
        expect(find.text('Gym gym-$i'), findsOneWidget);
      }
      expect(find.text('Gym gym-8'), findsNothing);
      expect(find.textContaining('a 0.0 km'), findsWidgets);
      expect(find.text('Ver más'), findsOneWidget);
    });

    testWidgets('dedup: current gym is absent from the nearby rows',
        (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      final gyms = [_gym('current-gym'), _gym('other-gym')];

      await tester.pumpWidget(ProviderScope(
        overrides: [
          nearbyLocationProvider.overrideWith((ref) => fake),
          nearbyGymsProvider(_bucket).overrideWith((ref) async => gyms),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: NearbyGymsList(
                uid: 'test-uid',
                currentGymId: 'current-gym',
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gym current-gym'), findsNothing);
      expect(find.text('Gym other-gym'), findsOneWidget);
    });

    testWidgets(
        '"Ver más" reveals already-fetched rows with zero additional '
        'provider calls', (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      var callCount = 0;
      final gyms = List.generate(9, (i) => _gym('gym-$i'));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          nearbyLocationProvider.overrideWith((ref) => fake),
          nearbyGymsProvider(_bucket).overrideWith((ref) async {
            callCount++;
            return gyms;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: NearbyGymsList(uid: 'test-uid', currentGymId: null),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gym gym-8'), findsNothing);
      expect(callCount, 1);

      await tester.ensureVisible(find.text('Ver más'));
      await tester.tap(find.text('Ver más'));
      await tester.pumpAndSettle();

      expect(find.text('Gym gym-8'), findsOneWidget);
      expect(callCount, 1); // no extra fetch — pure local toggle
    });
  });

  group('nearby tap selection (task 2.10)', () {
    testWidgets(
        'tapping a nearby row invokes select(uid, placeId) with no session '
        'token', (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      final mockResolveService = MockResolveGymPlaceService();
      when(() => mockResolveService.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          )).thenAnswer((_) async => const ResolveGymPlaceResult(
            gymId: 'gym-0',
            name: 'Gym gym-0',
            address: 'Address gym-0',
            source: 'google-places',
          ));

      await tester.pumpWidget(_wrap(overrides: [
        nearbyLocationProvider.overrideWith((ref) => fake),
        nearbyGymsProvider(_bucket)
            .overrideWith((ref) async => [_gym('gym-0')]),
        resolveGymPlaceServiceProvider.overrideWithValue(mockResolveService),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gym gym-0'));
      await tester.pumpAndSettle();

      verify(() => mockResolveService.call(
            placeId: 'gym-0',
            sessionToken: null,
          )).called(1);
    });
  });
}
