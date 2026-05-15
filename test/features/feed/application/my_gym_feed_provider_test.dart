import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

Post _makePost({
  String id = 'p1',
  String authorUid = 'u1',
  String text = 'Hola mundo',
  PostPrivacy privacy = PostPrivacy.gym,
}) =>
    Post(
      id: id,
      authorUid: authorUid,
      authorDisplayName: 'Tincho',
      authorAvatarUrl: null,
      authorGymId: 'gym-abc',
      text: text,
      routineTag: null,
      privacy: privacy,
      createdAt: DateTime.utc(2026, 5, 14, 10, 0, 0),
    );

UserProfile _makeProfile({String? gymId}) => UserProfile(
      uid: 'u1',
      email: 'tincho@test.com',
      displayName: 'Tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      gymId: gymId,
    );

void main() {
  group('myGymFeedProvider', () {
    // SCENARIO-190: profile with gymId null returns null
    test(
        'SCENARIO-190: profile with gymId null returns null (no-gym branch)',
        () async {
      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(gymId: null)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(myGymFeedProvider.future);
      expect(result, isNull);
    });

    // SCENARIO-191: profile with gymId non-null returns delegated list
    test(
        'SCENARIO-191: profile with gymId non-null returns delegated post list',
        () async {
      final posts = [_makePost(id: 'p1'), _makePost(id: 'p2')];

      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(gymId: 'gym-abc')),
          ),
          feedForGymProvider('gym-abc').overrideWith(
            (ref) => Future.value(posts),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(myGymFeedProvider.future);
      expect(result, equals(posts));
    });

    // SCENARIO-192: profile loading propagates AsyncLoading
    test(
        'SCENARIO-192: AsyncLoading propagated while userProfileProvider loads',
        () {
      final container = ProviderContainer(
        overrides: [
          // Stream.empty() never emits → userProfileProvider stays loading
          userProfileProvider.overrideWith(
            (ref) => const Stream<UserProfile?>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Must be AsyncLoading before any emission
      final state = container.read(myGymFeedProvider);
      expect(state, isA<AsyncLoading<List<Post>?>>());
    });

    // SCENARIO-193: auth null treated as no-data (no error surfaced)
    test(
        'SCENARIO-193: auth null (signed-out) resolves null without error',
        () async {
      final container = ProviderContainer(
        overrides: [
          // Signed out → userProfileProvider emits null
          userProfileProvider.overrideWith(
            (ref) => Stream<UserProfile?>.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(myGymFeedProvider.future);
      expect(result, isNull);
    });

    // SCENARIO-194: upstream error from feedForGymProvider is propagated
    test(
        'SCENARIO-194: error from feedForGymProvider propagated as AsyncError',
        () async {
      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(gymId: 'gym-abc')),
          ),
          feedForGymProvider('gym-abc').overrideWith(
            (ref) => Future<List<Post>>.error(
              Exception('network error'),
              StackTrace.empty,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Expect the future to throw, confirming an error was propagated
      await expectLater(
        container.read(myGymFeedProvider.future),
        throwsA(isA<Exception>()),
      );
    });
  });
}
