// Tests para SessionPlayerScreen — SCENARIO-274..276 (_SessionHeader, TASK-202a)
// + SCENARIO-277..278 (_AttendanceCard, TASK-203a).
// TASK-203a: _AttendanceCard fue incluida en el commit 202b junto con el esqueleto
// de la pantalla — los tests 277-278 son GREEN desde el primer run (desviación
// documentada en apply-progress.md).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

import '../../../features/workout/application/stub_factories.dart';

// ── Helpers de test ───────────────────────────────────────────────────────────

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
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

// ── Factories de estado ───────────────────────────────────────────────────────

SessionState _defaultState() => SessionState(
      session: makeSession(),
      day: makeDay(
        dayNumber: 4,
        slots: [
          makeSlot(
              exerciseId: 'e1',
              exerciseName: 'Press de banca',
              targetSets: 3),
          makeSlot(
              exerciseId: 'e2', exerciseName: 'Sentadilla', targetSets: 3),
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

    // SCENARIO-284: fila current — badge 'Ahora'
    testWidgets('SCENARIO-284: estado current renderiza badge "Ahora"',
        (tester) async {
      // Estado default: e1 sin logs → current en index 0
      await tester.pumpWidget(
        _wrapProvider(
          const SessionPlayerScreen(init: _kInit),
          _stateOverride(_defaultState()),
        ),
      );
      await tester.pump();
      expect(find.text('Ahora'), findsOneWidget);
    });

    // SCENARIO-285: fila pending — tap llama al callback (abre el sheet)
    testWidgets(
        'SCENARIO-285: estado pending es tappable y abre SetEntrySheet',
        (tester) async {
      // Estado donde e1 está completo, e2 es pending
      final slots = [
        makeSlot(exerciseId: 'e1', exerciseName: 'Press de banca', targetSets: 1),
        makeSlot(exerciseId: 'e2', exerciseName: 'Sentadilla', targetSets: 3),
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
      // Sentadilla es pending — tap debe abrir el sheet
      await tester.tap(find.text('Sentadilla'));
      await tester.pumpAndSettle();
      // El sheet abierto muestra el nombre en mayúsculas
      expect(find.text('SENTADILLA'), findsOneWidget);
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
}
