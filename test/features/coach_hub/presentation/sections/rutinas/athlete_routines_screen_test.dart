// Tests for AthleteRoutinesScreen — the per-athlete routines list reached from
// the Rutinas sidebar (elegí alumno → ver/crear/editar sus rutinas).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/athlete_routines_screen.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _athleteId = 'athlete-1';

Routine _routine({
  String id = 'r1',
  String name = 'Fuerza',
  int days = 1,
  int numWeeks = 1,
  RoutineStatus status = RoutineStatus.active,
}) =>
    Routine(
      id: id,
      name: name,
      level: ExperienceLevel.beginner,
      source: RoutineSource.trainerAssigned,
      assignedBy: 'trainer-1',
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      status: status,
      numWeeks: numWeeks,
      days: [
        for (var i = 0; i < days; i++)
          RoutineDay(
            dayNumber: i + 1,
            name: 'Día ${i + 1}',
            slots: const [
              RoutineSlot(
                exerciseId: 'e',
                exerciseName: 'Ex',
                muscleGroup: 'chest',
                targetSets: 1,
                targetRepsMin: 8,
                targetRepsMax: 8,
                restSeconds: 60,
                sets: [SetSpec(reps: 8)],
              ),
            ],
          ),
      ],
    );

Future<void> _pump(WidgetTester tester, List<Routine> routines) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/rutinas/$_athleteId',
    routes: [
      GoRoute(
        path: '/rutinas/:athleteId',
        builder: (_, s) => Scaffold(
          body:
              AthleteRoutinesScreen(athleteId: s.pathParameters['athleteId']!),
        ),
      ),
      // Editor stand-ins — assert navigation by the marker text.
      GoRoute(
        path: '/routine-editor/:athleteId',
        builder: (_, s) =>
            Scaffold(body: Text('CREATE ${s.pathParameters['athleteId']}')),
      ),
      GoRoute(
        path: '/routine-editor/:athleteId/:routineId',
        builder: (_, s) =>
            Scaffold(body: Text('EDIT ${s.pathParameters['routineId']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        assignedRoutinesProvider(_athleteId)
            .overrideWith((ref) async => routines),
        userPublicProfileProvider(_athleteId).overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(uid: _athleteId, displayName: 'Vicente'),
          ),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps the screen with `assignedRoutinesProvider` bound to whatever
/// [futureFactory] returns — no `pumpAndSettle`, así el frame queda
/// congelado mientras el future no resolvió (loading indefinido) o lo
/// dejamos resolver como error. `futureFactory` corre recién dentro del
/// override del provider, para que Riverpod (no la zone de test) sea quien
/// capture el rechazo.
Future<void> _pumpWithFuture(
  WidgetTester tester,
  Future<List<Routine>> Function() futureFactory,
) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        assignedRoutinesProvider(_athleteId)
            .overrideWith((ref) => futureFactory()),
        userPublicProfileProvider(_athleteId).overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(uid: _athleteId, displayName: 'Vicente'),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home:
            const Scaffold(body: AthleteRoutinesScreen(athleteId: _athleteId)),
      ),
    ),
  );
}

/// Pumps the screen with `routineRepositoryProvider` mockeado y
/// `assignedRoutinesProvider` recalculado a partir de [routinesOf] en cada
/// fetch — permite simular que la lista cambia después de archivar (WU-04).
Future<void> _pumpWithRepo(
  WidgetTester tester, {
  required List<Routine> Function() routinesOf,
  required RoutineRepository mockRepo,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routineRepositoryProvider.overrideWithValue(mockRepo),
        assignedRoutinesProvider(_athleteId)
            .overrideWith((ref) async => routinesOf()),
        userPublicProfileProvider(_athleteId).overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(uid: _athleteId, displayName: 'Vicente'),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home:
            const Scaffold(body: AthleteRoutinesScreen(athleteId: _athleteId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AthleteRoutinesScreen', () {
    testWidgets('lists active routines with the athlete name and a summary',
        (tester) async {
      await _pump(tester, [_routine(id: 'r1', name: 'Fuerza base', days: 3)]);

      // TreinoSectionHeader uppercasea el título (kit Fase 1, REQ-CK-002).
      expect(find.text('RUTINAS DE VICENTE'), findsOneWidget);
      expect(find.text('Fuerza base'), findsOneWidget);
      expect(find.text('3 días · 1 semana'), findsOneWidget);
    });

    testWidgets(
        'shows shimmer TreinoListRow skeletons keyed "loading" while the '
        'routines have not loaded yet', (tester) async {
      final completer = Completer<List<Routine>>();
      addTearDown(() {
        if (!completer.isCompleted) completer.complete(const []);
      });

      await _pumpWithFuture(tester, () => completer.future);

      expect(find.byKey(const ValueKey('loading')), findsOneWidget);
      expect(find.byType(TreinoStateSwitcher), findsOneWidget);
      expect(find.byType(TreinoListRow), findsWidgets);
    });

    testWidgets('shows a retry empty state when routines fail to load',
        (tester) async {
      await _pumpWithFuture(
        tester,
        () async => throw Exception('boom'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('error')), findsOneWidget);
      expect(find.text('No pudimos cargar las rutinas.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('hides archived routines', (tester) async {
      await _pump(tester, [
        _routine(id: 'r1', name: 'Activa'),
        _routine(id: 'r2', name: 'Vieja', status: RoutineStatus.archived),
      ]);

      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('Vieja'), findsNothing);
    });

    testWidgets('shows the empty state when there are no active routines',
        (tester) async {
      await _pump(tester, const []);

      expect(
        find.text('Todavía no le cargaste ninguna rutina.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a web-editable routine opens the editor for it',
        (tester) async {
      await _pump(tester, [_routine(id: 'r1', name: 'Fuerza base')]);

      await tester.tap(find.text('Fuerza base'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT r1'), findsOneWidget);
    });

    testWidgets('"Nueva rutina" opens the create editor', (tester) async {
      await _pump(tester, const []);

      await tester.tap(find.text('Nueva rutina'));
      await tester.pumpAndSettle();

      expect(find.text('CREATE $_athleteId'), findsOneWidget);
    });

    testWidgets('a periodized routine is view-only (tap does not open editor)',
        (tester) async {
      await _pump(
          tester, [_routine(id: 'r9', name: 'Periodizada', numWeeks: 4)]);

      expect(find.text('Editá en la app'), findsOneWidget);

      await tester.tap(find.text('Periodizada'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT r9'), findsNothing); // stayed on the list
      expect(find.text('Periodizada'), findsOneWidget);
    });
  });

  group('AthleteRoutinesScreen — filtro Activas/Archivadas (WU-03)', () {
    testWidgets(
        'por defecto muestra sólo Activas y expone el filtro con conteos '
        'reales', (tester) async {
      await _pump(tester, [
        _routine(id: 'r1', name: 'A1'),
        _routine(id: 'r2', name: 'A2'),
        _routine(id: 'r3', name: 'Vieja', status: RoutineStatus.archived),
      ]);

      expect(find.text('A1'), findsOneWidget);
      expect(find.text('A2'), findsOneWidget);
      expect(find.text('Vieja'), findsNothing);

      final chips =
          tester.widget<TreinoFilterChips>(find.byType(TreinoFilterChips));
      expect(chips.selected, {'Activas'});
      expect(chips.badgeCounts['Activas'], 2);
      expect(chips.badgeCounts['Archivadas'], 1);
    });

    testWidgets(
        'seleccionar "Archivadas" muestra las archivadas en modo view-only '
        '(sin tap al editor, sin trailing edit)', (tester) async {
      await _pump(tester, [
        _routine(id: 'r1', name: 'Activa'),
        _routine(id: 'r2', name: 'Vieja', status: RoutineStatus.archived),
      ]);

      await tester.tap(find.text('Archivadas'));
      await tester.pumpAndSettle();

      expect(find.text('Vieja'), findsOneWidget);
      expect(find.text('Activa'), findsNothing);

      // View-only: tap no navega al editor.
      await tester.tap(find.text('Vieja'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT r2'), findsNothing);
      expect(find.text('Vieja'), findsOneWidget); // seguimos en la lista

      // Trailing informativo (no el hint de "Editá en la app" de periodizadas
      // ni el ícono de edición de las activas web-editables).
      expect(find.text('Editá en la app'), findsNothing);
      expect(find.text('Archivada'), findsOneWidget);
    });

    testWidgets(
        'el childKey del TreinoStateSwitcher cambia con el filtro para '
        'cross-fadear', (tester) async {
      await _pump(tester, [
        _routine(id: 'r1', name: 'Activa'),
        _routine(id: 'r2', name: 'Vieja', status: RoutineStatus.archived),
      ]);

      var switcher =
          tester.widget<TreinoStateSwitcher>(find.byType(TreinoStateSwitcher));
      expect(switcher.childKey, const ValueKey('data-activas'));

      await tester.tap(find.text('Archivadas'));
      await tester.pumpAndSettle();

      switcher =
          tester.widget<TreinoStateSwitcher>(find.byType(TreinoStateSwitcher));
      expect(switcher.childKey, const ValueKey('data-archivadas'));
    });

    testWidgets('el empty state de "Archivadas" es honesto (mensaje propio)',
        (tester) async {
      await _pump(tester, [_routine(id: 'r1', name: 'Activa')]);

      await tester.tap(find.text('Archivadas'));
      await tester.pumpAndSettle();

      expect(find.text('No hay rutinas archivadas.'), findsOneWidget);
    });
  });

  group('AthleteRoutinesScreen — archivar rutina (WU-04)', () {
    late _MockRoutineRepository mockRepo;

    setUp(() {
      mockRepo = _MockRoutineRepository();
    });

    testWidgets('el botón de archivar sólo aparece en activas web-editables',
        (tester) async {
      final routines = [
        _routine(id: 'r1', name: 'Activa editable'),
        _routine(id: 'r2', name: 'Periodizada', numWeeks: 4),
      ];
      await _pumpWithRepo(
        tester,
        routinesOf: () => routines,
        mockRepo: mockRepo,
      );

      expect(
        find.byKey(const ValueKey('routine_row_archive_button_r1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('routine_row_archive_button_r2')),
        findsNothing,
      );
    });

    testWidgets('tocar archivar abre una confirmación con TreinoDialog',
        (tester) async {
      await _pumpWithRepo(
        tester,
        routinesOf: () => [_routine(id: 'r1', name: 'Activa editable')],
        mockRepo: mockRepo,
      );

      await tester
          .tap(find.byKey(const ValueKey('routine_row_archive_button_r1')));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsOneWidget);
      expect(find.text('Archivar'), findsWidgets);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('cancelar la confirmación NO llama a repo.archive',
        (tester) async {
      await _pumpWithRepo(
        tester,
        routinesOf: () => [_routine(id: 'r1', name: 'Activa editable')],
        mockRepo: mockRepo,
      );

      await tester
          .tap(find.byKey(const ValueKey('routine_row_archive_button_r1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byType(TreinoDialog), findsNothing);
      expect(find.text('Activa editable'), findsOneWidget);
      verifyNever(() => mockRepo.archive(any()));
    });

    testWidgets(
        'confirmar archiva: llama a repo.archive, refresca la lista y '
        'muestra un snackbar de éxito', (tester) async {
      var routines = [_routine(id: 'r1', name: 'Activa editable')];
      when(() => mockRepo.archive('r1')).thenAnswer((_) async {
        routines = const [];
      });

      await _pumpWithRepo(
        tester,
        routinesOf: () => routines,
        mockRepo: mockRepo,
      );

      await tester
          .tap(find.byKey(const ValueKey('routine_row_archive_button_r1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Archivar').last);
      await tester.pumpAndSettle();

      verify(() => mockRepo.archive('r1')).called(1);
      expect(find.text('Activa editable'), findsNothing);
      expect(find.text('Rutina archivada.'), findsOneWidget);
    });

    testWidgets('muestra estado busy mientras la operación está en curso',
        (tester) async {
      final completer = Completer<void>();
      when(() => mockRepo.archive('r1')).thenAnswer((_) => completer.future);

      await _pumpWithRepo(
        tester,
        routinesOf: () => [_routine(id: 'r1', name: 'Activa editable')],
        mockRepo: mockRepo,
      );

      await tester
          .tap(find.byKey(const ValueKey('routine_row_archive_button_r1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Archivar').last);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.byKey(const ValueKey('routine_row_archive_button_r1')),
        findsNothing,
      );

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets(
        'si repo.archive falla, muestra un snackbar de error y la fila '
        'sigue visible', (tester) async {
      when(() => mockRepo.archive('r1')).thenThrow(Exception('boom'));

      await _pumpWithRepo(
        tester,
        routinesOf: () => [_routine(id: 'r1', name: 'Activa editable')],
        mockRepo: mockRepo,
      );

      await tester
          .tap(find.byKey(const ValueKey('routine_row_archive_button_r1')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Archivar').last);
      await tester.pumpAndSettle();

      expect(find.text('No pudimos archivar la rutina.'), findsOneWidget);
      expect(find.text('Activa editable'), findsOneWidget);
    });
  });
}
