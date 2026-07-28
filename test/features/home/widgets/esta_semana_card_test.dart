import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/features/home/widgets/esta_semana_card.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/weekly_insights.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

WeeklyInsights _makeInsights({
  int sessionsCount = 3,
  int plannedSessionsCount = 5,
  int streak = 5,
  int monthSessionsCount = 12,
  List<bool>? daysTrained,
  bool hasEverCompletedAnyWorkout = false,
}) {
  final start = DateTime(2026, 5, 18); // Monday
  return WeeklyInsights(
    weekStart: start,
    weekEnd: start.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    ),
    daysTrained: daysTrained ?? List<bool>.filled(7, false),
    sessionsCount: sessionsCount,
    plannedSessionsCount: plannedSessionsCount,
    setsByGroup: const {},
    targetByGroup: const {},
    streak: streak,
    monthSessionsCount: monthSessionsCount,
    hasEverCompletedAnyWorkout: hasEverCompletedAnyWorkout,
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
      GoRouter(
        routes: [
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
        ],
      );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      routerConfig: goRouter,
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('EstaSemanaCard', () {
    // ── Legacy tests (updated for ConsumerWidget) ─────────────────────────────

    // Press feedback moved from the card to the CTA: the card is no longer a
    // tap target, so the only TreinoTappable left is the one inside
    // _InsightsCta, which is what should animate on press.
    testWidgets('the insights CTA uses TreinoTappable for press feedback',
        (tester) async {
      final insights = _makeInsights();
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith((_) async => insights),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.descendant(
          of: find.byType(TreinoTappable),
          matching: find.text('VER INSIGHTS  →'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'REQ-HOME-SEMANA-001: renders RACHA ACTUAL pill (mockup parity)',
      (tester) async {
        final insights = _makeInsights();
        await tester.pumpWidget(
          _wrapCard(
            overrides: [
              weeklyInsightsProvider.overrideWith((_) async => insights),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        // Loaded state replaces "ESTA SEMANA" header with RACHA ACTUAL pill +
        // SEM N · MMM label per esta-semana.png mockup.
        expect(find.text('RACHA ACTUAL'), findsOneWidget);
        expect(find.textContaining('SEM '), findsOneWidget);
      },
    );

    testWidgets('REQ-HOME-SEMANA-002: card decoration — bgCard, r=20, border', (
      tester,
    ) async {
      final insights = _makeInsights();
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith((_) async => insights),
          ],
        ),
      );
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

    // REQ-HOME-SEMANA-003 — la navegación a /home/insights sigue existiendo,
    // pero ahora la dispara el CTA explícito, no la card entera.
    testWidgets('REQ-HOME-SEMANA-003: el CTA pushea /home/insights', (
      tester,
    ) async {
      final insights = _makeInsights();
      String? pushedLocation;

      final router = GoRouter(
        routes: [
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
        ],
      );

      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith((_) async => insights),
          ],
          router: router,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('VER INSIGHTS  →'));
      await tester.pumpAndSettle();
      expect(pushedLocation, equals('/home/insights'));
    });

    // ── New SCENARIO tests (SCENARIO-305..310) ────────────────────────────────

    // SCENARIO-305: Loading state shows skeleton indicator
    testWidgets('SCENARIO-305: loading state shows CircularProgressIndicator', (
      tester,
    ) async {
      // Use a Completer so there's no lingering timer.
      final completer = Completer<WeeklyInsights?>();
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith((_) => completer.future),
          ],
        ),
      );
      await tester.pump(); // trigger build, provider still loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // No stats while loading
      expect(find.text('DÍAS'), findsNothing);
      // Complete the future so the widget can clean up.
      completer.complete(null);
      await tester.pump();
    });

    // SCENARIO-306: Data state renders streak + day strip + SEMANA + MES
    testWidgets('SCENARIO-306: data state renders streak, DÍAS, SEMANA, MES', (
      tester,
    ) async {
      final insights = _makeInsights(
        streak: 5,
        monthSessionsCount: 12,
        sessionsCount: 3,
      );
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith((_) async => insights),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('5'), findsAtLeastNWidgets(1));
      expect(find.text('DÍAS'), findsOneWidget);
      expect(find.text('SEMANA'), findsOneWidget);
      expect(find.text('MES'), findsOneWidget);
    });

    // SCENARIO-307: trained today → shows trained-today copy
    testWidgets('SCENARIO-307: trained today → trained-today streak copy', (
      tester,
    ) async {
      final now = DateTime.now().toLocal();
      final todayIndex = now.weekday - DateTime.monday;
      final daysTrained = List<bool>.filled(7, false);
      if (todayIndex >= 0 && todayIndex < 7) daysTrained[todayIndex] = true;

      final insights = _makeInsights(streak: 3, daysTrained: daysTrained);
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith((_) async => insights),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Mockup copy: "No rompas la racha — entrenaste hoy."
      expect(find.textContaining('entrenaste hoy'), findsOneWidget);
    });

    // SCENARIO-308: not trained today → shows not-yet-today copy
    testWidgets('SCENARIO-308: not trained today → not-yet-today streak copy', (
      tester,
    ) async {
      final insights = _makeInsights(
        streak: 3,
        daysTrained: List<bool>.filled(7, false),
      );
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith((_) async => insights),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Mockup copy: "No rompas la racha — entrená hoy."
      expect(find.textContaining('entrená hoy'), findsOneWidget);
    });

    // SCENARIO-309: error state shows fallback text
    testWidgets('SCENARIO-309: error state shows fallback message', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (ref) => Future<WeeklyInsights?>.error(
                Exception('test error'),
                StackTrace.empty,
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Header always visible
      expect(find.text('ESTA SEMANA'), findsOneWidget);
      // Error fallback text must contain reference to insights
      expect(find.textContaining('insights'), findsAtLeastNWidgets(1));
    });

    // SCENARIO-310 (superseded): the CARD used to navigate as a whole. That
    // is deliberately gone — only the explicit CTA navigates now, so a tap on
    // inert card chrome (the silhouettes, the SEMANA/MES tiles) must do
    // NOTHING. Navigation from the CTA itself is covered in the CTA group.
    testWidgets('tapping the card body does NOT navigate to /home/insights', (
      tester,
    ) async {
      final insights = _makeInsights();
      final navigated = <String>[];

      final router = GoRouter(
        routes: [
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
        ],
      );

      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith((_) async => insights),
          ],
          router: router,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Tap the SEMANA tile — inert card chrome, well away from the CTA.
      await tester.tap(find.text('SEMANA'));
      await tester.pumpAndSettle();

      expect(navigated, isEmpty);
      expect(find.byType(EstaSemanaCard), findsOneWidget);
    });

    // Null insights (user has no sessions) — renders motivational empty state
    testWidgets(
      'null insights (no sessions) → PRIMER PASO header + motivational copy + CTA',
      (tester) async {
        await tester.pumpWidget(
          _wrapCard(
            overrides: [weeklyInsightsProvider.overrideWith((_) async => null)],
          ),
        );
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
      },
    );

    testWidgets('sessionsCount == 0 (cuenta nueva) → renderiza empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (_) async => _makeInsights(
                sessionsCount: 0,
                streak: 0,
                monthSessionsCount: 0,
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Mismo empty state cuando sessionsCount == 0 (no solo null)
      expect(find.text('PRIMER PASO'), findsOneWidget);
      expect(find.text('EXPLORAR RUTINAS  →'), findsOneWidget);
    });

    testWidgets('empty state → tap EXPLORAR RUTINAS navega a /workout', (
      tester,
    ) async {
      String? navigated;
      final router = GoRouter(
        routes: [
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
        ],
      );

      await tester.pumpWidget(
        _wrapCard(
          overrides: [weeklyInsightsProvider.overrideWith((_) async => null)],
          router: router,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('EXPLORAR RUTINAS  →'));
      await tester.pumpAndSettle();

      expect(navigated, '/workout');
    });

    // ── #551: semana en 0 CON historial ≠ cuenta nueva ────────────────────────

    testWidgets(
      '#551: semana en 0 con historial → copy de retomar, no de onboarding',
      (tester) async {
        await tester.pumpWidget(
          _wrapCard(
            overrides: [
              weeklyInsightsProvider.overrideWith(
                (_) async => _makeInsights(
                  sessionsCount: 0,
                  streak: 0,
                  monthSessionsCount: 0,
                  hasEverCompletedAnyWorkout: true,
                ),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Pill de retomar, no de primer paso.
        expect(find.text('A RETOMAR'), findsOneWidget);
        expect(find.text('PRIMER PASO'), findsNothing);
        // Titular + copy de retomar — nada de "Hacé el primero".
        expect(find.text('TU RACHA\nTE ESPERA'), findsOneWidget);
        expect(find.textContaining('retomá hoy'), findsOneWidget);
        expect(find.textContaining('Hacé el primero'), findsNothing);
        // CTA propio.
        expect(find.text('VOLVER A ENTRENAR  →'), findsOneWidget);
        expect(find.text('EXPLORAR RUTINAS  →'), findsNothing);
      },
    );

    testWidgets('#551: cuenta nueva (0 totales) sigue viendo onboarding', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (_) async => _makeInsights(
                sessionsCount: 0,
                streak: 0,
                monthSessionsCount: 0,
                hasEverCompletedAnyWorkout: false,
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('PRIMER PASO'), findsOneWidget);
      expect(find.text('A RETOMAR'), findsNothing);
      expect(find.text('TU RACHA\nEMPIEZA ACÁ'), findsOneWidget);
      expect(find.text('EXPLORAR RUTINAS  →'), findsOneWidget);
    });

    testWidgets('#551: tap VOLVER A ENTRENAR navega a /workout', (
      tester,
    ) async {
      String? navigated;
      final router = GoRouter(
        routes: [
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
        ],
      );

      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (_) async => _makeInsights(
                sessionsCount: 0,
                streak: 0,
                monthSessionsCount: 0,
                hasEverCompletedAnyWorkout: true,
              ),
            ),
          ],
          router: router,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('VOLVER A ENTRENAR  →'));
      await tester.pumpAndSettle();

      expect(navigated, '/workout');
    });

    testWidgets(
      '#551: semana con sesiones muestra data aunque el DTO diga '
      'hasEverCompletedAnyWorkout=false (sessionsCount manda)',
      (tester) async {
        await tester.pumpWidget(
          _wrapCard(
            overrides: [
              weeklyInsightsProvider.overrideWith(
                (_) async => _makeInsights(sessionsCount: 2),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('RACHA ACTUAL'), findsOneWidget);
        expect(find.text('PRIMER PASO'), findsNothing);
        expect(find.text('A RETOMAR'), findsNothing);
      },
    );
  });

  // ── Insights CTA ────────────────────────────────────────────────────────────
  //
  // The card was ALREADY tappable to /home/insights, but with no visible
  // affordance the destination was undiscoverable. The CTA makes it explicit
  // and gives the action real button semantics.
  group('EstaSemanaCard — insights CTA', () {
    testWidgets('loaded state renders the VER INSIGHTS CTA', (tester) async {
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (_) async => _makeInsights(sessionsCount: 2),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('VER INSIGHTS  →'), findsOneWidget);
    });

    testWidgets('tapping the CTA navigates to /home/insights', (tester) async {
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (_) async => _makeInsights(sessionsCount: 2),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.ensureVisible(find.text('VER INSIGHTS  →'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VER INSIGHTS  →'));
      await tester.pumpAndSettle();

      expect(find.text('Insights'), findsOneWidget);
    });

    // The CTA shares a Row with the 96px streak digits. A long streak plus a
    // long translated label is the overflow case that layout risks.
    testWidgets('a 3-digit streak does not overflow the CTA row',
        (tester) async {
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (_) async => _makeInsights(sessionsCount: 4, streak: 365),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.text('365'), findsOneWidget);
      expect(find.text('VER INSIGHTS  →'), findsOneWidget);
    });

    // Hover is pointer-only — a touch screen never emits enter/exit, so this
    // is the ONLY place the hover branch can be exercised. Driving a synthetic
    // mouse is what makes it verifiable at all.
    testWidgets('hovering with a pointer lightens the CTA and adds a glow',
        (tester) async {
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (_) async => _makeInsights(sessionsCount: 2),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      ShapeDecoration decorationOf() => tester
          .widget<AnimatedContainer>(
            find.ancestor(
              of: find.text('VER INSIGHTS  →'),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .decoration! as ShapeDecoration;

      final resting = decorationOf();
      expect(resting.shadows, isEmpty, reason: 'no glow at rest');

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(tester.getCenter(find.text('VER INSIGHTS  →')));
      await tester.pumpAndSettle();

      final hovered = decorationOf();
      expect(hovered.shadows, isNotEmpty, reason: 'glow appears on hover');
      expect(
        hovered.color,
        isNot(equals(resting.color)),
        reason: 'fill lightens on hover',
      );

      // And it must revert when the pointer leaves.
      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(decorationOf().shadows, isEmpty);
    });

    // Press feedback: TreinoTappable scales its child to 0.97 while held.
    //
    // The gesture is CANCELLED rather than released: releasing fires onTap,
    // which navigates away and unmounts the CTA, so there would be no
    // AnimatedScale left to assert on. Cancelling also covers onTapCancel —
    // the drag-finger-away path that must restore the resting scale.
    testWidgets('pressing the CTA scales it down, and cancelling restores it',
        (tester) async {
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (_) async => _makeInsights(sessionsCount: 2),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      double scaleOf() => tester
          .widget<AnimatedScale>(
            find.ancestor(
              of: find.text('VER INSIGHTS  →'),
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale;

      expect(scaleOf(), equals(1.0));

      final press = await tester
          .startGesture(tester.getCenter(find.text('VER INSIGHTS  →')));
      // The card lives in a SingleChildScrollView, so the tap recognizer
      // shares the gesture arena with the scroll drag and holds onTapDown
      // until the press timeout (~100ms) resolves it. Pumping a single frame
      // would still read 1.0 — that delay is real product behaviour, not a
      // test artifact.
      await tester.pump(const Duration(milliseconds: 150));

      expect(scaleOf(), equals(TreinoTappable.pressedScale));

      await press.cancel();
      await tester.pumpAndSettle();

      expect(scaleOf(), equals(1.0));
    });

    testWidgets(
        'the zero-week state shows its own routines CTA, not the insights one',
        (tester) async {
      await tester.pumpWidget(
        _wrapCard(
          overrides: [
            weeklyInsightsProvider.overrideWith(
              (_) async => _makeInsights(sessionsCount: 0),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('VER INSIGHTS  →'), findsNothing);
      expect(find.textContaining('EXPLORAR RUTINAS'), findsOneWidget);
    });
  });
}
