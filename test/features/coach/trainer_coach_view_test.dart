import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/trainer_coach_view.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      ),
    );

/// Builds a GoRouter test harness with a ShellRoute so TreinoBottomBar is
/// visible AND so context.push() works for sub-routes.
GoRouter _wrapRouter({
  required List<Override> overrides,
  required List<GoRoute> subRoutes,
}) =>
    GoRouter(
      initialLocation: '/coach',
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              Scaffold(body: child, bottomNavigationBar: const SizedBox()),
          routes: [
            GoRoute(
              path: '/coach',
              builder: (_, __) => const TrainerCoachView(),
              routes: subRoutes,
            ),
          ],
        ),
      ],
    );

TrainerLink _link({
  required String id,
  required TrainerLinkStatus status,
  String athleteId = 'a1',
}) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 5, 18, 10, 0),
      acceptedAt: status == TrainerLinkStatus.active
          ? DateTime.utc(2026, 5, 18, 12, 0)
          : null,
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

List<Override> _stubLinks(List<TrainerLink> links) => [
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
      for (final l in links)
        userPublicProfileProvider(l.athleteId)
            .overrideWith((ref) async => _pub(l.athleteId, 'Atleta ${l.id}')),
    ];

void main() {
  group('TrainerCoachView — structure', () {
    testWidgets('renders 4 sub-tab labels in a TabBar', (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: _stubLinks(const []),
      ));
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD'), findsWidgets);
      expect(find.text('ALUMNOS'), findsWidgets);
      expect(find.text('AGENDA'), findsWidgets);
      expect(find.text('COMUNIDADES'), findsWidgets);
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('AGENDA y COMUNIDADES siguen como placeholder', (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: _stubLinks(const []),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AGENDA'));
      await tester.pumpAndSettle();
      expect(find.text('PRÓXIMAMENTE'), findsOneWidget);
    });
  });

  group('TrainerCoachView — DASHBOARD tab', () {
    testWidgets(
        'REQ-COACH-LINK-101: sin requests → muestra hint "sin solicitudes"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: _stubLinks(const []),
      ));
      await tester.pumpAndSettle();

      expect(find.text('SOLICITUDES PENDIENTES'), findsOneWidget);
      expect(find.text('Sin solicitudes nuevas por ahora.'), findsOneWidget);
    });

    testWidgets(
        'REQ-COACH-LINK-102: con request pending → muestra card con ACEPTAR/RECHAZAR',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: _stubLinks([
          _link(id: 'l1', status: TrainerLinkStatus.pending, athleteId: 'a1'),
        ]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Atleta l1'), findsOneWidget);
      expect(find.text('ACEPTAR'), findsOneWidget);
      expect(find.text('RECHAZAR'), findsOneWidget);
    });

    testWidgets(
        'REQ-COACH-LINK-103: contador refleja cantidad de active alumnos',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: _stubLinks([
          _link(id: 'l1', status: TrainerLinkStatus.active, athleteId: 'a1'),
          _link(id: 'l2', status: TrainerLinkStatus.active, athleteId: 'a2'),
        ]),
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Tenés 2 alumnos activos'),
        findsOneWidget,
      );
    });
  });

  group('TrainerCoachView — ALUMNOS tab', () {
    testWidgets('REQ-COACH-LINK-201: sin active → muestra empty state',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: _stubLinks(const []),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();

      expect(find.text('Sin alumnos activos todavía.'), findsOneWidget);
    });

    testWidgets(
        'REQ-COACH-LINK-202: con active → lista cards con TERMINAR VÍNCULO',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: _stubLinks([
          _link(id: 'l1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ]),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();

      expect(find.text('Atleta l1'), findsOneWidget);
      expect(find.text('TERMINAR VÍNCULO'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-454: tapping _ActiveAlumnoCard navigates to /coach/athlete/:athleteId',
        (tester) async {
      final router = _wrapRouter(
        overrides: [],
        subRoutes: [
          GoRoute(
            path: 'athlete/:athleteId',
            builder: (_, state) => Scaffold(
              body: Text('Athlete:${state.pathParameters['athleteId']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: _stubLinks([
            _link(id: 'l1', status: TrainerLinkStatus.active, athleteId: 'a1'),
          ]),
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();
      // Navigate to ALUMNOS tab
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();

      // Tap on the card area (not the TERMINAR VÍNCULO button)
      // The card has an InkWell wrapping the athlete name area
      await tester.tap(find.text('Atleta l1'));
      await tester.pumpAndSettle();

      expect(find.text('Athlete:a1'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-454 (triangulate): TERMINAR VÍNCULO button still works after InkWell wrap',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: _stubLinks([
          _link(id: 'l1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ]),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();

      // The TERMINAR VÍNCULO button must still be findable and tappable
      expect(find.text('TERMINAR VÍNCULO'), findsOneWidget);
      // Tapping it should show the confirmation dialog
      await tester.tap(find.text('TERMINAR VÍNCULO'));
      await tester.pumpAndSettle();
      expect(find.text('Terminar vínculo'), findsOneWidget);
    });
  });
}
