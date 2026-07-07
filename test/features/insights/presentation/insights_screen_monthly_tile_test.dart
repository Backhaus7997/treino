import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/weekly_insights.dart';
import 'package:treino/features/insights/presentation/insights_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

WeeklyInsights _insights() => WeeklyInsights(
      weekStart: DateTime(2026, 6, 1),
      weekEnd: DateTime(2026, 6, 7, 23, 59, 59, 999),
      daysTrained: List<bool>.filled(7, false)..[0] = true,
      sessionsCount: 1,
      plannedSessionsCount: 5,
      setsByGroup: const {},
      targetByGroup: const {},
    );

void main() {
  testWidgets(
      'InsightsScreen shows a Monthly Report tile navigating to /home/insights/monthly',
      (tester) async {
    String? navigatedTo;
    final router = GoRouter(
      initialLocation: '/home/insights',
      routes: [
        GoRoute(
          path: '/home/insights',
          builder: (_, __) => const InsightsScreen(),
        ),
        GoRoute(
          path: '/home/insights/monthly',
          builder: (_, __) {
            navigatedTo = '/home/insights/monthly';
            return const SizedBox.shrink();
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weeklyInsightsProvider.overrideWith((ref) async => _insights()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tileFinder = find.text('Reporte mensual', skipOffstage: false);
    expect(tileFinder, findsOneWidget);

    await tester.scrollUntilVisible(
      tileFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(navigatedTo, '/home/insights/monthly');
  });
}
