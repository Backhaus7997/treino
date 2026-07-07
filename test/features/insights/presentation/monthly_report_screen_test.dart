import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/presentation/monthly_report_screen.dart';
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
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: Scaffold(body: MonthlyReportScreen(uid: 'u1')),
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
}
