// Los roots de tab (barra inferior) entran con un fade corto (AppMotion.fast)
// en vez del corte seco, y con reduce-motion el cambio sigue siendo inmediato.
// La página del shell NO anima (ver el comentario del ShellRoute en router.dart).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/home/home_screen.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
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

import '../helpers/onboarding_test_helpers.dart';

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
      // Este test es sobre la barra, no sobre el onboarding: sin esto el tour
      // (#627) se monta full-screen sobre /home y los finders de la barra no
      // encuentran nada. Ver test/helpers/onboarding_test_helpers.dart.
      onboardingSeen: allSurfacesSeen(),
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
      pendingFollowRequestCountProvider('').overrideWith((_) => 0),
      pendingReceivedStreamProvider('').overrideWith((_) => Stream.value([])),
      feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
      myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
      myGymFeedProvider.overrideWith((ref) async => null),
      feedPublicProvider.overrideWith((ref) async => _manyPosts()),
    ];

Future<void> _pumpShell(
  WidgetTester tester,
  String location, {
  bool disableAnimations = false,
}) async {
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: child!,
        ),
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

/// Opacidad efectiva de [finder]: producto de los FadeTransition ancestros.
double _opacityOf(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  for (final e in find
      .ancestor(of: finder, matching: find.byType(FadeTransition))
      .evaluate()) {
    opacity *= (e.widget as FadeTransition).opacity.value;
  }
  return opacity;
}

void main() {
  testWidgets('cambiar de tab entra el tab nuevo con un fade corto', (
    tester,
  ) async {
    await _pumpShell(tester, '/feed');
    expect(find.byType(FeedScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('INICIO'));
    await tester.pump();
    await tester.pump(AppMotion.fast ~/ 2);

    // A mitad del fade el tab nuevo ya está montado pero a opacidad
    // intermedia: ni invisible ni completo. (go_router no anima el reemplazo
    // de páginas del shell, así que el saliente se desmonta al instante: no
    // hay dos tabs vivos ni taps fantasma.)
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(FeedScreen), findsNothing);
    final mid = _opacityOf(tester, find.byType(HomeScreen));
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(_opacityOf(tester, find.byType(HomeScreen)), 1.0);
  });

  testWidgets('con reduce-motion el cambio de tab es inmediato',
      (tester) async {
    await _pumpShell(tester, '/feed', disableAnimations: true);

    await tester.tap(find.bySemanticsLabel('INICIO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(FeedScreen), findsNothing);
    expect(_opacityOf(tester, find.byType(HomeScreen)), 1.0);
  });
}
