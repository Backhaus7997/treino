import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/presentation/exercise_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/stat_tile.dart';
import 'package:treino/features/workout/presentation/widgets/technique_instruction_item.dart';

Widget _wrapWithOverrides(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

Exercise _makeExercise({
  String id = 'bench-press',
  String name = 'Bench Press',
  String muscleGroup = 'Pecho',
  String category = 'compound',
  List<String>? techniqueInstructions = const ['Cue 1', 'Cue 2', 'Cue 3'],
  String? videoUrl,
}) =>
    Exercise(
      id: id,
      name: name,
      muscleGroup: muscleGroup,
      category: category,
      techniqueInstructions: techniqueInstructions,
      videoUrl: videoUrl,
    );

void main() {
  group('ExerciseDetailScreen', () {
    testWidgets(
        'SCENARIO-097: AsyncData(exercise) renders without exception and shows name',
        (tester) async {
      final exercise = _makeExercise();
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => exercise),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('BENCH'), findsAtLeastNWidgets(1));
    });

    testWidgets('SCENARIO-098: AsyncLoading shows skeleton, hides name',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) => Completer<Exercise?>().future,
          ),
        ],
      ));
      await tester.pump();
      expect(find.textContaining('BENCH'), findsNothing);
      expect(find.byType(StatTile), findsNothing);
    });

    testWidgets('SCENARIO-099: AsyncError shows error widget without exception',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => throw Exception('boom'),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('cargar'), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'SCENARIO-100: AsyncData(null) shows "Ejercicio no encontrado" + back button',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith((ref) async => null),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('no encontrado'), findsOneWidget);
      // Back button MUST be present so the user can never dead-end.
      expect(find.byIcon(TreinoIcon.back), findsOneWidget);
    });

    testWidgets('SCENARIO-101: breadcrumb and title render in uppercase',
        (tester) async {
      final exercise = _makeExercise(
        name: 'Press de Banca',
        muscleGroup: 'Pecho',
        category: 'compound',
      );
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => exercise),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('PECHO · COMPOUND'), findsOneWidget);
      expect(find.text('PRESS DE BANCA'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-102: exactly 3 StatTiles all showing dash placeholder',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => _makeExercise()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(StatTile), findsNWidgets(3));
      expect(find.text('—'), findsAtLeastNWidgets(3));
    });

    testWidgets(
        'SCENARIO-103: techniqueInstructions renders TÉCNICA header and 3 items',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(
              techniqueInstructions: ['Cue 1', 'Cue 2', 'Cue 3'],
            ),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('TÉCNICA'), findsOneWidget);
      expect(find.byType(TechniqueInstructionItem), findsNWidgets(3));
    });

    testWidgets('SCENARIO-104: techniqueInstructions null shows empty state',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(techniqueInstructions: null),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text('No hay instrucciones de técnica todavía'),
        findsOneWidget,
      );
      expect(find.byType(TechniqueInstructionItem), findsNothing);
    });

    testWidgets('SCENARIO-105: techniqueInstructions empty shows empty state',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(techniqueInstructions: []),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text('No hay instrucciones de técnica todavía'),
        findsOneWidget,
      );
    });

    testWidgets(
        'SCENARIO-106: HISTORIAL section header and empty state always present',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => _makeExercise()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // HISTORIAL is the last section in a CustomScrollView — outside the
      // default test viewport once the persistent back-bar takes ~48px off the
      // top. Scroll it into view before asserting.
      await tester.scrollUntilVisible(
        find.text('Aún no entrenaste este ejercicio'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('HISTORIAL'), findsOneWidget);
      expect(
        find.text('Aún no entrenaste este ejercicio'),
        findsOneWidget,
      );
    });

    testWidgets('SCENARIO-107: videoUrl null renders without exception',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(videoUrl: null),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SCENARIO-108: videoUrl non-null shows "Video próximamente"',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async =>
                _makeExercise(videoUrl: 'https://example.com/video.mp4'),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Video próximamente'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-109: no Scaffold/AppBackground/SafeArea inside screen subtree',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => _makeExercise()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBackground), findsNothing);
      expect(find.byType(SafeArea), findsNothing);
    });
  });
}
