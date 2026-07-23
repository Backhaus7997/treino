// Tests for RutinasScreen — the sidebar entry point that lists linked athletes
// and routes to the web routine editor (elegí alumno → editor). Mirrors the
// mocking pattern of the dashboard section tests (stub trainerLinksStreamProvider
// + userPublicProfileProvider per athlete).

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
import 'package:treino/features/profile/domain/user_public_profile.dart';

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

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

// ─── Test harness ─────────────────────────────────────────────────────────────

/// Pumps RutinasScreen behind a GoRouter so its `context.push('/rutinas/:id')`
/// has somewhere to go. That route renders a marker text we can assert on.
/// Each link's athleteId gets a stubbed public profile.
Future<void> _pumpRutinas(
  WidgetTester tester, {
  required List<TrainerLink> links,
  Map<String, String> names = const {},
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
        for (final l in links)
          userPublicProfileProvider(l.athleteId).overrideWith(
            (ref) => Stream.value(
              _pub(l.athleteId, names[l.athleteId] ?? 'Atleta ${l.id}'),
            ),
          ),
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
  });
}
