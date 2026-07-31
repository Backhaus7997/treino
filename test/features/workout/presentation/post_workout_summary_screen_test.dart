// Tests for PostWorkoutSummaryScreen — SCENARIO-342..353
// TDD RED: each group must fail before its GREEN implementation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/insights/domain/radar_axis.dart';
import 'package:treino/features/insights/presentation/widgets/muscle_distribution_radar.dart';
import 'package:treino/features/workout/application/post_workout_notifier.dart';
import 'package:treino/features/workout/application/session_highlights.dart';
import 'package:treino/features/workout/application/session_muscle_distribution.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_recognition.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/post_workout_summary_screen.dart';
import 'package:treino/features/workout/presentation/widgets/session_stats_card.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Session _makeSession({
  bool wasFullyCompleted = true,
  String routineName = 'Push',
  String routineId = 'r1',
  int durationMin = 52,
  double totalVolumeKg = 3.2,
}) =>
    Session(
      id: 's1',
      uid: 'u1',
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 18, 10, 0),
      finishedAt: DateTime.utc(2026, 5, 18, 11, 0),
      totalVolumeKg: totalVolumeKg,
      durationMin: durationMin,
      status: SessionStatus.finished,
      dayNumber: 1,
      wasFullyCompleted: wasFullyCompleted,
    );

SetLog _makeSetLog({String exerciseId = 'e1'}) => SetLog(
      id: 'sl1',
      exerciseId: exerciseId,
      exerciseName: 'Press',
      setNumber: 1,
      reps: 10,
      weightKg: 50.0,
      completedAt: DateTime.utc(2026, 5, 18, 10, 5),
    );

typedef _SummaryRecord = ({Session? session, List<SetLog> setLogs});

SessionExerciseSummary _exercise({
  String id = 'e1',
  String name = 'Press banca',
  int setCount = 4,
  double bestWeightKg = 80,
  int bestSetReps = 5,
  double sessionVolumeKg = 1200,
  bool isFirstTime = false,
  List<SessionExerciseRecord> records = const [],
}) =>
    (
      exerciseId: id,
      exerciseName: name,
      setCount: setCount,
      bestWeightKg: bestWeightKg,
      bestSetReps: bestSetReps,
      sessionVolumeKg: sessionVolumeKg,
      isFirstTime: isFirstTime,
      records: records,
    );

SessionHighlights _highlights({
  List<SessionExerciseSummary> exercises = const [],
  int recordCount = 0,
  bool hasHistory = true,
  SessionRecognition recognition = noRecognition,
}) =>
    (
      exercises: exercises,
      recordCount: recordCount,
      hasHistory: hasHistory,
      recognition: recognition,
    );

Widget _buildWithRouter({
  required _SummaryRecord Function() summaryOverride,
  PostWorkoutNotifier Function()? notifierOverride,
  bool summaryLoading = false,
  bool summaryError = false,
  SessionMuscleDistribution muscleDistribution = emptySessionMuscleDistribution,
  bool muscleError = false,
  SessionHighlights highlights = emptySessionHighlights,
  bool reduceMotion = false,
  double? textScale,
}) {
  final router = GoRouter(
    initialLocation: '/workout/session-summary/s1',
    routes: [
      GoRoute(
        path: '/workout/session-summary/:sessionId',
        builder: (context, state) => PostWorkoutSummaryScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
      GoRoute(
        path: '/workout',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('workout-home')),
        ),
      ),
      // Stub del composer: acá sólo importa que COMPARTIR navegue; el
      // composer real se testea en share_workout_composer_screen_test.dart.
      GoRoute(
        path: '/workout/session-summary/:sessionId/share',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('composer-screen')),
        ),
      ),
    ],
  );

  final overrides = <Override>[
    sessionSummaryProvider.overrideWith((ref, key) {
      if (summaryLoading) return Completer<_SummaryRecord>().future;
      if (summaryError) return Future.error(Exception('load error'));
      return Future.value(summaryOverride());
    }),
    // Always overridden: the real provider would hit the real exercise
    // catalog (Firestore) from inside a widget test.
    sessionMuscleDistributionProvider.overrideWith((ref, key) {
      if (muscleError) return Future.error(Exception('catalog error'));
      return Future.value(muscleDistribution);
    }),
    // Always overridden: the real provider would scan the athlete's session
    // history (Firestore) from inside a widget test.
    sessionHighlightsProvider.overrideWith(
      (ref, key) => Future.value(highlights),
    ),
    currentUidProvider.overrideWithValue('u1'),
    if (notifierOverride != null)
      postWorkoutNotifierProvider.overrideWith(notifierOverride),
  ];

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
      // Ajustes de accesibilidad inyectados por MediaQuery: "reducir
      // movimiento" (las entradas TreinoFadeSlideIn deben quedar visibles al
      // primer frame) y font scale grande.
      builder: reduceMotion || textScale != null
          ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: reduceMotion ? true : null,
                  textScaler:
                      textScale == null ? null : TextScaler.linear(textScale),
                ),
                child: child!,
              )
          : null,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

// ── SCENARIO-342: loading state ───────────────────────────────────────────────

void main() {
  testWidgets(
      'SCENARIO-342: shows CircularProgressIndicator while sessionSummaryProvider loads',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryLoading: true,
      summaryOverride: () => (session: null, setLogs: []),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // ── SCENARIO-343/344: header conditional ─────────────────────────────────

  testWidgets(
      'SCENARIO-343: shows "BUEN ENTRENO" header when wasFullyCompleted is true',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (
        session: _makeSession(wasFullyCompleted: true, routineName: 'Push'),
        setLogs: [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('BUEN ENTRENO'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
  });

  testWidgets(
      'SCENARIO-344: shows "SESIÓN INTERRUMPIDA" header when wasFullyCompleted is false',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (
        session: _makeSession(wasFullyCompleted: false, routineName: 'Push'),
        setLogs: [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('SESIÓN INTERRUMPIDA'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
  });

  // ── SCENARIO-345/346: stat grid ──────────────────────────────────────────

  testWidgets(
      'SCENARIO-345: stat grid shows correct DURACIÓN/VOLUMEN/SETS/— values',
      (tester) async {
    final setLogs = List.generate(22, (_) => _makeSetLog());
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (
        session: _makeSession(durationMin: 52, totalVolumeKg: 3.2),
        setLogs: setLogs,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('52'), findsOneWidget);
    expect(find.text('3.2'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    // PRS HOY ya es real: con highlights resueltos y sin récords muestra 0.
    expect(find.text('0'), findsOneWidget);

    // Labels carry their unit (#363) — bare DURACIÓN/VOLUMEN must be gone.
    expect(find.text('DURACIÓN MIN'), findsOneWidget);
    expect(find.text('VOLUMEN KG'), findsOneWidget);
    expect(find.text('DURACIÓN'), findsNothing);
    expect(find.text('VOLUMEN'), findsNothing);
  });

  testWidgets('SCENARIO-346: SETS stat uses count from setLogs',
      (tester) async {
    final setLogs = List.generate(5, (_) => _makeSetLog());
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (
        session: _makeSession(),
        setLogs: setLogs,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('stat card owns tile stagger and mood follows its four slots',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
    ));
    await tester.pump();
    await tester.pump();

    final card = tester.widget<SessionStatsCard>(
      find.byType(SessionStatsCard),
    );
    expect(card.animateTiles, isTrue);
    expect(card.entryDelay, AppMotion.stagger(1));

    final cardEntries = tester.widgetList<TreinoFadeSlideIn>(
      find.descendant(
        of: find.byType(SessionStatsCard),
        matching: find.byType(TreinoFadeSlideIn),
      ),
    );
    expect(cardEntries, hasLength(4));

    final moodEntry = tester.widget<TreinoFadeSlideIn>(
      find.ancestor(
        of: find.text('😐'),
        matching: find.byType(TreinoFadeSlideIn),
      ),
    );
    expect(moodEntry.delay, AppMotion.stagger(5));
  });

  // ── PRs reales (reemplaza el stub de SCENARIO-347) ───────────────────────

  testWidgets(
      'PRs: un récord muestra ejercicio, tipo, valor nuevo y marca anterior',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      highlights: _highlights(
        recordCount: 1,
        exercises: [
          _exercise(records: const [
            (
              recordType: ProgressionRecordType.heaviestWeight,
              value: 80.0,
              previousBest: 75.0,
            ),
          ]),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PRS DE LA SESIÓN'), findsOneWidget);
    expect(find.text('Peso máximo'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('→ 75 kg'), findsOneWidget);
    expect(find.textContaining('Próximamente'), findsNothing);
    // El tile PRS HOY refleja el conteo real.
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('PRs: tile PRS HOY muestra el conteo real de récords',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      highlights: _highlights(
        recordCount: 7,
        exercises: [_exercise()],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('7'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('PRs: sin récords pero con historial → línea coherente',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      highlights: _highlights(exercises: [_exercise()]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PRS DE LA SESIÓN'), findsOneWidget);
    expect(find.textContaining('Sin récords nuevos'), findsOneWidget);
  });

  testWidgets(
      'PRs: primer entreno (sin historial) → punto de partida + banner, '
      'sin números inventados', (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      highlights: _highlights(
        hasHistory: false,
        exercises: [_exercise()],
        recognition: (kind: SessionRecognitionKind.firstWorkout, count: 0),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('punto de partida'), findsOneWidget);
    expect(find.text('PRIMER ENTRENO COMPLETADO'), findsOneWidget);
  });

  testWidgets(
      'PRs: sesión abandonada → sin sección PRS, tile "—", EJERCICIOS sí',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () =>
          (session: _makeSession(wasFullyCompleted: false), setLogs: []),
      highlights: _highlights(exercises: [_exercise()]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PRS DE LA SESIÓN'), findsNothing);
    expect(find.text('EJERCICIOS'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  // ── Banner de reconocimiento ─────────────────────────────────────────────

  testWidgets('reconocimiento: récords → "2 RÉCORDS NUEVOS"', (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      highlights: _highlights(
        recordCount: 2,
        exercises: [_exercise()],
        recognition: (kind: SessionRecognitionKind.records, count: 2),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2 RÉCORDS NUEVOS'), findsOneWidget);
  });

  testWidgets('reconocimiento: nthSessionOfWeek → "3ª SESIÓN DE LA SEMANA"',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      highlights: _highlights(
        exercises: [_exercise()],
        recognition: (
          kind: SessionRecognitionKind.nthSessionOfWeek,
          count: 3,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3ª SESIÓN DE LA SEMANA'), findsOneWidget);
  });

  testWidgets('reconocimiento: none → sin banner', (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      highlights: _highlights(exercises: [_exercise()]),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('RÉCORD'), findsNothing);
    expect(find.textContaining('SESIÓN DE LA SEMANA'), findsNothing);
  });

  // ── Sección EJERCICIOS ───────────────────────────────────────────────────

  testWidgets(
      'EJERCICIOS: filas con sets y mejor set, badges PR / 1ª VEZ y '
      'estrella al de mayor volumen', (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      highlights: _highlights(
        recordCount: 1,
        exercises: [
          _exercise(
            records: const [
              (
                recordType: ProgressionRecordType.heaviestWeight,
                value: 80.0,
                previousBest: 75.0,
              ),
            ],
          ),
          _exercise(
            id: 'e2',
            name: 'Dominadas',
            setCount: 3,
            bestWeightKg: 0,
            bestSetReps: 12,
            sessionVolumeKg: 0,
            isFirstTime: true,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('EJERCICIOS'), findsOneWidget);
    expect(find.text('Press banca'), findsWidgets);
    expect(find.text('4 sets · 80 kg × 5'), findsOneWidget);
    // Bodyweight (#368): mejor set solo por reps.
    expect(find.text('3 sets · 12 reps'), findsOneWidget);
    expect(find.text('PR'), findsOneWidget);
    expect(find.text('1ª VEZ'), findsOneWidget);
    // Destacado: e1 tiene el mayor volumen → una sola estrella.
    expect(find.byIcon(TreinoIcon.starFill), findsOneWidget);
  });

  // ── Reduced motion ───────────────────────────────────────────────────────

  testWidgets(
      'reduce-motion: todo visible al primer frame, sin animar entradas',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      highlights: _highlights(
        recordCount: 1,
        exercises: [_exercise()],
        recognition: (kind: SessionRecognitionKind.records, count: 1),
      ),
      reduceMotion: true,
    ));
    // Solo frames sueltos — nada de pumpAndSettle: si algo animara, acá
    // seguiría a mitad de camino.
    await tester.pump();
    await tester.pump();

    expect(find.text('BUEN ENTRENO'), findsOneWidget);
    expect(find.text('1 RÉCORD NUEVO'), findsOneWidget);
    final fades = tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(TreinoFadeSlideIn),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades, isNotEmpty);
    for (final fade in fades) {
      expect(fade.opacity.value, 1.0);
    }
  });

  testWidgets('sin reduce-motion las entradas SÍ arrancan invisibles',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
    ));
    await tester.pump();
    await tester.pump();

    final fades = tester.widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(TreinoFadeSlideIn),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fades, isNotEmpty);
    expect(fades.any((f) => f.opacity.value < 1.0), isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('SCENARIO-348: renders exactly 5 emoji Text widgets in mood row',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
    ));
    await tester.pumpAndSettle();

    // The 5 mood emojis are plain Text widgets with emoji strings
    final emojiTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) =>
            t.data != null &&
            RegExp(r'[\u{1F600}-\u{1F64F}]', unicode: true).hasMatch(t.data!))
        .toList();
    expect(emojiTexts.length, equals(5));
  });

  // ── #456 regression: mood row must never overflow ────────────────────────

  testWidgets(
      '#456: mood row scales down instead of overflowing on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(180, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // At this extreme width the StatTile grid cells legitimately overflow
    // vertically before the mood row is even laid out, which would fail the
    // test for an unrelated reason. Capture layout errors and assert that
    // nothing overflows HORIZONTALLY — the mood row is the only horizontal
    // Flex at risk on this screen (#456).
    final horizontalOverflows = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed')) {
        if (message.contains('on the right')) {
          horizontalOverflows.add(details);
        }
        return; // vertical overflows of unrelated widgets tolerated here
      }
      originalOnError?.call(details);
    };
    try {
      await tester.pumpWidget(_buildWithRouter(
        summaryOverride: () => (session: _makeSession(), setLogs: []),
      ));
      await tester.pumpAndSettle();
    } finally {
      // Must be restored BEFORE any expect(): the test binding reports expect
      // failures through FlutterError.onError and asserts it wasn't replaced.
      FlutterError.onError = originalOnError;
    }

    expect(
      horizontalOverflows.map((d) => d.exceptionAsString()).toList(),
      isEmpty,
    );

    // The row itself still renders its 5 emojis (scaled, not dropped).
    final emojiTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) =>
            t.data != null &&
            RegExp(r'[\u{1F600}-\u{1F64F}]', unicode: true).hasMatch(t.data!))
        .toList();
    expect(emojiTexts.length, equals(5));
  });

  testWidgets(
      'filas de PRs y EJERCICIOS no desbordan horizontalmente: pantalla '
      'angosta con estrella, badges y valores largos', (tester) async {
    tester.view.physicalSize = const Size(180, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final horizontalOverflows = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed')) {
        if (message.contains('on the right')) {
          horizontalOverflows.add(details);
        }
        return; // los overflows verticales del grid a este ancho no aplican
      }
      originalOnError?.call(details);
    };
    try {
      await tester.pumpWidget(_buildWithRouter(
        summaryOverride: () => (session: _makeSession(), setLogs: []),
        highlights: _highlights(
          recordCount: 1,
          exercises: [
            _exercise(
              name: 'Press de banca inclinado con mancuernas',
              records: const [
                (
                  recordType: ProgressionRecordType.bestSetVolume,
                  value: 412.5,
                  previousBest: 375.0,
                ),
              ],
            ),
            _exercise(
              id: 'e2',
              name: 'Elevaciones laterales',
              sessionVolumeKg: 300,
              isFirstTime: true,
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = originalOnError;
    }

    expect(
      horizontalOverflows.map((d) => d.exceptionAsString()).toList(),
      isEmpty,
    );
    // Las secciones siguen presentes (escaladas, no descartadas).
    expect(find.text('PRS DE LA SESIÓN'), findsOneWidget);
    expect(find.text('EJERCICIOS'), findsOneWidget);
    expect(find.text('PR'), findsOneWidget);
    expect(find.text('1ª VEZ'), findsOneWidget);
  });

  testWidgets(
      'filas de PRs y EJERCICIOS no desbordan con font scale de '
      'accesibilidad 3x en un ancho normal', (tester) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final horizontalOverflows = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed')) {
        if (message.contains('on the right')) {
          horizontalOverflows.add(details);
        }
        return;
      }
      originalOnError?.call(details);
    };
    try {
      await tester.pumpWidget(_buildWithRouter(
        textScale: 3.0,
        summaryOverride: () => (session: _makeSession(), setLogs: []),
        highlights: _highlights(
          recordCount: 1,
          exercises: [
            _exercise(
              name: 'Press de banca inclinado con mancuernas',
              isFirstTime: true,
              records: const [
                (
                  recordType: ProgressionRecordType.bestSetVolume,
                  value: 412.5,
                  previousBest: 375.0,
                ),
              ],
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = originalOnError;
    }

    expect(
      horizontalOverflows.map((d) => d.exceptionAsString()).toList(),
      isEmpty,
    );
  });

  // ── SCENARIO-349/350: LISTO + COMPARTIR buttons ──────────────────────────

  testWidgets('SCENARIO-349: LISTO button navigates to /workout without Post',
      (tester) async {
    bool shareCalled = false;

    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      notifierOverride: () => _TrackingNotifier(onShare: () {
        shareCalled = true;
      }),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('LISTO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LISTO'));
    await tester.pumpAndSettle();

    expect(find.text('workout-home'), findsOneWidget);
    expect(shareCalled, isFalse);
  });

  // ── SCENARIO-350 (actualizado, share-composer PR2) ───────────────────────
  //
  // COMPARTIR ya NO publica de una: abre el composer, donde el texto es
  // editable y se puede adjuntar una foto. Publicar (y sus snackbars de éxito
  // y error, ex SCENARIO-351/352) vive ahora en
  // share_workout_composer_screen_test.dart, junto con el assert del conteo
  // de ejercicios DISTINTOS (ex QA-FEED-364/389).

  testWidgets('SCENARIO-350: COMPARTIR abre el composer sin publicar todavía',
      (tester) async {
    bool shareCalled = false;

    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      notifierOverride: () => _TrackingNotifier(onShare: () {
        shareCalled = true;
      }),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('COMPARTIR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMPARTIR'));
    await tester.pumpAndSettle();

    expect(find.text('composer-screen'), findsOneWidget);
    // Nada se publicó con el tap: eso ocurre recién al confirmar en el
    // composer.
    expect(shareCalled, isFalse);
    expect(find.text('workout-home'), findsNothing);
  });

  // ── SCENARIO-353: not-found state ────────────────────────────────────────

  testWidgets('SCENARIO-353: shows "Sesión no encontrada" when session is null',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: null, setLogs: []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sesión no encontrada'), findsOneWidget);

    await tester.tap(find.text('Volver a Entrenar'));
    await tester.pumpAndSettle();

    expect(find.text('workout-home'), findsOneWidget);
  });

  // ── Muscle distribution section ──────────────────────────────────────────

  testWidgets(
      'muscle distribution: ≥3 axes → radar without legend or stat cards',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      muscleDistribution: (
        setsByAxis: {
          RadarAxis.chest: 6,
          RadarAxis.arms: 4,
          RadarAxis.shoulders: 3,
        },
        volumeKgByAxis: {
          RadarAxis.chest: 1200.0,
          RadarAxis.arms: 400.0,
          RadarAxis.shoulders: 300.0,
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('DISTRIBUCIÓN MUSCULAR'), findsOneWidget);
    expect(find.byType(MuscleDistributionRadar), findsOneWidget);
    // Single-session mode: no Actual/Anterior legend, no stat cards (the
    // 2×2 grid above already shows those metrics).
    expect(find.text('Actual'), findsNothing);
    expect(find.text('Anterior'), findsNothing);
    expect(find.text('Entrenos'), findsNothing);
  });

  testWidgets(
      'muscle distribution: con 2 ejes también va el radar — las barras del '
      'PR #586 ya no existen (pedido directo: el mismo gráfico de Insights)',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      muscleDistribution: (
        setsByAxis: {RadarAxis.legs: 4, RadarAxis.core: 2},
        volumeKgByAxis: {RadarAxis.legs: 400.0, RadarAxis.core: 0.0},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('DISTRIBUCIÓN MUSCULAR'), findsOneWidget);
    expect(find.byType(MuscleDistributionRadar), findsOneWidget);
    expect(find.text('4 sets · 400 kg'), findsNothing);
  });

  testWidgets(
      'muscle distribution: un solo grupo (día de piernas) → radar igual, '
      'sin NaN ni crash', (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      muscleDistribution: (
        setsByAxis: {RadarAxis.legs: 12},
        volumeKgByAxis: {RadarAxis.legs: 2400.0},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(MuscleDistributionRadar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('muscle distribution: empty distribution → whole section absent',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('DISTRIBUCIÓN MUSCULAR'), findsNothing);
    expect(find.byType(MuscleDistributionRadar), findsNothing);
  });

  testWidgets(
      'muscle distribution: resolver error → section absent, summary intact',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      muscleError: true,
    ));
    await tester.pumpAndSettle();

    expect(find.text('DISTRIBUCIÓN MUSCULAR'), findsNothing);
    expect(find.text('BUEN ENTRENO'), findsOneWidget);
  });
}

// ── Stub notifiers ────────────────────────────────────────────────────────────

class _TrackingNotifier extends PostWorkoutNotifier {
  _TrackingNotifier({required this.onShare});
  final void Function() onShare;
  int? capturedExerciseCount;

  @override
  Future<void> shareWorkout(
    Session session, {
    required String text,
    required int exerciseCount,
    required PostPrivacy privacy,
    String? localPhotoPath,
  }) async {
    capturedExerciseCount = exerciseCount;
    onShare();
    state = const AsyncData(null);
  }
}

// Los stubs de éxito/error del share vivían acá para SCENARIO-351/352; esos
// escenarios se mudaron a share_workout_composer_screen_test.dart cuando
// COMPARTIR pasó a abrir el composer en vez de publicar.
