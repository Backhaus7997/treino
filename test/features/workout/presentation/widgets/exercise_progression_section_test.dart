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

ExerciseProgressionChartLabels _chartLabels() => ExerciseProgressionChartLabels(
      heaviestWeightLabel: 'Peso máximo',
      oneRepMaxLabel: '1RM',
      bestSetVolumeLabel: 'Mejor serie',
      bestSessionVolumeLabel: 'Volumen',
      volumeUnit: 'kg·reps',
      weightUnit: 'kg',
      frequencyLabel: (n) => n == 1
          ? '1 sesión en las últimas 8 semanas'
          : '$n sesiones en las últimas 8 semanas',
      singlePointHint: 'Necesitás al menos 2 sesiones para ver la evolución.',
      emptyHint: 'Sin datos suficientes para este ejercicio.',
    );

/// Generic label bag — used by tests that don't care about per-shell
/// divergence (empty state, picker rendering).
ExerciseProgressionSectionLabels _labels() => ExerciseProgressionSectionLabels(
      sectionTitle: 'EVOLUCIÓN POR EJERCICIO',
      loadingText: 'Cargando…',
      exerciseListErrorText: 'No se pudo cargar la evolución.',
      emptyStateText: 'Sin registros de series todavía.',
      chartLabels: _chartLabels(),
      localeName: 'es_AR',
    );

/// Mirrors the MOBILE coach shell's real `_ProgressionSection` wrapper
/// (athlete_detail_screen.dart): `exerciseListErrorText` is null — mobile
/// silently swallows exercise-list load errors (SizedBox.shrink), no l10n
/// key exists for it (see apply-progress WARNING-2, obs #434).
ExerciseProgressionSectionLabels _mobileLabels() =>
    ExerciseProgressionSectionLabels(
      sectionTitle: 'EVOLUCIÓN POR EJERCICIO',
      loadingText: 'Cargando…',
      exerciseListErrorText: null,
      emptyStateText: 'Sin registros de series todavía.',
      chartLabels: _chartLabels(),
      localeName: 'es_AR',
    );

/// Mirrors the WEB coach_hub shell's real `_ProgressionTabSection` wrapper
/// (alumno_detail_screen.dart): `exerciseListErrorText` is a real hardcoded
/// Spanish string, distinct from mobile's null.
ExerciseProgressionSectionLabels _webLabels() =>
    ExerciseProgressionSectionLabels(
      sectionTitle: 'EVOLUCIÓN POR EJERCICIO',
      loadingText: 'Cargando…',
      exerciseListErrorText: 'No se pudo cargar la evolución.',
      emptyStateText: 'Sin registros de series todavía.',
      chartLabels: _chartLabels(),
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
    // [AD3] "Peso máximo" replaces the old mislabeled "PR" chip label.
    expect(find.text('Peso máximo'), findsOneWidget); // chart metric chip
  });

  // Dedup contract: same data -> same render regardless of caller context.
  // This is the core AD1 behavioral invariant: both shells must produce an
  // identical widget tree for identical (athleteId, providers) given each
  // shell's OWN real, differing label bag.
  //
  // Strengthened per verify-report WARNING-1 (obs #434): previously this
  // test instantiated the widget twice with the SAME label bag, which could
  // not catch label-bag-shaped regressions. Now Instance A uses the mobile
  // shell's real bag (exerciseListErrorText: null) and Instance B uses the
  // web shell's real bag (exerciseListErrorText: non-null) — both must
  // still render the section title + picker identically given identical
  // provider data, proving the shared widget's core layout/behavior is
  // caller-agnostic even when label bags genuinely diverge.
  testWidgets(
      'DEDUP-CONTRACT: identical data renders identically across the two shells\' real (differing) label bags',
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

    // Instance A — mobile coach shell's real label bag.
    await tester.pumpWidget(_wrap(
      overrides: overrides,
      child: ExerciseProgressionSection(
        athleteId: 'a1',
        labels: _mobileLabels(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('EVOLUCIÓN POR EJERCICIO'), findsOneWidget);
    expect(find.text('Sentadilla'), findsOneWidget);
    expect(find.text('Peso máximo'), findsOneWidget);

    // Instance B — web coach_hub shell's real label bag, same provider data.
    await tester.pumpWidget(_wrap(
      overrides: overrides,
      child: ExerciseProgressionSection(
        athleteId: 'a1',
        labels: _webLabels(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('EVOLUCIÓN POR EJERCICIO'), findsOneWidget);
    expect(find.text('Sentadilla'), findsOneWidget);
    expect(find.text('Peso máximo'), findsOneWidget);
  });

  // Regression guard for the divergent field itself: mobile's null
  // errorText must silently swallow (SizedBox.shrink), web's non-null
  // errorText must render its text — proving the label-bag injection
  // point is actually exercised, not just structurally present.
  testWidgets(
      'exerciseListErrorText divergence: mobile bag swallows error, web bag shows it',
      (tester) async {
    when(() => repo.listSetLogs(uid: 'a1', sessionId: any(named: 'sessionId')))
        .thenThrow(Exception('boom'));

    // Mobile: null errorText → no error text rendered.
    await tester.pumpWidget(_wrap(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        sessionsByUidProvider('a1')
            .overrideWith((ref) async => [_s('s1', DateTime(2025, 1, 10))]),
      ],
      child: ExerciseProgressionSection(
        athleteId: 'a1',
        labels: _mobileLabels(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar la evolución.'), findsNothing);

    // Web: non-null errorText → error text rendered.
    await tester.pumpWidget(_wrap(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        sessionsByUidProvider('a1')
            .overrideWith((ref) async => [_s('s1', DateTime(2025, 1, 10))]),
      ],
      child: ExerciseProgressionSection(
        athleteId: 'a1',
        labels: _webLabels(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cargar la evolución.'), findsOneWidget);
  });
}
