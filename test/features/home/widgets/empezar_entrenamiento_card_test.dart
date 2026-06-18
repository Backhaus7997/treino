import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/home/application/todays_routine_provider.dart';
import 'package:treino/features/home/widgets/empezar_entrenamiento_card.dart';
import 'package:treino/features/home/widgets/home_cta_button.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/l10n/app_l10n.dart';

// ─── Test factories ──────────────────────────────────────────────────────────

RoutineSlot _slot({
  String exerciseId = 'bench-press',
  String exerciseName = 'Press de banca',
  String muscleGroup = 'chest',
  int targetSets = 3,
}) =>
    RoutineSlot(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      muscleGroup: muscleGroup,
      targetSets: targetSets,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
    );

RoutineDay _day({
  int dayNumber = 4,
  String name = 'DÍA 4',
  List<RoutineSlot>? slots,
  int? estimatedMinutes,
}) =>
    RoutineDay(
      dayNumber: dayNumber,
      name: name,
      slots: slots ?? [_slot(), _slot(muscleGroup: 'shoulders'), _slot(muscleGroup: 'triceps')],
      estimatedMinutes: estimatedMinutes,
    );

Routine _routine({String id = 'r1', List<RoutineDay>? days}) => Routine(
      id: id,
      name: 'Bro Split',
      level: ExperienceLevel.intermediate,
      days: days ?? [_day()],
      source: RoutineSource.trainerAssigned,
    );

TodaysRoutine _today({
  Routine? routine,
  RoutineDay? day,
  int dayNumber = 4,
  int weekNumber = 0,
}) {
  final r = routine ?? _routine();
  final d = day ?? r.days.first;
  return (routine: r, day: d, dayNumber: dayNumber, weekNumber: weekNumber);
}

// ─── Test harness ────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {TodaysRoutine? today, bool loading = false}) {
  final override = loading
      ? todaysRoutineProvider.overrideWith(
          (ref) => Future<TodaysRoutine?>.delayed(
            const Duration(seconds: 30), // never resolves during the test
            () => null,
          ),
        )
      : todaysRoutineProvider.overrideWith((ref) async => today);

  return ProviderScope(
    overrides: [override],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

// Spanish (es_AR) uppercase weekday names, Monday..Sunday — mirrors
// AppL10n.dashboardWeekday1..7 so the expected label can be derived for the
// real current weekday instead of asserting a hardcoded day.
const _esWeekdays = [
  'LUNES',
  'MARTES',
  'MIÉRCOLES',
  'JUEVES',
  'VIERNES',
  'SÁBADO',
  'DOMINGO',
];

String _expectedDayLabel() =>
    'HOY · ${_esWeekdays[DateTime.now().weekday - DateTime.monday]}';

void main() {
  group('EmpezarEntrenamientoCard', () {
    testWidgets(
        'REQ-HOME-EMPEZAR-DAY-001: day label reflects the real current weekday',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const EmpezarEntrenamientoCard(), today: _today()));
      await tester.pumpAndSettle();

      // The weekday prefix is derived from the device clock and stays
      // stable regardless of the provider state — must always show today's
      // actual weekday, never a stale "JUEVES" from the old hardcode.
      expect(find.text(_expectedDayLabel()), findsOneWidget);
      if (DateTime.now().weekday != DateTime.thursday) {
        expect(find.text('HOY · JUEVES'), findsNothing);
      }
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-PROVIDER-001: card reflects todaysRoutineProvider — '
        'hero label = day.name, subtitle = deduped Spanish muscle groups, '
        'exercise count, authored minutes without "~"', (tester) async {
      // Trainer-assigned plan, Día 4 with 3 slots (chest, shoulders, triceps)
      // and an authored estimate of 55 min.
      final day = _day(
        dayNumber: 4,
        name: 'DÍA 4',
        slots: [
          _slot(muscleGroup: 'chest'),
          _slot(muscleGroup: 'shoulders'),
          _slot(muscleGroup: 'triceps'),
        ],
        estimatedMinutes: 55,
      );
      await tester.pumpWidget(
        _wrap(
          const EmpezarEntrenamientoCard(),
          today: _today(routine: _routine(days: [day]), day: day),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DÍA 4'), findsOneWidget);
      expect(find.text('Pecho · Hombros · Tríceps'), findsOneWidget);
      expect(find.text('3 ejercicios'), findsOneWidget);
      // Authored estimate renders WITHOUT the "~" prefix to signal an
      // explicit (not computed) duration.
      expect(find.text('55 min'), findsOneWidget);
      expect(find.text('EMPEZAR ENTRENAMIENTO'), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-PROVIDER-002: computed duration renders with "~" prefix',
        (tester) async {
      // estimatedMinutes null → fallback to per-set computation. 3 sets × 12
      // reps × 3s + rest 60s = 96s per set → ~5 minutes for one slot of 3
      // sets. With our 3 chest/shoulders/triceps slots → ~15 min.
      final day = _day(estimatedMinutes: null);
      await tester.pumpWidget(
        _wrap(
          const EmpezarEntrenamientoCard(),
          today: _today(routine: _routine(days: [day]), day: day),
        ),
      );
      await tester.pumpAndSettle();

      // Just assert the "~" prefix is present somewhere in a "min" string —
      // the exact minute count depends on the formula and is asserted in the
      // routine_day_duration unit tests.
      final minTexts = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('min'),
      );
      expect(minTexts, findsOneWidget);
      final txt = (tester.widget<Text>(minTexts)).data ?? '';
      expect(txt.startsWith('~'), isTrue,
          reason: 'computed duration should be prefixed with ~, got "$txt"');
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-PROVIDER-003: provider returns null (no routine) → '
        'card renders "—" placeholders and CTA fallback to /workout tab',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(
              body: SingleChildScrollView(child: EmpezarEntrenamientoCard()),
            ),
          ),
          GoRoute(
            path: '/workout',
            builder: (_, __) =>
                const Scaffold(body: Text('WORKOUT_DESTINATION')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todaysRoutineProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Placeholders.
      expect(find.text('—'), findsAtLeastNWidgets(1)); // hero label + duration
      expect(find.text('— ejercicios'), findsOneWidget);

      // Safe fallback nav — tap should go to /workout tab, not dead-end.
      await tester.tap(find.byType(HomeCTAButton));
      await tester.pumpAndSettle();
      expect(find.text('WORKOUT_DESTINATION'), findsOneWidget);
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-PROVIDER-004: tap CTA pushes /workout/routine/{id}'
        '?day=N&week=M when provider has a routine', (tester) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(
              body: SingleChildScrollView(child: EmpezarEntrenamientoCard()),
            ),
          ),
          GoRoute(
            path: '/workout/routine/:routineId',
            builder: (_, state) => Scaffold(
              body: Text(
                'ROUTINE_DESTINATION:${state.pathParameters['routineId']}'
                ':${state.uri.queryParameters['day']}'
                ':${state.uri.queryParameters['week']}',
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            todaysRoutineProvider.overrideWith(
              (ref) async => _today(
                routine: _routine(id: 'route-xyz'),
                dayNumber: 3,
                weekNumber: 1,
              ),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(HomeCTAButton));
      await tester.pumpAndSettle();
      expect(
        find.text('ROUTINE_DESTINATION:route-xyz:3:1'),
        findsOneWidget,
      );
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-002: stat row uses TreinoIcon.tabWorkout and TreinoIcon.clock',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const EmpezarEntrenamientoCard(), today: _today()));
      await tester.pumpAndSettle();

      expect(find.byIcon(TreinoIcon.tabWorkout), findsAtLeastNWidgets(1));
      expect(find.byIcon(TreinoIcon.clock), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-003: card decoration — bgCard, r=20, border non-null',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const EmpezarEntrenamientoCard(), today: _today()));
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.byType(Container).first,
      );
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.borderRadius, equals(BorderRadius.circular(20)));
      expect(decoration.color, equals(AppPalette.mintMagenta.bgCard));
      expect(decoration.border, isNotNull);
    });

    testWidgets(
        'REQ-HOME-EMPEZAR-001: HomeCTAButton found with label + TreinoIcon.play leading',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const EmpezarEntrenamientoCard(), today: _today()));
      await tester.pumpAndSettle();

      expect(find.byType(HomeCTAButton), findsOneWidget);
      final btn = tester.widget<HomeCTAButton>(find.byType(HomeCTAButton));
      expect(btn.label, equals('EMPEZAR ENTRENAMIENTO'));
      expect(btn.leadingIcon, equals(TreinoIcon.play));
    });
  });
}
