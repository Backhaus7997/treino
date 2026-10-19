// #1485: una evaluación mal cargada tiene que poder editarse o borrarse desde
// el detalle de alumno, igual que las mediciones (#439).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/data/performance_test_repository.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/performance/presentation/widgets/performance_test_history_list.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockRepo extends Mock implements PerformanceTestRepository {}

PerformanceTest _test(String id, {String by = 'trainerT', int day = 1}) =>
    PerformanceTest(
      id: id,
      athleteId: 'athleteX',
      recordedBy: by,
      recordedAt: DateTime.utc(2026, 3, day, 15),
      cmjCm: 40,
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<PerformanceTest> tests,
  required PerformanceTestRepository repo,
  ValueChanged<PerformanceTest>? onEdit,
}) =>
    tester.pumpWidget(ProviderScope(
      overrides: [performanceTestRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PerformanceTestHistoryList(
              tests: tests,
              currentUid: 'trainerT',
              onEdit: onEdit ?? (_) {},
            ),
          ),
        ),
      ),
    ));

void main() {
  testWidgets('las filas propias ofrecen editar y borrar', (tester) async {
    PerformanceTest? editado;
    await _pump(
      tester,
      tests: [_test('t1')],
      repo: _MockRepo(),
      onEdit: (t) => editado = t,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar evaluación'));
    expect(editado?.id, 't1');
    expect(find.byTooltip('Eliminar evaluación'), findsOneWidget);
  });

  testWidgets(
      'una fila de otro entrenador es de sólo lectura: las reglas sólo dejan '
      'tocar al autor', (tester) async {
    await _pump(tester, tests: [_test('t1', by: 'otroPF')], repo: _MockRepo());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Editar evaluación'), findsNothing);
    expect(find.byTooltip('Eliminar evaluación'), findsNothing);
    expect(find.text('Cargada por otro entrenador'), findsOneWidget);
  });

  testWidgets('borrar confirma y llama a delete con el id', (tester) async {
    final repo = _MockRepo();
    when(() => repo.delete(any())).thenAnswer((_) async {});
    await _pump(tester, tests: [_test('t1')], repo: repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Eliminar evaluación'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar evaluación?'), findsOneWidget);

    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    verify(() => repo.delete('t1')).called(1);
    expect(find.text('Evaluación eliminada'), findsOneWidget);
  });

  testWidgets('cancelar el borrado no borra', (tester) async {
    final repo = _MockRepo();
    await _pump(tester, tests: [_test('t1')], repo: repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Eliminar evaluación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    verifyNever(() => repo.delete(any()));
  });

  testWidgets('ordena DESC: la más reciente primero', (tester) async {
    await _pump(
      tester,
      tests: [_test('viejo', day: 1), _test('nuevo', day: 20)],
      repo: _MockRepo(),
    );
    await tester.pumpAndSettle();

    final y20 = tester.getTopLeft(find.textContaining('20 ')).dy;
    final y1 = tester.getTopLeft(find.textContaining('1 ').first).dy;
    expect(y20, lessThan(y1));
  });

  testWidgets(
      '"Ver todas" no construye todo el historial de una: la lista expandida '
      'es perezosa (AGENTS §6)', (tester) async {
    final tests = [
      for (var i = 0; i < 200; i++) _test('t$i', day: 1 + i % 28),
    ];
    await _pump(tester, tests: tests, repo: _MockRepo());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver todas (200)'));
    await tester.pumpAndSettle();

    final filas = find.byTooltip('Editar evaluación').evaluate().length;
    expect(filas, greaterThan(5), reason: 'se expandió');
    expect(filas, lessThan(200), reason: 'pero sólo lo visible');
  });
}
