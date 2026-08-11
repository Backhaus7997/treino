import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Follow _edge(String follower, String followee, FollowStatus status) => Follow(
      // Los doc id de `follows` NO se ordenan: cada dirección es su propio
      // documento.
      id: Follow.edgeId(follower, followee),
      followerUid: follower,
      followeeUid: followee,
      status: status,
      members: [follower, followee],
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// `follows/viewer_target` aceptada — el equivalente direccional de lo que el
/// modelo viejo llamaba "amistad aceptada entre viewer y target": es la arista
/// SALIENTE, la que gobierna el pill SIGUIENDO.
Follow _acceptedOutgoing({
  String viewerUid = 'viewer',
  String targetUid = 'target',
}) =>
    _edge(viewerUid, targetUid, FollowStatus.accepted);

/// `follows/target_viewer` — la dirección inversa. En el modelo viejo no
/// existía como documento aparte (era el mismo doc del par); acá se usa para
/// verificar que dejar de seguir corta un solo sentido.
Follow _acceptedIncoming({
  String viewerUid = 'viewer',
  String targetUid = 'target',
}) =>
    _edge(targetUid, viewerUid, FollowStatus.accepted);

Future<void> _seed(FakeFirebaseFirestore firestore, Follow edge) => firestore
    .collection('follows')
    .doc(edge.id)
    .set({...edge.toJson(), 'createdAt': Timestamp.now()});

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
// Tests: SCENARIO-469, SCENARIO-471 wiring
// ---------------------------------------------------------------------------

void main() {
  group('PublicProfileFollowButton SIGUIENDO upgrade', () {
    // SCENARIO-469: SIGUIENDO pill has a non-null onTap when the OUTGOING edge
    // is accepted. This verifies the GestureDetector wrapping the pill has a
    // real callback. The previous implementation had onTap: null
    // (const _FollowPill).
    testWidgets(
        'SCENARIO-469: SIGUIENDO pill is tappable (tap does not throw and sheet opens)',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final outgoing = _acceptedOutgoing();

      await tester.pumpWidget(
        _wrap(
          PublicProfileFollowButton(
            outgoingFollow: outgoing,
            incomingFollow: null,
            viewerUid: 'viewer',
            targetUid: 'target',
          ),
          firestore,
          extraOverrides: [
            userPublicProfileProvider('target').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'target',
                displayName: 'Vicente',
              )),
            ),
          ],
        ),
      );

      await tester.pump();

      expect(find.text('SIGUIENDO'), findsOneWidget);

      // Tap the SIGUIENDO pill — should open the sheet (not be a no-op)
      await tester.tap(find.text('SIGUIENDO'));
      await tester.pumpAndSettle();

      // The confirmation sheet must be open
      expect(find.byType(UnfriendConfirmationSheet), findsOneWidget);
    });

    // SCENARIO-471 wiring: tapping DEJAR DE SEGUIR in the sheet calls repo.deleteEdge
    // on the OUTGOING edge (antes era repo.delete sobre el doc del par) so the
    // button can transition back to SEGUIR.
    //
    // Mapeo del modelo viejo: `friendshipByPairProvider` ya no existe y su
    // reemplazo, `followEdgeProvider`, es un StreamProvider sobre .snapshots()
    // que se auto-actualiza — por eso la evidencia observable de que el wiring
    // quedó bien sigue siendo la MISMA que probaba el test original: el
    // documento desaparece de Firestore.
    testWidgets(
        'SCENARIO-471 wiring: tapping DEJAR DE SEGUIR calls repo.deleteEdge and the outgoing edge doc is removed',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final outgoing = _acceptedOutgoing();
      final incoming = _acceptedIncoming();

      // Seed the doc in FakeFirestore so deleteEdge has something to remove.
      await _seed(firestore, outgoing);
      // Y la inversa: en el modelo viejo borrar el doc del par cortaba la
      // relación para los dos. Acá dejar de seguir corta UN solo sentido, así
      // que la entrante tiene que sobrevivir.
      await _seed(firestore, incoming);

      await tester.pumpWidget(
        _wrap(
          PublicProfileFollowButton(
            outgoingFollow: outgoing,
            incomingFollow: incoming,
            viewerUid: 'viewer',
            targetUid: 'target',
          ),
          firestore,
          extraOverrides: [
            userPublicProfileProvider('target').overrideWith(
              (_) => Stream.value(const UserPublicProfile(
                uid: 'target',
                displayName: 'Vicente',
              )),
            ),
          ],
        ),
      );

      await tester.pump();

      // Open the confirmation sheet
      await tester.tap(find.text('SIGUIENDO'));
      await tester.pumpAndSettle();

      expect(find.byType(UnfriendConfirmationSheet), findsOneWidget);

      // Confirm the unfollow
      await tester.tap(find.text('DEJAR DE SEGUIR'));
      await tester.pumpAndSettle();

      // Sheet dismissed
      expect(find.byType(UnfriendConfirmationSheet), findsNothing);

      // Firestore doc de la arista SALIENTE borrado
      final snap = await firestore.collection('follows').doc(outgoing.id).get();
      expect(snap.exists, isFalse);

      // La arista inversa queda intacta — deleteEdge nunca toca la otra
      // dirección.
      final inverseSnap =
          await firestore.collection('follows').doc(incoming.id).get();
      expect(inverseSnap.exists, isTrue);
    });
  });
}
