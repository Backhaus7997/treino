/// Tests for REQ-FPS-008 invalidation cleanup (SCENARIO-491b, SCENARIO-492).
///
/// Verifies that after the stream conversion:
///   - SEGUIR and ACEPTAR do NOT call ref.invalidate for followEdgeProvider
///     or followingProvider (streams self-update)
///   - ACEPTAR / dejar de seguir DOES preserve ref.invalidate(myFollowingFeedProvider)
///
/// Migración al grafo dirigido: donde antes había UN `friendshipByPairProvider`
/// por par ahora hay DOS aristas (`follows/{follower}_{followee}`), así que
/// `friendshipByPairProvider` mapea a `followEdgeProvider(Follow.edgeId(a, b))`
/// y `acceptedFriendsProvider` a `followingProvider`. Los doc id NO se ordenan.
library;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart'
    show myFollowingFeedProvider;
import 'package:treino/features/feed/application/follow_providers.dart'
    show followEdgeProvider, followingProvider;
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Arista SALIENTE del viewer: `follows/viewer_target` ("yo lo sigo").
String get _outgoingId => Follow.edgeId('viewer', 'target');

/// Arista ENTRANTE al viewer: `follows/target_viewer` ("él me sigue").
String get _incomingId => Follow.edgeId('target', 'viewer');

/// Solicitud RECIBIDA por el viewer: la mandó `target`, así que la arista
/// pendiente es la ENTRANTE. Reemplaza al viejo `_pending(requesterId: 'target')`
/// — con un doc por par la dirección se leía de `requesterId`; ahora se lee del
/// doc id, que no se ordena.
Follow _incomingPending() => Follow(
      id: _incomingId,
      followerUid: 'target',
      followeeUid: 'viewer',
      status: FollowStatus.pending,
      members: const ['target', 'viewer'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

Widget _wrap(
  Widget w,
  FakeFirebaseFirestore firestore, {
  List<Override> extraOverrides = const [],
}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: w),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PublicProfileFollowButton invalidation cleanup (SCENARIO-491b, 492)',
      () {
    // SCENARIO-491b: SEGUIR onTap does NOT call ref.invalidate for
    // followEdgeProvider or followingProvider
    testWidgets(
        'SCENARIO-491b: tap SEGUIR does NOT invalidate followEdgeProvider or followingProvider',
        (tester) async {
      final firestore = FakeFirebaseFirestore();

      // Invalidation detection: each overridden stream provider counts how many
      // times its create function runs. With an ACTIVE listener (the Consumer
      // below) a `ref.invalidate` would force a re-create and bump the counter;
      // a plain stream emission would not. So "counter unchanged after the tap"
      // is exactly "no manual invalidate was fired on these stream providers".
      //
      // (El test viejo no podía afirmar esto y lo dejaba como aserción
      // estructural en el código fuente; el contador lo vuelve ejecutable.)
      var edgeBuildCount = 0;
      var followingBuildCount = 0;

      await tester.pumpWidget(_wrap(
        Column(
          children: [
            // Listeners activos: sin ellos los autoDispose se recrean solos y
            // el contador no probaría nada.
            Consumer(
              builder: (_, ref, __) {
                ref.watch(followEdgeProvider(_outgoingId));
                ref.watch(followingProvider('viewer'));
                return const SizedBox.shrink();
              },
            ),
            const PublicProfileFollowButton(
              // Sin arista saliente ni entrante → SEGUIR.
              outgoingFollow: null,
              incomingFollow: null,
              viewerUid: 'viewer',
              targetUid: 'target',
            ),
          ],
        ),
        firestore,
        extraOverrides: [
          // Stream providers override — no invalidate should be called on these
          followEdgeProvider.overrideWith((ref, edgeId) {
            edgeBuildCount++;
            return Stream.value(null);
          }),
          followingProvider.overrideWith((ref, uid) {
            followingBuildCount++;
            return Stream.value(const <String>[]);
          }),
        ],
      ));
      await tester.pump();

      expect(find.text('SEGUIR'), findsOneWidget);
      expect(edgeBuildCount, equals(1));
      expect(followingBuildCount, equals(1));

      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();

      // Primary action: la arista SALIENTE quedó escrita
      final snap = await firestore.collection('follows').doc(_outgoingId).get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['followerUid'], equals('viewer'));
      expect(snap.data()!['followeeUid'], equals('target'));

      // Los stream providers NO fueron invalidados a mano — se auto-actualizan.
      expect(
        edgeBuildCount,
        equals(1),
        reason: 'SEGUIR no debe invalidar followEdgeProvider',
      );
      expect(
        followingBuildCount,
        equals(1),
        reason: 'SEGUIR no debe invalidar followingProvider',
      );
    });

    // SCENARIO-492: ACEPTAR onTap DOES call ref.invalidate(myFollowingFeedProvider)
    testWidgets(
        'SCENARIO-492: tap ACEPTAR calls repo.acceptRequest AND invalidates myFollowingFeedProvider',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      // "Solicitud recibida" → arista ENTRANTE pending (`follows/target_viewer`).
      final incoming = _incomingPending();

      // Seed la arista en Firestore para que acceptRequest() pueda promoverla
      await firestore
          .collection('follows')
          .doc(incoming.id)
          .set({...incoming.toJson(), 'createdAt': Timestamp.now()});

      // Track myFollowingFeedProvider rebuilds to detect invalidation.
      // Invalidation causes a rebuild only when there's an active listener.
      // We create an active listener on myFollowingFeedProvider via ProviderScope
      // + a Consumer widget, then check if it rebuilt after ACEPTAR.
      var myFollowingFeedBuildCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(firestore),
            followEdgeProvider.overrideWith(
              // Saliente ausente, entrante pendiente: el pill ofrece ACEPTAR.
              (ref, edgeId) => Stream.value(
                edgeId == _incomingId ? incoming : null,
              ),
            ),
            followingProvider.overrideWith(
              (ref, uid) => Stream.value(const <String>[]),
            ),
            myFollowingFeedProvider.overrideWith((ref) async {
              myFollowingFeedBuildCount++;
              return const [];
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: Scaffold(
              body: Column(
                children: [
                  // Active consumer of myFollowingFeedProvider — ensures
                  // ref.invalidate triggers a rebuild
                  Consumer(
                    builder: (_, ref, __) {
                      ref.watch(myFollowingFeedProvider);
                      return const SizedBox.shrink();
                    },
                  ),
                  PublicProfileFollowButton(
                    outgoingFollow: null,
                    incomingFollow: incoming,
                    viewerUid: 'viewer',
                    targetUid: 'target',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Wait for myFollowingFeedProvider to have an initial build
      await tester.pump();
      final countAfterInitialRender = myFollowingFeedBuildCount;
      expect(countAfterInitialRender, greaterThan(0),
          reason:
              'myFollowingFeedProvider should build at least once on render');

      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();

      // myFollowingFeedProvider should have been invalidated and rebuilt
      expect(
        myFollowingFeedBuildCount,
        greaterThan(countAfterInitialRender),
        reason: 'ACEPTAR must call ref.invalidate(myFollowingFeedProvider)',
      );

      // La arista entrante en Firestore ahora debe estar aceptada
      final snap = await firestore.collection('follows').doc(incoming.id).get();
      expect(snap.data()!['status'], equals('accepted'));
    });
  });
}
