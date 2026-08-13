import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/follow_providers.dart'
    show followRepositoryProvider;
import 'package:treino/features/feed/data/follow_repository.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Repository whose write paths always throw, simulating an offline /
/// permission-denied Firestore write (the bug repro).
class _ThrowingFollowRepository extends FollowRepository {
  _ThrowingFollowRepository() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<Follow> follow(
    String myUid,
    String targetUid, {
    required bool targetIsPublic,
  }) async {
    throw StateError('write failed');
  }

  @override
  Future<void> acceptRequest(String edgeId, String myUid) async {
    throw StateError('write failed');
  }
}

Widget _wrap(Widget w, FollowRepository repo) => ProviderScope(
      overrides: [
        followRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: w),
      ),
    );

/// Solicitud RECIBIDA: la arista ENTRANTE `follows/{target}_{viewer}` pendiente.
///
/// Mapea el viejo `_pending(requesterId: 'target')` — un solo documento por par
/// donde `requesterId` decía quién había pedido. En el grafo dirigido eso ya no
/// se desambigua con un campo: la dirección ES el documento, así que "target me
/// mandó solicitud" es la arista `target → viewer` en `pending`. Los uids NO se
/// ordenan al armar el id.
Follow _incomingPending() => Follow(
      id: Follow.edgeId('target', 'viewer'),
      followerUid: 'target',
      followeeUid: 'viewer',
      status: FollowStatus.pending,
      members: const ['target', 'viewer'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('PublicProfileFollowButton error handling', () {
    testWidgets(
        'tapping SEGUIR swallows a failing follow — no uncaught async error',
        (tester) async {
      final repo = _ThrowingFollowRepository();
      await tester.pumpWidget(_wrap(
        // Sin arista en ninguna de las dos direcciones → el pill ofrece SEGUIR.
        const PublicProfileFollowButton(
          outgoingFollow: null,
          incomingFollow: null,
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        repo,
      ));
      await tester.pump();

      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();

      // Before the fix the StateError escaped the async GestureDetector
      // callback as an unhandled error and would surface here.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tapping ACEPTAR swallows a failing accept — no uncaught async error',
        (tester) async {
      final repo = _ThrowingFollowRepository();
      await tester.pumpWidget(_wrap(
        PublicProfileFollowButton(
          // ACEPTAR = no hay saliente y la entrante está pendiente.
          outgoingFollow: null,
          incomingFollow: _incomingPending(),
          viewerUid: 'viewer',
          targetUid: 'target',
        ),
        repo,
      ));
      await tester.pump();

      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
