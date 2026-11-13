import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_segmented_pill.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/agenda_providers.dart'
    show appointmentRepositoryProvider;
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/trainer_coach_view.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

class _MockLinkRepo extends Mock implements TrainerLinkRepository {}

class _MockTurnos extends Mock implements AppointmentRepository {}

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  // es-AR es el locale de la app; por default queda el del test (inglés).
  Locale? locale,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: locale,
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

/// Los turnos del PF en un Firestore fake (por default, vacío): «Terminar
/// vínculo» cuenta y cancela los turnos futuros del alumno (#1792).
Override _stubTurnos([FakeFirebaseFirestore? db]) =>
    appointmentRepositoryProvider.overrideWithValue(
      AppointmentRepository(firestore: db ?? FakeFirebaseFirestore()),
    );

List<Override> _stubLinks(List<TrainerLink> links,
        {FakeFirebaseFirestore? turnosDb}) =>
    [
      _stubTurnos(turnosDb),
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
      for (final l in links)
        userPublicProfileProvider(l.athleteId).overrideWith(
            (ref) => Stream.value(_pub(l.athleteId, 'Atleta ${l.id}'))),
    ];

void main() {
  group('TrainerCoachView — structure', () {
    testWidgets('renders 2 sub-tab labels (DASHBOARD moved to HOME tab)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: _stubLinks(const []),
      ));
      await tester.pumpAndSettle();

      // DASHBOARD moved to the HOME bottom-bar tab — not present here.
      // COMUNIDADES removed entirely (2026-06-10).
      expect(find.text('DASHBOARD'), findsNothing);
      expect(find.text('ALUMNOS'), findsWidgets);
      expect(find.text('AGENDA'), findsWidgets);
      expect(find.text('COMUNIDADES'), findsNothing);
      // The shared kit component, not just any TabBar: the inline copy this
      // replaced also satisfied findsOneWidget, so reverting the migration
      // would otherwise leave the whole suite green (#646).
      expect(find.byType(TreinoSegmentedPill), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets(
        'initialTab="agenda" sets DefaultTabController.initialIndex to 1',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(initialTab: 'agenda'),
        overrides: _stubLinks(const []),
      ));
      // First-frame only — avoid pumpAndSettle so unstubbed agenda streams
      // can't time out the test. We only verify the TabController landed
      // on the AGENDA index (1), not its content.
      await tester.pump();

      final controller =
          DefaultTabController.of(tester.element(find.byType(TabBar)));
      expect(controller.index, 1);
    });

    testWidgets(
        'initialTab="comunidades" (legado, p.ej. deep-link viejo) cae en ALUMNOS',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(initialTab: 'comunidades'),
        overrides: _stubLinks(const []),
      ));
      await tester.pump();

      final controller =
          DefaultTabController.of(tester.element(find.byType(TabBar)));
      expect(controller.index, 0,
          reason: 'el tab COMUNIDADES fue eliminado — cualquier query param '
              'desconocido debe caer al default (ALUMNOS)');
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
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
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

  // ── Unread dot on alumno card ─────────────────────────────────────────────

  group('TrainerCoachView — unread dot on alumno card', () {
    List<Override> stubLinksWithUnread(
      List<TrainerLink> links, {
      required bool hasUnread,
    }) =>
        [
          trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
          for (final l in links) ...[
            userPublicProfileProvider(l.athleteId).overrideWith(
                (ref) => Stream.value(_pub(l.athleteId, 'Atleta ${l.id}'))),
            hasUnreadFromProvider(l.athleteId).overrideWith((ref) => hasUnread),
          ],
        ];

    testWidgets(
        'hasUnreadFromProvider true → unread dot rendered on alumno card',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: stubLinksWithUnread(
          [_link(id: 'l1', status: TrainerLinkStatus.active, athleteId: 'a1')],
          hasUnread: true,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();

      // The unread dot is a small circle Container with key 'unread-dot-a1'
      expect(find.byKey(const Key('unread-dot-a1')), findsOneWidget);
    });

    testWidgets('hasUnreadFromProvider false → no unread dot on alumno card',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: stubLinksWithUnread(
          [_link(id: 'l1', status: TrainerLinkStatus.active, athleteId: 'a1')],
          hasUnread: false,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unread-dot-a1')), findsNothing);
    });
  });

  // ── Turnos futuros al terminar el vínculo (#1792) ─────────────────────────
  group('TrainerCoachView — TERMINAR VÍNCULO y los turnos futuros', () {
    final futuro = DateTime.utc(2099, 1, 1, 10);

    Future<void> seedTurno(
      FakeFirebaseFirestore db,
      String id,
      DateTime at, {
      String athlete = 'a1',
    }) =>
        db.collection('appointments').doc(id).set(Appointment(
              id: id,
              trainerId: 'trainer-1',
              athleteId: athlete,
              athleteDisplayName: 'Atleta',
              startsAt: at,
              durationMin: 60,
              status: AppointmentStatus.confirmed,
            ).toJson());

    Future<String> statusOf(FakeFirebaseFirestore db, String id) async =>
        (await db.collection('appointments').doc(id).get()).data()!['status']
            as String;

    Future<void> abrirDialogo(
      WidgetTester tester, {
      required FakeFirebaseFirestore db,
      TrainerLinkRepository? repo,
    }) async {
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        locale: const Locale('es', 'AR'),
        overrides: [
          ..._stubLinks(
            [_link(id: 'l1', status: TrainerLinkStatus.active)],
            turnosDb: db,
          ),
          if (repo != null)
            trainerLinkRepositoryProvider.overrideWithValue(repo),
        ],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TERMINAR VÍNCULO'));
      await tester.pumpAndSettle();
    }

    testWidgets('el diálogo avisa cuántos turnos se cancelan', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedTurno(db, 't1', futuro);
      await seedTurno(db, 't2', futuro.add(const Duration(days: 1)));
      await seedTurno(db, 'viejo', DateTime.utc(2020, 1, 1, 10));
      await seedTurno(db, 'ajeno', futuro, athlete: 'otro');

      await abrirDialogo(tester, db: db);

      expect(
        find.textContaining(
          'También se cancelan 2 sesiones agendadas con este alumno',
        ),
        findsOneWidget,
      );
    });

    testWidgets('al confirmar cancela los turnos futuros Y termina el vínculo',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await seedTurno(db, 't1', futuro);
      await seedTurno(db, 'ajeno', futuro, athlete: 'otro');
      final repo = _MockLinkRepo();
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});

      await abrirDialogo(tester, db: db, repo: repo);
      await tester.tap(find.text('Terminar'));
      await tester.pumpAndSettle();

      expect(await statusOf(db, 't1'), 'cancelled');
      expect(await statusOf(db, 'ajeno'), 'confirmed');
      verify(() => repo.terminate('l1', reason: 'trainer-terminated'))
          .called(1);
    });

    testWidgets(
        'si no se pueden cancelar los turnos, el vínculo NO se termina y el '
        'toast lo dice', (tester) async {
      final turnos = _MockTurnos();
      when(() => turnos.listFutureConfirmedForPair(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
          )).thenThrow(Exception('sin red'));
      when(() => turnos.cancelFutureForPair(
            trainerId: any(named: 'trainerId'),
            athleteId: any(named: 'athleteId'),
            actorUid: any(named: 'actorUid'),
            reason: any(named: 'reason'),
          )).thenThrow(Exception('sin red'));
      final repo = _MockLinkRepo();
      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        locale: const Locale('es', 'AR'),
        overrides: [
          ..._stubLinks([_link(id: 'l1', status: TrainerLinkStatus.active)]),
          appointmentRepositoryProvider.overrideWithValue(turnos),
          trainerLinkRepositoryProvider.overrideWithValue(repo),
        ],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TERMINAR VÍNCULO'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No pudimos revisar'), findsOneWidget);

      await tester.tap(find.text('Terminar'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.terminate(any(), reason: any(named: 'reason')));
      expect(find.textContaining('el vínculo sigue activo'), findsOneWidget);
    });
  });

  // ── Silent-failure guard (QA H5) ──────────────────────────────────────────
  //
  // TERMINAR/PAUSAR/REANUDAR corrían `await action()` sin try/catch: si el
  // repo lanzaba (permission-denied, rules), la excepción escapaba como async
  // no capturada → fatal en Crashlytics, y el PF no veía nada. Ahora falla con
  // un SnackBar.
  group('TrainerCoachView — acciones de vínculo con feedback en error', () {
    testWidgets(
        'TERMINAR VÍNCULO que falla muestra SnackBar en vez de tragar el error',
        (tester) async {
      final repo = _MockLinkRepo();
      when(() => repo.terminate(any(), reason: any(named: 'reason')))
          .thenThrow(Exception('permission-denied'));

      await tester.pumpWidget(_wrap(
        const TrainerCoachView(),
        overrides: [
          ..._stubLinks([
            _link(id: 'l1', status: TrainerLinkStatus.active, athleteId: 'a1'),
          ]),
          trainerLinkRepositoryProvider.overrideWithValue(repo),
        ],
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALUMNOS'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TERMINAR VÍNCULO'));
      await tester.pumpAndSettle();
      // Confirmar en el diálogo.
      await tester.tap(find.text('Terminar'));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos actualizar el vínculo. Probá de nuevo.'),
        findsOneWidget,
      );
    });
  });
}
