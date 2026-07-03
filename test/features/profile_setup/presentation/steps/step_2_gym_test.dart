// Rewritten for gym-google-places Slice 3 (Phase 3): Step2Gym now wraps the
// shared GymSearchBox (single debounced Google Places search) — the prior
// version covered the retired two-step brand→branch picker (see git history).
// Mirrors profile_gym_screen_test.dart's mock/override conventions.
//
// Rewritten AGAIN for gym-selection-v2 Phase 3 (addendum, AD-12): typed
// search now runs via PlacesTextSearchService/placesTextSearchProvider
// instead of the retired PlacesAutocompleteService/gymSearchSessionTokenProvider.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/places_nearby_search_service.dart';
import 'package:treino/features/gyms/data/places_text_search_service.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/gyms/domain/gym_suggestion.dart';
import 'package:treino/features/gyms/domain/nearby_gym.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile_setup/application/profile_setup_notifier.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_draft.dart';
import 'package:treino/features/profile_setup/presentation/steps/step_2_gym.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Fakes / Mocks
// ---------------------------------------------------------------------------

/// Near-zero so widget tests don't have to pump the real 600ms debounce
/// window.
const _testDebounce = Duration(milliseconds: 1);

/// Fake notifier: mirrors [ProfileSetupNotifier.updateGymId] without touching
/// Firebase Auth / Firestore — this widget only exercises step-2 selection.
class _FakeProfileSetupNotifier extends ProfileSetupNotifier {
  @override
  ProfileSetupState build() =>
      const ProfileSetupState(draft: ProfileSetupDraft(), currentStep: 1);

  @override
  void updateGymId(String? value) =>
      state = state.copyWith(draft: state.draft.copyWith(gymId: value));
}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {
  @override
  String get uid => 'test-uid';
}

class MockPlacesTextSearchService extends Mock
    implements PlacesTextSearchService {}

class MockResolveGymPlaceService extends Mock
    implements ResolveGymPlaceService {}

class MockUserRepository extends Mock implements UserRepository {}

/// Call-counting fake — gym-selection-v2 Phase 2 task 2.3 regression guard.
/// Onboarding (`step_2_gym.dart`) must NEVER read `nearbyGymsProvider`,
/// which would invoke this and bill a `searchNearby` call mid-onboarding.
class _CountingNearbySearchService implements PlacesNearbySearchService {
  int callCount = 0;

  @override
  Future<List<NearbyGym>> search({
    required double latitude,
    required double longitude,
    int radiusMeters = PlacesNearbySearchService.defaultRadiusMeters,
    int maxResultCount = PlacesNearbySearchService.defaultMaxResultCount,
  }) async {
    callCount++;
    return const [];
  }
}

/// Call-counting fake — asserts `nearbyLocationProvider` is never read
/// (constructed) during onboarding either (task 2.3).
class _CountingNearbyLocationNotifier extends NearbyLocationNotifier {
  int checkSilentlyCallCount = 0;

  @override
  Future<void> checkSilently() async {
    checkSilentlyCallCount++;
    return super.checkSilently();
  }
}

Widget _buildStep({
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: [
      textSearchDebounceDurationProvider.overrideWithValue(_testDebounce),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: Step2Gym()),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockUser mockUser;
  late MockPlacesTextSearchService mockPlacesService;
  late MockResolveGymPlaceService mockResolveService;
  late MockUserRepository mockUserRepo;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockUser = MockUser();
    when(() => mockAuth.currentUser).thenReturn(mockUser);
    mockPlacesService = MockPlacesTextSearchService();
    mockResolveService = MockResolveGymPlaceService();
    mockUserRepo = MockUserRepository();
    when(() => mockUserRepo.update(any(), any())).thenAnswer((_) async {});
  });

  List<Override> baseOverrides() => [
        profileSetupNotifierProvider
            .overrideWith(_FakeProfileSetupNotifier.new),
        firebaseAuthProvider.overrideWithValue(mockAuth),
        placesTextSearchServiceProvider.overrideWithValue(mockPlacesService),
        resolveGymPlaceServiceProvider.overrideWithValue(mockResolveService),
        userRepositoryProvider.overrideWithValue(mockUserRepo),
        gymSearchLocationBiasProvider.overrideWith((ref) async => null),
      ];

  group('Step2Gym', () {
    testWidgets('shows the search box and kNoGymId option on first render',
        (tester) async {
      await tester.pumpWidget(_buildStep(overrides: baseOverrides()));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('OTRO GYM / SIN GYM'), findsOneWidget);
    });

    testWidgets(
        'typing shows debounced Text Search results without requesting '
        'location permission', (tester) async {
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

      await tester.pumpWidget(_buildStep(overrides: baseOverrides()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'qivox');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('QIVOX Villa Warcalde'), findsOneWidget);
      verify(() => mockPlacesService.search(
            textQuery: 'qivox',
            biasLatitude: null,
            biasLongitude: null,
          )).called(1);
    });

    testWidgets(
        'selecting a suggestion resolves it (no session token) and sets '
        "draft.gymId to the Place's id", (tester) async {
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

      await tester.pumpWidget(_buildStep(overrides: baseOverrides()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'qivox');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('QIVOX Villa Warcalde'));
      await tester.pumpAndSettle();

      verify(() => mockResolveService.call(
            placeId: 'ChIJ_1',
            sessionToken: null,
          )).called(1);
      verify(() => mockUserRepo.update('test-uid', {'gymId': 'ChIJ_1'}))
          .called(1);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Step2Gym)),
      );
      expect(
        container.read(profileSetupNotifierProvider).draft.gymId,
        'ChIJ_1',
      );
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

      await tester.pumpWidget(_buildStep(overrides: baseOverrides()));
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

    testWidgets('"no gym" option sets draft.gymId to kNoGymId without a search',
        (tester) async {
      await tester.pumpWidget(_buildStep(overrides: baseOverrides()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OTRO GYM / SIN GYM'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Step2Gym)),
      );
      expect(
        container.read(profileSetupNotifierProvider).draft.gymId,
        kNoGymId,
      );
      verifyNever(() => mockResolveService.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          ));
    });

    // gym-selection-v2 Phase 2 task 2.3 — onboarding isolation regression
    // guard (design AD-10 risk: "Breaking onboarding via the shared
    // widget"). Step2Gym constructs GymSearchBox WITHOUT emptyQueryContent
    // (verified by task 2.4), so it must never read nearbyGymsProvider or
    // nearbyLocationProvider — asserted here with call-counting fakes,
    // not just "existing tests still pass." Still holds after the Phase 3
    // typed-search backend swap (unrelated surface).
    testWidgets(
        'onboarding triggers zero nearbyGymsProvider/nearbyLocationProvider '
        'invocations', (tester) async {
      final countingNearbyService = _CountingNearbySearchService();
      final countingLocationNotifier = _CountingNearbyLocationNotifier();

      await tester.pumpWidget(_buildStep(
        overrides: [
          ...baseOverrides(),
          placesNearbySearchServiceProvider
              .overrideWithValue(countingNearbyService),
          nearbyLocationProvider
              .overrideWith((ref) => countingLocationNotifier),
        ],
      ));
      await tester.pumpAndSettle();

      // Interact with the widget the way a real onboarding session would —
      // type a query, clear it, tap the no-gym option — to prove these
      // reads stay at zero across the whole lifecycle, not just on mount.
      await tester.enterText(find.byType(TextField), 'qivox');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();

      expect(countingNearbyService.callCount, 0);
      expect(countingLocationNotifier.checkSilentlyCallCount, 0);
    });
  });
}
