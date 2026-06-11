// Tests for HistorialSection widget — SCENARIO-355..365
// REQ-HIST-001..008
// TDD RED: HistorialSection import not resolved → tests fail.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/presentation/widgets/historial_section.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

Session _makeSession({
  String id = 's1',
  String routineName = 'Push A',
  SessionStatus status = SessionStatus.finished,
  bool wasFullyCompleted = true,
  double totalVolumeKg = 100.0,
  int durationMin = 45,
  DateTime? startedAt,
}) =>
    Session(
      id: id,
      uid: 'test-uid',
      routineId: 'r1',
      routineName: routineName,
      startedAt: startedAt ?? DateTime(2025, 11, 26, 10, 30),
      finishedAt: DateTime(2025, 11, 26, 11, 15),
      totalVolumeKg: totalVolumeKg,
      durationMin: durationMin,
      status: status,
      dayNumber: 1,
      wasFullyCompleted: wasFullyCompleted,
    );

// ── Test helper ───────────────────────────────────────────────────────────────

/// Pumps a [HistorialSection] inside a GoRouter + ProviderScope so navigation
/// assertions work. [sessions] override [sessionsByUidProvider]; set
/// [loading] or [error] to test those states.
Future<void> _pumpHistorialSection(
  WidgetTester tester, {
  List<Session> sessions = const [],
  String uid = 'test-uid',
  bool loading = false,
  bool error = false,
  List<GoRoute> extraRoutes = const [],
}) async {
  final router = GoRouter(
    initialLocation: '/workout',
    routes: [
      GoRoute(
        path: '/workout',
        builder: (_, __) => const Scaffold(
          body: SingleChildScrollView(
            child: HistorialSection(),
          ),
        ),
      ),
      GoRoute(
        path: '/workout/historial/:sessionId',
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('Detalle'))),
      ),
      ...extraRoutes,
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        sessionsByUidProvider.overrideWith((ref, arg) {
          if (loading) return Completer<List<Session>>().future;
          if (error) return Future.error(Exception('network'));
          return Future.value(sessions);
        }),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('HistorialSection', () {
    // SCENARIO-355: widget mounts without parameters
    testWidgets('SCENARIO-355: HistorialSection mounts without parameters',
        (tester) async {
      await _pumpHistorialSection(tester, sessions: []);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(HistorialSection), findsOneWidget);
    });

    // SCENARIO-356: two finished sessions render in newest-first order
    testWidgets(
        'SCENARIO-356: two finished sessions render newest-first (by startedAt)',
        (tester) async {
      final older = _makeSession(
        id: 's-old',
        routineName: 'Legs',
        startedAt: DateTime(2025, 11, 20),
      );
      final newer = _makeSession(
        id: 's-new',
        routineName: 'Push A',
        startedAt: DateTime(2025, 11, 26),
      );
      // Provider returns newest-first (repo contract)
      await _pumpHistorialSection(tester, sessions: [newer, older]);
      await tester.pumpAndSettle();

      final legsPos = tester.getTopLeft(find.text('Legs')).dy;
      final pushPos = tester.getTopLeft(find.text('Push A')).dy;
      // Push A (newer) should appear before Legs (older) — lower dy
      expect(pushPos, lessThan(legsPos));
    });

    // SCENARIO-357: mixed list renders only finished session
    testWidgets('SCENARIO-357: only finished sessions are rendered',
        (tester) async {
      final finished = _makeSession(
        id: 's-fin',
        routineName: 'Push A',
        status: SessionStatus.finished,
      );
      final active = _makeSession(
        id: 's-act',
        routineName: 'Active Session',
        status: SessionStatus.active,
      );
      await _pumpHistorialSection(tester, sessions: [finished, active]);
      await tester.pumpAndSettle();

      expect(find.text('Push A'), findsOneWidget);
      expect(find.text('Active Session'), findsNothing);
    });

    // SCENARIO-358: all-unfinished triggers empty state text
    testWidgets('SCENARIO-358: all-active list triggers empty state',
        (tester) async {
      final active = _makeSession(
        id: 's-act',
        routineName: 'Active',
        status: SessionStatus.active,
      );
      await _pumpHistorialSection(tester, sessions: [active]);
      await tester.pumpAndSettle();

      expect(find.text('Todavía no entrenaste.'), findsOneWidget);
    });

    // SCENARIO-359: card renders routineName + formatted date + kg + min
    testWidgets('SCENARIO-359: card renders routineName + date + kg + min',
        (tester) async {
      final session = _makeSession(
        routineName: 'Push A',
        totalVolumeKg: 100.0,
        durationMin: 45,
        startedAt: DateTime(2025, 11, 26), // Mié 26 nov
      );
      await _pumpHistorialSection(tester, sessions: [session]);
      await tester.pumpAndSettle();

      expect(find.text('Push A'), findsOneWidget);
      expect(find.textContaining('Mié'), findsOneWidget);
      expect(find.textContaining('100.0'), findsOneWidget);
      expect(find.textContaining('45'), findsOneWidget);
    });

    // SCENARIO-360: abandoned sessions (wasFullyCompleted=false) are filtered out
    testWidgets(
        'SCENARIO-360: abandoned sessions (wasFullyCompleted=false) are filtered out',
        (tester) async {
      final completed = _makeSession(
        id: 's-comp',
        routineName: 'Push A',
        wasFullyCompleted: true,
      );
      final abandoned = _makeSession(
        id: 's-aban',
        routineName: 'Pull B',
        wasFullyCompleted: false,
      );
      await _pumpHistorialSection(tester, sessions: [completed, abandoned]);
      await tester.pumpAndSettle();

      // Only the completed session appears
      expect(find.text('Push A'), findsOneWidget);
      expect(find.text('Pull B'), findsNothing);
    });

    // SCENARIO-361: empty list renders empty message + CTA button
    testWidgets('SCENARIO-361: empty list renders empty message + CTA button',
        (tester) async {
      await _pumpHistorialSection(tester, sessions: []);
      await tester.pumpAndSettle();

      expect(find.text('Todavía no entrenaste.'), findsOneWidget);
      expect(find.text('Empezar entrenamiento'), findsOneWidget);
    });

    // SCENARIO-362: tapping CTA goes to /workout
    testWidgets('SCENARIO-362: tapping CTA button navigates to /workout',
        (tester) async {
      await _pumpHistorialSection(tester, sessions: []);
      await tester.pumpAndSettle();

      // After tap on CTA, router stays at /workout (context.go('/workout'))
      await tester.tap(find.text('Empezar entrenamiento'));
      await tester.pumpAndSettle();

      // The workout page is still visible (go to same route)
      expect(find.byType(HistorialSection), findsOneWidget);
    });

    // SCENARIO-363: AsyncLoading renders CircularProgressIndicator, no cards
    testWidgets(
        'SCENARIO-363: AsyncLoading shows CircularProgressIndicator, no cards',
        (tester) async {
      await _pumpHistorialSection(tester, loading: true);
      await tester.pump(); // single pump — stays loading

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Push A'), findsNothing);
    });

    // SCENARIO-364: AsyncError renders error text + retry button
    testWidgets('SCENARIO-364: AsyncError renders error text + retry button',
        (tester) async {
      await _pumpHistorialSection(tester, error: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No pudimos cargar tu historial.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    // SCENARIO-365: card tap navigates to /workout/historial/:sessionId
    testWidgets(
        'SCENARIO-365: tapping card navigates to /workout/historial/:sessionId',
        (tester) async {
      final session = _makeSession(id: 'session-abc', routineName: 'Push A');
      await _pumpHistorialSection(tester, sessions: [session]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Push A'));
      await tester.pumpAndSettle();

      expect(find.text('Detalle'), findsOneWidget);
    });

    // ── Expand / collapse toggle ────────────────────────────────────────────

    /// Builds N completed sessions with unique routineNames so we can count
    /// rendered cards via find.text per name.
    List<Session> manySessions(int n) => List.generate(
          n,
          (i) => _makeSession(
            id: 's$i',
            routineName: 'Rutina $i',
            startedAt: DateTime(2025, 11, 30 - i),
          ),
        );

    // SCENARIO-367: collapsed by default — shows max 5 cards + "Ver más (N)"
    testWidgets(
        'SCENARIO-367: with 8 sessions, collapsed view shows 5 cards + "Ver más (3)"',
        (tester) async {
      await _pumpHistorialSection(tester, sessions: manySessions(8));
      await tester.pumpAndSettle();

      // The first 5 cards are visible
      for (var i = 0; i < 5; i++) {
        expect(find.text('Rutina $i'), findsOneWidget);
      }
      // The last 3 are hidden
      for (var i = 5; i < 8; i++) {
        expect(find.text('Rutina $i'), findsNothing);
      }
      // "Ver más (3)" toggle button is visible
      expect(
        find.text('Ver más (3)'),
        findsOneWidget,
      );
    });

    // SCENARIO-368: tap "Ver más" expands to show all sessions
    testWidgets(
        'SCENARIO-368: tapping "Ver más" expands to show all 8 sessions',
        (tester) async {
      await _pumpHistorialSection(tester, sessions: manySessions(8));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver más (3)'));
      await tester.pumpAndSettle();

      // All 8 cards visible
      for (var i = 0; i < 8; i++) {
        expect(find.text('Rutina $i'), findsOneWidget);
      }
      // Button now says "Ver menos"
      expect(find.text('Ver menos'), findsOneWidget);
    });

    // SCENARIO-369: tap "Ver menos" collapses back to 5
    testWidgets('SCENARIO-369: tapping "Ver menos" collapses back to 5 cards',
        (tester) async {
      await _pumpHistorialSection(tester, sessions: manySessions(8));
      await tester.pumpAndSettle();

      // Expand
      await tester.tap(find.text('Ver más (3)'));
      await tester.pumpAndSettle();

      // Collapse
      await tester.tap(find.text('Ver menos'));
      await tester.pumpAndSettle();

      // Back to first 5 visible
      for (var i = 0; i < 5; i++) {
        expect(find.text('Rutina $i'), findsOneWidget);
      }
      for (var i = 5; i < 8; i++) {
        expect(find.text('Rutina $i'), findsNothing);
      }
    });

    // SCENARIO-370: when sessions <= 5, no toggle button is rendered
    testWidgets(
        'SCENARIO-370: with 5 sessions (exactly limit), no toggle is rendered',
        (tester) async {
      await _pumpHistorialSection(tester, sessions: manySessions(5));
      await tester.pumpAndSettle();

      // All 5 visible
      for (var i = 0; i < 5; i++) {
        expect(find.text('Rutina $i'), findsOneWidget);
      }
      // No "Ver más" / "Ver menos" anywhere
      expect(find.textContaining('Ver más'), findsNothing);
      expect(find.text('Ver menos'), findsNothing);
    });

    // SCENARIO-371: with 3 sessions (under limit), no toggle is rendered
    testWidgets(
        'SCENARIO-371: with 3 sessions (under limit), no toggle is rendered',
        (tester) async {
      await _pumpHistorialSection(tester, sessions: manySessions(3));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        expect(find.text('Rutina $i'), findsOneWidget);
      }
      expect(find.textContaining('Ver más'), findsNothing);
    });
  });
}
