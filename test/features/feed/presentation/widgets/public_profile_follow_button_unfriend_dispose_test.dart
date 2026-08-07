/// Regresión #500: dejar de seguir debe sobrevivir al dispose de la pantalla.
///
/// `_showUnfriendSheet` corre su `onConfirm` desde un route root que sigue vivo
/// aunque el perfil ya se haya popeado. Usar el `ref` del ConsumerState tras el
/// await lanza `StateError('Cannot use "ref" after the widget was disposed')`
/// (flutter_riverpod 2.6.1, `_assertNotDisposed`), y el catch del onConfirm lo
/// reporta como falla aunque el borrado de la arista YA se haya commiteado —
/// dejando además el feed de SEGUIDOS con el ex-seguido adentro.
///
/// El fix captura `ProviderScope.containerOf` ANTES del await, igual que
/// `_onAccept` en el mismo archivo (ADR-FPS-006).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart'
    show myFollowingFeedProvider;
import 'package:treino/features/feed/application/follow_providers.dart'
    show followRepositoryProvider;
import 'package:treino/features/feed/data/follow_repository.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockFollowRepository extends Mock implements FollowRepository {}

/// El caso original partía de una `Friendship` aceptada entre viewer y target.
/// En el grafo dirigido el equivalente es la arista SALIENTE
/// `follows/viewer_target` aceptada: es la única que pinta SIGUIENDO y la única
/// que el sheet borra (la inversa nunca se toca). El doc id NO se ordena.
Follow _acceptedOutgoing() => Follow(
      id: Follow.edgeId('viewer', 'target'),
      followerUid: 'viewer',
      followeeUid: 'target',
      status: FollowStatus.accepted,
      members: const ['viewer', 'target'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  testWidgets(
      'dejar de seguir: el invalidate del feed de SEGUIDOS sobrevive al pop '
      'del perfil mid-delete y no reporta error [dispose-race-regression]',
      (tester) async {
    final repo = _MockFollowRepository();
    final deleteGate = Completer<void>();
    when(() => repo.deleteEdge(any())).thenAnswer((_) => deleteGate.future);

    // El botón vive detrás de este flag: apagarlo desmonta el ConsumerState,
    // que es lo que pasa cuando el usuario toca back mientras el delete vuela.
    final buttonMounted = ValueNotifier<bool>(true);
    addTearDown(buttonMounted.dispose);

    var myFollowingFeedBuilds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          followRepositoryProvider.overrideWithValue(repo),
          userPublicProfileProvider('target').overrideWith(
            (_) => Stream.value(
              const UserPublicProfile(uid: 'target', displayName: 'Vicente'),
            ),
          ),
          myFollowingFeedProvider.overrideWith((ref) async {
            myFollowingFeedBuilds++;
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
                // Listener activo del feed de SEGUIDOS: sin él, invalidate no
                // dispara rebuild y el contador no serviría de sonda.
                Consumer(
                  builder: (_, ref, __) {
                    ref.watch(myFollowingFeedProvider);
                    return const SizedBox.shrink();
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: buttonMounted,
                  builder: (_, mounted, __) => mounted
                      ? PublicProfileFollowButton(
                          outgoingFollow: _acceptedOutgoing(),
                          // Sin arista entrante: el caso es "yo lo sigo", que
                          // es lo que la amistad aceptada representaba acá.
                          incomingFollow: null,
                          viewerUid: 'viewer',
                          targetUid: 'target',
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final buildsBeforeUnfollow = myFollowingFeedBuilds;
    expect(buildsBeforeUnfollow, greaterThan(0));

    await tester.tap(find.text('SIGUIENDO'));
    await tester.pumpAndSettle();
    expect(find.byType(UnfriendConfirmationSheet), findsOneWidget);

    await tester.tap(find.text('ELIMINAR'));
    await tester.pump();

    // El usuario vuelve atrás con el delete todavía en vuelo.
    buttonMounted.value = false;
    await tester.pump();

    // Recién ahora Firestore confirma el borrado.
    deleteGate.complete();
    await tester.pumpAndSettle();

    verify(() => repo.deleteEdge(_acceptedOutgoing().id)).called(1);
    expect(
      myFollowingFeedBuilds,
      greaterThan(buildsBeforeUnfollow),
      reason: 'El feed de SEGUIDOS debe refrescarse o queda mostrando al '
          'ex-seguido',
    );
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: 'El delete se commiteó: no se puede reportar como falla',
    );
  });
}
