import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/feed/application/search_users_provider.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUserPublicProfileRepository extends Mock
    implements UserPublicProfileRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UserPublicProfile _fakeProfile({
  required String uid,
  required String displayName,
  String? gymId,
}) =>
    UserPublicProfile(
      uid: uid,
      displayName: displayName,
      displayNameLowercase: displayName.toLowerCase(),
      gymId: gymId,
    );

ProviderContainer _makeContainer(
    MockUserPublicProfileRepository mockRepo) {
  return ProviderContainer(
    overrides: [
      userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
    ],
  );
}

void main() {
  late MockUserPublicProfileRepository mockRepo;

  setUp(() {
    mockRepo = MockUserPublicProfileRepository();
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-275: Provider delegates to repository
  // ---------------------------------------------------------------------------
  group('searchUsersProvider — delegates to repository', () {
    test(
        'SCENARIO-275: query of 2+ chars calls '
        'UserPublicProfileRepository.searchByDisplayName and returns result',
        () async {
      final profiles = [
        _fakeProfile(uid: 'u1', displayName: 'Martin'),
      ];
      when(() => mockRepo.searchByDisplayName('ma'))
          .thenAnswer((_) async => profiles);

      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final result =
          await container.read(searchUsersProvider('ma').future);

      expect(result, equals(profiles));
      verify(() => mockRepo.searchByDisplayName('ma')).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-276: blank query → empty, no repo call
  // ---------------------------------------------------------------------------
  group('searchUsersProvider — blank query guard', () {
    test(
        'SCENARIO-276: whitespace-only query returns empty list without '
        'calling repository',
        () async {
      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final result =
          await container.read(searchUsersProvider('  ').future);

      expect(result, isEmpty);
      verifyNever(() => mockRepo.searchByDisplayName(any()));
    });

    test('empty string returns empty without calling repository', () async {
      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final result =
          await container.read(searchUsersProvider('').future);

      expect(result, isEmpty);
      verifyNever(() => mockRepo.searchByDisplayName(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-277: 1-char query → empty, no repo call
  // ---------------------------------------------------------------------------
  group('searchUsersProvider — 2-char minimum gate', () {
    test(
        'SCENARIO-277: single-character query returns empty list without '
        'issuing a Firestore call',
        () async {
      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final result =
          await container.read(searchUsersProvider('m').future);

      expect(result, isEmpty);
      verifyNever(() => mockRepo.searchByDisplayName(any()));
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-278: Provider is keyed on lowercase query
  // ---------------------------------------------------------------------------
  group('searchUsersProvider — normalization / family key', () {
    test(
        'SCENARIO-278: uppercase query is lowercased before repository call; '
        '"MAR" and "mar" produce the same lowercased call',
        () async {
      when(() => mockRepo.searchByDisplayName('mar'))
          .thenAnswer((_) async => []);

      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      // Provider normalizes 'MAR' → 'mar' internally
      await container.read(searchUsersProvider('MAR').future);

      verify(() => mockRepo.searchByDisplayName('mar')).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-279: no matches → empty list
  // ---------------------------------------------------------------------------
  group('searchUsersProvider — empty results', () {
    test(
        'SCENARIO-279: repository returns empty list when no profiles match '
        'and provider returns it as-is',
        () async {
      when(() => mockRepo.searchByDisplayName('xyz123'))
          .thenAnswer((_) async => []);

      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final result =
          await container.read(searchUsersProvider('xyz123').future);

      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-280: repository error → AsyncError
  // ---------------------------------------------------------------------------
  group('searchUsersProvider — error propagation', () {
    test(
        'SCENARIO-280: repository error surfaces as AsyncError in the provider',
        () async {
      when(() => mockRepo.searchByDisplayName(any()))
          .thenThrow(Exception('network error'));

      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      expect(
        () => container.read(searchUsersProvider('fail').future),
        throwsA(isA<Exception>()),
      );
    });
  });
}
