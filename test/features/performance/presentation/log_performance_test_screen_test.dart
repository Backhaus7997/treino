import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/data/performance_test_repository.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/performance/presentation/log_performance_test_screen.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

class _MockPerformanceTestRepository extends Mock
    implements PerformanceTestRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      PerformanceTest(
        id: '',
        athleteId: 'x',
        recordedBy: 'x',
        recordedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  testWidgets(
      '#1485: un CMJ de 999 cm muestra el rango, deshabilita GUARDAR, y al '
      'corregir el error se va', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        performanceTestRepositoryProvider
            .overrideWithValue(_MockPerformanceTestRepository()),
        currentUidProvider.overrideWithValue('trainerT'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const LogPerformanceTestScreen(athleteId: 'athleteX'),
      ),
    ));
    await tester.pumpAndSettle();

    ButtonStyleButton guardar() => tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text('GUARDAR EVALUACIÓN'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );

    // Primer campo: CMJ.
    final cmj = find.byType(TextField).first;
    await tester.enterText(cmj, '999');
    await tester.pump();

    expect(find.text('Entre 0 y 150 cm'), findsOneWidget);
    expect(guardar().onPressed, isNull);

    await tester.enterText(cmj, '42,5');
    await tester.pump();

    expect(find.text('Entre 0 y 150 cm'), findsNothing);
    expect(guardar().onPressed, isNotNull);
  });

  // ── #1485: editar una evaluación mal cargada ───────────────────────────────

  testWidgets(
      '#1485 edición: pre-carga el form y guarda con update() preservando '
      'id/athleteId/recordedBy/recordedAt', (tester) async {
    final repo = _MockPerformanceTestRepository();
    when(() => repo.update(any())).thenAnswer((_) async {});

    // El caso del QA: un CMJ de 999 que hoy queda para siempre.
    final initial = PerformanceTest(
      id: 't1',
      athleteId: 'athleteX',
      recordedBy: 'trainerT',
      recordedAt: DateTime.utc(2026, 3, 10, 14, 30),
      cmjCm: 999,
      squat1rmKg: 120.5,
      notes: 'nota original',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        performanceTestRepositoryProvider.overrideWithValue(repo),
        currentUidProvider.overrideWithValue('trainerT'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: LogPerformanceTestScreen(athleteId: 'athleteX', initial: initial),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Editar evaluación'), findsOneWidget);
    expect(find.text('999'), findsOneWidget);
    expect(find.text('120.5'), findsOneWidget);
    expect(find.text('nota original'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '45');
    await tester.pump();
    await tester.tap(find.text('GUARDAR CAMBIOS'));
    await tester.pump();

    final captured = verify(() => repo.update(captureAny())).captured.single
        as PerformanceTest;
    expect(captured.id, 't1');
    expect(captured.athleteId, 'athleteX');
    expect(captured.recordedBy, 'trainerT');
    expect(captured.recordedAt, DateTime.utc(2026, 3, 10, 14, 30),
        reason: 'corregir valores no mueve el punto en la línea de tiempo');
    expect(captured.cmjCm, 45);
    expect(captured.squat1rmKg, 120.5);
    expect(captured.notes, 'nota original');
    verifyNever(() => repo.add(any()));
  });

  testWidgets(
      '#1485 edición: el CMJ viejo de 999 muestra su error al abrir y GUARDAR '
      'queda deshabilitado', (tester) async {
    final initial = PerformanceTest(
      id: 't1',
      athleteId: 'athleteX',
      recordedBy: 'trainerT',
      recordedAt: DateTime.utc(2026, 3, 10, 14, 30),
      cmjCm: 999,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        performanceTestRepositoryProvider
            .overrideWithValue(_MockPerformanceTestRepository()),
        currentUidProvider.overrideWithValue('trainerT'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: LogPerformanceTestScreen(athleteId: 'athleteX', initial: initial),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Entre 0 y 150 cm'), findsOneWidget,
        reason: 'GUARDAR gris sin decir por qué no sirve (Codex en #1524)');
    final guardar = tester.widget<ButtonStyleButton>(find.ancestor(
      of: find.text('GUARDAR CAMBIOS'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ));
    expect(guardar.onPressed, isNull);
  });

  testWidgets('#1485: sit and reach acepta el signo menos y guarda el negativo',
      (tester) async {
    final repo = _MockPerformanceTestRepository();
    when(() => repo.add(any())).thenAnswer(
      (inv) async => inv.positionalArguments.first as PerformanceTest,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        performanceTestRepositoryProvider.overrideWithValue(repo),
        currentUidProvider.overrideWithValue('trainerT'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const LogPerformanceTestScreen(athleteId: 'athleteX'),
      ),
    ));
    await tester.pumpAndSettle();

    final campo = find.descendant(
      of: find
          .ancestor(
            of: find.text('Flexibilidad sit-and-reach'),
            matching: find.byType(Column),
          )
          .first,
      matching: find.byType(TextField),
    );
    // `enterText` pasa por los inputFormatters: sin el `-` permitido, el
    // texto quedaría en "12".
    await tester.enterText(campo, '-12');
    await tester.pump();
    expect(
      tester.widget<TextField>(campo).controller!.text,
      '-12',
    );

    await tester.tap(find.text('GUARDAR EVALUACIÓN'));
    await tester.pump();

    final saved =
        verify(() => repo.add(captureAny())).captured.single as PerformanceTest;
    expect(saved.sitAndReachCm, -12);
  });

  testWidgets(
      '#1485 edición: una evaluación sólo con notas (las crea el Coach Hub) se '
      'puede guardar', (tester) async {
    final repo = _MockPerformanceTestRepository();
    when(() => repo.update(any())).thenAnswer((_) async {});
    final initial = PerformanceTest(
      id: 't1',
      athleteId: 'athleteX',
      recordedBy: 'trainerT',
      recordedAt: DateTime.utc(2026, 3, 10, 14, 30),
      notes: 'sólo una nota',
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        performanceTestRepositoryProvider.overrideWithValue(repo),
        currentUidProvider.overrideWithValue('trainerT'),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: LogPerformanceTestScreen(athleteId: 'athleteX', initial: initial),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.text('sólo una nota'), 'nota corregida');
    await tester.pump();
    await tester.tap(find.text('GUARDAR CAMBIOS'));
    await tester.pump();

    final saved = verify(() => repo.update(captureAny())).captured.single
        as PerformanceTest;
    expect(saved.notes, 'nota corregida');
  });
}
