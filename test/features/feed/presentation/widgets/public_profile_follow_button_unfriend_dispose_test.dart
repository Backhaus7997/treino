/// Regression #500: eliminar amistad debe sobrevivir al dispose de la pantalla.
///
/// `_showUnfriendSheet` corre su `onConfirm` desde un route root que sigue vivo
/// aunque el perfil ya se haya popeado. Usar el `ref` del ConsumerState tras el
/// await lanza `StateError('Cannot use "ref" after the widget was disposed')`
/// (flutter_riverpod 2.6.1, `_assertNotDisposed`), y el catch del onConfirm lo
/// reporta como falla aunque el delete YA se haya commiteado — dejando además
/// el feed AMIGOS con el ex-amigo adentro.
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
    show myFriendsFeedProvider;
import 'package:treino/features/feed/application/friendship_providers.dart'
    show friendshipRepositoryProvider;
import 'package:treino/features/feed/data/friendship_repository.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockFriendshipRepository extends Mock implements FriendshipRepository {}

Friendship _accepted() => Friendship(
      id: Friendship.sortedDocId('viewer', 'target'),
      uidA: 'target',
      uidB: 'viewer',
      status: FriendshipStatus.accepted,
      requesterId: 'viewer',
      members: const ['target', 'viewer'],
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  testWidgets(
      'unfriend: el invalidate del feed AMIGOS sobrevive al pop del perfil '
      'mid-delete y no reporta error [dispose-race-regression]',
      (tester) async {
    final repo = _MockFriendshipRepository();
    final deleteGate = Completer<void>();
    when(() => repo.delete(any(), any())).thenAnswer((_) => deleteGate.future);

    // El botón vive detrás de este flag: apagarlo desmonta el ConsumerState,
    // que es lo que pasa cuando el usuario toca back mientras el delete vuela.
    final buttonMounted = ValueNotifier<bool>(true);
    addTearDown(buttonMounted.dispose);

    var myFriendsFeedBuilds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          friendshipRepositoryProvider.overrideWithValue(repo),
          userPublicProfileProvider('target').overrideWith(
            (_) => Stream.value(
              const UserPublicProfile(uid: 'target', displayName: 'Vicente'),
            ),
          ),
          myFriendsFeedProvider.overrideWith((ref) async {
            myFriendsFeedBuilds++;
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
                // Listener activo del feed AMIGOS: sin él, invalidate no
                // dispara rebuild y el contador no serviría de sonda.
                Consumer(
                  builder: (_, ref, __) {
                    ref.watch(myFriendsFeedProvider);
                    return const SizedBox.shrink();
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: buttonMounted,
                  builder: (_, mounted, __) => mounted
                      ? PublicProfileFollowButton(
                          friendship: _accepted(),
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

    final buildsBeforeUnfriend = myFriendsFeedBuilds;
    expect(buildsBeforeUnfriend, greaterThan(0));

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

    verify(() => repo.delete(_accepted().id, 'viewer')).called(1);
    expect(
      myFriendsFeedBuilds,
      greaterThan(buildsBeforeUnfriend),
      reason: 'El feed AMIGOS debe refrescarse o queda mostrando al ex-amigo',
    );
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: 'El delete se commiteó: no se puede reportar como falla',
    );
  });
}
