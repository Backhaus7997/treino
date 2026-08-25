import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
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
    Routine(id: id, name: name, split: 'Full Body', level: level, days: days);

RoutineSlot _makeSlot(int i) => RoutineSlot(
      exerciseId: 'ex-$i',
      exerciseName: 'Exercise $i',
      muscleGroup: 'Chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
    );

RoutineDay makeDayWithSlots(
  int slotCount, {
  int dayNumber = 1,
  int? estimatedMinutes,
}) =>
    RoutineDay(
      dayNumber: dayNumber,
      name: 'Day $dayNumber',
      slots: List.generate(slotCount, _makeSlot),
      estimatedMinutes: estimatedMinutes,
    );

// Localizations are required since #639: the metadata caption is built from
// l10n keys (days/week is a plural, minutes carries a unit), so the card can
// no longer render under a bare MaterialApp.
Widget _wrap(Widget w, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: w),
      ),
    );

void main() {
  group('RoutineCard', () {
    testWidgets('uses TreinoTappable for press feedback', (tester) async {
      final routine = makeRoutine();
      await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
      await tester.pump();

      expect(find.byType(TreinoTappable), findsOneWidget);
    });

    testWidgets('name is rendered UPPERCASE', (tester) async {
      final routine = makeRoutine(name: 'full body');
      await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
      await tester.pump();
      expect(find.text('FULL BODY'), findsOneWidget);
    });

    // ── Metadata caption (#639) ──────────────────────────────────────────
    //
    // Replaces the old `{LevelEs} · {N} ej.` assertions. That exercise count
    // summed EVERY day, so a multi-day routine advertised a number no single
    // session ever matched; the caption now answers the two questions a reader
    // actually has: how many days a week, and how long a session runs.

    testWidgets(
      'caption shows level, days per week and the authored session length',
      (tester) async {
        final routine = makeRoutine(
          level: ExperienceLevel.beginner,
          days: [
            makeDayWithSlots(5, estimatedMinutes: 45),
            makeDayWithSlots(3, dayNumber: 2, estimatedMinutes: 45),
          ],
        );
        await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
        await tester.pump();
        expect(find.text('Principiante · 2 días/sem · 45 min'), findsOneWidget);
      },
    );

    testWidgets('a computed duration is prefixed "~" to read as an estimate', (
      tester,
    ) async {
      final routine = makeRoutine(
        level: ExperienceLevel.beginner,
        // No estimatedMinutes anywhere → the figure comes from the slots.
        days: [makeDayWithSlots(3)],
      );
      await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
      await tester.pump();
      expect(find.textContaining('· ~'), findsOneWidget);
      expect(find.textContaining('min'), findsOneWidget);
    });

    testWidgets('one day per week is singular, not "1 días/sem"', (
      tester,
    ) async {
      final routine = makeRoutine(
        days: [makeDayWithSlots(2, estimatedMinutes: 30)],
      );
      await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
      await tester.pump();
      expect(find.textContaining('1 día/sem'), findsOneWidget);
      expect(find.textContaining('1 días/sem'), findsNothing);
    });

    testWidgets(
      'nothing measurable → the duration segment is dropped, never "0 min"',
      (tester) async {
        final routine = makeRoutine(
          level: ExperienceLevel.beginner,
          days: [makeDayWithSlots(0)], // a day with no slots
        );
        await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
        await tester.pump();
        expect(find.text('Principiante · 1 día/sem'), findsOneWidget);
        expect(find.textContaining('min'), findsNothing);
      },
    );

    testWidgets(
      'zero-day routine → level alone, no "0 días/sem"',
      (tester) async {
        final routine = makeRoutine(
          level: ExperienceLevel.intermediate,
          days: const [],
        );
        await tester.pumpWidget(_wrap(RoutineCard(routine: routine)));
        await tester.pump();
        expect(find.text('Intermedio'), findsOneWidget);
        expect(find.textContaining('días/sem'), findsNothing);
      },
    );

    testWidgets('Icon widget present; no Image widget (imageUrl null)', (
      tester,
    ) async {
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
              body: RoutineCard(routine: makeRoutine(id: 'my-routine-id')),
            ),
          ),
          GoRoute(
            path: '/workout/routine/:id',
            builder: (_, state) =>
                Scaffold(body: Text('detail-${state.pathParameters['id']}')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            routerConfig: mockRouter,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      expect(find.text('detail-my-routine-id'), findsOneWidget);
    });

    testWidgets(
        'reserveTitleLines → card height independent of 1-line vs 2-line name',
        (tester) async {
      // La card vive siempre en contextos de altura unbounded (celda de
      // Table en Plantillas, children de ListView en feed/profile) donde su
      // Column interna se ajusta al contenido — la Column del harness replica
      // eso; bajo altura bounded (p.ej. Center) se estiraría al viewport.
      Widget host(String name, {required bool reserve}) => ProviderScope(
            child: MaterialApp(
              theme: AppTheme.dark(),
              localizationsDelegates: AppL10n.localizationsDelegates,
              supportedLocales: AppL10n.supportedLocales,
              locale: const Locale('es', 'AR'),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 280,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RoutineCard(
                          routine: makeRoutine(name: name),
                          reserveTitleLines: reserve,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );

      const shortName = 'Push';
      const longName =
          'Rutina de hipertrofia avanzada del tren superior completo';

      await tester.pumpWidget(host(shortName, reserve: true));
      await tester.pump();
      final reservedShort = tester.getSize(find.byType(RoutineCard)).height;

      await tester.pumpWidget(host(longName, reserve: true));
      await tester.pump();
      final reservedLong = tester.getSize(find.byType(RoutineCard)).height;

      // With the reservation the height is deterministic — the grid rows in
      // PlantillasSection align without an IntrinsicHeight pass (#402).
      expect(reservedShort, moreOrLessEquals(reservedLong, epsilon: 0.01));

      // Without it (default), a short name yields a shorter card — the flag
      // is what guarantees the deterministic height.
      await tester.pumpWidget(host(shortName, reserve: false));
      await tester.pump();
      final naturalShort = tester.getSize(find.byType(RoutineCard)).height;
      expect(naturalShort, lessThan(reservedShort));
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
