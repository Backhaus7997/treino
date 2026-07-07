import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/insights/presentation/insights_screen.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../workout/application/stub_factories.dart';

class _MockSessionRepository extends Mock implements SessionRepository {}

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

    // The screen watches athleteWeekInsightsProvider/athleteDayInsightsProvider
    // families keyed by (uid, ...) — feed them via the repo seam like
    // insights_screen_test.dart does. At least one session is required:
    // with zero sessions the screen renders the new-account CTA instead of
    // the insights content, and the tile never mounts.
    final repo = _MockSessionRepository();
    final now = DateTime.now();
    final session = makeSession(
      id: 's-today',
      startedAt: DateTime(now.year, now.month, now.day, 10),
      finishedAt: DateTime(now.year, now.month, now.day, 11),
      durationMin: 60,
      status: SessionStatus.finished,
    );
    when(() => repo.listByUid('u1')).thenAnswer((_) async => [session]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-today'))
        .thenAnswer((_) async => [makeSetLog()]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('u1'),
          sessionRepositoryProvider.overrideWithValue(repo),
          exercisesProvider.overrideWith((ref) async => []),
          routineByIdProvider('r1').overrideWith((ref) async => null),
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

    // The screen's ListView builds lazily — the tile sits below the fold in
    // the test viewport, so scroll it into existence BEFORE asserting.
    final tileFinder = find.text('Reporte mensual', skipOffstage: false);
    await tester.scrollUntilVisible(
      tileFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tileFinder, findsOneWidget);

    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    expect(navigatedTo, '/home/insights/monthly');
  });
}
