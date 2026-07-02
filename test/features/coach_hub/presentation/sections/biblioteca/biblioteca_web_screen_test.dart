// Widget smoke tests for BibliotecaWebScreen.
// REQ-BIBW-01, REQ-BIBW-02.
// SCENARIO-BIBW-02a.
// T-BIBW-005

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/biblioteca_web_screen.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-screen-test';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps BibliotecaWebScreen in a minimal shell that mimics what
/// CoachHubScaffold provides (Scaffold + Material theme). The screen itself
/// must NOT render its own Scaffold/SafeArea.
Widget _wrap() {
  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(_kTrainerId),
      exercisesProvider.overrideWith(
        // Never completes → stays in AsyncLoading; no Timer leak (no
        // Future.delayed — uses Completer as per the gotcha in PR1).
        (ref) => Completer<List<Exercise>>().future,
      ),
      customExercisesForTrainerStreamProvider(_kTrainerId).overrideWith(
        (ref) => Stream.value(<CustomExercise>[]),
      ),
      trainerTemplatesStreamProvider(_kTrainerId).overrideWith(
        (ref) => Stream.value(<Routine>[]),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      // Scaffold provided by the shell — BibliotecaWebScreen must NOT add one.
      home: const Scaffold(
        body: BibliotecaWebScreen(),
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('BibliotecaWebScreen — contract', () {
    testWidgets('mounts successfully and has 2 tabs — SCENARIO-BIBW-02a',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump(); // single frame

      // TabBar with 2 tabs must exist
      expect(find.byType(TabBar), findsOneWidget);

      // Both tab labels visible (labels include counts: "Ejercicios · N")
      expect(find.textContaining('Ejercicios'), findsWidgets);
      expect(find.textContaining('Templates Rutinas'), findsOneWidget);
    });

    testWidgets('does not render a Scaffold inside itself — SCENARIO-BIBW-02a',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      // The shell provides exactly 1 Scaffold. BibliotecaWebScreen must not
      // add another one inside itself.
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('does not render SafeArea — SCENARIO-BIBW-02a', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.byType(SafeArea), findsNothing);
    });

    testWidgets('BIBLIOTECA header text is present', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('BIBLIOTECA'), findsOneWidget); // i18n
    });
  });
}
