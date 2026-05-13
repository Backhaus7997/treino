import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/widgets/routine_card.dart';

Routine makeRoutine({
  String id = 'test-id',
  String name = 'Full Body',
  ExperienceLevel level = ExperienceLevel.beginner,
  List<RoutineDay> days = const [],
}) =>
    Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: level,
      days: days,
    );

RoutineSlot _makeSlot(int i) => RoutineSlot(
      exerciseId: 'ex-$i',
      exerciseName: 'Exercise $i',
      muscleGroup: 'Chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
    );

RoutineDay makeDayWithSlots(int slotCount) => RoutineDay(
      dayNumber: 1,
      name: 'Day 1',
      slots: List.generate(slotCount, _makeSlot),
    );

Widget _wrap(Widget w, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

void main() {
  group('RoutineCard', () {
    testWidgets('name is rendered UPPERCASE', (tester) async {
      final routine = makeRoutine(name: 'full body');
      await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
      await tester.pump();
      expect(find.text('FULL BODY'), findsOneWidget);
    });

    testWidgets(
        'subtitle shows "{LevelEs} · {N} ej." — 2 days (5+3 slots) → "Principiante · 8 ej."',
        (tester) async {
      final routine = makeRoutine(
        level: ExperienceLevel.beginner,
        days: [
          makeDayWithSlots(5),
          makeDayWithSlots(3),
        ],
      );
      await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
      await tester.pump();
      expect(find.text('Principiante · 8 ej.'), findsOneWidget);
    });

    testWidgets('subtitle for zero-day routine → "{LevelEs} · 0 ej."',
        (tester) async {
      final routine = makeRoutine(
        level: ExperienceLevel.intermediate,
        days: const [],
      );
      await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
      await tester.pump();
      expect(find.text('Intermedio · 0 ej.'), findsOneWidget);
    });

    testWidgets('Icon widget present; no Image widget (imageUrl null)',
        (tester) async {
      final routine = makeRoutine();
      await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
      await tester.pump();
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('tap navigates to /workout/routine/:id route', (tester) async {
      final mockRouter = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: RoutineCard(
                routine: makeRoutine(id: 'my-routine-id'),
              ),
            ),
          ),
          GoRoute(
            path: '/workout/routine/:id',
            builder: (_, state) => Scaffold(
              body: Text('detail-${state.pathParameters['id']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: mockRouter,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.text('detail-my-routine-id'), findsOneWidget);
    });

    testWidgets('renders without crash (smoke)', (tester) async {
      final routine = makeRoutine(
        name: 'PPL Advanced',
        level: ExperienceLevel.advanced,
        days: [makeDayWithSlots(4)],
      );
      await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
      await tester.pump();
      expect(find.byType(RoutineCard), findsOneWidget);
    });
  });
}
