// Widget smoke tests for BibliotecaWebScreen.
// REQ-BIBW-01, REQ-BIBW-02.
// SCENARIO-BIBW-02a.
// T-BIBW-005

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/biblioteca_web_screen.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_source.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-screen-test';

const _bench = Exercise(
  id: 'bench-press',
  name: 'Press de Banca',
  muscleGroup: 'chest',
  category: 'compound',
  equipment: EquipmentType.barra,
  defaultRestSeconds: 90,
);

const _curl = Exercise(
  id: 'biceps-curl',
  name: 'Curl de Bíceps',
  muscleGroup: 'biceps',
  category: 'isolation',
);

final _customEx = CustomExercise(
  id: 'custom-squat',
  ownerId: _kTrainerId,
  name: 'Sentadilla Personalizada',
  muscleGroup: 'quads',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

Routine _makeTemplate(String id, String name) {
  return Routine(
    id: id,
    name: name,
    level: ExperienceLevel.intermediate,
    days: const [
      RoutineDay(dayNumber: 1, name: 'Día 1', slots: []),
    ],
    numWeeks: 8,
    source: RoutineSource.trainerTemplate,
  );
}

final _templateA = _makeTemplate('tpl-a', 'Fuerza Total');
final _templateB = _makeTemplate('tpl-b', 'Hipertrofia Máxima');

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

/// Wraps BibliotecaWebScreen with resolved (non-loading) providers so the
/// counts settle to real values — 2 catalog + 1 custom = 3 ejercicios,
/// 2 templates.
Widget _wrapWithData() {
  return ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(_kTrainerId),
      exercisesProvider.overrideWith((ref) async => [_bench, _curl]),
      customExercisesForTrainerStreamProvider(_kTrainerId).overrideWith(
        (ref) => Stream.value(<CustomExercise>[_customEx]),
      ),
      trainerTemplatesStreamProvider(_kTrainerId).overrideWith(
        (ref) => Stream.value(<Routine>[_templateA, _templateB]),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
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

    testWidgets('renders TreinoSectionHeader for the title', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.byType(TreinoSectionHeader), findsOneWidget);
    });

    testWidgets(
        'header está envuelto en TreinoFadeSlideIn con stagger explícito '
        '(índice 0) — ADR-B7-03', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      final fadeSlideInAncestor = tester.widget<TreinoFadeSlideIn>(
        find.ancestor(
          of: find.byType(TreinoSectionHeader),
          matching: find.byType(TreinoFadeSlideIn),
        ),
      );

      expect(fadeSlideInAncestor.delay, AppMotion.stagger(0));
    });

    testWidgets('shows honest subtitle with real exercise + template counts',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrapWithData());
      await tester.pumpAndSettle();

      // 2 catalog + 1 custom = 3 ejercicios · 2 templates.
      expect(find.textContaining('3 ejercicios'), findsOneWidget);
      expect(find.textContaining('2 templates'), findsOneWidget);
    });

    testWidgets('still has exactly 2 tabs with no own Scaffold/SafeArea',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.byType(Tab), findsNWidgets(2));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(SafeArea), findsNothing);
    });
  });
}
