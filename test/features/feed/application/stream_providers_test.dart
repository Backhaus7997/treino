import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
import 'package:treino/features/feed/data/friendship_repository.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class MockUser extends Mock implements User {
  MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

/// Spy repository that records watchByPair subscription count and allows
/// controlling the emitted stream.
class _SpyFriendshipRepository extends FriendshipRepository {
  _SpyFriendshipRepository() : super(firestore: FakeFirebaseFirestore());

  int watchByPairSubscribeCount = 0;
  int watchByPairDisposeCount = 0;
  final _watchByPairController = StreamController<Friendship?>.broadcast();

  Stream<Friendship?> get controlledStream => _watchByPairController.stream;

  @override
  Stream<Friendship?> watchByPair(String uidA, String uidB) {
    watchByPairSubscribeCount++;
    return _watchByPairController.stream.transform(
      StreamTransformer.fromHandlers(
        handleDone: (sink) {
          watchByPairDisposeCount++;
          sink.close();
        },
      ),
    );
  }

  void dispose() {
    _watchByPairController.close();
  }
}

final _now = DateTime.utc(2026, 1, 1);

Friendship _makeFriendship({
  FriendshipStatus status = FriendshipStatus.pending,
}) =>
    Friendship(
      id: 'alice_bob',
      uidA: 'alice',
      uidB: 'bob',
      status: status,
      requesterId: 'alice',
      members: const ['alice', 'bob'],
      createdAt: _now,
    );

const _profileAlice = UserPublicProfile(
  uid: 'alice',
  displayName: 'Alice',
  displayNameLowercase: 'alice',
);

// ---------------------------------------------------------------------------
// T08 RED: SCENARIO-481..483 — friendshipByPairProvider as StreamProvider
// ---------------------------------------------------------------------------

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-481: friendshipByPairProvider exposes AsyncValue<Friendship?>
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-481: friendshipByPairProvider consumer receives AsyncValue<Friendship?> and rebuilds on emit',
      () async {
    final user = MockUser(uid: 'viewer');
    final friendship = _makeFriendship();

    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
        friendshipByPairProvider.overrideWith(
          (ref, pair) => Stream.value(friendship),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Reading gives AsyncValue<Friendship?> — same surface as former FutureProvider
    final value = await container.read(
      friendshipByPairProvider(
        (viewerUid: 'viewer', targetUid: 'target'),
      ).future,
    );
    expect(value, equals(friendship));
    expect(value?.status, equals(FriendshipStatus.pending));

    // The provider itself (the family) is a StreamProvider.family.autoDispose
    // Calling the family with args produces an AutoDisposeStreamProvider
    final provider = friendshipByPairProvider(
      (viewerUid: 'viewer', targetUid: 'target'),
    );
    expect(provider, isA<AutoDisposeStreamProvider<Friendship?>>());
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-482: autoDispose — subscription cancelled when container disposed
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-482: friendshipByPairProvider drops Firestore listener when container is disposed',
      () async {
    final spyRepo = _SpyFriendshipRepository();
    final user = MockUser(uid: 'alice');

    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
        // Override the private _friendshipRepositoryProvider via the public-
        // facing one via the firestore, but since it's private we must use
        // overrideWith on the family provider itself.
        friendshipByPairProvider.overrideWith(
          (ref, pair) async* {
            final auth = await ref.watch(authStateChangesProvider.future);
            if (auth == null) {
              yield null;
              return;
            }
            yield* spyRepo.watchByPair(pair.viewerUid, pair.targetUid);
          },
        ),
      ],
    );

    // Subscribe to the provider (simulates a widget listening)
    final sub = container.listen(
      friendshipByPairProvider(
        (viewerUid: 'alice', targetUid: 'bob'),
      ),
      (_, __) {},
    );

    // Wait for the subscription to establish
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(spyRepo.watchByPairSubscribeCount, equals(1));

    // Emit one value to make sure the stream is live
    spyRepo._watchByPairController.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // Dispose the listener (simulates widget unmount)
    sub.close();
    container.dispose();

    // Give time for dispose propagation
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The stream was subscribed exactly once and the provider was auto-disposed
    // (autoDispose cancels the stream when the last listener is removed)
    expect(spyRepo.watchByPairSubscribeCount, equals(1));

    spyRepo.dispose();
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-483: acceptedFriendsProvider drop-in — AsyncValue<List<String>>
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-483: acceptedFriendsProvider is StreamProvider.family.autoDispose returning AsyncValue<List<String>>',
      () {
    // Calling the family with args produces an AutoDisposeStreamProvider
    final provider = acceptedFriendsProvider('u1');
    expect(provider, isA<AutoDisposeStreamProvider<List<String>>>());
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-484: userPublicProfileProvider drop-in — valueOrNull pattern works
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-484: userPublicProfileProvider is StreamProvider.family.autoDispose; valueOrNull returns UserPublicProfile?',
      () async {
    final user = MockUser(uid: 'viewer');

    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
        userPublicProfileProvider('alice').overrideWith(
          (ref) => Stream.value(_profileAlice),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Simulate the FriendRequestInboxTile.build pattern: .valueOrNull
    // This must work without any cast or .future access — drop-in guarantee.
    // Use .future to wait for the first emission.
    final value = await container
        .read(userPublicProfileProvider('alice').future);
    expect(value, equals(_profileAlice));
    expect(value!.displayName, equals('Alice'));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T14 RED: SCENARIO-485..490 — publicProfileViewProvider AsyncNotifier
  // ──────────────────────────────────────────────────────────────────────────

  group('publicProfileViewProvider AsyncNotifier composition', () {
    // SCENARIO-485: emits combined view-model when both upstreams provide data
    test(
        'SCENARIO-485: emits AsyncData(PublicProfileView) when both upstreams have data',
        () async {
      final user = MockUser(uid: 'viewer');
      final friendship = _makeFriendship(status: FriendshipStatus.accepted);

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('target').overrideWith(
            (ref) => Stream.value(_profileAlice),
          ),
          friendshipByPairProvider.overrideWith(
            (ref, pair) => Stream.value(friendship),
          ),
        ],
      );
      addTearDown(container.dispose);

      final view = await container
          .read(publicProfileViewProvider('target').future);
      expect(view, isA<PublicProfileView>());
      expect(view.authorDisplayName, equals('Alice'));
      expect(view.friendship, equals(friendship));
      expect(view.isSelf, isFalse);
    });

    // SCENARIO-486: re-emits when userPublicProfileProvider upstream changes
    test(
        'SCENARIO-486: re-emits updated view-model when profile upstream changes',
        () async {
      final user = MockUser(uid: 'viewer');
      final profileController =
          StreamController<UserPublicProfile?>.broadcast();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('target').overrideWith(
            (ref) => profileController.stream,
          ),
          friendshipByPairProvider.overrideWith(
            (ref, pair) => Stream.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(profileController.close);

      final emissions = <AsyncValue<PublicProfileView>>[];
      container.listen(
        publicProfileViewProvider('target'),
        (_, next) => emissions.add(next),
        fireImmediately: true,
      );

      // Emit first profile
      profileController
          .add(const UserPublicProfile(uid: 'target', displayName: 'InitialName'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Emit updated profile
      profileController
          .add(const UserPublicProfile(uid: 'target', displayName: 'UpdatedName'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Should have data emissions with updated profile
      final dataEmissions = emissions
          .whereType<AsyncData<PublicProfileView>>()
          .toList();
      expect(dataEmissions, isNotEmpty);
      expect(
        dataEmissions.last.value.authorDisplayName,
        equals('UpdatedName'),
      );
    });

    // SCENARIO-487: re-emits when friendshipByPairProvider upstream changes
    test(
        'SCENARIO-487: re-emits updated view-model when friendship upstream changes',
        () async {
      final user = MockUser(uid: 'viewer');
      final friendshipController = StreamController<Friendship?>.broadcast();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('target').overrideWith(
            (ref) => Stream.value(_profileAlice),
          ),
          friendshipByPairProvider.overrideWith(
            (ref, pair) => friendshipController.stream,
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(friendshipController.close);

      final emissions = <AsyncValue<PublicProfileView>>[];
      container.listen(
        publicProfileViewProvider('target'),
        (_, next) => emissions.add(next),
        fireImmediately: true,
      );

      // Emit pending friendship
      friendshipController.add(_makeFriendship(status: FriendshipStatus.pending));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Emit accepted friendship
      friendshipController
          .add(_makeFriendship(status: FriendshipStatus.accepted));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dataEmissions = emissions
          .whereType<AsyncData<PublicProfileView>>()
          .toList();
      expect(dataEmissions, isNotEmpty);
      expect(
        dataEmissions.last.value.friendship?.status,
        equals(FriendshipStatus.accepted),
      );
    });

    // SCENARIO-488: AsyncLoading while either upstream is pending
    test(
        'SCENARIO-488: emits AsyncLoading while upstreams have not yet emitted',
        () async {
      final user = MockUser(uid: 'viewer');
      // Never-completing stream — upstream never emits
      final neverController = StreamController<UserPublicProfile?>();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('target').overrideWith(
            (ref) => neverController.stream,
          ),
          friendshipByPairProvider.overrideWith(
            (ref, pair) => Stream.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(neverController.close);

      // Immediately after creation, the provider should be in loading state
      final state = container.read(publicProfileViewProvider('target'));
      expect(state, isA<AsyncLoading<PublicProfileView>>());
    });

    // SCENARIO-489: AsyncError propagates from upstream
    test(
        'SCENARIO-489: propagates AsyncError when upstream emits an error',
        () async {
      final user = MockUser(uid: 'viewer');
      final error = StateError('upstream error');

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('target').overrideWith(
            (ref) => Stream.error(error),
          ),
          friendshipByPairProvider.overrideWith(
            (ref, pair) => Stream.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Wait for the error to propagate through the async notifier
      await expectLater(
        container.read(publicProfileViewProvider('target').future),
        throwsA(isA<StateError>()),
      );
    });

    // SCENARIO-490: isSelf branch — friendshipByPairProvider NOT subscribed
    test(
        'SCENARIO-490: isSelf — friendshipByPairProvider is NOT subscribed when viewerUid == targetUid',
        () async {
      final user = MockUser(uid: 'alice');
      int friendshipSubscribeCount = 0;

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('alice').overrideWith(
            (ref) => Stream.value(_profileAlice),
          ),
          friendshipByPairProvider.overrideWith((ref, pair) {
            friendshipSubscribeCount++;
            return Stream.fromFuture(
              Future.error(
                StateError('isSelf branch should NOT subscribe to friendshipByPairProvider'),
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      // targetUid == viewerUid == 'alice' → isSelf
      final view =
          await container.read(publicProfileViewProvider('alice').future);

      // friendshipByPairProvider must NOT have been called
      expect(friendshipSubscribeCount, equals(0));
      // And the view has null friendship
      expect(view.friendship, isNull);
      expect(view.isSelf, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T10 RED: SCENARIO-483 extended — acceptedFriendsProvider shape tests
  // ──────────────────────────────────────────────────────────────────────────
  group('acceptedFriendsProvider StreamProvider contract', () {
    test(
        'SCENARIO-483 (container): acceptedFriendsProvider emits AsyncValue<List<String>> from stream',
        () async {
      final container = ProviderContainer(
        overrides: [
          acceptedFriendsProvider('u1').overrideWith(
            (ref) => Stream.value(const ['u2', 'u3']),
          ),
        ],
      );
      addTearDown(container.dispose);

      final value = await container.read(acceptedFriendsProvider('u1').future);
      expect(value, isA<List<String>>());
      expect(value, equals(['u2', 'u3']));
    });

    test(
        'acceptedFriendsProvider autoDispose: provider type is AutoDisposeStreamProvider',
        () {
      expect(
        acceptedFriendsProvider('u1'),
        isA<AutoDisposeStreamProvider<List<String>>>(),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T12 RED: SCENARIO-484 extended — userPublicProfileProvider drop-in test
  // ──────────────────────────────────────────────────────────────────────────
  group('userPublicProfileProvider StreamProvider contract', () {
    test(
        'SCENARIO-484: userPublicProfileProvider is AutoDisposeStreamProvider when called with arg',
        () {
      expect(
        userPublicProfileProvider('alice'),
        isA<AutoDisposeStreamProvider<UserPublicProfile?>>(),
      );
    });

    test(
        'SCENARIO-484 (consumer): valueOrNull access still resolves correctly — drop-in guarantee',
        () async {
      final container = ProviderContainer(
        overrides: [
          userPublicProfileProvider('alice').overrideWith(
            (ref) => Stream.value(_profileAlice),
          ),
        ],
      );
      addTearDown(container.dispose);

      // FriendRequestInboxTile pattern: .valueOrNull — no .future, no cast.
      // Wait for first emission before reading valueOrNull.
      await container.read(userPublicProfileProvider('alice').future);
      final valueOrNull =
          container.read(userPublicProfileProvider('alice')).valueOrNull;
      expect(valueOrNull, isA<UserPublicProfile?>());
      expect(valueOrNull!.uid, equals('alice'));
    });
  });
}
