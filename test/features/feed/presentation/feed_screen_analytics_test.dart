// Issue #666 — que Feed esté REALMENTE instrumentado.
//
// Feed tiene DOS niveles de sub-navegación y ninguno se ve desde las rutas:
//   1. FEED / RANKINGS — páginas de un TabBarView, las dos en `/feed`.
//      Es el caso que originó la issue: #642 preguntó cuánta gente usa
//      RANKINGS y no había con qué responder.
//   2. AMIGOS / MI GYM / PÚBLICO — segmentos dentro de la página FEED, que
//      no son un TabController sino un StateProvider.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/notifications/application/notification_history_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/fake_analytics_service.dart';

UserProfile _profile(UserRole role) => UserProfile(
      uid: 'u1',
      email: 'a@example.com',
      displayName: 'Tincho',
      role: role,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _pumpFeed(
  WidgetTester tester,
  FakeAnalyticsService analytics, {
  String? initialTab,
  FeedSegment segment = FeedSegment.amigos,
  UserRole role = UserRole.athlete,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(analytics),
        currentUidProvider.overrideWithValue('u1'),
        userProfileProvider.overrideWith((ref) => Stream.value(_profile(role))),
        feedSegmentProvider.overrideWith((ref) => segment),
        myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
        myGymFeedProvider.overrideWith((ref) async => null),
        feedPublicProvider.overrideWith((ref) async => const <Post>[]),
        unreadFromFriendsProvider.overrideWith((ref) => 0),
        notificationHeaderBadgeProvider('u1').overrideWith((ref) => 0),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: FeedScreen(initialTab: initialTab),
          ),
        ),
      ),
    ),
  );
  // pump() explícito y no pumpAndSettle: el feed usa TreinoFadeSlideIn y el
  // settle global no llega nunca.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _settleTabs(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeAnalyticsService analytics;

  setUp(() => analytics = FakeAnalyticsService());

  group('Feed — analytics de FEED / RANKINGS', () {
    testWidgets('al abrir /feed se cuenta la página FEED', (tester) async {
      await _pumpFeed(tester, analytics);

      expect(analytics.subTabsFor('feed'), ['feed']);
    });

    testWidgets('entrar por ?tab=rankings cuenta RANKINGS', (tester) async {
      await _pumpFeed(tester, analytics, initialTab: 'rankings');

      // ESTE es el número que #642 pidió y no se pudo dar. `/feed?tab=rankings`
      // es un deep-link vivo: si la página inicial no contara, todo el que
      // entre por ahí sería invisible.
      expect(analytics.subTabsFor('feed'), ['rankings']);
    });

    testWidgets('cambiar a RANKINGS por swipe cuenta', (tester) async {
      await _pumpFeed(tester, analytics);

      await tester.drag(find.byType(TabBarView), const Offset(-500, 0));
      await _settleTabs(tester);

      expect(analytics.subTabsFor('feed'), ['feed', 'rankings']);
    });

    testWidgets('un PF emite feed una vez, y NUNCA rankings', (tester) async {
      // Comportamiento CONOCIDO y aceptado, no un descuido. `FeedScreen`
      // renderiza el layout de atleta mientras el rol carga —decisión
      // deliberada para evitar un skeleton, ya documentada en el propio
      // widget: "A trainer may see the pill for one frame before their role
      // resolves — acceptable"—. Así que un PF emite un `sub_tab_viewed{feed}`
      // antes de que su rol resuelva.
      //
      // Se evaluó gatear el wrapper con el rol y se descartó: cambia la
      // estructura del árbol al resolver y REMONTA `_FeedPage`, tirando el
      // `AutomaticKeepAliveClientMixin` y reconstruyendo los providers del
      // feed. Ensuciar un evento es más barato que reconstruir la pantalla.
      //
      // Lo que sí importa y este test fija: un PF NUNCA puede emitir
      // `rankings`, que es el número que #642 quiere leer.
      await _pumpFeed(tester, analytics, role: UserRole.trainer);

      expect(analytics.subTabsFor('feed'), ['feed']);
      expect(analytics.subTabsFor('feed'), isNot(contains('rankings')));
    });
  });

  group('Feed — analytics de segmentos', () {
    testWidgets('el segmento inicial se cuenta', (tester) async {
      await _pumpFeed(tester, analytics);

      // Sin esto AMIGOS —que es el default y nunca se tapea— quedaría
      // sistemáticamente subcontado contra GYM y PÚBLICO.
      expect(analytics.subTabsFor('feed_segments'), ['amigos']);
    });

    testWidgets('el segmento inicial reportado es el que está activo',
        (tester) async {
      await _pumpFeed(tester, analytics, segment: FeedSegment.public);

      // `FeedSegment.public` se reporta como `publico`, que es como se llama
      // el segmento en la UI.
      expect(analytics.subTabsFor('feed_segments'), ['publico']);
    });
  });
}
