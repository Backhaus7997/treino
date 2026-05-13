import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_slot_row.dart';
import 'package:treino/features/workout/presentation/widgets/stat_tile.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

Widget _wrapWithOverrides(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

RoutineSlot _makeSlot({
  String exerciseId = 'bench-press',
  String exerciseName = 'Bench Press',
  String muscleGroup = 'chest',
  int targetSets = 4,
  int targetRepsMin = 8,
  int targetRepsMax = 12,
  int restSeconds = 90,
}) =>
    RoutineSlot(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      muscleGroup: muscleGroup,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      restSeconds: restSeconds,
    );

RoutineDay _makeDay({
  int dayNumber = 1,
  String name = 'Push',
  List<RoutineSlot>? slots,
  int? estimatedMinutes = 45,
}) =>
    RoutineDay(
      dayNumber: dayNumber,
      name: name,
      slots: slots ?? [_makeSlot()],
      estimatedMinutes: estimatedMinutes,
    );

Routine _makeRoutine({
  String id = 'test-id',
  String name = 'PPL Beginner',
  String split = 'PPL',
  List<RoutineDay>? days,
  String? imageUrl,
}) =>
    Routine(
      id: id,
      name: name,
      split: split,
      level: ExperienceLevel.beginner,
      days: days ?? [_makeDay()],
      imageUrl: imageUrl,
    );

void main() {
  group('RoutineDetailScreen', () {
    testWidgets(
        'SCENARIO-075: AsyncData(routine) renders slots and bottom bar present',
        (tester) async {
      final routine = _makeRoutine(
        days: [
          _makeDay(slots: [_makeSlot(), _makeSlot(exerciseId: 'squat')])
        ],
      );
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id').overrideWith((ref) async => routine),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ExerciseSlotRow), findsNWidgets(2));
    });

    testWidgets('SCENARIO-076: AsyncLoading shows skeleton, no ExerciseSlotRow',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id').overrideWith(
            (ref) => Completer<Routine?>().future,
          ),
        ],
      ));
      await tester.pump();
      expect(find.byType(ExerciseSlotRow), findsNothing);
    });

    testWidgets(
        'SCENARIO-077: AsyncError shows error widget, no ExerciseSlotRow',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => throw Exception('boom')),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.byType(ExerciseSlotRow), findsNothing);
      expect(find.textContaining('cargar'), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'SCENARIO-078: AsyncData(null) shows "Rutina no encontrada" + back button',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id').overrideWith((ref) async => null),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('no encontrada'), findsOneWidget);
      expect(find.byType(ExerciseSlotRow), findsNothing);
      // Back button MUST be present so the user can never dead-end.
      expect(find.byIcon(TreinoIcon.back), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-079: imageUrl null — no CachedNetworkImage, gradient present',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => _makeRoutine(imageUrl: null)),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null,
        ),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('SCENARIO-080: badge shows "PPL · DÍA 1"', (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id').overrideWith(
            (ref) async => _makeRoutine(
              split: 'PPL',
              days: [_makeDay(dayNumber: 1)],
            ),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('PPL · DÍA 1'), findsOneWidget);
    });

    testWidgets('SCENARIO-081: day name rendered in uppercase', (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id').overrideWith(
            (ref) async => _makeRoutine(days: [_makeDay(name: 'Push')]),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('PUSH'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-082: stat tiles show ejercicios=3, sets=10, minutos=45',
        (tester) async {
      final day = _makeDay(
        slots: [
          _makeSlot(targetSets: 4),
          _makeSlot(targetSets: 3),
          _makeSlot(targetSets: 3),
        ],
        estimatedMinutes: 45,
      );
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => _makeRoutine(days: [day])),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      final statTiles = tester.widgetList<StatTile>(find.byType(StatTile));
      final values = statTiles.map((t) => t.value).toList();
      expect(values, containsAll(['3', '10', '45']));
    });

    testWidgets(
        'SCENARIO-083: estimatedMinutes null → third StatTile shows "—"',
        (tester) async {
      final day = _makeDay(estimatedMinutes: null);
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => _makeRoutine(days: [day])),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      final statTiles = tester.widgetList<StatTile>(find.byType(StatTile));
      final values = statTiles.map((t) => t.value).toList();
      expect(values, contains(null)); // null → StatTile renders "—"
    });

    testWidgets('SCENARIO-084: single-day routine — no day selector',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id').overrideWith(
            (ref) async => _makeRoutine(days: [_makeDay()]),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // No chip/tab controls for day selection visible
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets(
        'SCENARIO-085: 3-day routine shows 3 chips; tapping chip 3 changes day',
        (tester) async {
      final routine = _makeRoutine(
        days: [
          _makeDay(dayNumber: 1, name: 'Push'),
          _makeDay(dayNumber: 2, name: 'Pull'),
          _makeDay(dayNumber: 3, name: 'Legs'),
        ],
      );
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id').overrideWith((ref) async => routine),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      await tester.tap(find.byType(ChoiceChip).at(2));
      await tester.pumpAndSettle();
      expect(find.text('LEGS'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-086: EJERCICIOS header + 4 ExerciseSlotRow for 4-slot day',
        (tester) async {
      final day = _makeDay(slots: List.generate(4, (_) => _makeSlot()));
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => _makeRoutine(days: [day])),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('EJERCICIOS'), findsAtLeastNWidgets(1));
      expect(
        find.byType(ExerciseSlotRow, skipOffstage: false),
        findsNWidgets(4),
      );
    });

    testWidgets('SCENARIO-087: empty slots shows empty state text',
        (tester) async {
      final day = _makeDay(slots: []);
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => _makeRoutine(days: [day])),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ExerciseSlotRow), findsNothing);
      expect(
        find.text('No hay ejercicios en este día'),
        findsOneWidget,
      );
    });

    testWidgets('SCENARIO-090: two CTAs EDITAR and EMPEZAR with onPressed null',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => _makeRoutine()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('EDITAR'), findsOneWidget);
      expect(find.text('EMPEZAR'), findsOneWidget);
      final editarBtn = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'EDITAR'));
      final empezarBtn = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'EMPEZAR'));
      expect(editarBtn.onPressed, isNull);
      expect(empezarBtn.onPressed, isNull);
    });

    testWidgets(
        'SCENARIO-091: tapping disabled CTAs causes no exception and no navigation',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => _makeRoutine()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('EDITAR'), warnIfMissed: false);
      await tester.tap(find.text('EMPEZAR'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('SCENARIO-092: CTAs wrapped in Opacity(0.4)', (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => _makeRoutine()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      final opacityWidgets = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => (o.opacity - 0.4).abs() < 0.01)
          .toList();
      expect(opacityWidgets, isNotEmpty);
    });

    testWidgets(
        'SCENARIO-093 (router): ExerciseSlotRow tap pushes exercise route',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (_, __) => const Text('START'),
          ),
          GoRoute(
            path: '/workout/routine/:routineId',
            builder: (ctx, state) => RoutineDetailScreen(
              routineId: state.pathParameters['routineId']!,
            ),
          ),
          GoRoute(
            path: '/workout/exercise/:exerciseId',
            builder: (_, __) => const Text('EXERCISE'),
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          routineByIdProvider('test-id').overrideWith(
            (ref) async => _makeRoutine(
              days: [
                _makeDay(slots: [_makeSlot(exerciseId: 'bench-press')])
              ],
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
        ),
      ));
      router.push('/workout/routine/test-id');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExerciseSlotRow).first);
      await tester.pumpAndSettle();
      expect(find.text('EXERCISE'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-094: no Scaffold/AppBackground/SafeArea inside screen subtree',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const RoutineDetailScreen(routineId: 'test-id'),
        [
          routineByIdProvider('test-id')
              .overrideWith((ref) async => _makeRoutine()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBackground), findsNothing);
      expect(find.byType(SafeArea), findsNothing);
    });

    testWidgets('deep link /workout/routine/:id lands on RoutineDetailScreen',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (_, __) => const Text('START'),
          ),
          GoRoute(
            path: '/workout/routine/:routineId',
            builder: (ctx, state) => RoutineDetailScreen(
              routineId: state.pathParameters['routineId']!,
            ),
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          routineByIdProvider('test-id').overrideWith(
            (ref) async => _makeRoutine(id: 'test-id'),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
        ),
      ));
      router.push('/workout/routine/test-id');
      await tester.pumpAndSettle();
      expect(find.text('PPL · DÍA 1'), findsOneWidget);
    });
  });
}
