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
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/places_autocomplete_service.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/gyms/domain/gym_suggestion.dart';
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
}
