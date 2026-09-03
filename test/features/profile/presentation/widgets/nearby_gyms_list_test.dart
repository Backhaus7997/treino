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
import 'package:treino/features/profile_setup/presentation/widgets/gym_card.dart';
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
  String? currentGymId,
  String? selectedGymId,
  void Function(String gymId)? onGymSelected,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: NearbyGymsList(
              currentGymId: currentGymId,
              selectedGymId: selectedGymId,
              onGymSelected: onGymSelected,
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
        'data shows ALL fetched rows with "a X km" labels, current gym '
        'absent, no "Ver más" affordance (AD-13)', (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      // 14 gyms — the exact device-testing scenario (the user's real gym
      // ranked #14, previously buried behind the retired 8-row cap /
      // "Ver más" affordance). All must render without extra interaction.
      final gyms = List.generate(14, (i) => _gym('gym-$i'));

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
              child: NearbyGymsList(currentGymId: null),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // All 14 rows render — no cap, no "Ver más" gate.
      for (var i = 0; i < 14; i++) {
        expect(find.text('Gym gym-$i'), findsOneWidget);
      }
      expect(find.textContaining('a 0.0 km'), findsWidgets);
      expect(find.text('Ver más'), findsNothing);
    });

    testWidgets(
        'the full maxResultCount:20 fetch renders all 20 rows without an '
        'expand step (AD-13)', (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      final gyms = List.generate(20, (i) => _gym('gym-$i'));

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
              child: NearbyGymsList(currentGymId: null),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gym gym-19'), findsOneWidget);
      expect(find.text('Ver más'), findsNothing);
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
              child: NearbyGymsList(currentGymId: 'current-gym'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gym current-gym'), findsNothing);
      expect(find.text('Gym other-gym'), findsOneWidget);
    });

    testWidgets(
        'rendering every fetched row costs exactly one provider call — no '
        'extra fetch is triggered by rendering more rows (AD-13)',
        (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      var callCount = 0;
      final gyms = List.generate(14, (i) => _gym('gym-$i'));

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
              child: NearbyGymsList(currentGymId: null),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gym gym-13'), findsOneWidget);
      expect(callCount, 1);
    });
  });

  // Antes de #814 este grupo verificaba que el tap resolviera el Place y
  // escribiera `users/{uid}.gymId` en el acto. Eso ERA el bug: la selección
  // tiene que ser borrador y la escritura ocurrir recién en GUARDAR (ver
  // profile_gym_screen_test.dart para el camino completo hasta Firestore).
  group('nearby tap selection — draft-only (#814)', () {
    testWidgets('tapping a nearby row notifies onGymSelected with its placeId',
        (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);
      final selected = <String>[];

      await tester.pumpWidget(_wrap(
        overrides: [
          nearbyLocationProvider.overrideWith((ref) => fake),
          nearbyGymsProvider(_bucket)
              .overrideWith((ref) async => [_gym('gym-0')]),
        ],
        onGymSelected: selected.add,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gym gym-0'));
      await tester.pumpAndSettle();

      expect(selected, ['gym-0']);
    });

    testWidgets('tapping a nearby row NEVER resolves the Place',
        (tester) async {
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

      await tester.pumpWidget(_wrap(
        overrides: [
          nearbyLocationProvider.overrideWith((ref) => fake),
          nearbyGymsProvider(_bucket)
              .overrideWith((ref) async => [_gym('gym-0')]),
          resolveGymPlaceServiceProvider.overrideWithValue(mockResolveService),
        ],
        onGymSelected: (_) {},
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gym gym-0'));
      await tester.pumpAndSettle();

      // Place Details es facturable: que no salga en el tap no es sólo
      // correctitud de datos, también es plata.
      verifyNever(() => mockResolveService.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          ));
    });

    testWidgets(
        'the row matching selectedGymId renders as selected — el único '
        'feedback visible del tap ahora que no escribe', (tester) async {
      final fake = _FakeNearbyLocationNotifier(granted: true);

      await tester.pumpWidget(_wrap(
        overrides: [
          nearbyLocationProvider.overrideWith((ref) => fake),
          nearbyGymsProvider(_bucket)
              .overrideWith((ref) async => [_gym('gym-0'), _gym('gym-1')]),
        ],
        selectedGymId: 'gym-1',
      ));
      await tester.pumpAndSettle();

      GymCard cardFor(String name) => tester.widget<GymCard>(
            find.ancestor(
              of: find.text(name),
              matching: find.byType(GymCard),
            ),
          );

      expect(cardFor('Gym gym-1').selected, isTrue);
      expect(cardFor('Gym gym-0').selected, isFalse);
    });
  });
}
