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

const _frame = Duration(milliseconds: 16);

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

    testWidgets(
      'el rebote del final en iOS no expande la barra (no corre el final)',
      (tester) async {
        // Reporte de device (EXPLORAR, iPhone 16): al llegar abajo el scroll
        // se sentía trabado. BouncingScrollPhysics pasa de largo el final y
        // vuelve solo; ese regreso llega como scroll hacia ARRIBA y expandía
        // la barra. La barra expandida agranda `padding.bottom`, el final del
        // scroll se corre en pleno rebote y la última fila queda pegada al
        // vidrio.
        await _pumpShell(tester, '/feed');

        final scroller = find.byType(CustomScrollView).first;
        await tester.drag(scroller, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(_collapsed(tester), isTrue);

        // Hasta el final y bastante más allá: el overscroll y su regreso.
        for (var i = 0; i < 6; i++) {
          await tester.drag(scroller, const Offset(0, -3000));
          await tester.pumpAndSettle();
        }

        expect(_collapsed(tester), isTrue,
            reason: 'el regreso del rebote no es un gesto hacia arriba');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

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

  group('Nav bar — sigue al scroll', () {
    double expansion(WidgetTester tester) =>
        tester.widget<TreinoBottomBar>(find.byType(TreinoBottomBar)).expansion!;

    /// Mueve el dedo apoyado (sin soltar) en pasos de 4 px, como un dedo real:
    /// con un solo `moveBy` Flutter sólo reconoce el arranque del drag.
    ///
    /// Un paso por frame de 16 ms = 250 px/s, un scroll de lectura: muy por
    /// debajo de [ScrollFollowController.maxTrackingSpeed], así que la barra
    /// sigue 1:1. Sin el tiempo entre pasos, todos caerían en el mismo
    /// instante y contarían como un salto infinitamente rápido.
    Future<void> move(WidgetTester tester, TestGesture g, double dy) async {
      final steps = (dy.abs() / 4).ceil();
      for (var i = 0; i < steps; i++) {
        await g.moveBy(Offset(0, dy / steps));
        await tester.pump(_frame);
      }
    }

    /// Apoya el dedo, sale de la zona del tope (que siempre la deja entera) y
    /// devuelve el gesto todavía apoyado, con la barra entera.
    Future<TestGesture> holdPastTop(WidgetTester tester) async {
      final scroller = find.byType(CustomScrollView).first;
      final g = await tester.startGesture(tester.getCenter(scroller));
      await move(tester, g, -140);
      await move(tester, g, 70); // vuelve a entera lejos de la zona del tope
      return g;
    }

    testWidgets('a mitad del gesto queda a mitad, y quieta si el dedo para',
        (tester) async {
      await _pumpShell(tester, '/feed');
      final g = await holdPastTop(tester);
      final antes = expansion(tester);

      await move(tester, g, -32); // medio `_collapseRange` (64)
      final mitad = expansion(tester);
      expect(antes - mitad, closeTo(0.5, 0.05),
          reason: '32 px de dedo mueven la barra media carrera');
      expect(mitad, greaterThan(0));

      await tester.pump(const Duration(seconds: 1));
      expect(expansion(tester), mitad,
          reason: 'sin scroll no se mueve: no es una animación con tiempo');
      await g.up();
      await tester.pumpAndSettle();
    });

    testWidgets('al soltar a medias se asienta del lado más cercano',
        (tester) async {
      await _pumpShell(tester, '/feed');
      final g = await holdPastTop(tester);
      await move(tester, g, -24);
      expect(expansion(tester), greaterThan(0.5));

      await g.up();
      await tester.pumpAndSettle();
      expect(expansion(tester), anyOf(0.0, 1.0));
    });

    testWidgets('un scroll muy rápido no la compacta de golpe: la persigue',
        (tester) async {
      // Feedback de device: el 1:1 está bien, pero con un scroll muy rápido
      // la barra se iba en un frame y se sentía seco.
      await _pumpShell(tester, '/feed');
      final g = await holdPastTop(tester);
      expect(expansion(tester), 1);

      // 64 px en dos frames de 8 ms = 4000 px/s. A 1:1 ya estaría en 0.
      const fast = Duration(milliseconds: 8);
      await g.moveBy(const Offset(0, -32));
      await tester.pump(fast);
      await g.moveBy(const Offset(0, -32));
      await tester.pump(fast);
      expect(expansion(tester), greaterThan(0.5),
          reason: 'arrancó a perseguir, no saltó');

      // Con el dedo quieto llega igual, sin escalones.
      var antes = expansion(tester);
      var frames = 0;
      while (expansion(tester) > 0) {
        await tester.pump(fast);
        expect(antes - expansion(tester), lessThan(0.25),
            reason: 'frame $frames: ningún salto de más de un cuarto');
        antes = expansion(tester);
        expect(++frames, lessThan(60));
      }
      expect(frames, greaterThan(10),
          reason: 'una animación de verdad, no dos o tres frames');
      await g.up();
      await tester.pumpAndSettle();
      expect(_collapsed(tester), isTrue);
    });

    testWidgets('con «reducir movimiento» el scroll rápido va directo',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpShell(tester, '/feed');
      final g = await holdPastTop(tester);

      const fast = Duration(milliseconds: 8);
      await g.moveBy(const Offset(0, -32));
      await tester.pump(fast);
      await g.moveBy(const Offset(0, -32));
      await tester.pump(fast);
      expect(expansion(tester), lessThan(0.1),
          reason: 'sin resorte: sigue al scroll aunque sea rápido');
      await g.up();
      await tester.pumpAndSettle();
    });
  });
}
