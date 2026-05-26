import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/home/widgets/esta_semana_card.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/weekly_insights.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

WeeklyInsights _makeInsights({
  int sessionsCount = 3,
  int plannedSessionsCount = 5,
  int streak = 5,
  int monthSessionsCount = 12,
  List<bool>? daysTrained,
}) {
  final start = DateTime(2026, 5, 18); // Monday
  return WeeklyInsights(
    weekStart: start,
    weekEnd:
        start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59)),
    daysTrained: daysTrained ?? List<bool>.filled(7, false),
    sessionsCount: sessionsCount,
    plannedSessionsCount: plannedSessionsCount,
    setsByGroup: const {},
    targetByGroup: const {},
    streak: streak,
    monthSessionsCount: monthSessionsCount,
  );
}

/// Wraps EstaSemanaCard with ProviderScope + GoRouter.
///
/// Body wraps the card in `SingleChildScrollView` because the card height
/// (full streak + day strip + 280px body silhouette + period cards) can
/// exceed the default 800x600 test viewport. In production the card lives
/// inside a scrollable Home — the same wrapping pattern.
Widget _wrapCard({required List<Override> overrides, GoRouter? router}) {
  final goRouter = router ??
      GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: EstaSemanaCard()),
          ),
        ),
        GoRoute(
          path: '/home/insights',
          builder: (_, __) => const Scaffold(body: Text('Insights')),
        ),
      ]);

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: goRouter,
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('EstaSemanaCard', () {
    // ── Legacy tests (updated for ConsumerWidget) ─────────────────────────────

    testWidgets(
        'REQ-HOME-SEMANA-001: renders RACHA ACTUAL pill (mockup parity)',
        (tester) async {
      final insights = _makeInsights();
      await tester.pumpWidget(_wrapCard(overrides: [
        weeklyInsightsProvider.overrideWith((_) async => insights),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Loaded state replaces "ESTA SEMANA" header with RACHA ACTUAL pill +
      // SEM N · MMM label per esta-semana.png mockup.
      expect(find.text('RACHA ACTUAL'), findsOneWidget);
      expect(find.textContaining('SEM '), findsOneWidget);
    });

    testWidgets('REQ-HOME-SEMANA-002: card decoration — bgCard, r=20, border',
        (tester) async {
      final insights = _makeInsights();
      await tester.pumpWidget(_wrapCard(overrides: [
        weeklyInsightsProvider.overrideWith((_) async => insights),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final containers =
          tester.widgetList<Container>(find.byType(Container)).toList();
      final styledContainer = containers.firstWhere(
        (c) => c.decoration is BoxDecoration,
      );
      final decoration = styledContainer.decoration as BoxDecoration;
      expect(decoration.borderRadius, equals(BorderRadius.circular(20)));
      expect(decoration.color, equals(AppPalette.mintMagenta.bgCard));
      expect(decoration.border, isNotNull);
    });

    testWidgets('REQ-HOME-SEMANA-003: tap en la card pushea /home/insights',
        (tester) async {
      final insights = _makeInsights();
      String? pushedLocation;

      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: EstaSemanaCard()),
          ),
        ),
        GoRoute(
          path: '/home/insights',
          builder: (_, state) {
            pushedLocation = state.matchedLocation;
            return const Scaffold(body: Text('insights-stub'));
          },
        ),
      ]);

      await tester.pumpWidget(_wrapCard(
        overrides: [
          weeklyInsightsProvider.overrideWith((_) async => insights),
        ],
        router: router,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(EstaSemanaCard));
      await tester.pumpAndSettle();
      expect(pushedLocation, equals('/home/insights'));
    });

    // ── New SCENARIO tests (SCENARIO-305..310) ────────────────────────────────

    // SCENARIO-305: Loading state shows skeleton indicator
    testWidgets('SCENARIO-305: loading state shows CircularProgressIndicator',
        (tester) async {
      // Use a Completer so there's no lingering timer.
      final completer = Completer<WeeklyInsights?>();
      await tester.pumpWidget(_wrapCard(overrides: [
        weeklyInsightsProvider.overrideWith((_) => completer.future),
      ]));
      await tester.pump(); // trigger build, provider still loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // No stats while loading
      expect(find.text('DÍAS'), findsNothing);
      // Complete the future so the widget can clean up.
      completer.complete(null);
      await tester.pump();
    });

    // SCENARIO-306: Data state renders streak + day strip + SEMANA + MES
    testWidgets('SCENARIO-306: data state renders streak, DÍAS, SEMANA, MES',
        (tester) async {
      final insights =
          _makeInsights(streak: 5, monthSessionsCount: 12, sessionsCount: 3);
      await tester.pumpWidget(_wrapCard(overrides: [
        weeklyInsightsProvider.overrideWith((_) async => insights),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('5'), findsAtLeastNWidgets(1));
      expect(find.text('DÍAS'), findsOneWidget);
      expect(find.text('SEMANA'), findsOneWidget);
      expect(find.text('MES'), findsOneWidget);
    });

    // SCENARIO-307: trained today → shows trained-today copy
    testWidgets('SCENARIO-307: trained today → trained-today streak copy',
        (tester) async {
      final now = DateTime.now().toLocal();
      final todayIndex = now.weekday - DateTime.monday;
      final daysTrained = List<bool>.filled(7, false);
      if (todayIndex >= 0 && todayIndex < 7) daysTrained[todayIndex] = true;

      final insights = _makeInsights(streak: 3, daysTrained: daysTrained);
      await tester.pumpWidget(_wrapCard(overrides: [
        weeklyInsightsProvider.overrideWith((_) async => insights),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Mockup copy: "No rompas la racha — entrenaste hoy."
      expect(find.textContaining('entrenaste hoy'), findsOneWidget);
    });

    // SCENARIO-308: not trained today → shows not-yet-today copy
    testWidgets('SCENARIO-308: not trained today → not-yet-today streak copy',
        (tester) async {
      final insights = _makeInsights(
        streak: 3,
        daysTrained: List<bool>.filled(7, false),
      );
      await tester.pumpWidget(_wrapCard(overrides: [
        weeklyInsightsProvider.overrideWith((_) async => insights),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Mockup copy: "No rompas la racha — entrená hoy."
      expect(find.textContaining('entrená hoy'), findsOneWidget);
    });

    // SCENARIO-309: error state shows fallback text
    testWidgets('SCENARIO-309: error state shows fallback message',
        (tester) async {
      await tester.pumpWidget(_wrapCard(overrides: [
        weeklyInsightsProvider.overrideWith(
          (ref) => Future<WeeklyInsights?>.error(
            Exception('test error'),
            StackTrace.empty,
          ),
        ),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Header always visible
      expect(find.text('ESTA SEMANA'), findsOneWidget);
      // Error fallback text must contain reference to insights
      expect(find.textContaining('insights'), findsAtLeastNWidgets(1));
    });

    // SCENARIO-310: card tap → /home/insights navigation
    testWidgets('SCENARIO-310: tap on card navigates to /home/insights',
        (tester) async {
      final insights = _makeInsights();
      final navigated = <String>[];

      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: EstaSemanaCard()),
          ),
        ),
        GoRoute(
          path: '/home/insights',
          builder: (_, __) {
            navigated.add('/home/insights');
            return const Scaffold(body: Text('Insights'));
          },
        ),
      ]);

      await tester.pumpWidget(_wrapCard(
        overrides: [
          weeklyInsightsProvider.overrideWith((_) async => insights),
        ],
        router: router,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byType(EstaSemanaCard));
      await tester.pumpAndSettle();

      expect(navigated, contains('/home/insights'));
    });

    // Null insights (user has no sessions) — renders motivational empty state
    testWidgets(
        'null insights (no sessions) → PRIMER PASO header + motivational copy + CTA',
        (tester) async {
      await tester.pumpWidget(_wrapCard(overrides: [
        weeklyInsightsProvider.overrideWith((_) async => null),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Empty state: header pill cambia a "PRIMER PASO" (no "RACHA ACTUAL")
      expect(find.text('PRIMER PASO'), findsOneWidget);
      expect(find.text('RACHA ACTUAL'), findsNothing);
      // Titular motivacional
      expect(find.text('TU RACHA\nEMPIEZA ACÁ'), findsOneWidget);
      // Copy invitante
      expect(
        find.textContaining('Cada entrenamiento alimenta'),
        findsOneWidget,
      );
      // CTA outlined
      expect(find.text('EXPLORAR RUTINAS  →'), findsOneWidget);
    });

    testWidgets('sessionsCount == 0 (cuenta nueva) → renderiza empty state',
        (tester) async {
      await tester.pumpWidget(_wrapCard(overrides: [
        weeklyInsightsProvider.overrideWith(
          (_) async => _makeInsights(
            sessionsCount: 0,
            streak: 0,
            monthSessionsCount: 0,
          ),
        ),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Mismo empty state cuando sessionsCount == 0 (no solo null)
      expect(find.text('PRIMER PASO'), findsOneWidget);
      expect(find.text('EXPLORAR RUTINAS  →'), findsOneWidget);
    });

    testWidgets('empty state → tap EXPLORAR RUTINAS navega a /workout',
        (tester) async {
      String? navigated;
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: SingleChildScrollView(child: EstaSemanaCard()),
          ),
        ),
        GoRoute(
          path: '/workout',
          builder: (_, __) {
            navigated = '/workout';
            return const Scaffold(body: Text('Workout'));
          },
        ),
      ]);

      await tester.pumpWidget(_wrapCard(
        overrides: [
          weeklyInsightsProvider.overrideWith((_) async => null),
        ],
        router: router,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('EXPLORAR RUTINAS  →'));
      await tester.pumpAndSettle();

      expect(navigated, '/workout');
    });
  });
}
