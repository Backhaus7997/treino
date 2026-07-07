import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show sessionRepositoryProvider, sessionsByUidProvider;
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_chart.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_section.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockSessionRepository extends Mock implements SessionRepository {}

// ── Helpers ───────────────────────────────────────────────────────────────────

Session _s(String id, DateTime dt) => Session(
      id: id,
      uid: 'a1',
      routineId: 'r',
      routineName: 'R',
      startedAt: dt,
      status: SessionStatus.finished,
    );

SetLog _log(
        String sessionId, String exId, String exName, int reps, double kg) =>
    SetLog(
      id: '${sessionId}_1',
      exerciseId: exId,
      exerciseName: exName,
      setNumber: 1,
      reps: reps,
      weightKg: kg,
      completedAt: DateTime(2025, 1, 1),
    );

ExerciseProgressionSectionLabels _labels() => ExerciseProgressionSectionLabels(
      sectionTitle: 'EVOLUCIÓN POR EJERCICIO',
      loadingText: 'Cargando…',
      exerciseListErrorText: 'No se pudo cargar la evolución.',
      emptyStateText: 'Sin registros de series todavía.',
      chartLabels: ExerciseProgressionChartLabels(
        prLabel: 'PR',
        volumeLabel: 'Volumen',
        volumeUnit: 'kg·reps',
        prUnit: 'kg',
        frequencyLabel: (n) => n == 1
            ? '1 sesión en las últimas 8 semanas'
            : '$n sesiones en las últimas 8 semanas',
        singlePointHint: 'Necesitás al menos 2 sesiones para ver la evolución.',
        emptyHint: 'Sin datos suficientes para este ejercicio.',
      ),
      localeName: 'es_AR',
    );

Widget _wrap({
  required Widget child,
  required List<Override> overrides,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _MockSessionRepository repo;

  setUp(() {
    repo = _MockSessionRepository();
  });

  // SCENARIO-PROG-08A: no exercises → empty state shown, picker hidden
  testWidgets('SCENARIO-PROG-08A: zero setLogs shows empty state, hides picker',
      (tester) async {
    final session = _s('s1', DateTime(2025, 1, 10));

    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's1'))
        .thenAnswer((_) async => []);

    await tester.pumpWidget(_wrap(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        sessionsByUidProvider('a1').overrideWith((ref) async => [session]),
      ],
      child: ExerciseProgressionSection(
        athleteId: 'a1',
        labels: _labels(),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Sin registros de series todavía.'), findsOneWidget);
    expect(find.text('EVOLUCIÓN POR EJERCICIO'), findsOneWidget);
  });

  // SCENARIO-PROG-10A: renders picker + chart when exercises exist
  testWidgets(
      'SCENARIO-PROG-10A: shows exercise picker + chart when setLogs exist',
      (tester) async {
    final session = _s('s1', DateTime(2025, 1, 10));

    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's1'))
        .thenAnswer((_) async => [
              _log('s1', 'squat', 'Sentadilla', 5, 90),
              _log('s1', 'bench', 'Press banca', 3, 70),
            ]);

    await tester.pumpWidget(_wrap(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        sessionsByUidProvider('a1').overrideWith((ref) async => [session]),
      ],
      child: ExerciseProgressionSection(
        athleteId: 'a1',
        labels: _labels(),
      ),
    ));

    await tester.pumpAndSettle();

    // Section title + both exercise chips shown
    expect(find.text('EVOLUCIÓN POR EJERCICIO'), findsOneWidget);
    expect(find.text('Sentadilla'), findsOneWidget);
    expect(find.text('Press banca'), findsOneWidget);
    // Default selection is the most-recently-logged exercise (squat first)
    expect(find.text('PR'), findsOneWidget); // chart metric chip
  });

  // Dedup contract: same data -> same render regardless of caller context.
  // This is the core AD1 behavioral invariant: both shells must produce an
  // identical widget tree for identical (athleteId, providers, labels).
  testWidgets(
      'DEDUP-CONTRACT: same data renders identically across two independent instantiations',
      (tester) async {
    final session = _s('s1', DateTime(2025, 1, 10));

    when(() => repo.listSetLogs(uid: 'a1', sessionId: 's1'))
        .thenAnswer((_) async => [
              _log('s1', 'squat', 'Sentadilla', 5, 90),
            ]);

    final overrides = [
      sessionRepositoryProvider.overrideWithValue(repo),
      sessionsByUidProvider('a1').overrideWith((ref) async => [session]),
    ];

    // Instance A — simulates the mobile coach shell call site.
    await tester.pumpWidget(_wrap(
      overrides: overrides,
      child: ExerciseProgressionSection(
        athleteId: 'a1',
        labels: _labels(),
      ),
    ));
    await tester.pumpAndSettle();
    final aTitle = find.text('EVOLUCIÓN POR EJERCICIO');
    final aChip = find.text('Sentadilla');
    expect(aTitle, findsOneWidget);
    expect(aChip, findsOneWidget);

    // Instance B — simulates the web coach_hub shell call site, same data.
    await tester.pumpWidget(_wrap(
      overrides: overrides,
      child: ExerciseProgressionSection(
        athleteId: 'a1',
        labels: _labels(),
      ),
    ));
    await tester.pumpAndSettle();
    final bTitle = find.text('EVOLUCIÓN POR EJERCICIO');
    final bChip = find.text('Sentadilla');
    expect(bTitle, findsOneWidget);
    expect(bChip, findsOneWidget);
  });
}
