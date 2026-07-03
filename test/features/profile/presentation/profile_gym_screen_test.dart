// Rewritten for gym-google-places Slice 3 (Phase 3): ProfileGymScreen now
// wraps the shared GymSearchBox (single debounced Google Places search) —
// SCENARIO-516/517 originally covered the retired two-step brand→branch
// picker (see git history for the prior version).
//
// Rewritten AGAIN for gym-selection-v2 Phase 3 (addendum, AD-12): typed
// search now runs via PlacesTextSearchService/placesTextSearchProvider
// instead of the retired PlacesAutocompleteService/gymSearchSessionTokenProvider.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/geohash.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/places_text_search_service.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';
import 'package:treino/features/gyms/domain/gym_suggestion.dart';
import 'package:treino/features/gyms/domain/nearby_gym.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/profile_gym_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUser extends Mock implements User {
  @override
  String get uid => 'test-uid';
}

class MockUserRepository extends Mock implements UserRepository {}

class MockPlacesTextSearchService extends Mock
    implements PlacesTextSearchService {}

class MockResolveGymPlaceService extends Mock
    implements ResolveGymPlaceService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _uid = 'test-uid';

/// Near-zero so widget tests don't have to pump the real 600ms debounce
/// window.
const _testDebounce = Duration(milliseconds: 1);

UserProfile _profile({String? gymId}) => UserProfile(
      uid: _uid,
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      gymId: gymId,
    );

Widget _buildScreen({
  required UserProfile profile,
  required MockUserRepository userRepo,
  required MockPlacesTextSearchService placesService,
  MockResolveGymPlaceService? resolveService,
  List<Override> extraOverrides = const [],
  // gym-selection-v2 CRITICAL-1 fix: lets a test push new profile
  // emissions (e.g. after a mocked write) to prove `userProfileProvider`
  // consumers (PinnedCurrentGym) re-render on the NEW value. Defaults to
  // a fixed single-emission stream, matching every other test's behavior.
  Stream<UserProfile>? profileStream,
}) {
  final mockUser = MockUser();

  final router = GoRouter(
    initialLocation: '/profile/gym',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PROFILE_SCREEN')),
        routes: [
          GoRoute(
            path: 'gym',
            builder: (_, __) => const Scaffold(body: ProfileGymScreen()),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
      userProfileProvider
          .overrideWith((_) => profileStream ?? Stream.value(profile)),
      userRepositoryProvider.overrideWithValue(userRepo),
      placesTextSearchServiceProvider.overrideWithValue(placesService),
      textSearchDebounceDurationProvider.overrideWithValue(_testDebounce),
      gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      if (resolveService != null)
        resolveGymPlaceServiceProvider.overrideWithValue(resolveService),
      // gym-selection-v2 Phase 2: NearbyGymsList is now the emptyQueryContent
      // for GymSearchBox. Default every pre-existing test to the
      // not-granted state (via setForTest seam — NEVER real Geolocator,
      // confirmed testWidgets hang gotcha) so it renders only the inline
      // affordance and never touches these tests' typed-search-focused
      // assertions. Composition-specific tests override this explicitly.
      nearbyLocationProvider.overrideWith(
        (ref) => NearbyLocationNotifier()..setDeniedForTest(),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

void main() {
  late MockUserRepository mockUserRepo;
  late MockPlacesTextSearchService mockPlacesService;
  late MockResolveGymPlaceService mockResolveService;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    mockUserRepo = MockUserRepository();
    mockPlacesService = MockPlacesTextSearchService();
    mockResolveService = MockResolveGymPlaceService();
    when(() => mockUserRepo.update(any(), any())).thenAnswer((_) async {});
  });

  group('ProfileGymScreen', () {
    testWidgets('typing shows debounced Text Search results', (tester) async {
      when(() => mockPlacesService.search(
            textQuery: any(named: 'textQuery'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async => const [
            GymSuggestion(
              placeId: 'ChIJ_1',
              primaryText: 'QIVOX Villa Warcalde',
              secondaryText: 'Some street 123',
            ),
          ]);

      await tester.pumpWidget(_buildScreen(
        profile: _profile(),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'qivox');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('QIVOX Villa Warcalde'), findsOneWidget);
    });

    testWidgets(
        'selecting a suggestion and confirming resolves (no session token) '
        '+ saves via selectGymActionProvider', (tester) async {
      when(() => mockPlacesService.search(
            textQuery: any(named: 'textQuery'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async => const [
            GymSuggestion(
              placeId: 'ChIJ_1',
              primaryText: 'QIVOX Villa Warcalde',
              secondaryText: 'Some street 123',
            ),
          ]);
      when(() => mockResolveService.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          )).thenAnswer((_) async => const ResolveGymPlaceResult(
            gymId: 'ChIJ_1',
            name: 'QIVOX Villa Warcalde',
            address: 'Some street 123',
            source: 'google-places',
          ));

      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: null),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
        resolveService: mockResolveService,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'qivox');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('QIVOX Villa Warcalde'));
      await tester.pump();

      await tester.tap(find.text('GUARDAR')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      verify(() => mockResolveService.call(
            placeId: 'ChIJ_1',
            sessionToken: null,
          )).called(1);
      verify(() => mockUserRepo.update(_uid, {'gymId': 'ChIJ_1'})).called(1);
    });

    testWidgets('error state shows retry that re-issues the search',
        (tester) async {
      var attempt = 0;
      when(() => mockPlacesService.search(
            textQuery: any(named: 'textQuery'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async {
        attempt++;
        if (attempt == 1) {
          throw const PlacesTextSearchError('network down');
        }
        return const [
          GymSuggestion(placeId: 'ChIJ_1', primaryText: 'QIVOX Villa Warcalde'),
        ];
      });

      await tester.pumpWidget(_buildScreen(
        profile: _profile(),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'qivox');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('QIVOX Villa Warcalde'), findsNothing);
      final retryFinder = find.text('Reintentar');
      expect(retryFinder, findsOneWidget);

      await tester.tap(retryFinder);
      await tester.pumpAndSettle();

      expect(find.text('QIVOX Villa Warcalde'), findsOneWidget);
    });

    testWidgets('"no gym" option remains selectable without a search',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: null),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      expect(find.text('OTRO GYM / SIN GYM'), findsOneWidget);
      await tester.tap(find.text('OTRO GYM / SIN GYM'));
      await tester.pump();

      await tester.tap(find.text('GUARDAR')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      verify(() => mockUserRepo.update(_uid, {'gymId': kNoGymId})).called(1);
      verifyNever(() => mockResolveService.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          ));
    });

    testWidgets(
        'save button is disabled when pending selection equals current '
        'gymId', (tester) async {
      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: null),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      // No selection made — pending stays equal to the lazily-initialized
      // current gymId (null): save disabled.
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'GUARDAR'), // i18n: Fase 6 Etapa 3
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('tapping back pops the screen', (tester) async {
      await tester.pumpWidget(_buildScreen(
        profile: _profile(),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      expect(find.text('GIMNASIO'), findsOneWidget);
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.text('PROFILE_SCREEN'), findsOneWidget);
    });
  });

  // gym-selection-v2 Phase 2 task 2.13 — composition cases per
  // spec gym-selection-screen.
  group('ProfileGymScreen composition (gym-selection-v2 Phase 2)', () {
    Gym gym(String id, String name) => Gym(
          id: id,
          name: name,
          address: 'Some address',
          lat: -34.5,
          lng: -58.4,
          geohash: 'abcde',
          source: GymSource.seed,
          createdAt: DateTime(2025),
        );

    testWidgets('pinned card shown at top when gymId resolved', (tester) async {
      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: 'gym-current'),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
        extraOverrides: [
          gymByIdProvider('gym-current')
              .overrideWith((ref) async => gym('gym-current', 'Current Gym')),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Current Gym'), findsOneWidget);
    });

    testWidgets('pinned card absent when gymId is null', (tester) async {
      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: null),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('pinned card absent when gymId is kNoGymId', (tester) async {
      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: kNoGymId),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
        'empty query shows nearby list, non-empty query shows Text Search '
        'results, clearing restores nearby list', (tester) async {
      final position = Position(
        latitude: -34.5,
        longitude: -58.4,
        timestamp: DateTime(2025),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      final bucket = geohash5(position.latitude, position.longitude);

      when(() => mockPlacesService.search(
            textQuery: any(named: 'textQuery'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async => const [
            GymSuggestion(
              placeId: 'ChIJ_1',
              primaryText: 'QIVOX Villa Warcalde',
            ),
          ]);

      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: null),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
        extraOverrides: [
          nearbyLocationProvider.overrideWith(
              (ref) => NearbyLocationNotifier()..setForTest(position)),
          nearbyGymsProvider(bucket).overrideWith(
            (ref) async => [
              const NearbyGym(
                placeId: 'nearby-1',
                name: 'Nearby Gym',
                address: 'Nearby address',
                lat: -34.5,
                lng: -58.4,
              ),
            ],
          ),
        ],
      ));
      await tester.pumpAndSettle();

      // Empty query: nearby list visible, no Text Search results.
      expect(find.text('Nearby Gym'), findsOneWidget);
      expect(find.text('QIVOX Villa Warcalde'), findsNothing);

      // Non-empty query: Text Search replaces nearby.
      await tester.enterText(find.byType(TextField), 'qivox');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('QIVOX Villa Warcalde'), findsOneWidget);
      expect(find.text('Nearby Gym'), findsNothing);

      // Clearing restores the nearby list.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('Nearby Gym'), findsOneWidget);
      expect(find.text('QIVOX Villa Warcalde'), findsNothing);
    });

    testWidgets(
        '"No tengo gimnasio" stays visible in both empty and non-empty '
        'query states', (tester) async {
      when(() => mockPlacesService.search(
            textQuery: any(named: 'textQuery'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async => const []);

      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: null),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      expect(find.text('OTRO GYM / SIN GYM'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'qivox');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('OTRO GYM / SIN GYM'), findsOneWidget);
    });

    testWidgets(
        'selecting a nearby gym replaces the active selection in the UI',
        (tester) async {
      final position = Position(
        latitude: -34.5,
        longitude: -58.4,
        timestamp: DateTime(2025),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      final bucket = geohash5(position.latitude, position.longitude);

      when(() => mockResolveService.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          )).thenAnswer((_) async => const ResolveGymPlaceResult(
            gymId: 'nearby-1',
            name: 'Nearby Gym',
            address: 'Nearby address',
            source: 'google-places',
          ));

      // gym-selection-v2 CRITICAL-1 fix: a controllable stream lets this
      // test re-emit the profile AFTER the mocked write completes, the
      // same way the real Firestore-backed `userProfileProvider` re-emits
      // in production. A fixed `Stream.value(...)` (as used everywhere
      // else in this file) can never prove the pinned card re-renders.
      final oldProfile = _profile(gymId: 'gym-current');
      final newProfile = oldProfile.copyWith(gymId: 'nearby-1');
      final profileController = StreamController<UserProfile>.broadcast();
      addTearDown(profileController.close);

      when(() => mockUserRepo.update('test-uid', {'gymId': 'nearby-1'}))
          .thenAnswer((_) async {
        profileController.add(newProfile);
      });

      await tester.pumpWidget(_buildScreen(
        profile: oldProfile,
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
        resolveService: mockResolveService,
        profileStream: profileController.stream,
        extraOverrides: [
          gymByIdProvider('gym-current')
              .overrideWith((ref) async => gym('gym-current', 'Current Gym')),
          gymByIdProvider('nearby-1')
              .overrideWith((ref) async => gym('nearby-1', 'Nearby Gym')),
          nearbyLocationProvider.overrideWith(
              (ref) => NearbyLocationNotifier()..setForTest(position)),
          nearbyGymsProvider(bucket).overrideWith(
            (ref) async => [
              const NearbyGym(
                placeId: 'nearby-1',
                name: 'Nearby Gym',
                address: 'Nearby address',
                lat: -34.5,
                lng: -58.4,
              ),
            ],
          ),
        ],
      ));
      profileController.add(oldProfile);
      await tester.pumpAndSettle();

      expect(find.text('Current Gym'), findsOneWidget);
      expect(find.text('Nearby Gym'), findsOneWidget);

      await tester.tap(find.text('Nearby Gym'));
      await tester.pumpAndSettle();

      verify(() => mockUserRepo.update('test-uid', {'gymId': 'nearby-1'}))
          .called(1);

      // The pinned card must now reflect the NEW gym — proving
      // `PinnedCurrentGym` re-renders from `userProfileProvider`'s
      // updated `currentGymId`, not just that the repo write happened.
      expect(find.text('Nearby Gym'), findsOneWidget);
      expect(find.text('Current Gym'), findsNothing);
    });
  });
}
