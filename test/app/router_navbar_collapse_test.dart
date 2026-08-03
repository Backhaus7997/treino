// La barra de navegación se compacta al scrollear hacia abajo y vuelve al
// subir, en TODA la app.
//
// Estos tests cruzan la frontera a propósito. El colapso se decide en
// `_ShellScaffold` escuchando `ScrollNotification`, pero el scroll lo produce
// una PANTALLA: un test que solo mirara `TreinoBottomBar(collapsed: ...)` daría
// verde aunque el shell nunca se enterase del gesto. Acá se scrollea la
// pantalla real y se mira la barra real.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/friendship_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/user_session_stats.dart';
import 'package:treino/l10n/app_l10n.dart';

class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() => Completer<User?>().future;
}

UserProfile _testProfile() => UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

List<Post> _manyPosts() => List.generate(
      30,
      (index) => Post(
        id: 'nav-$index',
        authorUid: 'author-$index',
        authorDisplayName: 'Atleta $index',
        authorAvatarUrl: null,
        authorGymId: null,
        text: 'Post $index ${'contenido ' * 8}',
        routineTag: null,
        privacy: PostPrivacy.public,
        createdAt: DateTime.utc(2026, 7, 30).subtract(Duration(hours: index)),
      ),
    );

List<Override> _overrides() => [
      authStateChangesProvider.overrideWith((_) => const Stream<User?>.empty()),
      authNotifierProvider.overrideWith(_LoadingAuthNotifier.new),
      userProfileProvider.overrideWith((_) => Stream.value(_testProfile())),
      userSessionStatsProvider.overrideWith(
        (_) async => const UserSessionStats(
          totalSessions: 0,
          totalVolumeKg: 0,
          streak: 0,
        ),
      ),
      pendingRequestCountProvider('').overrideWith((_) => 0),
      pendingRequestsStreamProvider('').overrideWith((_) => Stream.value([])),
      feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
      myFriendsFeedProvider.overrideWith((ref) async => const <Post>[]),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => _manyPosts()),
    ];

Future<void> _pumpShell(WidgetTester tester, String location) async {
  final container = ProviderContainer(overrides: _overrides());
  addTearDown(container.dispose);
  final router = buildRouter(
    refreshListenable: ValueNotifier<int>(0),
    read: container.read,
  );
  router.go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _collapsed(WidgetTester tester) =>
    tester.widget<TreinoBottomBar>(find.byType(TreinoBottomBar)).collapsed;

void main() {
  group('Nav bar — compactar al scrollear', () {
    testWidgets('scrollear hacia abajo la compacta y hacia arriba la devuelve',
        (
      tester,
    ) async {
      await _pumpShell(tester, '/feed');
      expect(_collapsed(tester), isFalse, reason: 'arranca expandida');

      final scroller = find.byType(CustomScrollView).first;
      await tester.drag(scroller, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(_collapsed(tester), isTrue,
          reason: 'bajar tiene que compactar la barra');

      await tester.drag(scroller, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(_collapsed(tester), isFalse,
          reason: 'subir tiene que devolverla entera');
    });

    testWidgets('volver al tope de la lista siempre la deja expandida', (
      tester,
    ) async {
      await _pumpShell(tester, '/feed');

      final scroller = find.byType(CustomScrollView).first;
      await tester.drag(scroller, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(_collapsed(tester), isTrue);

      await tester.drag(scroller, const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(_collapsed(tester), isFalse);
    });

    testWidgets('el swipe HORIZONTAL no toca la barra', (tester) async {
      // Guardia de regresión del filtro por eje. Sin él, el swipe entre
      // FEED y RANKINGS —y cualquier carrusel horizontal, como el de
      // sugerencias— colapsaría la barra sin que nadie lo haya pedido.
      await _pumpShell(tester, '/feed');
      expect(_collapsed(tester), isFalse);

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      expect(_collapsed(tester), isFalse,
          reason: 'un gesto horizontal no es scroll de lectura');
    });

    testWidgets('cambiar de tab devuelve la barra entera', (tester) async {
      await _pumpShell(tester, '/feed');

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(_collapsed(tester), isTrue);

      await tester.tap(find.bySemanticsLabel('INICIO'));
      await tester.pumpAndSettle();

      expect(_collapsed(tester), isFalse,
          reason: 'la pantalla nueva se ve desde arriba');
    });
  });
}
