import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/presentation/performance_screen.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/performance/presentation/widgets/performance_progress_chart.dart';
import 'package:treino/l10n/app_l10n.dart';

PerformanceTest _t(DateTime at, double cmj) => PerformanceTest(
      id: 't-${at.millisecondsSinceEpoch}',
      athleteId: 'u1',
      recordedBy: 'trainerA',
      recordedAt: at,
      cmjCm: cmj,
    );

Widget _wrap({required List<Override> overrides}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: PerformanceScreen(uid: 'u1')),
      ),
    );

void main() {
  testWidgets('2+ evaluaciones → renderiza el chart de progreso',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownPerformanceTestsProvider('u1').overrideWith(
        (ref) => Stream.value([
          _t(DateTime.utc(2026, 1, 1), 30),
          _t(DateTime.utc(2026, 2, 1), 34),
        ]),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('RENDIMIENTO'), findsOneWidget);
    expect(find.byType(PerformanceProgressChart), findsOneWidget);
  });

  testWidgets('CERO evaluaciones → empty state que dice QUIÉN las carga',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownPerformanceTestsProvider('u1').overrideWith((ref) => Stream.value([])),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(PerformanceProgressChart), findsNothing);
    expect(
      find.text(
          'Todavía no tenés evaluaciones cargadas. Las registra tu entrenador.'),
      findsOneWidget,
    );
  });

  testWidgets('UNA sola evaluación → mensaje distinto al de cero',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownPerformanceTestsProvider('u1').overrideWith(
        (ref) => Stream.value([_t(DateTime.utc(2026, 1, 1), 30)]),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(PerformanceProgressChart), findsNothing);
    expect(
      find.text(
          'Con una sola evaluación no hay progreso que mostrar. Falta al menos una más.'),
      findsOneWidget,
    );
  });

  testWidgets('fallo de carga → error VISIBLE con retry, nunca card vacía',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownPerformanceTestsProvider('u1').overrideWith(
        (ref) => Stream.error(Exception('boom')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(PerformanceProgressChart), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
