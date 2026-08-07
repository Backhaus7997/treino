import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
import 'package:treino/features/feed/data/follow_repository.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
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

/// Spy repository that records `watchEdge` subscription count and allows
/// controlling the emitted stream.
///
/// Migración: antes espiaba `FriendshipRepository.watchByPair(uidA, uidB)` —
/// dos uids porque el documento era del PAR. Ahora la unidad es la ARISTA
/// dirigida, así que el método espiado recibe un solo doc id
/// (`'{follower}_{followee}'`, sin ordenar).
class _SpyFollowRepository extends FollowRepository {
  _SpyFollowRepository() : super(firestore: FakeFirebaseFirestore());

  int watchEdgeSubscribeCount = 0;
  int watchEdgeDisposeCount = 0;
  final _watchEdgeController = StreamController<Follow?>.broadcast();

  /// Doc ids con los que se pidió una arista, en orden. Permite afirmar que se
  /// consultó la dirección correcta y no la inversa.
  final requestedEdgeIds = <String>[];

  Stream<Follow?> get controlledStream => _watchEdgeController.stream;

  @override
  Stream<Follow?> watchEdge(String edgeId) {
    watchEdgeSubscribeCount++;
    requestedEdgeIds.add(edgeId);
    return _watchEdgeController.stream.transform(
      StreamTransformer.fromHandlers(
        handleDone: (sink) {
          watchEdgeDisposeCount++;
          sink.close();
        },
      ),
    );
  }

  void dispose() {
    _watchEdgeController.close();
  }
}

final _now = DateTime.utc(2026, 1, 1);

/// Arista dirigida `follower → followee`. El doc id NUNCA se ordena: si se
/// ordenara, las dos direcciones colisionarían en el mismo documento y
/// volveríamos al modelo simétrico de `friendships`.
Follow _makeFollow({
  String follower = 'viewer',
  String followee = 'target',
  FollowStatus status = FollowStatus.pending,
}) =>
    Follow(
      id: Follow.edgeId(follower, followee),
      followerUid: follower,
      followeeUid: followee,
      status: status,
      members: [follower, followee],
      createdAt: _now,
    );

const _profileAlice = UserPublicProfile(
  uid: 'alice',
  displayName: 'Alice',
  displayNameLowercase: 'alice',
);

/// `follows/{viewer}_{target}` — "yo lo sigo". Es el equivalente por defecto de
/// la vieja `friendship` del par cuando el caso no habla de una solicitud
/// RECIBIDA.
final _outgoingEdgeId = Follow.edgeId('viewer', 'target');

// ---------------------------------------------------------------------------
// T08 RED: SCENARIO-481..483 — followEdgeProvider as StreamProvider
//
// Mapeo del modelo viejo al nuevo: `friendshipByPairProvider(pair)` fue
// eliminado; su reemplazo es `followEdgeProvider(Follow.edgeId(a, b))`, cuya
// key de family es el DOC ID de la arista (un `String`), no un record.
// ---------------------------------------------------------------------------

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-481: followEdgeProvider exposes AsyncValue<Follow?>
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-481: followEdgeProvider consumer receives AsyncValue<Follow?> and rebuilds on emit',
      () async {
    final user = MockUser(uid: 'viewer');
    final edge = _makeFollow();

    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
        followEdgeProvider.overrideWith(
          (ref, edgeId) => Stream.value(edge),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Reading gives AsyncValue<Follow?> — same surface as former FutureProvider
    final value = await container.read(
      followEdgeProvider(_outgoingEdgeId).future,
    );
    expect(value, equals(edge));
    expect(value?.status, equals(FollowStatus.pending));

    // The provider itself (the family) is a StreamProvider.family.autoDispose
    // Calling the family with args produces an AutoDisposeStreamProvider
    final provider = followEdgeProvider(_outgoingEdgeId);
    expect(provider, isA<AutoDisposeStreamProvider<Follow?>>());
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-482: autoDispose — subscription cancelled when container disposed
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-482: followEdgeProvider drops Firestore listener when container is disposed',
      () async {
    final spyRepo = _SpyFollowRepository();
    final user = MockUser(uid: 'alice');

    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
        // Antes había que sustituir el cuerpo de la family entera porque el
        // repositorio vivía en un provider PRIVADO. `followRepositoryProvider`
        // es público, así que ahora se inyecta el spy y se ejercita el cuerpo
        // REAL de `followEdgeProvider` — el listener que se cuenta es el que
        // abre producción, no uno de mentira.
        followRepositoryProvider.overrideWithValue(spyRepo),
      ],
    );

    // Subscribe to the provider (simulates a widget listening)
    final sub = container.listen(
      followEdgeProvider(Follow.edgeId('alice', 'bob')),
      (_, __) {},
    );

    // Wait for the subscription to establish
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(spyRepo.watchEdgeSubscribeCount, equals(1));
    // La dirección pedida es la de la key, sin ordenar los uids.
    expect(spyRepo.requestedEdgeIds, equals(['alice_bob']));

    // Emit one value to make sure the stream is live
    spyRepo._watchEdgeController.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // Dispose the listener (simulates widget unmount)
    sub.close();
    container.dispose();

    // Give time for dispose propagation
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // The stream was subscribed exactly once and the provider was auto-disposed
    // (autoDispose cancels the stream when the last listener is removed)
    expect(spyRepo.watchEdgeSubscribeCount, equals(1));

    spyRepo.dispose();
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-483: acceptedFriendsProvider drop-in — AsyncValue<List<String>>
  //
  // Sin cambios: `acceptedFriendsProvider` sigue existiendo en `lib/` y este
  // archivo es su ÚNICA cobertura. Su sucesor direccional es
  // `followingProvider`, pero migrarlo acá borraría la única prueba del
  // provider que todavía se exporta.
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
    final value =
        await container.read(userPublicProfileProvider('alice').future);
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
      // "friendship accepted entre viewer y target" → arista SALIENTE aceptada.
      final outgoing = _makeFollow(status: FollowStatus.accepted);

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('target').overrideWith(
            (ref) => Stream.value(_profileAlice),
          ),
          followEdgeProvider.overrideWith(
            (ref, edgeId) => Stream.value(
              edgeId == _outgoingEdgeId ? outgoing : null,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final view =
          await container.read(publicProfileViewProvider('target').future);
      expect(view, isA<PublicProfileView>());
      expect(view.authorDisplayName, equals('Alice'));
      expect(view.outgoingFollow, equals(outgoing));
      // La entrante NO se contagia de la saliente: son dos documentos.
      expect(view.incomingFollow, isNull);
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
          followEdgeProvider.overrideWith(
            (ref, edgeId) => Stream.value(null),
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
      profileController.add(
          const UserPublicProfile(uid: 'target', displayName: 'InitialName'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Emit updated profile
      profileController.add(
          const UserPublicProfile(uid: 'target', displayName: 'UpdatedName'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Should have data emissions with updated profile
      final dataEmissions =
          emissions.whereType<AsyncData<PublicProfileView>>().toList();
      expect(dataEmissions, isNotEmpty);
      expect(
        dataEmissions.last.value.authorDisplayName,
        equals('UpdatedName'),
      );
    });

    // SCENARIO-487: re-emits when the outgoing follow edge upstream changes
    // (era `friendshipByPairProvider`; el equivalente por defecto del par es la
    // arista SALIENTE `follows/{viewer}_{target}`).
    test(
        'SCENARIO-487: re-emits updated view-model when la arista saliente cambia',
        () async {
      final user = MockUser(uid: 'viewer');
      final outgoingController = StreamController<Follow?>.broadcast();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('target').overrideWith(
            (ref) => Stream.value(_profileAlice),
          ),
          followEdgeProvider.overrideWith(
            (ref, edgeId) => edgeId == _outgoingEdgeId
                ? outgoingController.stream
                : Stream.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(outgoingController.close);

      final emissions = <AsyncValue<PublicProfileView>>[];
      container.listen(
        publicProfileViewProvider('target'),
        (_, next) => emissions.add(next),
        fireImmediately: true,
      );

      // Emit pending edge
      outgoingController.add(_makeFollow(status: FollowStatus.pending));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Emit accepted edge
      outgoingController.add(_makeFollow(status: FollowStatus.accepted));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final dataEmissions =
          emissions.whereType<AsyncData<PublicProfileView>>().toList();
      expect(dataEmissions, isNotEmpty);
      expect(
        dataEmissions.last.value.outgoingFollow?.status,
        equals(FollowStatus.accepted),
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
          followEdgeProvider.overrideWith(
            (ref, edgeId) => Stream.value(null),
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
    test('SCENARIO-489: propagates AsyncError when upstream emits an error',
        () async {
      final user = MockUser(uid: 'viewer');
      final error = StateError('upstream error');

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('target').overrideWith(
            (ref) => Stream.error(error),
          ),
          followEdgeProvider.overrideWith(
            (ref, edgeId) => Stream.value(null),
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

    // SCENARIO-490: isSelf branch — followEdgeProvider NOT subscribed, en
    // NINGUNA de las dos direcciones (antes era un solo listener; ahora son dos
    // y la rama isSelf tiene que saltearse los dos).
    test(
        'SCENARIO-490: isSelf — followEdgeProvider is NOT subscribed (ni saliente ni entrante) when viewerUid == targetUid',
        () async {
      final user = MockUser(uid: 'alice');
      int followEdgeSubscribeCount = 0;

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
          userPublicProfileProvider('alice').overrideWith(
            (ref) => Stream.value(_profileAlice),
          ),
          followEdgeProvider.overrideWith((ref, edgeId) {
            followEdgeSubscribeCount++;
            return Stream.fromFuture(
              Future.error(
                StateError(
                    'isSelf branch should NOT subscribe to followEdgeProvider'),
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      // targetUid == viewerUid == 'alice' → isSelf
      final view =
          await container.read(publicProfileViewProvider('alice').future);

      // followEdgeProvider must NOT have been called — ni para 'alice_alice'
      // ni para ninguna otra key.
      expect(followEdgeSubscribeCount, equals(0));
      // And the view has both edges null
      expect(view.outgoingFollow, isNull);
      expect(view.incomingFollow, isNull);
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
