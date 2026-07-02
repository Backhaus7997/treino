// T2.12 RED — gym-google-places Phase 2.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/places_autocomplete_service.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/gyms/domain/gym_suggestion.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';

class MockPlacesAutocompleteService extends Mock
    implements PlacesAutocompleteService {}

class MockResolveGymPlaceService extends Mock
    implements ResolveGymPlaceService {}

class MockUserRepository extends Mock implements UserRepository {}

void main() {
  group('placesSuggestionsProvider', () {
    test('empty query returns [] without calling the service', () async {
      final mockService = MockPlacesAutocompleteService();
      final container = ProviderContainer(
        overrides: [
          placesAutocompleteServiceProvider.overrideWithValue(mockService),
          gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(placesSuggestionsProvider('').future);

      expect(result, isEmpty);
      verifyNever(() => mockService.search(
            query: any(named: 'query'),
            sessionToken: any(named: 'sessionToken'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          ));
    });

    test('non-empty query delegates to the service with the session token',
        () async {
      final mockService = MockPlacesAutocompleteService();
      when(() => mockService.search(
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

      final container = ProviderContainer(
        overrides: [
          placesAutocompleteServiceProvider.overrideWithValue(mockService),
          gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        ],
      );
      addTearDown(container.dispose);

      final result =
          await container.read(placesSuggestionsProvider('sport').future);

      expect(result, hasLength(1));
      expect(result.single.placeId, 'ChIJ_1');
      verify(() => mockService.search(
            query: 'sport',
            sessionToken: 'tok-fixed',
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).called(1);
    });

    test('propagates service errors as AsyncError', () async {
      final mockService = MockPlacesAutocompleteService();
      when(() => mockService.search(
            query: any(named: 'query'),
            sessionToken: any(named: 'sessionToken'),
            biasLatitude: any(named: 'biasLatitude'),
            biasLongitude: any(named: 'biasLongitude'),
          )).thenThrow(Exception('boom'));

      final container = ProviderContainer(
        overrides: [
          placesAutocompleteServiceProvider.overrideWithValue(mockService),
          gymSearchSessionTokenProvider.overrideWith((ref) => 'tok-fixed'),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(placesSuggestionsProvider('sport').future),
        throwsException,
      );
    });
  });

  group('selectGymActionProvider', () {
    late MockResolveGymPlaceService mockResolve;
    late MockUserRepository mockUserRepo;

    setUpAll(() {
      registerFallbackValue(<String, Object?>{});
    });

    setUp(() {
      mockResolve = MockResolveGymPlaceService();
      mockUserRepo = MockUserRepository();
    });

    ProviderContainer buildContainer({String sessionToken = 'tok-fixed'}) =>
        ProviderContainer(
          overrides: [
            resolveGymPlaceServiceProvider.overrideWithValue(mockResolve),
            userRepositoryProvider.overrideWithValue(mockUserRepo),
            gymSearchSessionTokenProvider.overrideWith((ref) => sessionToken),
          ],
        );

    test(
        'resolves the place, updates the profile with gymId, and resets the '
        'session token', () async {
      when(() => mockResolve.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          )).thenAnswer((_) async => const ResolveGymPlaceResult(
            gymId: 'ChIJ_1',
            name: 'SportClub Belgrano',
            address: 'Cabildo 1789',
            source: 'google-places',
          ));
      when(() => mockUserRepo.update(any(), any())).thenAnswer((_) async {});

      final container = buildContainer();
      addTearDown(container.dispose);

      final tokenBefore = container.read(gymSearchSessionTokenProvider);

      await container
          .read(selectGymActionProvider.notifier)
          .select(uid: 'uid-1', placeId: 'ChIJ_1');

      verify(() => mockResolve.call(
            placeId: 'ChIJ_1',
            sessionToken: tokenBefore,
          )).called(1);
      verify(() => mockUserRepo.update('uid-1', {'gymId': 'ChIJ_1'})).called(1);

      final state = container.read(selectGymActionProvider);
      expect(state.hasValue, isTrue);
      expect(state.value?.gymId, 'ChIJ_1');
    });

    test('exposes AsyncLoading while resolving', () async {
      when(() => mockResolve.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          )).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return const ResolveGymPlaceResult(
          gymId: 'ChIJ_1',
          name: 'SportClub Belgrano',
          address: null,
          source: 'google-places',
        );
      });
      when(() => mockUserRepo.update(any(), any())).thenAnswer((_) async {});

      final container = buildContainer();
      addTearDown(container.dispose);

      final future = container
          .read(selectGymActionProvider.notifier)
          .select(uid: 'uid-1', placeId: 'ChIJ_1');

      expect(container.read(selectGymActionProvider).isLoading, isTrue);
      await future;
    });

    test('exposes AsyncError when resolve fails, does not call update',
        () async {
      when(() => mockResolve.call(
            placeId: any(named: 'placeId'),
            sessionToken: any(named: 'sessionToken'),
          )).thenThrow(const ResolveGymPlaceFailure$Server(
        code: 'invalid-argument',
        message: 'bad placeId',
      ));

      final container = buildContainer();
      addTearDown(container.dispose);

      await container
          .read(selectGymActionProvider.notifier)
          .select(uid: 'uid-1', placeId: 'bad');

      final state = container.read(selectGymActionProvider);
      expect(state.hasError, isTrue);
      verifyNever(() => mockUserRepo.update(any(), any()));
    });
  });
}
