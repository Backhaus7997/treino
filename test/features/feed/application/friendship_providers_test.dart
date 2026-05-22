import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/data/friendship_repository.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _FakeFriendshipRepository extends FriendshipRepository {
  _FakeFriendshipRepository({required Stream<List<Friendship>> stream})
      : _stream = stream,
        super(firestore: FakeFirebaseFirestore());

  final Stream<List<Friendship>> _stream;

  @override
  Stream<List<Friendship>> watchPendingRequestsFor(String uid) => _stream;
}

final _now = DateTime.utc(2026, 1, 1);

Friendship _makeFriendship(String id, String requesterId) => Friendship(
      id: id,
      uidA: 'alice',
      uidB: requesterId,
      status: FriendshipStatus.pending,
      requesterId: requesterId,
      members: ['alice', requesterId],
      createdAt: _now,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // SCENARIO-454: pendingRequestsStreamProvider emits AsyncData([]) from
  // empty repo stream.
  test(
      'SCENARIO-454: pendingRequestsStreamProvider emits AsyncData([]) when repo stream emits []',
      () async {
    final controller = StreamController<List<Friendship>>();

    final container = ProviderContainer(
      overrides: [
        friendshipRepositoryProvider.overrideWithValue(
          _FakeFriendshipRepository(stream: controller.stream),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    // Read the provider — initially AsyncLoading
    final sub = container.listen(
      pendingRequestsStreamProvider('alice'),
      (_, __) {},
    );

    // Emit an empty list
    controller.add([]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final state = container.read(pendingRequestsStreamProvider('alice'));
    expect(state, isA<AsyncData<List<Friendship>>>());
    expect(state.value, isEmpty);

    sub.close();
  });

  // SCENARIO-455: pendingRequestCountProvider returns 0 when upstream is AsyncLoading
  test(
      'SCENARIO-455: pendingRequestCountProvider returns 0 when stream is AsyncLoading',
      () async {
    final controller = StreamController<List<Friendship>>();

    final container = ProviderContainer(
      overrides: [
        friendshipRepositoryProvider.overrideWithValue(
          _FakeFriendshipRepository(stream: controller.stream),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(controller.close);

    // Don't emit anything — stream provider stays in AsyncLoading
    final count = container.read(pendingRequestCountProvider('alice'));
    expect(count, equals(0));
  });

  // SCENARIO-456: pendingRequestCountProvider returns 3 when upstream emits 3 items
  test(
      'SCENARIO-456: pendingRequestCountProvider returns 3 when upstream emits AsyncData([F1,F2,F3])',
      () async {
    final f1 = _makeFriendship('alice_bob', 'bob');
    final f2 = _makeFriendship('alice_charlie', 'charlie');
    final f3 = _makeFriendship('alice_dave', 'dave');

    final stream = Stream.value([f1, f2, f3]);

    final container = ProviderContainer(
      overrides: [
        friendshipRepositoryProvider.overrideWithValue(
          _FakeFriendshipRepository(stream: stream),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Subscribe to trigger stream emission
    final sub = container.listen(
      pendingRequestsStreamProvider('alice'),
      (_, __) {},
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    final count = container.read(pendingRequestCountProvider('alice'));
    expect(count, equals(3));

    sub.close();
  });
}
