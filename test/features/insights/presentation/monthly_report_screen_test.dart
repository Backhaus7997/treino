import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/insights/presentation/monthly_report_screen.dart';
import 'package:treino/features/insights/presentation/widgets/monthly_report_chart.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  Widget wrap(Widget child, {required List<Override> overrides}) =>
      ProviderScope(
        overrides: [
          // Defaults so the month-vs-month radar section (AD6/PR5c) doesn't
          // hit real Firebase resolving routines/exercises — individual
          // tests can still override these explicitly if needed.
          exercisesProvider.overrideWith((ref) async => []),
          visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: MonthlyReportScreen(uid: 'u1')),
        ),
      );

  testWidgets('renders chart + summary cards when data loads', (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: now,
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('REPORTE MENSUAL'), findsOneWidget);
    expect(find.text('Entrenos'), findsWidgets);
    expect(find.text('Duración'), findsWidgets);
  });

  testWidgets(
      'Duration cross-check: the summary card sums Session.durationMin '
      'consistently for the selected month, matching the aggregator '
      '(AD6/PR5c pinning test — not just presence of the label)',
      (tester) async {
    final repo = MockSessionRepository();
    // [#379] Anchor in the Argentina frame (as the aggregator does via
    // argentinaNow()) and store startedAt as real UTC instants at NOON on
    // mid-month days: `toArgentina` shifts by -3h, so day-1 LOCAL midnight would
    // spill into the PREVIOUS month and drop the session — noon mid-month keeps
    // the Argentina calendar month unambiguous and TZ-independent.
    final now = argentinaNow();

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: DateTime.utc(now.year, now.month, 10, 12),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 40,
              ),
              makeSession(
                id: 's2',
                startedAt: DateTime.utc(now.year, now.month, 11, 12),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 25,
              ),
              // A non-finished session's duration must NOT be counted.
              makeSession(
                id: 's3',
                startedAt: DateTime.utc(now.year, now.month, 12, 12),
                status: SessionStatus.active,
                durationMin: 999,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    // 40 + 25 = 65 min = 1.1 h — active session's 999 must be excluded.
    expect(find.text('1.1'), findsOneWidget);
    expect(find.text('h'), findsOneWidget);
  });

  testWidgets('shows error state + retry on load failure', (tester) async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenThrow(Exception('boom'));

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('No pudimos cargar tu reporte mensual. Probá de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });

  // QA-498: `ref.invalidate` NO cascada a las dependencias, y exercisesProvider
  // NO es autoDispose — cachea su AsyncError para toda la vida del container.
  // Invalidando SOLO el provider del radar se re-leía el MISMO error del
  // catálogo: un botón que no podía recuperar justo el caso que trae al usuario
  // acá (catálogo frío que falló / offline).
  testWidgets(
      'QA-498: Reintentar en el radar RECUPERA — re-fetchea el catálogo, '
      'no repite su error cacheado', (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: now,
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                routineId: 'r1',
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

    // El catálogo falla en frío una vez y después anda.
    var catalogAttempts = 0;

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async {
          catalogAttempts++;
          if (catalogAttempts == 1) throw Exception('catalogue fetch failed');
          return [
            const Exercise(
              id: 'e-chest',
              name: 'Press',
              muscleGroup: 'chest',
              category: 'compound',
            ),
          ];
        }),
      ],
    ));
    await tester.pumpAndSettle();

    // El radar vive al fondo del scroll: hay que llegar hasta él para que se
    // construya (mismo criterio que el test del legend del radar).
    await tester.scrollUntilVisible(
      find.text('Reintentar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // El radar cayó en error (las sesiones sí cargaron).
    expect(find.text('Reintentar'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(
      catalogAttempts,
      2,
      reason: 'el retry debe re-fetchear el catálogo, no repetir su error '
          'cacheado (sin el fix queda en 1)',
    );
  });

  testWidgets('switching to POR DÍA renders the daily duration chart',
      (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: today,
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('POR DÍA'));
    await tester.pumpAndSettle();

    expect(find.byType(DailyDurationChart), findsOneWidget);
  });

  testWidgets(
      'renders the workout-days streak calendar below the summary cards '
      'for the selected month', (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: today,
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
              makeSession(
                id: 's2',
                startedAt: today.subtract(const Duration(days: 1)),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    // Trap: the report screen's ListView is scrollable — the calendar
    // section sits below the fold, so it must be scrolled into view before
    // asserting on it (bitten twice already per PR5b instructions).
    final streakFinder = find.textContaining('Racha de');
    await tester.scrollUntilVisible(
      streakFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(streakFinder, findsOneWidget);
    expect(find.text('Racha de 2 días'), findsOneWidget);
  });

  testWidgets(
      'selecting a different month re-fetches and updates the calendar '
      "trained-day marks (not just a no-crash smoke check)", (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final olderMonth = DateTime(now.year, now.month - 2);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              // Only trains in the OLDER month — the current month (default
              // selection) has zero trained days.
              makeSession(
                id: 's1',
                startedAt: DateTime(olderMonth.year, olderMonth.month, 10),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    // Default selection is the current (most recent) month → 0 trained days
    // marked, streak is 0 (session is in a different month, not
    // yesterday/today).
    await tester.scrollUntilVisible(
      find.textContaining('Racha de'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Racha de 0 días'), findsOneWidget);
    expect(find.byKey(const ValueKey('workout-day-trained')), findsNothing);

    // Scroll the chart itself into view before grabbing its state — the
    // ListView is lazy, so widgets below the fold aren't built yet.
    await tester.scrollUntilVisible(
      find.byType(MonthlyReportChart),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Switch the selected month via the chart's test hook (same seam
    // `onMonthSelected` uses) to the older month that HAS a trained day.
    final chartState = tester.state<MonthlyReportChartState>(
      find.byType(MonthlyReportChart),
    );
    chartState.debugSelectMonth(olderMonth);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('workout-day-trained')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workout-day-trained')), findsOneWidget);
  });

  testWidgets(
      'renders the month-vs-month muscle distribution radar below the '
      'workout-days calendar, with month-name legend labels (AD6/PR5c)',
      (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: currentMonthStart,
                status: SessionStatus.finished,
                wasFullyCompleted: true,
                durationMin: 45,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('DISTRIBUCIÓN MUSCULAR'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('DISTRIBUCIÓN MUSCULAR'), findsOneWidget);
    // Legend shows the selected month's short name, not the generic
    // "Actual"/"Anterior" labels used by the athlete-insights radar.
    final expectedCurrentLabel =
        intl.DateFormat('MMM yyyy', 'es_AR').format(currentMonthStart);
    expect(
      find.text(_capitalize(expectedCurrentLabel)),
      findsOneWidget,
    );
  });

  testWidgets(
      'switching the selected month updates the radar legend to that '
      "month's name (real data-delta, not a smoke check)", (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final olderMonth = DateTime(now.year, now.month - 2);

    when(() => repo.listByUid('u1', limit: any(named: 'limit')))
        .thenAnswer((_) async => [
              makeSession(
                id: 's1',
                startedAt: DateTime(olderMonth.year, olderMonth.month, 10),
                status: SessionStatus.finished,
                wasFullyCompleted: true,
              ),
            ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: any(named: 'sessionId')))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byType(MonthlyReportChart),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final chartState = tester.state<MonthlyReportChartState>(
      find.byType(MonthlyReportChart),
    );
    chartState.debugSelectMonth(olderMonth);
    await tester.pumpAndSettle();

    final expectedLabel =
        intl.DateFormat('MMM yyyy', 'es_AR').format(olderMonth);

    await tester.scrollUntilVisible(
      find.text(_capitalize(expectedLabel)),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text(_capitalize(expectedLabel)), findsOneWidget);
  });
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
