import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';

import '../../../helpers/fake_analytics_service.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_slot_row.dart';
import 'package:treino/features/workout/presentation/widgets/stat_tile.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _profile(UserRole role) => UserProfile(
      uid: 'u1',
      email: 'u1@test.com',
      displayName: 'U',
      role: role,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Widget _wrapWithOverrides(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
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
  int? supersetGroup,
}) =>
    RoutineSlot(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      muscleGroup: muscleGroup,
      targetSets: targetSets,
      targetRepsMin: targetRepsMin,
      targetRepsMax: targetRepsMax,
      restSeconds: restSeconds,
      supersetGroup: supersetGroup,
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
  String? assignedBy,
  String? createdBy,
}) =>
    Routine(
      id: id,
      name: name,
      split: split,
      level: ExperienceLevel.beginner,
      days: days ?? [_makeDay()],
      imageUrl: imageUrl,
      assignedBy: assignedBy,
      createdBy: createdBy,
    );

void main() {
  group('RoutineDetailScreen', () {
    testWidgets('uses TreinoStateSwitcher for async content transitions', (
      tester,
    ) async {
      final routine = _makeRoutine();
      await tester.pumpWidget(
        _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
          routineByIdStreamProvider(
            'test-id',
          ).overrideWith((ref) => Stream.value(routine)),
        ]),
      );
      await tester.pump();

      expect(find.byType(TreinoStateSwitcher), findsOneWidget);
    });

    testWidgets(
      'SCENARIO-075: AsyncData(routine) renders slots and bottom bar present',
      (tester) async {
        final routine = _makeRoutine(
          days: [
            _makeDay(
              slots: [
                _makeSlot(),
                _makeSlot(exerciseId: 'squat'),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(routine)),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(ExerciseSlotRow), findsNWidgets(2));
      },
    );

    testWidgets(
      'SCENARIO-076: AsyncLoading shows skeleton, no ExerciseSlotRow',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            // Never-closed, never-emitting controller keeps the provider in
            // AsyncLoading forever — mirrors the old Completer().future.
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => StreamController<Routine?>().stream),
          ]),
        );
        await tester.pump();
        expect(find.byType(ExerciseSlotRow), findsNothing);
      },
    );

    testWidgets(
      'SCENARIO-077: AsyncError shows error widget, no ExerciseSlotRow',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.error(Exception('boom'))),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        expect(find.byType(ExerciseSlotRow), findsNothing);
        expect(find.textContaining('cargar'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'SCENARIO-078: AsyncData(null) shows "Rutina no encontrada" + back button',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(null)),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.textContaining('no encontrada'), findsOneWidget);
        expect(find.byType(ExerciseSlotRow), findsNothing);
        // Back button MUST be present so the user can never dead-end.
        expect(find.byIcon(TreinoIcon.back), findsOneWidget);
      },
    );

    testWidgets('SCENARIO-079: hero strip attempts Image.asset by routine id', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
          routineByIdStreamProvider(
            'test-id',
          ).overrideWith((ref) => Stream.value(_makeRoutine(id: 'test-id'))),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final image = tester.widget<Image>(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName ==
                  'assets/routines/test-id.png',
        ),
      );
      expect(image.errorBuilder, isNotNull);
    });

    testWidgets('SCENARIO-080: badge shows "PPL · DÍA 1"', (tester) async {
      await tester.pumpWidget(
        _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
          routineByIdStreamProvider('test-id').overrideWith(
            (ref) => Stream.value(
              _makeRoutine(split: 'PPL', days: [_makeDay(dayNumber: 1)]),
            ),
          ),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('PPL · DÍA 1'), findsOneWidget);
    });

    testWidgets('SCENARIO-081: day name rendered in uppercase', (tester) async {
      await tester.pumpWidget(
        _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
          routineByIdStreamProvider('test-id').overrideWith(
            (ref) => Stream.value(_makeRoutine(days: [_makeDay(name: 'Push')])),
          ),
        ]),
      );
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
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(_makeRoutine(days: [day]))),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        final statTiles = tester.widgetList<StatTile>(find.byType(StatTile));
        final values = statTiles.map((t) => t.value).toList();
        expect(values, containsAll(['3', '10', '45']));
      },
    );

    testWidgets(
        'SCENARIO-083: estimatedMinutes null → third StatTile shows a '
        'computed "~N" estimate (2026-06-11)', (tester) async {
      final day = _makeDay(estimatedMinutes: null);
      await tester.pumpWidget(
        _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
          routineByIdStreamProvider(
            'test-id',
          ).overrideWith((ref) => Stream.value(_makeRoutine(days: [day]))),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final statTiles = tester.widgetList<StatTile>(find.byType(StatTile));
      final values = statTiles.map((t) => t.value).toList();
      // No authored estimate → the screen computes one from the sets and
      // shows it with a "~" prefix; it is NOT a dead dash.
      expect(values.any((v) => v != null && v.startsWith('~')), isTrue);
      expect(values, isNot(contains(null)));
    });

    testWidgets('SCENARIO-084: single-day routine — no day selector', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
          routineByIdStreamProvider(
            'test-id',
          ).overrideWith(
              (ref) => Stream.value(_makeRoutine(days: [_makeDay()]))),
        ]),
      );
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
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(routine)),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(ChoiceChip), findsNWidgets(3));
        await tester.tap(find.byType(ChoiceChip).at(2));
        await tester.pumpAndSettle();
        expect(find.text('LEGS'), findsOneWidget);
      },
    );

    testWidgets(
      'SCENARIO-086: EJERCICIOS header + 4 ExerciseSlotRow for 4-slot day',
      (tester) async {
        final day = _makeDay(slots: List.generate(4, (_) => _makeSlot()));
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(_makeRoutine(days: [day]))),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('EJERCICIOS'), findsAtLeastNWidgets(1));
        expect(
          find.byType(ExerciseSlotRow, skipOffstage: false),
          findsNWidgets(4),
        );
      },
    );

    testWidgets('SCENARIO-087: empty slots shows empty state text', (
      tester,
    ) async {
      final day = _makeDay(slots: []);
      await tester.pumpWidget(
        _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
          routineByIdStreamProvider(
            'test-id',
          ).overrideWith((ref) => Stream.value(_makeRoutine(days: [day]))),
        ]),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ExerciseSlotRow), findsNothing);
      expect(find.text('No hay ejercicios en este día'), findsOneWidget);
    });

    testWidgets(
      'SCENARIO-560: consecutive slots sharing supersetGroup render a '
      'SUPERSERIE block (label once, both rows present)',
      (tester) async {
        final day = _makeDay(
          slots: [
            _makeSlot(exerciseId: 'bench', supersetGroup: 1),
            _makeSlot(exerciseId: 'fly', supersetGroup: 1),
          ],
        );
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(_makeRoutine(days: [day]))),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        // The block header appears exactly once for the two grouped slots.
        expect(find.text('SUPERSERIE'), findsOneWidget);
        // Both exercises still render as their normal cards inside the block.
        expect(
          find.byType(ExerciseSlotRow, skipOffstage: false),
          findsNWidgets(2),
        );
      },
    );

    testWidgets(
      'SCENARIO-561: a lone tagged slot (run length 1) does NOT render a '
      'SUPERSERIE block — no superset of one',
      (tester) async {
        final day = _makeDay(
          slots: [
            _makeSlot(exerciseId: 'bench', supersetGroup: 1),
            _makeSlot(exerciseId: 'squat'), // breaks the run
          ],
        );
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(_makeRoutine(days: [day]))),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('SUPERSERIE'), findsNothing);
        expect(
          find.byType(ExerciseSlotRow, skipOffstage: false),
          findsNWidgets(2),
        );
      },
    );

    testWidgets(
      'SCENARIO-562: mixed day (standalone + superset) keeps every slot '
      'rendered as an ExerciseSlotRow',
      (tester) async {
        final day = _makeDay(
          slots: [
            _makeSlot(exerciseId: 'warmup'), // standalone #1
            _makeSlot(exerciseId: 'bench', supersetGroup: 7), // block #2
            _makeSlot(exerciseId: 'fly', supersetGroup: 7), // block #3
            _makeSlot(exerciseId: 'cooldown'), // standalone #4
          ],
        );
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(_makeRoutine(days: [day]))),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text('SUPERSERIE'), findsOneWidget);
        expect(
          find.byType(ExerciseSlotRow, skipOffstage: false),
          findsNWidgets(4),
        );
      },
    );

    testWidgets(
      'SCENARIO-313 (rev): EMPEZAR habilitado; EDITAR removido del CTA',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(_makeRoutine())),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        // EDITAR was a disabled stub — removed (the athlete plan view is
        // read-only; editing lives on the trainer side).
        expect(find.text('EDITAR'), findsNothing);
        expect(find.text('EMPEZAR'), findsOneWidget);
        final empezarBtn = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'EMPEZAR'),
        );
        expect(empezarBtn.onPressed, isNotNull);
      },
    );

    testWidgets(
      'SCENARIO-564: trainer role hides EMPEZAR (plan view is read-only for '
      'coaches)',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(_makeRoutine())),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_profile(UserRole.trainer)),
            ),
          ]),
        );
        // Two settles: routine future resolves (CTA mounts + first subscribes to
        // userProfileProvider), then the role stream emits → CTA rebuilds hidden.
        await tester.pumpAndSettle();
        expect(find.text('EMPEZAR'), findsNothing);
      },
    );

    testWidgets('SCENARIO-565: athlete role shows EMPEZAR', (tester) async {
      await tester.pumpWidget(
        _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
          routineByIdStreamProvider(
            'test-id',
          ).overrideWith((ref) => Stream.value(_makeRoutine())),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_profile(UserRole.athlete)),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('EMPEZAR'), findsOneWidget);
    });

    testWidgets(
      'SCENARIO-314: tap en EMPEZAR pushea /workout/session/{id}/{day}',
      (tester) async {
        String? pushedLocation;
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) =>
                  const RoutineDetailScreen(routineId: 'test-id'),
            ),
            GoRoute(
              path: '/workout/session/:routineId/:dayNumber',
              builder: (_, state) {
                pushedLocation = state.matchedLocation;
                return const Scaffold(
                  body: Center(child: Text('session-stub')),
                );
              },
            ),
          ],
        );
        final analytics = FakeAnalyticsService();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              routineByIdStreamProvider('test-id').overrideWith(
                (ref) => Stream.value(
                  _makeRoutine(days: [_makeDay(dayNumber: 4)]),
                ),
              ),
              analyticsServiceProvider.overrideWithValue(analytics),
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
        await tester.pump(const Duration(milliseconds: 50));
        await tester.ensureVisible(find.text('EMPEZAR'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('EMPEZAR'));
        await tester.pumpAndSettle();
        expect(pushedLocation, equals('/workout/session/test-id/4'));
        expect(analytics.events, contains('routine_started'));
      },
    );

    testWidgets(
      'SCENARIO-093 (router): ExerciseSlotRow tap pushes exercise route',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/start',
          routes: [
            GoRoute(path: '/start', builder: (_, __) => const Text('START')),
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
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              routineByIdStreamProvider('test-id').overrideWith(
                (ref) => Stream.value(
                  _makeRoutine(
                    days: [
                      _makeDay(slots: [_makeSlot(exerciseId: 'bench-press')]),
                    ],
                  ),
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
        router.push('/workout/routine/test-id');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ExerciseSlotRow).first);
        await tester.pumpAndSettle();
        expect(find.text('EXERCISE'), findsOneWidget);
      },
    );

    testWidgets(
      'SCENARIO-093b (router): self-created routine slot tap passes createdBy '
      'as ownerId so custom exercises resolve (no "Ejercicio no encontrado")',
      (tester) async {
        String? capturedOwnerId;
        final router = GoRouter(
          initialLocation: '/start',
          routes: [
            GoRoute(path: '/start', builder: (_, __) => const Text('START')),
            GoRoute(
              path: '/workout/routine/:routineId',
              builder: (ctx, state) => RoutineDetailScreen(
                routineId: state.pathParameters['routineId']!,
              ),
            ),
            GoRoute(
              path: '/workout/exercise/:exerciseId',
              builder: (ctx, state) {
                capturedOwnerId = state.uri.queryParameters['ownerId'];
                return const Text('EXERCISE');
              },
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              routineByIdStreamProvider('test-id').overrideWith(
                (ref) => Stream.value(
                  _makeRoutine(
                    assignedBy: null,
                    createdBy: 'athlete-123',
                    days: [
                      _makeDay(slots: [_makeSlot(exerciseId: 'my-custom-ex')]),
                    ],
                  ),
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
        router.push('/workout/routine/test-id');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ExerciseSlotRow).first);
        await tester.pumpAndSettle();
        expect(find.text('EXERCISE'), findsOneWidget);
        expect(capturedOwnerId, equals('athlete-123'));
      },
    );

    testWidgets(
      'SCENARIO-094: no Scaffold/AppBackground/SafeArea inside screen subtree',
      (tester) async {
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(_makeRoutine())),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(AppBackground), findsNothing);
        expect(find.byType(SafeArea), findsNothing);
      },
    );

    testWidgets('deep link /workout/routine/:id lands on RoutineDetailScreen', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(path: '/start', builder: (_, __) => const Text('START')),
          GoRoute(
            path: '/workout/routine/:routineId',
            builder: (ctx, state) => RoutineDetailScreen(
              routineId: state.pathParameters['routineId']!,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(_makeRoutine(id: 'test-id'))),
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
      router.push('/workout/routine/test-id');
      await tester.pumpAndSettle();
      expect(find.text('PPL · DÍA 1'), findsOneWidget);
    });

    testWidgets(
      'initialDayNumber pre-selects the matching day chip on first render',
      (tester) async {
        // Routine with 3 days; initialDayNumber: 3 should land on the third
        // day chip selected, not the default first day. Used by the home
        // EmpezarEntrenamientoCard to deep-link to today's day.
        final routine = _makeRoutine(
          days: [
            _makeDay(dayNumber: 1, name: 'Día 1'),
            _makeDay(dayNumber: 2, name: 'Día 2'),
            _makeDay(dayNumber: 3, name: 'Día 3'),
          ],
        );
        await tester.pumpWidget(
          _wrapWithOverrides(
            const RoutineDetailScreen(
              routineId: 'test-id',
              initialDayNumber: 3,
            ),
            [
              routineByIdStreamProvider(
                'test-id',
              ).overrideWith((ref) => Stream.value(routine)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // The breadcrumb badge reflects the SELECTED day's name, so finding
        // "Día 3" there proves day index 3 (1-based → index 2) won.
        expect(find.text('PPL · DÍA 3'), findsOneWidget);
      },
    );

    testWidgets(
      'initialDayNumber out of range clamps to the last day (defensive)',
      (tester) async {
        // Routine has 2 days but caller passes initialDayNumber: 99 (e.g. a
        // stale deep link to a routine that lost days since the URL was made).
        // The screen's clamp() in build() saves the day → falls back to the
        // last available day instead of crashing.
        final routine = _makeRoutine(
          days: [
            _makeDay(dayNumber: 1, name: 'Día 1'),
            _makeDay(dayNumber: 2, name: 'Día 2'),
          ],
        );
        await tester.pumpWidget(
          _wrapWithOverrides(
            const RoutineDetailScreen(
              routineId: 'test-id',
              initialDayNumber: 99,
            ),
            [
              routineByIdStreamProvider(
                'test-id',
              ).overrideWith((ref) => Stream.value(routine)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('PPL · DÍA 2'), findsOneWidget);
      },
    );

    testWidgets(
      'initialDayNumber null → defaults to first day (no regression)',
      (tester) async {
        final routine = _makeRoutine(
          days: [
            _makeDay(dayNumber: 1, name: 'Día 1'),
            _makeDay(dayNumber: 2, name: 'Día 2'),
          ],
        );
        await tester.pumpWidget(
          _wrapWithOverrides(const RoutineDetailScreen(routineId: 'test-id'), [
            routineByIdStreamProvider(
              'test-id',
            ).overrideWith((ref) => Stream.value(routine)),
          ]),
        );
        await tester.pumpAndSettle();

        expect(find.text('PPL · DÍA 1'), findsOneWidget);
      },
    );
  });

  // ── SCENARIO-WPRES-035 — single-week plan regression (REQ-WPRES-030) ───────

  group('SCENARIO-WPRES-035 — single-week plan edit/save round-trip unchanged',
      () {
    // Verifies the REQ-WPRES-030 hard invariant: single-week routines must
    // produce no behavioral change — no filtering, no "Sin ejercicios" message,
    // all slots rendered identically to pre-change behavior.

    testWidgets(
      'SCENARIO-WPRES-035a: single-week routine renders all slots (no presence filter)',
      (tester) async {
        // Slots with explicitly empty activeWeeks (as serialized by a round-trip)
        const slotA = RoutineSlot(
          exerciseId: 'bench',
          exerciseName: 'Press Banca',
          muscleGroup: 'Pecho',
          targetSets: 4,
          targetRepsMin: 8,
          targetRepsMax: 12,
          restSeconds: 90,
          // activeWeeks: [] default — identical to pre-change
        );
        const slotB = RoutineSlot(
          exerciseId: 'squat',
          exerciseName: 'Sentadilla',
          muscleGroup: 'Piernas',
          targetSets: 4,
          targetRepsMin: 6,
          targetRepsMax: 10,
          restSeconds: 120,
          // activeWeeks: [] default — identical to pre-change
        );
        const routine = Routine(
          id: 'single-week-rt',
          name: 'Plan Simple',
          level: ExperienceLevel.beginner,
          days: [
            RoutineDay(dayNumber: 1, name: 'Push', slots: [slotA, slotB]),
          ],
          numWeeks: 1, // single-week plan
        );
        await tester.pumpWidget(
          _wrapWithOverrides(RoutineDetailScreen(routineId: routine.id), [
            routineByIdStreamProvider(
              routine.id,
            ).overrideWith((ref) => Stream.value(routine)),
          ]),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Both slots must render — no filtering on single-week plan
        expect(
          find.byType(ExerciseSlotRow),
          findsNWidgets(2),
          reason: 'Single-week plan: all slots rendered, no filter',
        );
        // No "Sin ejercicios" message (that is only for multi-week empty days)
        expect(
          find.textContaining('Sin ejercicios', skipOffstage: false),
          findsNothing,
          reason: 'No "Sin ejercicios" message on single-week plan',
        );
      },
    );

    testWidgets(
      'SCENARIO-WPRES-035b: activeWeeks stays empty in domain object after round-trip',
      (tester) async {
        // Verifies the domain invariant: single-week slots always have
        // activeWeeks == [] so the presence filter is a no-op.
        const slot = RoutineSlot(
          exerciseId: 'bench',
          exerciseName: 'Press Banca',
          muscleGroup: 'Pecho',
          targetSets: 3,
          targetRepsMin: 8,
          targetRepsMax: 12,
          restSeconds: 90,
        );
        expect(
          slot.activeWeeks,
          isEmpty,
          reason: 'Default slot has empty activeWeeks (single-week invariant)',
        );
        expect(
          slot.isPresentInWeek(0),
          isTrue,
          reason: 'Empty mask → present in week 0',
        );
      },
    );
  });
}
