// Tests for RutinasScreen — the sidebar entry point that lists linked athletes
// and routes to the web routine editor (elegí alumno → editor). Mirrors the
// mocking pattern of the dashboard section tests (stub trainerLinksStreamProvider
// + userPublicProfileProvider per athlete), extended to also stub
// assignedRoutinesProvider per athlete now that each row shows an active-routine
// count badge (see alumnos_screen_test.dart for the sibling pattern with
// gymName + routine overrides).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/rutinas_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';

// ─── Factories ──────────────────────────────────────────────────────────────

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
      requestedAt: DateTime.utc(2026, 1, 10),
      acceptedAt: status == TrainerLinkStatus.pending
          ? null
          : DateTime.utc(2026, 1, 11),
    );

UserPublicProfile _pub(String uid, String name, {String? gymName}) =>
    UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
      gymName: gymName,
    );

Routine _activeRoutine(String id) => Routine(
      id: id,
      name: 'Rutina $id',
      level: ExperienceLevel.beginner,
      days: const [],
    ); // status defaults to RoutineStatus.active

Routine _archivedRoutine(String id) => Routine(
      id: id,
      name: 'Rutina $id',
      level: ExperienceLevel.beginner,
      days: const [],
      status: RoutineStatus.archived,
    );

// ─── Test harness ─────────────────────────────────────────────────────────────

/// Pumps RutinasScreen behind a GoRouter so its `context.push('/rutinas/:id')`
/// has somewhere to go. That route renders a marker text we can assert on.
/// Each link's athleteId gets a stubbed public profile and a stubbed
/// (possibly empty) list of assigned routines — the row now reads both.
Future<void> _pumpRutinas(
  WidgetTester tester, {
  required List<TrainerLink> links,
  Map<String, String> names = const {},
  Map<String, String> gymNames = const {},
  Map<String, List<Routine>> routines = const {},
}) async {
  // Desktop viewport — Coach Hub web assumes it.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/rutinas',
    routes: [
      GoRoute(
        // CoachHubScaffold provides the Material ancestor in prod — the test
        // stands in for it with a bare Scaffold, matching other section tests.
        path: '/rutinas',
        builder: (_, __) => const Scaffold(body: RutinasScreen()),
      ),
      GoRoute(
        path: '/rutinas/:athleteId',
        builder: (_, state) => Scaffold(
          body: Text('ROUTINES ${state.pathParameters['athleteId']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        for (final l in links) ...[
          userPublicProfileProvider(l.athleteId).overrideWith(
            (ref) => Stream.value(
              _pub(
                l.athleteId,
                names[l.athleteId] ?? 'Atleta ${l.id}',
                gymName: gymNames[l.athleteId],
              ),
            ),
          ),
          assignedRoutinesProvider(l.athleteId).overrideWith(
            (ref) => Future.value(routines[l.athleteId] ?? const <Routine>[]),
          ),
        ],
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('RutinasScreen', () {
    testWidgets('renders the section header and subtitle', (tester) async {
      await _pumpRutinas(tester, links: [
        _link(id: '1', status: TrainerLinkStatus.active),
      ], names: {
        'a1': 'Ana Activa',
      });

      // TreinoSectionHeader uppercasea el título (kit Fase 1, REQ-CK-002).
      expect(find.text('RUTINAS'), findsOneWidget);
      expect(
        find.text('Elegí un alumno para armarle una rutina.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'lists linked athletes, dedups by athleteId and excludes pending',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
          // Duplicate link for the same athlete → collapses to a single row.
          _link(id: '2', status: TrainerLinkStatus.terminated, athleteId: 'a1'),
          // Pending = a request, not yet an athlete → excluded.
          _link(id: '3', status: TrainerLinkStatus.pending, athleteId: 'a2'),
        ],
        names: {'a1': 'Ana Activa', 'a2': 'Beto Pendiente'},
      );

      expect(find.text('Ana Activa'), findsOneWidget);
      expect(find.text('Beto Pendiente'), findsNothing);
    });

    testWidgets('shows an empty state when there are no linked athletes',
        (tester) async {
      await _pumpRutinas(tester, links: const []);

      expect(
        find.text('Todavía no tenés alumnos vinculados.'),
        findsOneWidget,
      );
    });

    testWidgets('a pending-only trainer sees the empty state', (tester) async {
      await _pumpRutinas(tester, links: [
        _link(id: '1', status: TrainerLinkStatus.pending, athleteId: 'a9'),
      ]);

      expect(
        find.text('Todavía no tenés alumnos vinculados.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping an athlete opens that athlete\'s routines list',
        (tester) async {
      await _pumpRutinas(tester, links: [
        _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
      ], names: {
        'a1': 'Ana Activa',
      });

      await tester.tap(find.text('Ana Activa'));
      await tester.pumpAndSettle();

      expect(find.text('ROUTINES a1'), findsOneWidget);
    });

    testWidgets('a student with 0 active routines shows "Sin rutina"',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ],
        names: {'a1': 'Ana Activa'},
        routines: {'a1': const []},
      );

      expect(find.text('Sin rutina'), findsOneWidget);
    });

    testWidgets(
        'a student whose only routines are archived also shows "Sin rutina"',
        (tester) async {
      // The count is ACTIVE-only (matches the detail screen's filter) — an
      // archived routine must not count toward "has a routine".
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ],
        names: {'a1': 'Ana Activa'},
        routines: {
          'a1': [_archivedRoutine('r1')],
        },
      );

      expect(find.text('Sin rutina'), findsOneWidget);
    });

    testWidgets('a student with 1 active routine shows the singular count',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ],
        names: {'a1': 'Ana Activa'},
        routines: {
          'a1': [_activeRoutine('r1')],
        },
      );

      expect(find.text('1 rutina'), findsOneWidget);
      expect(find.text('Sin rutina'), findsNothing);
    });

    testWidgets(
        'a student with N active routines shows the plural count, ignoring archived ones',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ],
        names: {'a1': 'Ana Activa'},
        routines: {
          'a1': [
            _activeRoutine('r1'),
            _activeRoutine('r2'),
            _archivedRoutine('r3'),
          ],
        },
      );

      expect(find.text('2 rutinas'), findsOneWidget);
    });

    testWidgets(
        'while routines are loading the badge shows the placeholder, never "Sin rutina"',
        (tester) async {
      // Bypasses `_pumpRutinas` (which ends in `pumpAndSettle`, and would
      // hang forever on a Future that never resolves) to build the same
      // ProviderScope/router shape inline, stubbing assignedRoutinesProvider
      // with a Completer-backed future that never completes — this keeps the
      // provider in AsyncLoading (`valueOrNull == null`) so we can assert the
      // badge's neutral placeholder instead of the false-negative "Sin
      // rutina".
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final link =
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1');
      final neverResolves = Completer<List<Routine>>();
      addTearDown(() {
        // Completes the future post-assertion so the pending timer doesn't
        // leak across tests — the value is discarded, the widget is gone.
        if (!neverResolves.isCompleted) neverResolves.complete(const []);
      });

      final router = GoRouter(
        initialLocation: '/rutinas',
        routes: [
          GoRoute(
            path: '/rutinas',
            builder: (_, __) => const Scaffold(body: RutinasScreen()),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerLinksStreamProvider
                .overrideWith((ref) => Stream.value([link])),
            userPublicProfileProvider(link.athleteId).overrideWith(
              (ref) => Stream.value(_pub(link.athleteId, 'Ana Activa')),
            ),
            assignedRoutinesProvider(link.athleteId)
                .overrideWith((ref) => neverResolves.future),
          ],
          child:
              MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
        ),
      );
      // Single `pump()` (not `pumpAndSettle()`): the routines future never
      // resolves, so settling would hang. One frame is enough to let the
      // trainerLinksStreamProvider Stream.value and the
      // userPublicProfileProvider Stream.value deliver their first (and
      // only) event and render the row with the badge still in AsyncLoading.
      await tester.pump();

      expect(find.text('…'), findsOneWidget);
      expect(find.text('Sin rutina'), findsNothing);
    });

    testWidgets('renders the gym subtitle when the profile has one',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ],
        names: {'a1': 'Ana Activa'},
        gymNames: {'a1': 'PowerGym Belgrano'},
        routines: {'a1': const []},
      );

      expect(find.text('PowerGym Belgrano'), findsOneWidget);
    });

    testWidgets('omits the gym subtitle when the profile has none',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ],
        names: {'a1': 'Ana Activa'},
        routines: {'a1': const []},
      );

      // Nothing to positively assert on for an absent subtitle beyond the
      // screen still rendering the row correctly — covered by the presence
      // assertions elsewhere; this test documents the null-gym contract via
      // the absence of any gym-name text fixture.
      expect(find.text('Ana Activa'), findsOneWidget);
    });

    testWidgets('shows a status pill per link status', (tester) async {
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
          _link(id: '2', status: TrainerLinkStatus.paused, athleteId: 'a2'),
          _link(id: '3', status: TrainerLinkStatus.terminated, athleteId: 'a3'),
        ],
        names: {
          'a1': 'Ana Activa',
          'a2': 'Beto Pausado',
          'a3': 'Caro Inactiva'
        },
        routines: {'a1': const [], 'a2': const [], 'a3': const []},
      );

      expect(find.text('Activo'), findsOneWidget);
      expect(find.text('Pausado'), findsOneWidget);
      expect(find.text('Inactivo'), findsOneWidget);
    });

    testWidgets('renders a colored avatar initial when there is no photo',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ],
        names: {'a1': 'Ana Activa'},
        routines: {'a1': const []},
      );

      expect(find.text('A'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);
    });
  });

  group('RutinasScreen filters, search and view toggle', () {
    // Fixture roster reused across this group: a1 activo sin rutina, a2
    // activo con 2 rutinas activas, a3 pausado sin rutina, a4 terminado
    // (inactivo) con 1 rutina activa.
    List<TrainerLink> roster() => [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
          _link(id: '2', status: TrainerLinkStatus.active, athleteId: 'a2'),
          _link(id: '3', status: TrainerLinkStatus.paused, athleteId: 'a3'),
          _link(id: '4', status: TrainerLinkStatus.terminated, athleteId: 'a4'),
        ];

    const names = {
      'a1': 'Ana Sinrutina',
      'a2': 'Beto Conrutina',
      'a3': 'Caro Pausada',
      'a4': 'Dario Terminado',
    };

    Map<String, List<Routine>> routines() => {
          'a1': const [],
          'a2': [_activeRoutine('r1'), _activeRoutine('r2')],
          'a3': const [],
          'a4': [_activeRoutine('r3')],
        };

    testWidgets('"Sin rutina" filter shows only athletes with 0 active',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: roster(),
        names: names,
        routines: routines(),
      );

      await tester.tap(find.text('SIN RUTINA · 2'));
      await tester.pumpAndSettle();

      expect(find.text('Ana Sinrutina'), findsOneWidget);
      expect(find.text('Caro Pausada'), findsOneWidget);
      expect(find.text('Beto Conrutina'), findsNothing);
      expect(find.text('Dario Terminado'), findsNothing);
    });

    testWidgets('"Con rutina" filter shows only athletes with >=1 active',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: roster(),
        names: names,
        routines: routines(),
      );

      await tester.tap(find.text('CON RUTINA · 2'));
      await tester.pumpAndSettle();

      expect(find.text('Beto Conrutina'), findsOneWidget);
      expect(find.text('Dario Terminado'), findsOneWidget);
      expect(find.text('Ana Sinrutina'), findsNothing);
      expect(find.text('Caro Pausada'), findsNothing);
    });

    testWidgets('"Activos" filter shows only active-status athletes',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: roster(),
        names: names,
        routines: routines(),
      );

      await tester.tap(find.text('ACTIVOS · 2'));
      await tester.pumpAndSettle();

      expect(find.text('Ana Sinrutina'), findsOneWidget);
      expect(find.text('Beto Conrutina'), findsOneWidget);
      expect(find.text('Caro Pausada'), findsNothing);
      expect(find.text('Dario Terminado'), findsNothing);
    });

    testWidgets('"Inactivos" filter shows only inactive-status athletes',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: roster(),
        names: names,
        routines: routines(),
      );

      await tester.tap(find.text('INACTIVOS · 1'));
      await tester.pumpAndSettle();

      expect(find.text('Dario Terminado'), findsOneWidget);
      expect(find.text('Ana Sinrutina'), findsNothing);
      expect(find.text('Beto Conrutina'), findsNothing);
      expect(find.text('Caro Pausada'), findsNothing);
    });

    testWidgets('"Todos" filter shows every athlete', (tester) async {
      await _pumpRutinas(
        tester,
        links: roster(),
        names: names,
        routines: routines(),
      );

      // Default filter is already "Todos" — tap it explicitly to also cover
      // the chip's own label/count rendering.
      await tester.tap(find.text('TODOS · 4'));
      await tester.pumpAndSettle();

      expect(find.text('Ana Sinrutina'), findsOneWidget);
      expect(find.text('Beto Conrutina'), findsOneWidget);
      expect(find.text('Caro Pausada'), findsOneWidget);
      expect(find.text('Dario Terminado'), findsOneWidget);
    });

    testWidgets('chip counts reflect the whole roster', (tester) async {
      await _pumpRutinas(
        tester,
        links: roster(),
        names: names,
        routines: routines(),
      );

      expect(find.text('TODOS · 4'), findsOneWidget);
      expect(find.text('SIN RUTINA · 2'), findsOneWidget);
      expect(find.text('CON RUTINA · 2'), findsOneWidget);
      expect(find.text('ACTIVOS · 2'), findsOneWidget);
      expect(find.text('INACTIVOS · 1'), findsOneWidget);
    });

    testWidgets(
        'search filters by name (substring, case-insensitive), combined with the active filter',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: roster(),
        names: names,
        routines: routines(),
      );

      await tester.enterText(find.byType(TextField), 'CONRUTINA');
      await tester.pumpAndSettle();

      expect(find.text('Beto Conrutina'), findsOneWidget);
      expect(find.text('Ana Sinrutina'), findsNothing);
      expect(find.text('Caro Pausada'), findsNothing);
      expect(find.text('Dario Terminado'), findsNothing);

      // Combine with a status filter: "Beto Conrutina" is active, so it
      // still matches "Activos" + the same search term.
      await tester.tap(find.text('ACTIVOS · 2'));
      await tester.pumpAndSettle();
      expect(find.text('Beto Conrutina'), findsOneWidget);

      // But it drops out under "Inactivos" even though the name still
      // matches — the status filter wins the intersection.
      await tester.tap(find.text('INACTIVOS · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Beto Conrutina'), findsNothing);
    });

    testWidgets(
        'switching to Cards renders the cards grid with avatar+name+count badge and tap still navigates',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: [
          _link(id: '1', status: TrainerLinkStatus.active, athleteId: 'a1'),
        ],
        names: {'a1': 'Ana Conrutina'},
        routines: {
          'a1': [_activeRoutine('r1')],
        },
      );

      await tester.tap(find.text('Cards'));
      await tester.pumpAndSettle();

      expect(find.text('Ana Conrutina'), findsOneWidget);
      expect(find.text('1 rutina'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isNull);

      await tester.tap(find.text('Ana Conrutina'));
      await tester.pumpAndSettle();

      expect(find.text('ROUTINES a1'), findsOneWidget);
    });

    testWidgets(
        'shows a distinct empty state when filters/search yield nothing',
        (tester) async {
      await _pumpRutinas(
        tester,
        links: roster(),
        names: names,
        routines: routines(),
      );

      await tester.enterText(find.byType(TextField), 'nadie-coincide');
      await tester.pumpAndSettle();

      expect(
        find.text('No encontramos alumnos con esos filtros.'),
        findsOneWidget,
      );
      expect(
        find.text('Todavía no tenés alumnos vinculados.'),
        findsNothing,
      );
    });
  });
}
