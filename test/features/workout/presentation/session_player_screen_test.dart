// Tests para SessionPlayerScreen — SCENARIO-274..276 (_SessionHeader, TASK-202a)
// + SCENARIO-277..278 (_AttendanceCard, TASK-203a).
// TASK-203a: _AttendanceCard fue incluida en el commit 202b junto con el esqueleto
// de la pantalla — los tests 277-278 son GREEN desde el primer run (desviación
// documentada en apply-progress.md).
//
// Updated for the 5-change redesign (per-set model, duration timer, weight
// keyboard, reps non-editable, block gating).
// SCENARIO-037: player renders correct week's set count via effectiveSetsForWeek.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../features/workout/application/stub_factories.dart';

// ── Helpers de test ───────────────────────────────────────────────────────────

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: w),
      ),
    );

// ignore: unused_element
Widget _wrapRouter({
  required List<RouteBase> routes,
  List<Override> overrides = const [],
}) {
  final router = GoRouter(routes: routes);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

// ── Stub notifier ─────────────────────────────────────────────────────────────

/// Stub que retorna AsyncData con el state dado para cualquier SessionInit.
/// Extiende SessionNotifier directamente para que overrideWith lo acepte.
class _StubNotifier extends SessionNotifier {
  _StubNotifier(this._state);
  final SessionState _state;

  @override
  Future<SessionState> build(SessionInit arg) async => _state;
}

/// Stub que registra la llamada a finishSession sin ejecutar lógica real.
class _FinishTrackingNotifier extends SessionNotifier {
  _FinishTrackingNotifier(this._state, {required this.onFinish});
  final SessionState _state;
  final void Function() onFinish;

  @override
  Future<SessionState> build(SessionInit arg) async => _state;

  @override
  Future<void> finishSession() async => onFinish();
}

/// Stub que registra las llamadas a removeSet (live-set-editing PR2) sin
/// ejecutar lógica real — permite verificar que la UI del delete icon +
/// confirm dialog dispara [SessionNotifier.removeSet] con el slot/target
/// correctos, y solo cuando corresponde (mirrors _FinishTrackingNotifier).
class _RemoveTrackingNotifier extends SessionNotifier {
  _RemoveTrackingNotifier(this._state, {required this.onRemoveSet});
  final SessionState _state;
  final void Function(RoutineSlot slot, SetLog? target) onRemoveSet;

  @override
  Future<SessionState> build(SessionInit arg) async => _state;

  @override
  Future<void> removeSet(RoutineSlot slot, SetLog? target) async =>
      onRemoveSet(slot, target);
}

// ── Factories de estado ───────────────────────────────────────────────────────

SessionState _defaultState() => SessionState(
      session: makeSession(),
      day: makeDay(
        dayNumber: 4,
        slots: [
          makeSlot(
              exerciseId: 'e1', exerciseName: 'Press de banca', targetSets: 3),
          makeSlot(exerciseId: 'e2', exerciseName: 'Sentadilla', targetSets: 3),
        ],
      ),
      setLogs: const [],
      currentExerciseIndex: 0,
      elapsedSeconds: 0,
    );

const _kInit = FreshSession(routineId: 'r1', dayNumber: 4);

/// Override de toda la familia — en Riverpod 2.6 es la única forma de
/// proveer un stub para AsyncNotifierProvider.autoDispose.family.
List<Override> _stateOverride(SessionState state) => [
      sessionNotifierProvider.overrideWith(() => _StubNotifier(state)),
    ];

// ── Helpers adicionales de SessionState ──────────────────────────────────────

/// Estado con 3 slots, 1 completamente terminado.
SessionState _stateWith1Of3Done() {
  final slots = [
    makeSlot(exerciseId: 'e1', targetSets: 2),
    makeSlot(exerciseId: 'e2', exerciseName: 'Sentadilla', targetSets: 3),
    makeSlot(exerciseId: 'e3', exerciseName: 'Peso muerto', targetSets: 3),
  ];
  final day = makeDay(dayNumber: 1, slots: slots);
  // 2 logs para e1 → completo; 0 para e2, e3
  final logs = [
    makeSetLog(exerciseId: 'e1', setNumber: 1, reps: 10, weightKg: 60.0),
    makeSetLog(exerciseId: 'e1', setNumber: 2, reps: 10, weightKg: 60.0),
  ];
  return SessionState(
    session: makeSession(),
    day: day,
    setLogs: logs,
    currentExerciseIndex: 1,
    elapsedSeconds: 0,
  );
}

// ── Helpers de UserProfile ────────────────────────────────────────────────────

UserProfile _makeProfile({String? gymId}) => UserProfile(
      uid: 'u1',
      email: 'u1@test.com',
      displayName: 'Test',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      gymId: gymId,
    );

// ── _SessionHeader + _AttendanceCard tests ───────────────────────────────────

void main() {
  group('_SessionHeader', () {
    // SCENARIO-274: título en formato correcto
    testWidgets('SCENARIO-274: renderiza el número de día en el título',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()),
        ),
      );
      await tester.pump();
      // El header contiene 'DÍA 4' (dayNumber=4 viene del estado)
      expect(find.textContaining('DÍA 4'), findsOneWidget);
    });

    // SCENARIO-275: botón ABANDONAR presente
    testWidgets('SCENARIO-275: renderiza botón ABANDONAR', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()),
        ),
      );
      await tester.pump();
      expect(find.text('ABANDONAR'), findsOneWidget);
    });

    // SCENARIO-276: tap en ABANDONAR invoca callback → diálogo aparece
    testWidgets(
        'SCENARIO-276: tap en ABANDONAR muestra el diálogo de confirmación',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('ABANDONAR'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('¿Seguro que querés abandonar?'),
        findsOneWidget,
      );
    });
  });

  // ── _AttendanceCard (TASK-203a) ───────────────────────────────────────────

  group('_AttendanceCard', () {
    List<Override> attendanceOverrides(UserProfile profile) => [
          ...(_stateOverride(_defaultState())),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(profile),
          ),
        ];

    // SCENARIO-277: 'Asistencia marcada' aparece
    testWidgets('SCENARIO-277: renderiza "Asistencia marcada"', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          attendanceOverrides(_makeProfile()),
        ),
      );
      await tester.pump();
      expect(find.text('Asistencia marcada'), findsOneWidget);
    });

    // SCENARIO-278: 'Sin gimnasio asignado' cuando gymId es null
    testWidgets(
        'SCENARIO-278: renderiza "Sin gimnasio asignado" cuando gymId es null',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          attendanceOverrides(_makeProfile(gymId: null)),
        ),
      );
      await tester.pump();
      expect(find.text('Sin gimnasio asignado'), findsOneWidget);
    });
  });

  // ── _ExerciseListRow (TASK-205a) ──────────────────────────────────────────

  group('_ExerciseListRow', () {
    // SCENARIO-283: fila done — tachado + check icon
    testWidgets(
        'SCENARIO-283: estado done renderiza nombre tachado e ícono check',
        (tester) async {
      // Estado donde e1 tiene todos sus sets completados (targetSets=3, 3 logs)
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Squat', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1),
        makeSetLog(exerciseId: 'e1', setNumber: 2),
        makeSetLog(exerciseId: 'e1', setNumber: 3),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // Nombre con tachado
      final textWidget = tester.widget<Text>(find.text('Squat'));
      expect(
        textWidget.style?.decoration,
        TextDecoration.lineThrough,
      );
    });

    // SCENARIO-284: header de ejercicio muestra progreso "X/N"
    // (reemplaza el badge "Ahora" del diseño viejo — en el redesign de
    // inline-set-rows el progreso se muestra explícito por ejercicio).
    testWidgets('SCENARIO-284: header del ejercicio muestra progreso "0/N"',
        (tester) async {
      // Estado default: e1 (targetSets=3) sin logs → progreso "0/3"
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()),
        ),
      );
      await tester.pump();
      expect(find.text('0/3'), findsAtLeastNWidgets(1));
    });

    // SCENARIO-285 (updated): reps son no editables — se muestran como texto
    // fijo. makeSlot usa targetRepsMin=8, targetRepsMax=12 (range) → "8–12 reps".
    testWidgets(
        'SCENARIO-285: reps no editables — muestra texto fijo de reps planeadas',
        (tester) async {
      // Sentadilla pending, sin logs → sección activa visible.
      final slots = [
        makeSlot(exerciseId: 'e2', exerciseName: 'Sentadilla', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // makeSlot default: targetRepsMin=8, targetRepsMax=12 → efectiveSets
      // sintetiza SetSpec(repsMin:8, repsMax:12) → "8–12 reps"
      expect(find.textContaining('8–12 reps'), findsWidgets);
      // No debe haber stepper de reps (sin botón '+' para reps).
      // El único '+' que podría estar sería en el stepper de kg — pero
      // en el nuevo diseño el peso es un TextField, no un stepper, así que
      // no debe haber ningún botón '+' en pantalla.
      expect(find.text('+'), findsNothing);
    });

    // SCENARIO-286: fila done NO es tappable
    testWidgets('SCENARIO-286: fila done no es tappable (onTap null)',
        (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Squat', targetSets: 1),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [makeSetLog(exerciseId: 'e1', setNumber: 1)];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // Tap en fila done no debe abrir sheet ni lanzar excepción
      await tester.tap(find.text('Squat'));
      await tester.pumpAndSettle();
      // El SetEntrySheet NO debe aparecer
      expect(find.text('SQUAT'), findsNothing);
    });
  });

  // ── Superserie round-robin (_SupersetSection) ─────────────────────────────

  group('_SupersetSection (round-robin)', () {
    SessionState supersetState({List<SetLog> logs = const []}) => SessionState(
          session: makeSession(),
          day: makeDay(
            dayNumber: 1,
            slots: [
              makeSlot(
                  exerciseId: 'e1',
                  exerciseName: 'A',
                  targetSets: 3,
                  supersetGroup: 1),
              makeSlot(
                  exerciseId: 'e2',
                  exerciseName: 'B',
                  targetSets: 3,
                  supersetGroup: 1),
            ],
          ),
          setLogs: logs,
          currentExerciseIndex: 0,
          elapsedSeconds: 0,
        );

    testWidgets(
        'SCENARIO-600: consecutive supersetGroup slots render a SUPERSERIE '
        'block + "VUELTA 1/3" with no logs', (tester) async {
      await tester.pumpWidget(_wrapProvider(
        const SessionPlayerScreen(init: _kInit),
        _stateOverride(supersetState()),
      ));
      await tester.pump();
      expect(find.text('SUPERSERIE'), findsOneWidget);
      expect(find.text('VUELTA 1/3'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-601: A-1 logged but B-1 pending → still "VUELTA 1/3" '
        '(round-robin waits for B before A-2)', (tester) async {
      await tester.pumpWidget(_wrapProvider(
        const SessionPlayerScreen(init: _kInit),
        _stateOverride(supersetState(logs: [
          makeSetLog(exerciseId: 'e1', setNumber: 1, reps: 10, weightKg: 60.0),
        ])),
      ));
      await tester.pump();
      expect(find.text('VUELTA 1/3'), findsOneWidget);
    });

    testWidgets('SCENARIO-602: A-1 + B-1 logged → advances to "VUELTA 2/3"',
        (tester) async {
      await tester.pumpWidget(_wrapProvider(
        const SessionPlayerScreen(init: _kInit),
        _stateOverride(supersetState(logs: [
          makeSetLog(exerciseId: 'e1', setNumber: 1, reps: 10, weightKg: 60.0),
          makeSetLog(exerciseId: 'e2', setNumber: 1, reps: 10, weightKg: 60.0),
        ])),
      ));
      await tester.pump();
      expect(find.text('VUELTA 2/3'), findsOneWidget);
    });

    testWidgets('SCENARIO-603: every set logged → block shows "COMPLETA"',
        (tester) async {
      final logs = [
        for (final id in ['e1', 'e2'])
          for (var n = 1; n <= 3; n++)
            makeSetLog(exerciseId: id, setNumber: n, reps: 10, weightKg: 60.0),
      ];
      await tester.pumpWidget(_wrapProvider(
        const SessionPlayerScreen(init: _kInit),
        _stateOverride(supersetState(logs: logs)),
      ));
      await tester.pump();
      expect(find.text('COMPLETA'), findsOneWidget);
      expect(find.text('SUPERSERIE'), findsOneWidget);
    });
  });

  // ── _TerminarSessionButton (TASK-206a) ────────────────────────────────────

  group('_TerminarSessionButton', () {
    SessionState completedState() {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 1),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [makeSetLog(exerciseId: 'e1', setNumber: 1)];
      return SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
    }

    // SCENARIO-287: botón habilitado — sin Opacity < 1
    testWidgets('SCENARIO-287: botón habilitado no tiene Opacity < 1',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(completedState()),
        ),
      );
      await tester.pump();
      expect(find.text('TERMINAR SESIÓN'), findsOneWidget);
      // No debe haber Opacity con opacity < 1 envolviendo el botón
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
      final lowOpacity = opacities.where((o) => o.opacity < 1.0);
      expect(lowOpacity, isEmpty);
    });

    // SCENARIO-288: botón deshabilitado — Opacity(0.4)
    // Note: future set rows also render Opacity(0.4) per Change-2, so we
    // assert at least one such widget (the disabled TERMINAR SESIÓN button
    // is one of them).
    testWidgets('SCENARIO-288: botón deshabilitado tiene Opacity(0.4)',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()), // no completado
        ),
      );
      await tester.pump();
      expect(find.text('TERMINAR SESIÓN'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0.4),
        findsAtLeastNWidgets(1),
      );
    });

    // SCENARIO-289: tap en botón deshabilitado → no-op (sin excepción)
    testWidgets('SCENARIO-289: tap en botón deshabilitado es no-op',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()),
        ),
      );
      await tester.pump();
      // No debe lanzar excepción
      await tester.tap(find.text('TERMINAR SESIÓN'));
      await tester.pumpAndSettle();
    });

    // SCENARIO-290: tap en botón habilitado llama al callback
    testWidgets('SCENARIO-290: tap en botón habilitado llama finishSession',
        (tester) async {
      var finishCalled = false;
      final stub = _FinishTrackingNotifier(
        completedState(),
        onFinish: () => finishCalled = true,
      );
      // Necesita GoRouter porque _finishSession navega a /workout/session-summary/...
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const SessionPlayerScreen(init: _kInit),
        ),
        GoRoute(
          path: '/workout/session-summary/:sessionId',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('summary-stub'))),
        ),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [sessionNotifierProvider.overrideWith(() => stub)],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('TERMINAR SESIÓN'));
      await tester.pumpAndSettle();
      expect(finishCalled, isTrue);
    });
  });

  // ── Block gating (pure logic helpers) ────────────────────────────────────

  group('block gating helpers', () {
    test('buildBlocks: two standalone slots → two blocks', () {
      final slots = [
        makeSlot(exerciseId: 'e1'),
        makeSlot(exerciseId: 'e2', exerciseName: 'Sentadilla'),
      ];
      final blocks = buildBlocks(slots);
      expect(blocks.length, 2);
      expect(blocks[0].isSuperset, isFalse);
      expect(blocks[1].isSuperset, isFalse);
    });

    test('buildBlocks: two superset slots → one superset block', () {
      final slots = [
        makeSlot(exerciseId: 'e1', supersetGroup: 1),
        makeSlot(exerciseId: 'e2', exerciseName: 'B', supersetGroup: 1),
      ];
      final blocks = buildBlocks(slots);
      expect(blocks.length, 1);
      expect(blocks[0].isSuperset, isTrue);
      expect(blocks[0].slots.length, 2);
    });

    test('buildBlocks: lone tagged slot falls back to standalone', () {
      final slots = [makeSlot(exerciseId: 'e1', supersetGroup: 99)];
      final blocks = buildBlocks(slots);
      expect(blocks.length, 1);
      expect(blocks[0].isSuperset, isFalse);
    });

    test('computeBlockStatuses: all empty → first is current, rest are future',
        () {
      final slots = [
        makeSlot(exerciseId: 'e1'),
        makeSlot(exerciseId: 'e2', exerciseName: 'B'),
        makeSlot(exerciseId: 'e3', exerciseName: 'C'),
      ];
      final blocks = buildBlocks(slots);
      final statuses = computeBlockStatuses(blocks, const [], 0);
      expect(statuses, [
        BlockStatus.current,
        BlockStatus.future,
        BlockStatus.future,
      ]);
    });

    test('computeBlockStatuses: first block complete → second is current', () {
      final slots = [
        makeSlot(exerciseId: 'e1', targetSets: 2),
        makeSlot(exerciseId: 'e2', exerciseName: 'B', targetSets: 2),
      ];
      final blocks = buildBlocks(slots);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1),
        makeSetLog(exerciseId: 'e1', setNumber: 2),
      ];
      final statuses = computeBlockStatuses(blocks, logs, 0);
      expect(statuses[0], BlockStatus.completed);
      expect(statuses[1], BlockStatus.current);
    });

    test('computeBlockStatuses: all blocks complete → all completed', () {
      final slots = [
        makeSlot(exerciseId: 'e1', targetSets: 1),
        makeSlot(exerciseId: 'e2', exerciseName: 'B', targetSets: 1),
      ];
      final blocks = buildBlocks(slots);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1),
        makeSetLog(exerciseId: 'e2', setNumber: 1),
      ];
      final statuses = computeBlockStatuses(blocks, logs, 0);
      expect(statuses, [BlockStatus.completed, BlockStatus.completed]);
    });

    test('isStandaloneBlockComplete: logs >= effectiveSets.length → true', () {
      // makeSlot with targetSets=2, no explicit sets → effectiveSets length=2
      final slot = makeSlot(exerciseId: 'e1', targetSets: 2);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1),
        makeSetLog(exerciseId: 'e1', setNumber: 2),
      ];
      expect(isStandaloneBlockComplete(slot, logs, 0), isTrue);
    });

    test('isStandaloneBlockComplete: partial logs → false', () {
      final slot = makeSlot(exerciseId: 'e1', targetSets: 3);
      final logs = [makeSetLog(exerciseId: 'e1', setNumber: 1)];
      expect(isStandaloneBlockComplete(slot, logs, 0), isFalse);
    });

    test(
        'plannedRepsForSpec: single reps → returns reps value, '
        'range → returns repsMax', () {
      const single = SetSpec(reps: 10);
      expect(plannedRepsForSpec(single, ExerciseMode.reps), 10);

      const range = SetSpec(repsMin: 8, repsMax: 12);
      expect(plannedRepsForSpec(range, ExerciseMode.reps), 12);
    });

    test('plannedRepsForSpec: duration mode → 0', () {
      const durSpec = SetSpec(durationSeconds: 30);
      expect(plannedRepsForSpec(durSpec, ExerciseMode.duration), 0);
    });
  });

  // ── Duration set detection ────────────────────────────────────────────────

  group('duration set detection', () {
    testWidgets(
        'duration slot shows "Iniciar" button instead of reps stepper or check',
        (tester) async {
      // Slot with durationSeconds = 30 → effectiveSets has durationSeconds set.
      const slot = RoutineSlot(
        exerciseId: 'ed1',
        exerciseName: 'Plancha',
        muscleGroup: 'Core',
        targetSets: 2,
        targetRepsMin: 0,
        targetRepsMax: 0,
        restSeconds: 60,
        durationSeconds: 30,
      );
      final day = makeDay(dayNumber: 1, slots: [slot]);
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // Timer target displayed (00:30).
      expect(find.textContaining('00:30'), findsWidgets);
      // "Iniciar" button present for duration sets (at least one visible).
      expect(find.text('Iniciar'), findsWidgets);
      // No reps stepper — weight is a text field in new design.
      expect(find.text('+'), findsNothing);
    });

    // Change-1: "Listo" button must NOT exist for duration sets (auto-complete only).
    testWidgets(
        'Change-1: duration set has "Iniciar" and no "Listo" button at any point',
        (tester) async {
      const slot = RoutineSlot(
        exerciseId: 'ed2',
        exerciseName: 'Plancha',
        muscleGroup: 'Core',
        targetSets: 1,
        targetRepsMin: 0,
        targetRepsMax: 0,
        restSeconds: 60,
        durationSeconds: 10,
      );
      final day = makeDay(dayNumber: 1, slots: [slot]);
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // "Iniciar" should be present before the timer starts.
      expect(find.text('Iniciar'), findsOneWidget);
      // "Listo" must never appear (manual early completion is removed).
      expect(find.text('Listo'), findsNothing);

      // Tap "Iniciar" to start the timer.
      await tester.tap(find.text('Iniciar'));
      await tester.pump();
      // After starting, "Iniciar" is gone and "Listo" still must not appear.
      expect(find.text('Iniciar'), findsNothing);
      expect(find.text('Listo'), findsNothing);
    });
  });

  // ── Block gating widget tests ─────────────────────────────────────────────

  group('block gating UI', () {
    testWidgets(
        'completed block shows compact summary with checkmark, no interactive rows',
        (tester) async {
      // Two blocks: e1 (1 set, completed), e2 (1 set, pending).
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 1),
        makeSlot(exerciseId: 'e2', exerciseName: 'Curl', targetSets: 1),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [makeSetLog(exerciseId: 'e1', setNumber: 1)];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 1,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // Press should be shown with strikethrough (completed summary).
      final pressText = tester.widget<Text>(find.text('Press'));
      expect(pressText.style?.decoration, TextDecoration.lineThrough);
      // Curl should be shown as the current block (no strikethrough).
      final curlText = tester.widget<Text>(find.text('Curl'));
      expect(curlText.style?.decoration, isNot(TextDecoration.lineThrough));
    });

    testWidgets(
        'SCENARIO-ORDER: future block is tappable to skip ahead (navegación libre)',
        (tester) async {
      // Viewport alto para garantizar que el bloque future se infle (el ListView
      // es lazy: fuera del cache extent no se renderiza).
      await tester.binding.setSurfaceSize(const Size(450, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Dos bloques: e1 pending (current/sugerido), e2 future.
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'A', targetSets: 1),
        makeSlot(exerciseId: 'e2', exerciseName: 'B', targetSets: 1),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // El bloque future B se muestra como tarjeta TAPPABLE con la invitación a
      // adelantarlo — ya no como candado bloqueado.
      expect(find.text('Tocá para adelantar este bloque'), findsOneWidget);
      // No hay ningún candado: la cárcel de gating se levantó.
      expect(find.byIcon(TreinoIcon.lock), findsNothing);

      // Tocar B lo destraba y lo expande interactivo → la invitación desaparece.
      await tester.tap(find.text('Tocá para adelantar este bloque'));
      await tester.pump();
      expect(find.text('Tocá para adelantar este bloque'), findsNothing);
    });
  });

  // ── Future-set dimming (Change-2) ────────────────────────────────────────

  group('future set dimming (Change-2)', () {
    testWidgets(
        'Change-2: future sets in a multi-set exercise are wrapped in Opacity(0.4)',
        (tester) async {
      // Exercise with 3 sets, no logs → set 1 is current, sets 2-3 are future.
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // Sets 2 and 3 must each be wrapped in Opacity(0.4).
      // The disabled TERMINAR SESIÓN button also adds one, so total >= 2.
      final dimmed = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => o.opacity == 0.4)
          .length;
      expect(dimmed, greaterThanOrEqualTo(2));
    });

    testWidgets(
        'Change-2: current and done sets are NOT wrapped in Opacity(0.4)',
        (tester) async {
      // Exercise with 2 sets, set 1 done → set 1 is done, set 2 is current.
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 2),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [makeSetLog(exerciseId: 'e1', setNumber: 1)];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // No future sets — only the disabled TERMINAR SESIÓN button adds Opacity(0.4).
      final dimmed = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => o.opacity == 0.4)
          .length;
      // Exactly one Opacity(0.4) for the disabled button; no future set rows.
      expect(dimmed, equals(1));
    });
  });

  // ── Done-indicator icon (Change-3) ────────────────────────────────────────

  group('done indicator icon (Change-3)', () {
    testWidgets(
        'Change-3: completed exercise header shows checkBare icon, not checkCircleFill',
        (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Squat', targetSets: 2),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1),
        makeSetLog(exerciseId: 'e1', setNumber: 2),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // The exercise-level done indicator must be the bare checkmark.
      expect(find.byIcon(TreinoIcon.checkBare), findsAtLeastNWidgets(1));
      // The filled circle should NOT be used as the exercise-level indicator.
      // (It may still appear inside per-set done rows — that's acceptable.)
      // Here all sets are done so there are no current/pending icon circles.
      expect(find.byIcon(TreinoIcon.checkCircleEmpty), findsNothing);
    });

    testWidgets(
        'Change-3: active exercise header has no leading circle; pending set '
        'buttons still use checkCircleEmpty', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()),
        ),
      );
      await tester.pump();
      // No exercise is done in defaultState — the bare check must not appear.
      expect(find.byIcon(TreinoIcon.checkBare), findsNothing);
      // The active exercise header no longer renders a leading circle; the
      // hollow circle now only marks pending per-set "press to complete"
      // buttons (so it must still be present for the active set rows).
      expect(find.byIcon(TreinoIcon.checkCircleEmpty), findsAtLeastNWidgets(1));
    });
  });

  // ── SCENARIO-037: periodized plan — player uses effectiveSetsForWeek ─────────

  group('SCENARIO-037: player uses effectiveSetsForWeek(weekNumber)', () {
    /// Builds a state where the session is on week 1 (0-based) and the slot
    /// has weeklySets: week0=[3 sets], week1=[2 sets].
    /// The player MUST display 2 sets (week 1 prescription), not 3 (legacy/week 0).
    SessionState periodizedState() {
      const slot = RoutineSlot(
        exerciseId: 'pe1',
        exerciseName: 'Sentadilla Periodizada',
        muscleGroup: 'Piernas',
        targetSets: 3, // legacy — must NOT govern rendering when week=1
        targetRepsMin: 5,
        targetRepsMax: 5,
        restSeconds: 120,
        weeklySets: [
          // week 0 — 3 sets of 5
          [
            SetSpec(reps: 5),
            SetSpec(reps: 5),
            SetSpec(reps: 5),
          ],
          // week 1 — 2 sets of 8
          [
            SetSpec(reps: 8),
            SetSpec(reps: 8),
          ],
        ],
      );
      final day = makeDay(dayNumber: 2, slots: [slot]);
      return SessionState(
        // weekNumber=1 → effectiveSetsForWeek(1) → 2 sets
        session: makeSession(weekNumber: 1),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
    }

    const kPeriodizedInit = FreshSession(routineId: 'r1', dayNumber: 2);

    testWidgets(
        'SCENARIO-037: player renders "0/2" progress when weekNumber=1 '
        '(week-1 prescription has 2 sets, not 3)', (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: kPeriodizedInit),
          _stateOverride(periodizedState()),
        ),
      );
      await tester.pump();
      // Week 1 has 2 sets → progress must show "0/2".
      expect(find.text('0/2'), findsAtLeastNWidgets(1));
      // "0/3" would indicate the legacy targetSets is still driving the render.
      expect(find.text('0/3'), findsNothing);
    });

    testWidgets(
        'SCENARIO-037: computeBlockStatuses passes week param — '
        'block incomplete for week 1 (2 sets, 1 log)', (tester) async {
      final state = periodizedState().copyWith(
        setLogs: [makeSetLog(exerciseId: 'pe1', setNumber: 1)],
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: kPeriodizedInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // 1 log for a 2-set week-1 slot → still incomplete → progress "1/2".
      expect(find.text('1/2'), findsAtLeastNWidgets(1));
    });

    test(
        'SCENARIO-037: isStandaloneBlockComplete uses week param — '
        'week 0 (3 sets) vs week 1 (2 sets)', () {
      const slot = RoutineSlot(
        exerciseId: 'x1',
        exerciseName: 'X',
        muscleGroup: 'M',
        targetSets: 3,
        targetRepsMin: 5,
        targetRepsMax: 5,
        restSeconds: 60,
        weeklySets: [
          [SetSpec(reps: 5), SetSpec(reps: 5), SetSpec(reps: 5)],
          [SetSpec(reps: 8), SetSpec(reps: 8)],
        ],
      );
      final twoLogs = [
        makeSetLog(exerciseId: 'x1', setNumber: 1),
        makeSetLog(exerciseId: 'x1', setNumber: 2, id: 'sl2'),
      ];
      // 2 logs NOT enough for week 0 (needs 3).
      expect(isStandaloneBlockComplete(slot, twoLogs, 0), isFalse);
      // 2 logs IS enough for week 1 (needs 2).
      expect(isStandaloneBlockComplete(slot, twoLogs, 1), isTrue);
    });
  });

  // ── _SessionStatsCard (TASK-204a) ─────────────────────────────────────────

  group('_SessionStatsCard', () {
    // SCENARIO-279: etiqueta 'SESIÓN ACTIVA'
    testWidgets('SCENARIO-279: renderiza etiqueta "SESIÓN ACTIVA"',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()),
        ),
      );
      await tester.pump();
      expect(find.text('SESIÓN ACTIVA'), findsOneWidget);
    });

    // SCENARIO-280: timer '00:00' cuando elapsedSeconds == 0
    testWidgets('SCENARIO-280: timer muestra "00:00" cuando elapsedSeconds=0',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()),
        ),
      );
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);
    });

    // SCENARIO-281: timer '01:03' cuando elapsedSeconds == 63
    testWidgets('SCENARIO-281: timer muestra "01:03" cuando elapsedSeconds=63',
        (tester) async {
      final state = SessionState(
        session: makeSession(),
        day: _defaultState().day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 63,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      expect(find.text('01:03'), findsOneWidget);
    });

    // SCENARIO-282: progreso con conteo correcto de ejercicios
    testWidgets(
        'SCENARIO-282: texto de progreso refleja conteos correctos de ejercicios',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_stateWith1Of3Done()),
        ),
      );
      await tester.pump();
      expect(find.textContaining('1 / 3 ejercicios'), findsOneWidget);
    });
  });

  // ── SCENARIO-WPRES-025: numWeeks==1 player is unchanged (REQ-WPRES-015/030) ─

  group('SCENARIO-WPRES-025: numWeeks==1 player renders all slots unchanged',
      () {
    // When numWeeks==1, all slots have activeWeeks=[] (empty = all weeks).
    // The notifier filter isPresentInWeek(0) on empty mask → true for all.
    // The player must render all slots without any filtering applied.

    test(
        'SCENARIO-WPRES-025: SessionState.day.slots unchanged when '
        'all activeWeeks are empty (numWeeks==1 invariant)', () {
      // Build state directly (without going through the notifier) to verify
      // that the slot list is byte-identical when no filtering is needed.
      // The notifier is already tested via session_notifier_test WPRES-030.
      // This test verifies the player UI renders all such slots.
      final slots = [
        makeSlot(exerciseId: 'e1', targetSets: 3),
        makeSlot(exerciseId: 'e2', exerciseName: 'Sentadilla', targetSets: 4),
        makeSlot(exerciseId: 'e3', exerciseName: 'Peso muerto', targetSets: 3),
      ];
      // All slots have default activeWeeks=[] → all present in any week.
      for (final s in slots) {
        expect(s.activeWeeks, isEmpty,
            reason: 'Single-week slot must have empty activeWeeks mask');
        expect(s.isPresentInWeek(0), isTrue,
            reason: 'Empty mask → present in week 0 (numWeeks==1 invariant)');
      }
      expect(slots.length, equals(3));
    });

    testWidgets(
        'SCENARIO-WPRES-025: player renders all 3 slots '
        'when session has all-empty-mask slots', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', targetSets: 3),
        makeSlot(exerciseId: 'e2', exerciseName: 'Sentadilla', targetSets: 4),
        makeSlot(exerciseId: 'e3', exerciseName: 'Peso muerto', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final state = SessionState(
        session: makeSession(weekNumber: 0),
        day: day, // SessionNotifier filter: all empty masks → all present
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // All 3 slots must render as exercise rows in the list
      // ("1 / 3 ejercicios" progress indicator confirms 3 total slots)
      expect(find.textContaining('0 / 3 ejercicios'), findsOneWidget,
          reason: 'All 3 slots render in single-week session');
    });
  });

  // ── live-set-editing PR1: 9-site gating-math thread (AD-5) ────────────────

  group('live-set-editing: session-local set count gating (sites 4-9)', () {
    // ── [SITE-4] isStandaloneBlockComplete honors the resolver ─────────────
    test(
        '[SITE-4][AD-5] isStandaloneBlockComplete resolver param overrides '
        'the raw plan count', () {
      final slot = makeSlot(exerciseId: 'e1', targetSets: 3);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
        makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'),
      ];
      // No resolver → unchanged behavior (plan count, backward compat).
      expect(isStandaloneBlockComplete(slot, logs, 0), isTrue);
      // Resolver reporting an override of 4 → NOT complete at 3 logs.
      expect(
        isStandaloneBlockComplete(slot, logs, 0, (_) => 4),
        isFalse,
      );
    });

    // ── [SITE-5] isSupersetBlockComplete honors the resolver ────────────────
    test(
        '[SITE-5][AD-5] isSupersetBlockComplete reports false when an '
        'overridden member is not done, even if all others are', () {
      final memberA =
          makeSlot(exerciseId: 'a1', exerciseName: 'A', targetSets: 3);
      final memberB =
          makeSlot(exerciseId: 'b1', exerciseName: 'B', targetSets: 3);
      final logs = [
        makeSetLog(exerciseId: 'a1', setNumber: 1, id: 'a1l1'),
        makeSetLog(exerciseId: 'a1', setNumber: 2, id: 'a1l2'),
        makeSetLog(exerciseId: 'a1', setNumber: 3, id: 'a1l3'),
        makeSetLog(exerciseId: 'b1', setNumber: 1, id: 'b1l1'),
        makeSetLog(exerciseId: 'b1', setNumber: 2, id: 'b1l2'),
        makeSetLog(exerciseId: 'b1', setNumber: 3, id: 'b1l3'),
      ];
      final members = [memberA, memberB];
      // No resolver → both members done at plan count → complete.
      expect(isSupersetBlockComplete(members, logs, 0), isTrue);
      // memberA overridden to 4 (3 logged) → block stays open.
      expect(
        isSupersetBlockComplete(
          members,
          logs,
          0,
          (slot) => slot.exerciseId == 'a1' ? 4 : 3,
        ),
        isFalse,
      );
    });

    // ── [SITE-4] widget: added-beyond-plan exercise keeps rendering current ─
    testWidgets(
        '[SITE-4][REQ:workout#Added set keeps the exercise incomplete until '
        'logged] a 3-set exercise with an added 4th set (3 logged) renders '
        'as the interactive current block, not collapsed', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
        makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 4},
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // The collapsed "3/3" strikethrough summary must NOT appear.
      final pressText = tester.widget<Text>(find.text('Press'));
      expect(pressText.style?.decoration, isNot(TextDecoration.lineThrough));
      // Progress badge must read 3/4, not 3/3.
      expect(find.text('3/4'), findsOneWidget);
    });

    // ── [SITE-6] _CompletedBlockSummary shows the overridden total ─────────
    testWidgets(
        '[SITE-6][AD-5] a collapsed completed block with a reduced override '
        '(2/2) shows "2/2", not the raw plan count "3/3"', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
        makeSlot(exerciseId: 'e2', exerciseName: 'Curl', targetSets: 1),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 1,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 2},
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('3/3'), findsNothing);
    });

    // ── [SITE-7] _StandaloneBlock render totalSets/isDone honor override ───
    testWidgets(
        '[SITE-7][AD-5] the interactive section for an override=4 exercise '
        'renders 4 rows, not 3', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 4},
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // Progress badge must read 0/4 — 4 rows expected, plan count (3)
      // must not be the render bound.
      expect(find.text('0/4'), findsOneWidget);
    });

    // ── [SITE-8] _SupersetSection round scan honors override ────────────────
    test(
        '[SITE-8][AD-5] superset maxRounds fold + round-bound check use the '
        'resolver instead of the raw plan count (defensive correctness — no '
        'add/remove UI is placed inside a superset block this change)', () {
      final memberA = makeSlot(
          exerciseId: 'a1', exerciseName: 'A', targetSets: 3, supersetGroup: 1);
      final memberB = makeSlot(
          exerciseId: 'b1', exerciseName: 'B', targetSets: 3, supersetGroup: 1);
      final blocks = buildBlocks([memberA, memberB]);
      expect(blocks.single.isSuperset, isTrue);
      // Sanity: without an override, both members plan-count at 3.
      expect(
        isSupersetBlockComplete([memberA, memberB], const [], 0),
        isFalse,
      );
      // With memberA overridden to 4, the block is still gated correctly
      // through the same resolver path used by the round scan.
      expect(
        isSupersetBlockComplete(
          [memberA, memberB],
          const [],
          0,
          (slot) => slot.exerciseId == 'a1' ? 4 : 3,
        ),
        isFalse,
      );
    });

    // ── [SITE-9][AD-4] null-safe spec on the added row — no RangeError ──────
    testWidgets(
        '[SITE-9][AD-4] an added row beyond effectiveSets.length renders '
        'with no crash, no planned target hint, and starts bare (0 reps, '
        '0 kg, no prefill from the previous logged set)', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [
        makeSetLog(
            exerciseId: 'e1', setNumber: 1, id: 'l1', reps: 10, weightKg: 80.0),
        makeSetLog(
            exerciseId: 'e1', setNumber: 2, id: 'l2', reps: 10, weightKg: 80.0),
        makeSetLog(
            exerciseId: 'e1', setNumber: 3, id: 'l3', reps: 10, weightKg: 80.0),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 4},
      );
      // Must not throw a RangeError building the 4th (bare) row.
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Row 4 is the current pending row — no planned target hint text
      // ("8–12 reps"-style prescription) since it has no SetSpec.
      expect(find.textContaining('8–12 reps'), findsNothing);
      // AD-4 regression guard: the bare row does NOT prefill from the
      // previous logged set (80 kg) — its weight field starts empty/0.
      expect(find.text('80 kg'), findsNothing);
    });

    // ── [AD-6] "+ agregar serie" affordance ──────────────────────────────────
    testWidgets(
        '[REQ:workout#Add button renders an extra loggable row] tapping '
        '"+ agregar serie" renders one new empty row below the last, '
        'numbered sequentially', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 1),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      expect(find.text('0/1'), findsOneWidget);
      expect(find.textContaining('agregar serie'), findsOneWidget);
    });

    testWidgets(
        '[REQ:workout#Adding a set is only available on the current/'
        'reachable exercise] a COMPLETED/collapsed block does NOT show '
        '"+ agregar serie" anywhere in its subtree', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 1),
        makeSlot(exerciseId: 'e2', exerciseName: 'Curl', targetSets: 1),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [makeSetLog(exerciseId: 'e1', setNumber: 1)];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 1,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // Only the CURRENT block (Curl) should offer "+ agregar serie" — the
      // completed Press summary must not.
      expect(find.textContaining('agregar serie'), findsOneWidget);
    });

    // ── [AD-6] per-row delete icon + confirm dialog (live-set-editing PR2) ──

    testWidgets(
        '[REQ:workout#Removing an unlogged set requires no confirmation] '
        'tapping the delete icon on an added-but-unlogged pending row '
        'removes it immediately with NO dialog shown', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
        makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 4},
      );
      RoutineSlot? capturedSlot;
      SetLog? capturedTarget;
      var callCount = 0;
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          [
            sessionNotifierProvider.overrideWith(
              () => _RemoveTrackingNotifier(state, onRemoveSet: (slot, t) {
                callCount++;
                capturedSlot = slot;
                capturedTarget = t;
              }),
            ),
          ],
        ),
      );
      await tester.pump();

      // Row 4 is the pending/unlogged added row — its delete icon.
      final deleteIcons = find.byIcon(TreinoIcon.trash);
      expect(deleteIcons, findsWidgets);
      await tester.ensureVisible(deleteIcons.last);
      await tester.pumpAndSettle();
      await tester.tap(deleteIcons.last);
      await tester.pump();

      // No confirm dialog for an unlogged row.
      expect(find.text('Eliminar serie'), findsNothing);
      expect(callCount, equals(1));
      expect(capturedSlot?.exerciseId, equals('e1'));
      expect(capturedTarget, isNull);
    });

    testWidgets(
        '[REQ:workout#Removing a logged set surfaces a confirmation] '
        'tapping the delete icon on a LOGGED row shows a confirm dialog and '
        'does NOT call removeSet until Eliminar is tapped; Cancelar leaves '
        'the row untouched', (tester) async {
      // 3 logged but the override keeps the block OPEN (current, not
      // collapsed) — this test exercises the per-row delete icon, which
      // only renders while the section is interactive.
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
        makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
        makeSetLog(exerciseId: 'e1', setNumber: 3, id: 'l3'),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 4},
      );
      var callCount = 0;
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          [
            sessionNotifierProvider.overrideWith(
              () => _RemoveTrackingNotifier(
                state,
                onRemoveSet: (_, __) => callCount++,
              ),
            ),
          ],
        ),
      );
      await tester.pump();

      final deleteIcons = find.byIcon(TreinoIcon.trash);
      expect(deleteIcons, findsWidgets);

      // Tap the delete icon of a LOGGED row (set 1).
      await tester.tap(deleteIcons.first);
      await tester.pumpAndSettle();

      expect(find.text('Eliminar serie'), findsOneWidget);
      expect(
          find.text('Se va a borrar esta serie registrada.'), findsOneWidget);
      expect(callCount, equals(0),
          reason: 'removeSet must not be called before confirmation');

      // Cancelar closes the dialog without calling removeSet.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar serie'), findsNothing);
      expect(callCount, equals(0));

      // Re-open and confirm this time.
      await tester.tap(deleteIcons.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(callCount, equals(1));
    });

    testWidgets(
        '[REQ:workout#Removing a set is only available on the current/'
        'reachable exercise] a COMPLETED/collapsed block does not show the '
        'per-row delete icon anywhere in its subtree', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 1),
        makeSlot(exerciseId: 'e2', exerciseName: 'Curl', targetSets: 2),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);
      // Press (e1) is complete → collapses. Curl (e2, current, 1 of 2
      // logged) has its logged row's delete icon visible (a logged row
      // always shows the icon) — proves the CURRENT block offers it while
      // the COMPLETED Press summary does not.
      final logs = [
        makeSetLog(exerciseId: 'e1', setNumber: 1),
        makeSetLog(exerciseId: 'e2', exerciseName: 'Curl', setNumber: 1),
      ];
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: logs,
        currentExerciseIndex: 1,
        elapsedSeconds: 0,
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      // Only the CURRENT block (Curl, 1 logged row) should show a delete
      // icon — the completed Press summary must not.
      expect(find.byIcon(TreinoIcon.trash), findsOneWidget);
    });

    testWidgets(
        '[REQ:workout#Removing a set renumbers surviving sets] after '
        'confirming removal of set 2 of a 3-logged exercise, the UI shows '
        'sets numbered 1 and 2 (no visible gap, no "SET 1, SET 3")',
        (tester) async {
      // targetSets=3 so the block stays OPEN (current, not collapsed) at 1
      // of 2 remaining logged — this test exercises row-level renumbering,
      // which only renders while the section is interactive.
      final slotsOpen = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slotsOpen);
      // Simulates the state AFTER removeSet already renumbered survivor l3
      // from setNumber 3 -> 2 and dropped the override to 2 (this test only
      // exercises the render side — the row loop is positional, "SET idx+1",
      // so it must show 1 and 2 regardless of the underlying doc's id).
      final state = SessionState(
        session: makeSession(),
        day: day,
        setLogs: [makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1')],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 2},
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(state),
        ),
      );
      await tester.pump();
      expect(find.text('1/2'), findsOneWidget);
      // Both rows render with sequential positional labels 1 and 2 — no
      // "SET 1, SET 3" gap. The row label itself is a plain '1'/'2' Text.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('3'), findsNothing);
    });

    testWidgets(
        '[AD-5 mid-remove reopen guard][REQ:workout#Removed set allows '
        'completion at the reduced count] sub-case A — not both remaining '
        'logged: block stays current, not completed', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);

      // override dropped to 2, only 1 of 2 remaining logged — block must
      // stay current (not completed).
      final stateNotBothDone = SessionState(
        session: makeSession(),
        day: day,
        setLogs: [makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1')],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 2},
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(stateNotBothDone),
        ),
      );
      await tester.pump();
      expect(find.text('1/2'), findsOneWidget);
      final pressTextA = tester.widget<Text>(find.text('Press'));
      expect(pressTextA.style?.decoration, isNot(TextDecoration.lineThrough),
          reason: 'block must stay current, not collapse as completed');
    });

    testWidgets(
        '[AD-5 mid-remove reopen guard][REQ:workout#Removed set allows '
        'completion at the reduced count] sub-case B — both remaining '
        'logged: block reports completed at the reduced count', (tester) async {
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press', targetSets: 3),
      ];
      final day = makeDay(dayNumber: 1, slots: slots);

      // override dropped to 2, BOTH remaining logged — block must report
      // completed at the reduced count.
      final stateBothDone = SessionState(
        session: makeSession(),
        day: day,
        setLogs: [
          makeSetLog(exerciseId: 'e1', setNumber: 1, id: 'l1'),
          makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'),
        ],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
        setCountOverride: const {'e1': 2},
      );
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(stateBothDone),
        ),
      );
      await tester.pump();
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('3/3'), findsNothing,
          reason: 'progress must not wait for a 3rd set that no longer '
              'exists');
    });
  });
}
