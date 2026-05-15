import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;

Widget _wrap(Widget w, FakeFirebaseFirestore firestore) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

Friendship _accepted({String requesterId = 'viewer'}) => Friendship(
      id: Friendship.sortedDocId('viewer', 'target'),
      uidA: 'target',
      uidB: 'viewer',
      status: FriendshipStatus.accepted,
      requesterId: requesterId,
      members: const ['target', 'viewer'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

Friendship _pending({required String requesterId}) => Friendship(
      id: Friendship.sortedDocId('viewer', 'target'),
      uidA: 'target',
      uidB: 'viewer',
      status: FriendshipStatus.pending,
      requesterId: requesterId,
      members: const ['target', 'viewer'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('PublicProfileFollowButton', () {
    testWidgets(
        'SCENARIO-219: friendship null → SEGUIR pill mint active',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        const PublicProfileFollowButton(
          friendship: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('SEGUIR'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-220: pending + requesterId == viewerUid → SOLICITUD ENVIADA',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          friendship: _pending(requesterId: 'viewer'),
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('SOLICITUD ENVIADA'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-221: SOLICITUD ENVIADA wrapped in Opacity(0.6) (disabled visual)',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          friendship: _pending(requesterId: 'viewer'),
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      final opacityFinder = find.ancestor(
        of: find.text('SOLICITUD ENVIADA'),
        matching: find.byType(Opacity),
      );
      expect(opacityFinder, findsOneWidget);
      final op = tester.widget<Opacity>(opacityFinder);
      expect(op.opacity, equals(0.6));
    });

    testWidgets(
        'SCENARIO-222: pending + requesterId == targetUid → ACEPTAR pill mint active',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          friendship: _pending(requesterId: 'target'),
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('ACEPTAR'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-223: accepted → SIGUIENDO with check icon',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          friendship: _accepted(),
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();

      expect(find.text('SIGUIENDO'), findsOneWidget);
      expect(find.byIcon(TreinoIcon.check), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-224: tap SEGUIR fires request and writes Firestore',
        (tester) async {
      final firestore = FakeFirebaseFirestore();

      await tester.pumpWidget(_wrap(
        const PublicProfileFollowButton(
          friendship: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();
      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();

      final docId = Friendship.sortedDocId('viewer', 'target');
      final snap = await firestore.collection('friendships').doc(docId).get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['requesterId'], equals('viewer'));
      expect(snap.data()!['status'], equals('pending'));
    });

    testWidgets(
        'SCENARIO-225: tap ACEPTAR transitions friendship to accepted',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final pending = _pending(requesterId: 'target');
      await firestore
          .collection('friendships')
          .doc(pending.id)
          .set({...pending.toJson(), 'createdAt': Timestamp.now()});

      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          friendship: pending,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();
      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();

      final snap =
          await firestore.collection('friendships').doc(pending.id).get();
      expect(snap.data()!['status'], equals('accepted'));
    });

    testWidgets(
        'SCENARIO-226: tap SIGUIENDO is a no-op (no Firestore change)',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final accepted = _accepted();
      await firestore
          .collection('friendships')
          .doc(accepted.id)
          .set({...accepted.toJson(), 'createdAt': Timestamp.now()});

      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          friendship: accepted,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        firestore,
      ));
      await tester.pump();
      // Tap should not throw and should not change state.
      await tester.tap(find.text('SIGUIENDO'));
      await tester.pumpAndSettle();

      final snap =
          await firestore.collection('friendships').doc(accepted.id).get();
      expect(snap.data()!['status'], equals('accepted'));
    });
  });
}
