// Tests for SessionDetailScreen — SCENARIO-372..377 + back navigation
// TDD RED: each test must fail before the GREEN implementation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/application/exercise_feedback_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/utils/date_helpers.dart';
import 'package:treino/features/workout/presentation/session_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/session_stats_card.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Session _makeSession({
  String routineName = 'Push',
  int durationMin = 45,
  double totalVolumeKg = 1800.0,
  bool wasFullyCompleted = true,
  DateTime? startedAt,
}) =>
    Session(
      id: 's1',
      uid: 'u1',
      routineId: 'r1',
      routineName: routineName,
      startedAt: startedAt ?? DateTime.utc(2026, 5, 19, 10, 30),
      finishedAt: DateTime.utc(2026, 5, 19, 11, 15),
      totalVolumeKg: totalVolumeKg,
      durationMin: durationMin,
      status: SessionStatus.finished,
      dayNumber: 1,
      wasFullyCompleted: wasFullyCompleted,
    );

SetLog _makeSetLog({
  String exerciseName = 'Bench Press',
  int setNumber = 1,
  int reps = 10,
  double weightKg = 80.0,
  // #628 — el id se deriva del nombre en vez de ser 'e1' fijo: la pantalla
  // ahora agrupa por `exerciseId` (es la clave a la que se anclan los
  // reportes), y un fixture con dos ejercicios DISTINTOS compartiendo id no
  // existe en datos reales — el nombre está denormalizado desde el id.
  String? exerciseId,
}) =>
    SetLog(
      id: 'sl-$exerciseName-$setNumber',
      exerciseId: exerciseId ?? 'e-$exerciseName',
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      completedAt: DateTime.utc(2026, 5, 19, 10, 35),
    );

/// Un reporte del alumno sobre esta sesión (#628).
ExerciseFeedback _makeFeedback({
  String id = 'fb1',
  String exerciseId = 'e-Bench Press',
  String exerciseName = 'Bench Press',
  int? setNumber,
  ExerciseFeedbackKind kind = ExerciseFeedbackKind.discomfort,
  String text = 'Me tira el hombro',
}) =>
    ExerciseFeedback(
      id: id,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      kind: kind,
      text: text,
      createdAt: DateTime.utc(2026, 5, 19, 10, 36),
    );

typedef _SummaryRecord = ({Session? session, List<SetLog> setLogs});

Widget _pumpDetailScreen({
  required _SummaryRecord Function() summaryOverride,
  bool loading = false,
  bool error = false,
  String sessionId = 's1',
  String uid = 'u1',
  // If provided, wrap in a GoRouter with an initial route so back-nav tests work
  bool withBackRoute = false,
  // #628 — lo que el alumno reportó en ESTA sesión. Se overridea siempre
  // (default vacío) para que ningún test toque Firestore por el stream real.
  List<ExerciseFeedback> feedback = const [],
  // #628 — la lectura de reportes ROTA, que no es lo mismo que "sin reportes".
  bool feedbackError = false,
}) {
  final router = GoRouter(
    initialLocation:
        withBackRoute ? '/workout' : '/workout/historial/$sessionId',
    routes: [
      if (withBackRoute)
        GoRoute(
          path: '/workout',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('workout-home')),
          ),
        ),
      GoRoute(
        path: '/workout/historial/:sessionId',
        builder: (context, state) => SessionDetailScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
      if (!withBackRoute)
        GoRoute(
          path: '/workout',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('workout-home')),
          ),
        ),
    ],
  );

  final overrides = <Override>[
    currentUidProvider.overrideWithValue(uid),
    sessionSummaryProvider.overrideWith((ref, key) {
      if (loading) return Completer<_SummaryRecord>().future;
      if (error) return Future<_SummaryRecord>.error(Exception('load error'));
      return Future.value(summaryOverride());
    }),
    sessionExerciseFeedbackProvider.overrideWith((ref, key) => feedbackError
        ? Stream<List<ExerciseFeedback>>.error(Exception('boom'))
        : Stream.value(feedback)),
  ];

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // SCENARIO-372: loading state
  testWidgets(
      'SCENARIO-372: shows CircularProgressIndicator while sessionSummaryProvider loads',
      (tester) async {
    await tester.pumpWidget(_pumpDetailScreen(
      loading: true,
      summaryOverride: () => (session: null, setLogs: []),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // SCENARIO-373: data state — header + 4 StatTiles + grouped exercise blocks
  testWidgets(
      'SCENARIO-373: data state renders header (date+time+routineName) + 4 StatTiles + exercise blocks',
      (tester) async {
    final setLogs = [
      _makeSetLog(exerciseName: 'Bench Press', setNumber: 1),
      _makeSetLog(exerciseName: 'Bench Press', setNumber: 2, reps: 8),
      _makeSetLog(exerciseName: 'Squat', setNumber: 1, reps: 5, weightKg: 100),
    ];
    // Real UTC instant, mid-day so no TZ boundary crossing muddies the assertion.
    final startedAtUtc = DateTime.utc(2026, 5, 19, 10, 30);

    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (
        session: _makeSession(
          routineName: 'Push',
          durationMin: 45,
          totalVolumeKg: 1800,
          startedAt: startedAtUtc,
        ),
        setLogs: setLogs,
      ),
    ));
    await tester.pumpAndSettle();

    // Header shows the session's startedAt in the viewer's LOCAL time (#380):
    // startedAt is a real UTC instant, so the expected strings are derived from
    // .toLocal() — keeps the test correct in any TZ (Argentina dev box or UTC CI)
    // and pins the localization itself, not a raw UTC literal.
    final local = startedAtUtc.toLocal();
    final expectedTime =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    expect(find.text(formatSessionDate(local)), findsWidgets);
    expect(find.textContaining(expectedTime), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);

    // 4 StatTiles — labels (duración/volumen carry their unit, #363)
    expect(find.text('DURACIÓN MIN'), findsOneWidget);
    expect(find.text('SETS'), findsOneWidget);
    expect(find.text('VOLUMEN KG'), findsOneWidget);
    expect(find.text('PRS HOY'), findsOneWidget);

    // Stat values: duration=45, sets=3 (count of setLogs), volume=1800.
    // Volume renders via formatVolumeKg — whole values drop the .0 (#436).
    expect(find.text('45'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1800'), findsOneWidget);
    expect(find.text('1800.0'), findsNothing);

    // Historical details use the shared card without post-workout count-ups.
    final statsCard = tester.widget<SessionStatsCard>(
      find.byType(SessionStatsCard),
    );
    expect(
      statsCard.tiles.map((tile) => tile.icon),
      [
        TreinoIcon.clock,
        TreinoIcon.statSets,
        TreinoIcon.dumbbell,
        TreinoIcon.statPr,
      ],
    );
    expect(statsCard.tiles.every((tile) => tile.countUpValue == null), isTrue);

    // Exercise group headings
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
  });

  // SCENARIO-374: setLogs grouped by exerciseName preserving first-appearance order
  testWidgets(
      'SCENARIO-374: setLogs grouped by exerciseName in first-appearance order (LinkedHashMap)',
      (tester) async {
    // Sets arrive ordered: Squat s1, Bench s1, Squat s2, Bench s2
    // Groups should appear in first-appearance order: Squat, Bench
    final setLogs = [
      _makeSetLog(exerciseName: 'Squat', setNumber: 1),
      _makeSetLog(exerciseName: 'Bench Press', setNumber: 1),
      _makeSetLog(exerciseName: 'Squat', setNumber: 2),
      _makeSetLog(exerciseName: 'Bench Press', setNumber: 2),
    ];

    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (
        session: _makeSession(),
        setLogs: setLogs,
      ),
    ));
    await tester.pumpAndSettle();

    // Both exercise names must appear
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);

    // Squat appears before Bench Press in the widget tree
    final squatPos = tester.getTopLeft(find.text('Squat')).dy;
    final benchPos = tester.getTopLeft(find.text('Bench Press')).dy;
    expect(squatPos, lessThan(benchPos));

    // Each group shows correct set count (2 rows each)
    // Set numbers 1 and 2 appear at least twice (once per group)
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  // SCENARIO-375: no PR badge on set rows (QA-WKT-007). The Etapa-5 stub
  // rendered a "PR" badge on EVERY set, so the athlete — and the trainer via
  // the coach-hub reuse — saw false personal records. Removed until real PR
  // detection exists.
  testWidgets('SCENARIO-375: no "PR" badge rendered on set rows',
      (tester) async {
    final setLogs = [
      _makeSetLog(exerciseName: 'Bench Press', setNumber: 1),
      _makeSetLog(exerciseName: 'Bench Press', setNumber: 2),
      _makeSetLog(exerciseName: 'Squat', setNumber: 1),
    ];

    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (session: _makeSession(), setLogs: setLogs),
    ));
    await tester.pumpAndSettle();

    // The fake per-set PR badge is gone — no "PR" chip on any row.
    expect(find.text('PR'), findsNothing);
  });

  // SCENARIO-376: not-found state when session is null
  testWidgets(
      'SCENARIO-376: shows not-found state when session is null in provider record',
      (tester) async {
    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (session: null, setLogs: []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sesión no encontrada'), findsOneWidget);
  });

  // SCENARIO-377: error state renders message + retry button
  testWidgets(
      'SCENARIO-377: error state renders error message and retry button',
      (tester) async {
    await tester.pumpWidget(_pumpDetailScreen(
      error: true,
      summaryOverride: () => (session: null, setLogs: []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No pudimos cargar tu sesión'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  // SCENARIO-378: back button navigates correctly
  // context.canPop() == true → pop(); false → go('/workout')
  testWidgets(
      'SCENARIO-378: back button uses go(/workout) when canPop() is false (deep link)',
      (tester) async {
    // No previous route in stack → canPop() returns false → should go /workout
    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (
        session: _makeSession(),
        setLogs: [],
      ),
    ));
    await tester.pumpAndSettle();

    // Tap the back button
    expect(find.byType(IconButton), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    expect(find.text('workout-home'), findsOneWidget);
  });

  testWidgets(
      'SCENARIO-378b: back button uses pop() when canPop() is true (pushed route)',
      (tester) async {
    // We navigate from /workout to /workout/historial/s1 so canPop() = true
    final router = GoRouter(
      initialLocation: '/workout',
      routes: [
        GoRoute(
          path: '/workout',
          builder: (_, __) => const Scaffold(
            body: Center(child: Text('workout-home')),
          ),
        ),
        GoRoute(
          path: '/workout/historial/:sessionId',
          builder: (context, state) => SessionDetailScreen(
            sessionId: state.pathParameters['sessionId']!,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('u1'),
          sessionSummaryProvider.overrideWith(
            (ref, key) async => (session: _makeSession(), setLogs: <SetLog>[]),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
        ),
      ),
    );

    // Navigate to the detail screen (pushes on top of /workout)
    router.push('/workout/historial/s1');
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailScreen), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // After pop, /workout is visible again
    expect(find.text('workout-home'), findsOneWidget);
  });

  // SCENARIO-REL-001: Regression — exercise blocks still render after widget extraction.
  // E1 = 3 sets, E2 = 2 sets: both headers visible, 5 total set rows,
  // no edit button. This guards against regressions when _ExerciseBlock/_SetRow
  // are replaced by the shared SessionExerciseBlock. (REQ-SETLOGS-011)
  testWidgets(
      'SCENARIO-REL-001: session_detail_screen renders E1+E2 correctly after SessionExerciseBlock extraction',
      (tester) async {
    final setLogs = [
      _makeSetLog(exerciseName: 'Squat', setNumber: 1, reps: 5, weightKg: 120),
      _makeSetLog(exerciseName: 'Squat', setNumber: 2, reps: 5, weightKg: 120),
      _makeSetLog(exerciseName: 'Squat', setNumber: 3, reps: 5, weightKg: 120),
      _makeSetLog(
          exerciseName: 'Bench Press', setNumber: 1, reps: 8, weightKg: 80),
      _makeSetLog(
          exerciseName: 'Bench Press', setNumber: 2, reps: 8, weightKg: 80),
    ];

    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (session: _makeSession(), setLogs: setLogs),
    ));
    await tester.pumpAndSettle();

    // Both exercise headers visible.
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);

    // Set numbers 1..3 appear (at least Squat has 1,2,3).
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('3'), findsOneWidget);

    // No edit/delete buttons anywhere in the tree.
    expect(find.byType(IconButton), findsOneWidget); // only the back button
  });

  // ── #628 — el alumno relee lo que él mismo reportó ────────────────────────

  testWidgets('#628: el alumno ve su propio reporte pegado a la serie',
      (tester) async {
    // No alcanza con que lo vea el PF: si el reporte sólo existe del otro
    // lado, la persona no tiene registro de lo que dijo que le pasó.
    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (
        session: _makeSession(),
        setLogs: [_makeSetLog(setNumber: 1), _makeSetLog(setNumber: 2)],
      ),
      feedback: [_makeFeedback(setNumber: 2)],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Me tira el hombro'), findsOneWidget);
  });

  testWidgets('#628: un reporte sobre un ejercicio SIN series igual se ve',
      (tester) async {
    // Serie pendiente que nunca se registró / miembro de superset que no fue
    // la celda activa: cero SetLogs de ese exerciseId.
    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (
        session: _makeSession(),
        setLogs: [_makeSetLog(exerciseName: 'Squat')],
      ),
      feedback: [
        _makeFeedback(
          exerciseId: 'e-remo',
          exerciseName: 'Remo en polea',
          setNumber: 1,
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Squat'), findsOneWidget);
    expect(find.text('Remo en polea'), findsOneWidget);
    expect(find.text('Me tira el hombro'), findsOneWidget);
  });

  testWidgets('#628: sesión con reportes y CERO series no muestra el vacío',
      (tester) async {
    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (session: _makeSession(), setLogs: <SetLog>[]),
      feedback: [_makeFeedback(exerciseName: 'Remo en polea')],
    ));
    await tester.pumpAndSettle();

    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
    expect(find.text(l10n.sessionDetailNoSets), findsNothing);
    expect(find.text('Remo en polea'), findsOneWidget);
    expect(find.text('Me tira el hombro'), findsOneWidget);
  });

  testWidgets(
      '#628: si FALLA la lectura de reportes se avisa Y la sesión sigue',
      (tester) async {
    // Del lado del alumno el silencio es igual de malo: relee la sesión, no ve
    // ningún reporte y da por hecho que no reportó nada. El aviso usa la clave
    // PROPIA (`sessionFeedbackLoadError`, "tus reportes") — la del PF habla de
    // "los reportes del alumno" y acá el alumno es el que lee.
    await tester.pumpWidget(_pumpDetailScreen(
      summaryOverride: () => (
        session: _makeSession(),
        setLogs: [_makeSetLog(exerciseName: 'Squat')],
      ),
      feedbackError: true,
    ));
    await tester.pumpAndSettle();

    final l10n = await AppL10n.delegate.load(const Locale('es', 'AR'));
    expect(find.text(l10n.sessionFeedbackLoadError), findsOneWidget);
    // La sesión NO se cae ni se vacía por un fallo leyendo reportes.
    expect(find.text('Squat'), findsOneWidget);
    expect(find.text(l10n.sessionDetailNoSets), findsNothing);
  });
}
