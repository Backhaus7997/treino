// Tests para SessionPlayerScreen — SCENARIO-274..276 (_SessionHeader, TASK-202a).
// El archivo de producción no existe — RED.

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

// ── _SessionHeader (TASK-202a) ────────────────────────────────────────────────

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
}
