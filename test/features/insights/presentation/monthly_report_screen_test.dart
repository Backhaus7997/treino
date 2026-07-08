import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/presentation/monthly_report_screen.dart';
import 'package:treino/features/insights/presentation/widgets/monthly_report_chart.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
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
          routineByIdProvider('r1').overrideWith((ref) async => null),
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
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: now,
            status: SessionStatus.finished,
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
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: monthStart,
            status: SessionStatus.finished,
            durationMin: 40,
          ),
          makeSession(
            id: 's2',
            startedAt: DateTime(monthStart.year, monthStart.month, 2),
            status: SessionStatus.finished,
            durationMin: 25,
          ),
          // A non-finished session's duration must NOT be counted.
          makeSession(
            id: 's3',
            startedAt: DateTime(monthStart.year, monthStart.month, 3),
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

    // 40 + 25 = 65 min — active session's 999 must be excluded.
    expect(find.text('65'), findsOneWidget);
  });

  testWidgets('shows error state + retry on load failure', (tester) async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1')).thenThrow(Exception('boom'));

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

  testWidgets(
      'renders the workout-days streak calendar below the summary cards '
      'for the selected month', (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: today,
            status: SessionStatus.finished,
            durationMin: 45,
          ),
          makeSession(
            id: 's2',
            startedAt: today.subtract(const Duration(days: 1)),
            status: SessionStatus.finished,
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

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          // Only trains in the OLDER month — the current month (default
          // selection) has zero trained days.
          makeSession(
            id: 's1',
            startedAt: DateTime(olderMonth.year, olderMonth.month, 10),
            status: SessionStatus.finished,
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

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: currentMonthStart,
            status: SessionStatus.finished,
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

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: DateTime(olderMonth.year, olderMonth.month, 10),
            status: SessionStatus.finished,
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
