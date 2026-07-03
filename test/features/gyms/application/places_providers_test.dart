// T2.12 RED — gym-google-places Phase 2.
// Plan B REWORK: selectGymActionProvider's external behavior (resolve then
// update the profile gymId) is unchanged — only ResolveGymPlaceService is
// mocked as an interface, so this file needed no structural rewrite beyond
// matching ResolveGymPlaceFailure$Server's new (client-side) constructor
// shape. See resolve_gym_place_service_test.dart for the client-side
// resolve logic itself.
//
// Rewritten for gym-selection-v2 Phase 3 (addendum, AD-12): the
// `placesSuggestionsProvider` group is REMOVED — that provider (and
// PlacesAutocompleteService/gymSearchSessionTokenProvider it depended on)
// is deleted. Typed-search cost-gating/debounce/cache coverage now lives in
// `places_text_search_provider_test.dart`. `selectGymActionProvider` no
// longer reads a session token at all — every selection resolves with
// `sessionToken: null` (AD-12: Text Search has no session concept, and the
// nearby list already had none since AD-9).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';

class MockResolveGymPlaceService extends Mock
    implements ResolveGymPlaceService {}

class MockUserRepository extends Mock implements UserRepository {}

void main() {
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

    ProviderContainer buildContainer() => ProviderContainer(
          overrides: [
            resolveGymPlaceServiceProvider.overrideWithValue(mockResolve),
            userRepositoryProvider.overrideWithValue(mockUserRepo),
          ],
        );

    test(
        'resolves the place with no session token and updates the profile '
        'with gymId', () async {
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

      await container
          .read(selectGymActionProvider.notifier)
          .select(uid: 'uid-1', placeId: 'ChIJ_1');

      verify(() => mockResolve.call(
            placeId: 'ChIJ_1',
            sessionToken: null,
          )).called(1);
      verify(() => mockUserRepo.update('uid-1', {'gymId': 'ChIJ_1'})).called(1);

      final state = container.read(selectGymActionProvider);
      expect(state.hasValue, isTrue);
      expect(state.value?.gymId, 'ChIJ_1');
    });

    test(
        'passing useSessionToken: true does not change the resolved '
        'sessionToken — Text Search/nearby have no session concept (AD-12)',
        () async {
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

      await container.read(selectGymActionProvider.notifier).select(
            uid: 'uid-1',
            placeId: 'ChIJ_1',
            useSessionToken: true,
          );

      verify(() => mockResolve.call(
            placeId: 'ChIJ_1',
            sessionToken: null,
          )).called(1);
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
        'bad placeId',
        statusCode: 500,
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
