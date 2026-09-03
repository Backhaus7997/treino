// Regresión de QA-WKT-001 (CRITICAL) — sets por DURACIÓN nunca se logueaban.
//
// El bug (fase-2, verificado fase-9): cuando el countdown de un set de duración
// llegaba a 0, `_DurationSetRow.onDone` invoca `onSetCheck(setNumber, 0, 0.0)` y
// el handler `_logSet` descartaba TODO log con `reps <= 0`. Resultado: el SetLog
// nunca se creaba, el bloque no se marcaba completo, `isFullyCompleted` jamás
// era true y TERMINAR SESIÓN quedaba deshabilitado para siempre en cualquier día
// con al menos un ejercicio por tiempo.
//
// El fix (session_player_screen.dart): `_logSet` solo aplica el guard `reps<=0`
// a los sets por REPS; en modo duración (`slot.effectiveExerciseMode ==
// ExerciseMode.duration`) permite `reps == 0` y loguea el set.
//
// Estos tests verifican el comportamiento correcto: al terminar el countdown el
// set se loguea (`notifier.logSet` se invoca), el bloque completa y TERMINAR
// SESIÓN se habilita. Setup basado en session_player_screen_test.dart, grupo
// "duration set detection".

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/application/workout_clock.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/duration_timer.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../features/workout/application/stub_factories.dart';

// ── Setup común ───────────────────────────────────────────────────────────────

const _kInit = FreshSession(routineId: 'r1', dayNumber: 1);

/// Notifier stub que replica el comportamiento CORRECTO del real: registra el
/// SetLog y lo agrega al estado para que la UI recompute la completitud. NO
/// pasa por Firestore (test puro). Extiende `SessionNotifier` directamente para
/// que `overrideWith` lo acepte (mismo patrón que `_StubNotifier` /
/// `_FinishTrackingNotifier` en session_player_screen_test.dart).
///
/// `build` se sobreescribe por completo y NO llama a super, así que tampoco se
/// arranca el timer de tiempo transcurrido de la sesión real: el único Timer en
/// juego es el countdown del `_DurationSetRow`, que se auto-cancela al llegar a
/// 0 (no quedan timers pendientes al terminar el test).
class _DurationLoggingNotifier extends SessionNotifier {
  _DurationLoggingNotifier(this._initial);

  final SessionState _initial;

  /// Todos los SetLog despachados vía [logSet] durante el test.
  final List<SetLog> loggedSets = <SetLog>[];

  @override
  Future<SessionState> build(SessionInit arg) async => _initial;

  @override
  Future<void> logSet(SetLog setLog) async {
    loggedSets.add(setLog);
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(setLogs: [...current.setLogs, setLog]),
    );
  }
}

/// Día con UN solo ejercicio por duración (1 set, 00:03). `durationSeconds > 0`
/// hace que `effectiveExerciseMode` sea `ExerciseMode.duration` y que
/// `effectiveSets` sintetice 1 SetSpec de duración → `_DurationSetRow`.
SessionState _durationOnlyState() => SessionState(
      session: makeSession(),
      day: makeDay(
        dayNumber: 1,
        slots: const [
          RoutineSlot(
            exerciseId: 'edur',
            exerciseName: 'Plancha',
            muscleGroup: 'Core',
            targetSets: 1,
            targetRepsMin: 0,
            targetRepsMax: 0,
            restSeconds: 60,
            durationSeconds: 3,
          ),
        ],
      ),
      setLogs: const [],
      currentExerciseIndex: 0,
      elapsedSeconds: 0,
    );

/// Reloj de pared controlable.
///
/// La cuenta de un ejercicio por tiempo se deriva del INSTANTE de fin, no de
/// cuántos ticks corrieron (ver `DurationTimerRules`). `tester.pump(5s)` mueve
/// el tiempo falso de los timers pero NO el reloj de pared, así que para llevar
/// el countdown a cero hay que mover este.
///
/// El test verifica exactamente lo mismo que antes; lo único que cambió es cómo
/// se hace pasar el tiempo.
DateTime _ahora = DateTime.utc(2027, 1, 15, 10);

Widget _wrap(
  SessionNotifier Function() create, {
  List<Override> extra = const [],
}) =>
    ProviderScope(
      overrides: [
        sessionNotifierProvider.overrideWith(create),
        workoutClockProvider.overrideWithValue(() => _ahora),
        ...extra,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(body: SessionPlayerScreen(init: _kInit)),
      ),
    );

ElevatedButton _finishButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('TERMINAR SESIÓN'),
        matching: find.byType(ElevatedButton),
      ),
    );

void main() {
  group('QA-WKT-001: completar un set de duración', () {
    // El reloj arranca en el mismo punto en cada test: es estado global del
    // archivo y sin esto el orden de ejecucion podria filtrarse de uno a otro.
    setUp(() => _ahora = DateTime.utc(2027, 1, 15, 10));

    // Ancla GREEN ejecutable (SIN skip): precondición estable que se cumple
    // HOY y también DESPUÉS del fix. Un día de solo-duración, sin sets
    // logueados aún, arranca con "Iniciar" visible y TERMINAR deshabilitado.
    // Valida además que el harness de este archivo monta bien la pantalla.
    testWidgets(
        'precondición: día de solo-duración arranca con "Iniciar" visible y '
        'TERMINAR deshabilitado', (tester) async {
      await tester.pumpWidget(
        _wrap(() => _DurationLoggingNotifier(_durationOnlyState())),
      );
      await tester.pump();

      expect(find.text('Iniciar'), findsOneWidget);

      final button = _finishButton(tester);
      expect(
        button.onPressed,
        isNull,
        reason:
            'sin sets logueados la sesión no está completa → botón inactivo',
      );
    });

    // Regresión del bug. Comportamiento CORRECTO: al llegar el countdown a 0,
    // el set de duración se persiste (SetLog creado y despachado al notifier),
    // el bloque se colapsa a "completo" y TERMINAR SESIÓN se habilita.
    //
    // Por qué HOY falla: `_DurationSetRow.onDone` llama
    // `onSetCheck(setNumber, 0, 0.0)` y `_logSet` retorna sin loguear porque
    // `reps <= 0` (session_player_screen.dart:353-354). Entonces
    // `notifier.logSet` NUNCA se invoca → `loggedSets` queda vacío, el bloque
    // nunca completa y TERMINAR sigue deshabilitado → las tres aserciones
    // fallan. Al corregir el guard (permitir reps == 0 en modo duración) el
    // test pasa. La aserción es agnóstica al valor de reps del fix (0 o 1):
    // solo exige que EXISTA el log del set de duración.
    testWidgets(
        'countdown a 0 loguea el set de duración, completa el bloque y '
        'habilita TERMINAR SESIÓN', (tester) async {
      final notifier = _DurationLoggingNotifier(_durationOnlyState());
      await tester.pumpWidget(_wrap(() => notifier));
      await tester.pump();

      // Precondición: incompleto, botón "Iniciar" presente.
      expect(find.text('Iniciar'), findsOneWidget);
      expect(_finishButton(tester).onPressed, isNull);

      // Arrancar el countdown y llevarlo más allá de 0. Con targetSeconds = 3
      // basta con adelantar el reloj de pared 5 segundos: la cuenta se deriva
      // del instante de fin, así que UN tick alcanza para verla terminada. Ya
      // no importa cuántos ticks hayan corrido — que es todo el punto del
      // cambio a reloj de pared.
      await tester.tap(find.text('Iniciar'));
      await tester.pump();
      _ahora = _ahora.add(const Duration(seconds: 5));
      await tester.pump(DurationTimerRules.tickInterval);
      await tester.pump();

      // 1) El set quedó logueado: SetLog creado para el ejercicio de duración.
      expect(notifier.loggedSets, hasLength(1));
      expect(notifier.loggedSets.single.exerciseId, 'edur');
      expect(notifier.loggedSets.single.setNumber, 1);

      // 2) El bloque se marca completo: colapsa al resumen "1/1" con el nombre
      //    tachado (_CompletedBlockSummary). El layout ampliado del player
      //    renderiza los nombres en UPPERCASE (heading condensed).
      expect(find.text('1/1'), findsOneWidget);
      final nameText = tester.widget<Text>(find.text('PLANCHA'));
      expect(nameText.style?.decoration, TextDecoration.lineThrough);

      // 3) TERMINAR SESIÓN habilitado (isFullyCompleted == true).
      expect(_finishButton(tester).onPressed, isNotNull);
    });
  });

  group('la PANTALLA es la autoridad de completado', () {
    setUp(() => _ahora = DateTime.utc(2027, 1, 15, 10));

    testWidgets('marca la serie aunque la fila NUNCA se haya redibujado',
        (tester) async {
      // El punto del cambio: quien completa es la pantalla, que está montada
      // todo el tiempo que el player está abierto. Antes completaba la fila, y
      // la fila se desmonta al scrollear — con ella moría la cuenta y nadie
      // marcaba nada.
      //
      // Acá se avanza el reloj de pared y se corre UN tick sin tocar la fila.
      final notifier = _DurationLoggingNotifier(_durationOnlyState());
      await tester.pumpWidget(_wrap(() => notifier));
      await tester.pump();

      await tester.tap(find.text('Iniciar'));
      await tester.pump();

      _ahora = _ahora.add(const Duration(seconds: 5));
      await tester.pump(DurationTimerRules.tickInterval);
      await tester.pump();

      expect(notifier.loggedSets, hasLength(1));
      expect(notifier.loggedSets.single.exerciseId, 'edur');
      expect(notifier.loggedSets.single.setNumber, 1);
    });

    testWidgets('no marca dos veces si entran varios ticks', (tester) async {
      // La cuenta se limpia al vencer, así que el tick siguiente no encuentra
      // nada. Sin eso, cada tick posterior marcaría la serie de nuevo.
      final notifier = _DurationLoggingNotifier(_durationOnlyState());
      await tester.pumpWidget(_wrap(() => notifier));
      await tester.pump();

      await tester.tap(find.text('Iniciar'));
      await tester.pump();

      _ahora = _ahora.add(const Duration(seconds: 5));
      for (var i = 0; i < 4; i++) {
        await tester.pump(DurationTimerRules.tickInterval);
      }
      await tester.pump();

      expect(notifier.loggedSets, hasLength(1));
    });
  });

  // ── #817 ────────────────────────────────────────────────────────────────────
  group('la anotación de la sesión no queda huérfana al llegar a cero', () {
    // El bug: `_revisarCronometro` limpiaba el `ValueNotifier` local con
    // `clear()` —que a propósito NO toca Firestore— y ahí terminaba. Los dos
    // caminos que sí borraban la anotación cubren CANCELACIONES: la fila cuando
    // el atleta corta, y `WearTimerSync` cuando corta el reloj. El fin natural
    // de la cuenta no lo cubría ninguno, así que el documento de la sesión
    // quedaba con el cronómetro puesto para siempre.
    //
    // No rompía el teléfono —el filtro `owner == reloj` de `_resolver` hace que
    // la app ignore su propia anotación—, pero el companion de Wear espeja lo
    // anotado: abrir el reloj un rato después mostraba una cuenta vencida que
    // nadie limpió.
    //
    // Este test entra por la PANTALLA REAL y mira Firestore, no un mock del
    // recorder. Es deliberado: el borrado tiene que salir del `ProviderScope`
    // que monta el player, y un doble del recorder no distingue el scope
    // correcto del que devuelve `null` y no borra nada en silencio.
    late FakeFirebaseFirestore firestore;
    late SessionRepository repo;

    const uid = 'u1';
    const sessionId = 's1';

    setUp(() {
      _ahora = DateTime.utc(2027, 1, 15, 10);
      firestore = FakeFirebaseFirestore();
      repo = SessionRepository(firestore: firestore);
    });

    List<Override> overrides() => [
          sessionRepositoryProvider.overrideWithValue(repo),
          currentUidProvider.overrideWithValue(uid),
        ];

    Future<Map<String, dynamic>?> docDeSesion() async => (await firestore
            .collection('users')
            .doc(uid)
            .collection('sessions')
            .doc(sessionId)
            .get())
        .data();

    testWidgets('al vencer la cuenta, el cronómetro se borra del documento',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          () => _DurationLoggingNotifier(_durationOnlyState()),
          extra: overrides(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Iniciar'));
      await tester.pump();
      await tester.pump();

      // Precondición, y no es decorativa: si esto ya fuera null el test pasaría
      // por la razón equivocada —nunca se anotó nada— y no probaría el borrado.
      expect(
        (await docDeSesion())?[SessionRepository.fieldTimerEndsAt],
        isNotNull,
        reason: 'la fila tiene que haber anotado el cronómetro al arrancar',
      );

      // Y ahora la cuenta termina SOLA: nadie cancela nada.
      _ahora = _ahora.add(const Duration(seconds: 5));
      await tester.pump(DurationTimerRules.tickInterval);
      await tester.pump();

      final doc = await docDeSesion();
      expect(
        doc?[SessionRepository.fieldTimerEndsAt],
        isNull,
        reason: 'el reloj de Wear espeja esto: si queda, muestra una cuenta '
            'vencida que nadie limpió',
      );
      // Los cinco campos se van juntos: media anotación es un estado que
      // `watchExerciseTimer` lee como "no hay", pero deja basura en el doc.
      expect(doc?[SessionRepository.fieldTimerExerciseId], isNull);
      expect(doc?[SessionRepository.fieldTimerSetNumber], isNull);
      expect(doc?[SessionRepository.fieldTimerTotalSeconds], isNull);
      expect(doc?[SessionRepository.fieldTimerOwner], isNull);
    });

    testWidgets('y la serie se marca igual: el borrado no la pisa',
        (tester) async {
      // El borrado y el `logSet` salen en la misma función. No compiten —uno
      // borra campos del documento de la sesión con `merge`, el otro crea un
      // documento en la subcolección `setLogs`— y ninguno espera al otro. Esto
      // lo fija: si algún día el borrado pasara a ser bloqueante o a reescribir
      // el documento entero, la serie dejaría de marcarse y se vería acá.
      final notifier = _DurationLoggingNotifier(_durationOnlyState());
      await tester.pumpWidget(_wrap(() => notifier, extra: overrides()));
      await tester.pump();

      await tester.tap(find.text('Iniciar'));
      await tester.pump();
      _ahora = _ahora.add(const Duration(seconds: 5));
      await tester.pump(DurationTimerRules.tickInterval);
      await tester.pump();

      expect(notifier.loggedSets, hasLength(1));
      expect(notifier.loggedSets.single.exerciseId, 'edur');
      expect(
        (await docDeSesion())?[SessionRepository.fieldTimerEndsAt],
        isNull,
      );
    });
  });
}
