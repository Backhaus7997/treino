// Tests for PostWorkoutSummaryScreen — SCENARIO-342..353
// TDD RED: each group must fail before its GREEN implementation.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/application/post_workout_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/post_workout_summary_screen.dart';
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

SetLog _makeSetLog() => SetLog(
      id: 'sl1',
      exerciseId: 'e1',
      exerciseName: 'Press',
      setNumber: 1,
      reps: 10,
      weightKg: 50.0,
      completedAt: DateTime.utc(2026, 5, 18, 10, 5),
    );

typedef _SummaryRecord = ({Session? session, List<SetLog> setLogs});

Widget _buildWithRouter({
  required _SummaryRecord Function() summaryOverride,
  PostWorkoutNotifier Function()? notifierOverride,
  bool summaryLoading = false,
  bool summaryError = false,
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
    ],
  );

  final overrides = <Override>[
    sessionSummaryProvider.overrideWith((ref, key) {
      if (summaryLoading) return Completer<_SummaryRecord>().future;
      if (summaryError) return Future.error(Exception('load error'));
      return Future.value(summaryOverride());
    }),
    currentUidProvider.overrideWithValue('u1'),
    if (notifierOverride != null)
      postWorkoutNotifierProvider.overrideWith(notifierOverride),
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
    expect(find.text('—'), findsWidgets);
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

  // ── SCENARIO-347/348: PRs section + mood row ─────────────────────────────

  testWidgets('SCENARIO-347: renders PRs section with placeholder content',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Próximamente'),
      findsOneWidget,
    );
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

  testWidgets(
      'SCENARIO-350: COMPARTIR button triggers shareWorkout on notifier',
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

    expect(shareCalled, isTrue);
  });

  // ── SCENARIO-351/352: SnackBars ──────────────────────────────────────────

  testWidgets(
      'SCENARIO-351: success SnackBar "¡Post compartido!" + nav to /workout',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      notifierOverride: () => _SuccessNotifier(),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('COMPARTIR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMPARTIR'));
    await tester.pumpAndSettle();

    expect(find.text('¡Post compartido!'), findsOneWidget);
    expect(find.text('workout-home'), findsOneWidget);
  });

  testWidgets(
      'SCENARIO-352: error SnackBar shown without nav on shareWorkout failure',
      (tester) async {
    await tester.pumpWidget(_buildWithRouter(
      summaryOverride: () => (session: _makeSession(), setLogs: []),
      notifierOverride: () => _ErrorNotifier(),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('COMPARTIR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMPARTIR'));
    await tester.pumpAndSettle();

    expect(find.text('No pudimos compartir tu post. Intentá de nuevo.'), findsOneWidget);
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
}

// ── Stub notifiers ────────────────────────────────────────────────────────────

class _TrackingNotifier extends PostWorkoutNotifier {
  _TrackingNotifier({required this.onShare});
  final void Function() onShare;

  @override
  Future<void> shareWorkout(Session session) async {
    onShare();
    state = const AsyncData(null);
  }
}

class _SuccessNotifier extends PostWorkoutNotifier {
  @override
  Future<void> shareWorkout(Session session) async {
    state = const AsyncLoading();
    await Future<void>.delayed(Duration.zero);
    state = const AsyncData(null);
  }
}

class _ErrorNotifier extends PostWorkoutNotifier {
  @override
  Future<void> shareWorkout(Session session) async {
    state = const AsyncLoading();
    await Future<void>.delayed(Duration.zero);
    final err = Exception('fail');
    state = AsyncError(err, StackTrace.empty);
    throw err;
  }
}
