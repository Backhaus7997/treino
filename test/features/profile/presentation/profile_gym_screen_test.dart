// Rewritten for gym-google-places Slice 3 (Phase 3): ProfileGymScreen now
// wraps the shared GymSearchBox (single debounced Google Places search) —
// SCENARIO-516/517 originally covered the retired two-step brand→branch
// picker (see git history for the prior version). This version drives the
// screen end-to-end via placesSuggestionsProvider/selectGymActionProvider
// mocks, mirroring gym_search_box_test.dart's widget-test conventions.
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
import 'package:treino/features/gyms/data/places_autocomplete_service.dart';
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

class MockPlacesAutocompleteService extends Mock
    implements PlacesAutocompleteService {}

class MockResolveGymPlaceService extends Mock
    implements ResolveGymPlaceService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _uid = 'test-uid';

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
  required MockPlacesAutocompleteService placesService,
  MockResolveGymPlaceService? resolveService,
  List<Override> extraOverrides = const [],
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
      userProfileProvider.overrideWith((_) => Stream.value(profile)),
      userRepositoryProvider.overrideWithValue(userRepo),
      placesAutocompleteServiceProvider.overrideWithValue(placesService),
      gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
      gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      if (resolveService != null)
        resolveGymPlaceServiceProvider.overrideWithValue(resolveService),
      // gym-selection-v2 Phase 2: NearbyGymsList is now the emptyQueryContent
      // for GymSearchBox. Default every pre-existing test to the
      // not-granted state (via setForTest seam — NEVER real Geolocator,
      // confirmed testWidgets hang gotcha) so it renders only the inline
      // affordance and never touches these tests' Autocomplete-focused
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
  late MockPlacesAutocompleteService mockPlacesService;
  late MockResolveGymPlaceService mockResolveService;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    mockUserRepo = MockUserRepository();
    mockPlacesService = MockPlacesAutocompleteService();
    mockResolveService = MockResolveGymPlaceService();
    when(() => mockUserRepo.update(any(), any())).thenAnswer((_) async {});
  });

  group('ProfileGymScreen', () {
    testWidgets('typing shows debounced Autocomplete suggestions',
        (tester) async {
      when(() => mockPlacesService.search(
            query: any(named: 'query'),
            sessionToken: any(named: 'sessionToken'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async => const [
            GymSuggestion(
              placeId: 'ChIJ_1',
              primaryText: 'SportClub Belgrano',
              secondaryText: 'Cabildo 1789',
            ),
          ]);

      await tester.pumpWidget(_buildScreen(
        profile: _profile(),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'sport');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('SportClub Belgrano'), findsOneWidget);
    });

    testWidgets(
        'selecting a suggestion and confirming resolves + saves via '
        'selectGymActionProvider', (tester) async {
      when(() => mockPlacesService.search(
            query: any(named: 'query'),
            sessionToken: any(named: 'sessionToken'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async => const [
            GymSuggestion(
              placeId: 'ChIJ_1',
              primaryText: 'SportClub Belgrano',
              secondaryText: 'Cabildo 1789',
            ),
          ]);
      when(() => mockResolveService.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          )).thenAnswer((_) async => const ResolveGymPlaceResult(
            gymId: 'ChIJ_1',
            name: 'SportClub Belgrano',
            address: 'Cabildo 1789',
            source: 'google-places',
          ));

      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: null),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
        resolveService: mockResolveService,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'sport');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await tester.tap(find.text('SportClub Belgrano'));
      await tester.pump();

      await tester.tap(find.text('GUARDAR')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      verify(() => mockResolveService.call(
            placeId: 'ChIJ_1',
            sessionToken: 'tok-fixed',
          )).called(1);
      verify(() => mockUserRepo.update(_uid, {'gymId': 'ChIJ_1'})).called(1);
    });

    testWidgets('error state shows retry that re-issues the search',
        (tester) async {
      var attempt = 0;
      when(() => mockPlacesService.search(
            query: any(named: 'query'),
            sessionToken: any(named: 'sessionToken'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async {
        attempt++;
        if (attempt == 1) {
          throw const PlacesAutocompleteError('network down');
        }
        return const [
          GymSuggestion(placeId: 'ChIJ_1', primaryText: 'SportClub Belgrano'),
        ];
      });

      await tester.pumpWidget(_buildScreen(
        profile: _profile(),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'sport');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('SportClub Belgrano'), findsNothing);
      final retryFinder = find.text('Reintentar');
      expect(retryFinder, findsOneWidget);

      await tester.tap(retryFinder);
      await tester.pumpAndSettle();

      expect(find.text('SportClub Belgrano'), findsOneWidget);
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
        'empty query shows nearby list, non-empty query shows Autocomplete, '
        'clearing restores nearby list', (tester) async {
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
            query: any(named: 'query'),
            sessionToken: any(named: 'sessionToken'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenAnswer((_) async => const [
            GymSuggestion(
              placeId: 'ChIJ_1',
              primaryText: 'SportClub Belgrano',
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

      // Empty query: nearby list visible, no Autocomplete results.
      expect(find.text('Nearby Gym'), findsOneWidget);
      expect(find.text('SportClub Belgrano'), findsNothing);

      // Non-empty query: Autocomplete replaces nearby.
      await tester.enterText(find.byType(TextField), 'sport');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('SportClub Belgrano'), findsOneWidget);
      expect(find.text('Nearby Gym'), findsNothing);

      // Clearing restores the nearby list.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Nearby Gym'), findsOneWidget);
      expect(find.text('SportClub Belgrano'), findsNothing);
    });

    testWidgets(
        '"No tengo gimnasio" stays visible in both empty and non-empty '
        'query states', (tester) async {
      when(() => mockPlacesService.search(
            query: any(named: 'query'),
            sessionToken: any(named: 'sessionToken'),
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

      await tester.enterText(find.byType(TextField), 'sport');
      await tester.pump(const Duration(milliseconds: 300));
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

      await tester.pumpWidget(_buildScreen(
        profile: _profile(gymId: 'gym-current'),
        userRepo: mockUserRepo,
        placesService: mockPlacesService,
        resolveService: mockResolveService,
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
      await tester.pumpAndSettle();

      expect(find.text('Current Gym'), findsOneWidget);

      await tester.tap(find.text('Nearby Gym'));
      await tester.pumpAndSettle();

      verify(() => mockUserRepo.update('test-uid', {'gymId': 'nearby-1'}))
          .called(1);
    });
  });
}
