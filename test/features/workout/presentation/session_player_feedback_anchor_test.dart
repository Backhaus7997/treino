// Tests del ancla de "Comentar / Reportar" en el player (#628).
//
// Cubren las dos cosas que el commit original hacía mal y que ningún test
// miraba —`Key('exercise_feedback_open')` no aparecía en NINGÚN test—:
//
//  1. El reporte se anclaba a `currentSetNumber`, que es la serie PENDIENTE.
//     Con 3 de 4 series hechas, el reporte salía con `setNumber: 4`, una serie
//     que todavía no existía; del lado del PF `session_exercise_block.dart`
//     matchea por `setNumber` y la nota caía bajo el log equivocado.
//  2. Al completarse el ejercicio el bloque colapsa en el MISMO frame, y el
//     resumen colapsado no llevaba el botón: el atleta que sale del ejercicio
//     con una molestia se quedaba sin ninguna puerta para avisar.
//
// El contrato que fijan estos tests, en una frase válida en TODOS los call
// sites: el reporte se ancla a la ÚLTIMA serie que el atleta REALMENTE hizo, o
// a `null` (nivel ejercicio) si todavía no hizo ninguna. Las dos torceduras
// posibles son simétricas y las dos falsean el dato del PF: inventar una serie
// que no existe (la pendiente, o la "1" con cero series cargadas) y tirar la
// que sí existe (mandar null desde un bloque terminado).
//
// Se verifica contra el submitter real del sheet (no contra un espía de la
// pantalla) porque lo que importa es lo que termina PERSISTIDO.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/workout/application/exercise_feedback_submitter.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../features/workout/application/stub_factories.dart';

class _MockSubmitter extends Mock implements ExerciseFeedbackSubmitter {}

/// Stub que devuelve el state dado para cualquier SessionInit — mismo patrón
/// que `_StubNotifier` en session_player_screen_test.dart.
class _StubNotifier extends SessionNotifier {
  _StubNotifier(this._state);
  final SessionState _state;

  @override
  Future<SessionState> build(SessionInit arg) async => _state;
}

const _kInit = FreshSession(routineId: 'r1', dayNumber: 1);

TrainerLink _activeLink() => TrainerLink(
      id: 'link-1',
      trainerId: 'pf-1',
      athleteId: 'u1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 8, 1),
      acceptedAt: DateTime.utc(2026, 8, 2),
    );

void main() {
  late _MockSubmitter submitter;

  setUpAll(() {
    registerFallbackValue(ExerciseFeedbackKind.comment);
  });

  setUp(() {
    submitter = _MockSubmitter();
    when(() => submitter.submit(
          uid: any(named: 'uid'),
          sessionId: any(named: 'sessionId'),
          exerciseId: any(named: 'exerciseId'),
          exerciseName: any(named: 'exerciseName'),
          kind: any(named: 'kind'),
          setNumber: any(named: 'setNumber'),
          text: any(named: 'text'),
          localPhotoPath: any(named: 'localPhotoPath'),
          now: any(named: 'now'),
        )).thenAnswer((_) async => ExerciseFeedback(
          id: 'fb-1',
          exerciseId: 'e1',
          exerciseName: 'Press de banca',
          kind: ExerciseFeedbackKind.comment,
          text: 'x',
          createdAt: DateTime.utc(2026, 8, 25),
        ));
  });

  /// Monta el player con PF vinculado (sin vínculo `active` el botón ni se
  /// dibuja) y el submitter mockeado. Locale fijo: el sheet lee copy de
  /// AppL10n y el host de tests resuelve `en` por default.
  ///
  /// [linked] false ⇒ atleta SIN PF, la población que nunca ve el botón.
  Future<void> pumpPlayer(
    WidgetTester tester,
    SessionState state, {
    bool linked = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionNotifierProvider.overrideWith(() => _StubNotifier(state)),
          currentUidProvider.overrideWithValue('u1'),
          currentAthleteLinkProvider
              .overrideWith((ref) async => linked ? _activeLink() : null),
          exerciseFeedbackSubmitterProvider.overrideWithValue(submitter),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          locale: const Locale('es', 'AR'),
          localizationsDelegates: const [
            AppL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppL10n.supportedLocales,
          home: const Scaffold(body: SessionPlayerScreen(init: _kInit)),
        ),
      ),
    );
    // frame 1: state + link en loading; frame 2: resueltos → botón visible.
    await tester.pump();
    await tester.pump();
  }

  /// Toca el botón de reporte [index], escribe algo y envía. Devuelve control
  /// recién cuando el submit resolvió.
  Future<void> reportThroughSheet(
    WidgetTester tester, {
    int index = 0,
    String text = 'Me tira el hombro',
  }) async {
    final action = find.byKey(const Key('exercise_feedback_open'));
    expect(action, findsWidgets,
        reason:
            'el acceso a "Comentar / Reportar" tiene que estar en pantalla');
    await tester.tap(action.at(index));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('exercise_feedback_text')),
      text,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('exercise_feedback_submit')));
    await tester.pumpAndSettle();
  }

  /// Espía del `setNumber` con el que se persistió el reporte.
  int? capturedSetNumber() => verify(() => submitter.submit(
        uid: any(named: 'uid'),
        sessionId: any(named: 'sessionId'),
        exerciseId: any(named: 'exerciseId'),
        exerciseName: any(named: 'exerciseName'),
        kind: any(named: 'kind'),
        setNumber: captureAny(named: 'setNumber'),
        text: any(named: 'text'),
        localPhotoPath: any(named: 'localPhotoPath'),
      )).captured.single as int?;

  SessionState standaloneState({
    required int targetSets,
    required int loggedSets,
  }) =>
      SessionState(
        session: makeSession(),
        day: makeDay(
          dayNumber: 1,
          slots: [
            makeSlot(
              exerciseId: 'e1',
              exerciseName: 'Press de banca',
              targetSets: targetSets,
            ),
          ],
        ),
        setLogs: [
          for (var n = 1; n <= loggedSets; n++)
            makeSetLog(id: 'sl$n', exerciseId: 'e1', setNumber: n),
        ],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );

  group('ancla del reporte (#628)', () {
    testWidgets(
        'con 3 de 4 series hechas el reporte se ancla a la 3 — la ÚLTIMA hecha, '
        'no la que falta', (tester) async {
      await pumpPlayer(tester, standaloneState(targetSets: 4, loggedSets: 3));

      await reportThroughSheet(tester);

      // El bug: reusaba `currentSetNumber` (= 4, la fila resaltada como
      // pendiente) y el PF veía la nota colgada de una serie inexistente.
      expect(capturedSetNumber(), equals(3));
    });

    testWidgets(
        'sin ninguna serie cargada el reporte va a NIVEL EJERCICIO, no a una '
        'serie 1 inventada', (tester) async {
      await pumpPlayer(tester, standaloneState(targetSets: 4, loggedSets: 0));

      await reportThroughSheet(tester, text: 'La máquina está floja');

      // `setNumber: 1` acá persiste el reporte contra una serie que el atleta
      // NO hizo — mismo defecto que anclar a la pendiente, corrido un lugar.
      // El nivel ejercicio (null) ya está soportado por la API y es lo único
      // verdadero cuando todavía no se cargó nada.
      expect(capturedSetNumber(), isNull);
    });

    testWidgets(
        'en una superserie cada miembro se ancla a SU propia última serie',
        (tester) async {
      // Round-robin: A-1, B-1, A-2 hechas → el turno es de B-2. Antes, sólo el
      // miembro con el turno tenía `currentSetNumber`; el otro reportaba sin
      // serie.
      final state = SessionState(
        session: makeSession(),
        day: makeDay(
          dayNumber: 1,
          slots: [
            makeSlot(
                exerciseId: 'e1',
                exerciseName: 'Remo',
                targetSets: 3,
                supersetGroup: 1),
            makeSlot(
                exerciseId: 'e2',
                exerciseName: 'Curl',
                targetSets: 3,
                supersetGroup: 1),
          ],
        ),
        setLogs: [
          makeSetLog(id: 'a1', exerciseId: 'e1', setNumber: 1),
          makeSetLog(id: 'b1', exerciseId: 'e2', setNumber: 1),
          makeSetLog(id: 'a2', exerciseId: 'e1', setNumber: 2),
        ],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await pumpPlayer(tester, state);

      // index 0 = primer miembro (e1 "Remo"), con 2 series hechas.
      await reportThroughSheet(tester, text: 'Me tira el hombro en el remo');

      expect(capturedSetNumber(), equals(2));
    });
  });

  group('reporte sobre el bloque ya completado (#628)', () {
    testWidgets(
        'terminada la última serie el acceso SIGUE en pantalla y se ancla a esa '
        'última serie', (tester) async {
      // 2 de 2 → `computeBlockStatuses` marca el bloque completed y colapsa a
      // _CompletedBlockSummary en el mismo frame.
      await pumpPlayer(tester, standaloneState(targetSets: 2, loggedSets: 2));

      await reportThroughSheet(tester, text: 'Terminé con molestia lumbar');

      // Este ES el escenario que motivó el botón: la molestia se siente al
      // SOLTAR la última serie. Que no haya serie EN CURSO no borra la última
      // HECHA, y mandar null acá tiraba justo el dato más caro — el PF no
      // sabría en qué serie pasó. `_CompletedBlockSummary` es además la única
      // superficie de este caso: dentro de _ExerciseSection el camino
      // `isDone == true` es inalcanzable para un standalone.
      expect(capturedSetNumber(), equals(2));
    });

    testWidgets('la superserie completa deja un acceso POR MIEMBRO',
        (tester) async {
      final state = SessionState(
        session: makeSession(),
        day: makeDay(
          dayNumber: 1,
          slots: [
            makeSlot(
                exerciseId: 'e1',
                exerciseName: 'Remo',
                targetSets: 2,
                supersetGroup: 1),
            makeSlot(
                exerciseId: 'e2',
                exerciseName: 'Curl',
                targetSets: 2,
                supersetGroup: 1),
          ],
        ),
        setLogs: [
          for (final id in ['e1', 'e2'])
            for (var n = 1; n <= 2; n++)
              makeSetLog(id: '$id-$n', exerciseId: id, setNumber: n),
        ],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await pumpPlayer(tester, state);

      // Uno por miembro: en una superserie el dolor es de UN ejercicio, y sin
      // el botón por miembro el reporte no sabría a cuál apuntar.
      expect(find.byKey(const Key('exercise_feedback_open')), findsNWidgets(2));

      // El segundo miembro (e2 "Curl") también reporta, no sólo el primero, y
      // se ancla a SU última serie (la 2), no a null.
      await reportThroughSheet(tester, index: 1, text: 'Me molesta el codo');

      verify(() => submitter.submit(
            uid: 'u1',
            sessionId: 's1',
            exerciseId: 'e2',
            exerciseName: 'Curl',
            kind: ExerciseFeedbackKind.comment,
            setNumber: 2,
            text: 'Me molesta el codo',
            localPhotoPath: null,
          )).called(1);
    });

    testWidgets(
        'en la superserie completa cada miembro se ancla a SU propia última '
        'serie, no al conteo del grupo', (tester) async {
      // Miembros DESPAREJOS a propósito (2 y 3 series): con targetSets
      // distintos el bloque igual cierra completo, y si el ancla se leyera del
      // grupo —o del otro miembro— la nota del Curl caería bajo un log que no
      // existe. `session_exercise_block.dart` matchea por `setNumber`.
      final state = SessionState(
        session: makeSession(),
        day: makeDay(
          dayNumber: 1,
          slots: [
            makeSlot(
                exerciseId: 'e1',
                exerciseName: 'Remo',
                targetSets: 2,
                supersetGroup: 1),
            makeSlot(
                exerciseId: 'e2',
                exerciseName: 'Curl',
                targetSets: 3,
                supersetGroup: 1),
          ],
        ),
        setLogs: [
          for (var n = 1; n <= 2; n++)
            makeSetLog(id: 'e1-$n', exerciseId: 'e1', setNumber: n),
          for (var n = 1; n <= 3; n++)
            makeSetLog(id: 'e2-$n', exerciseId: 'e2', setNumber: n),
        ],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await pumpPlayer(tester, state);

      await reportThroughSheet(tester, text: 'El remo me dejó el hombro');
      expect(capturedSetNumber(), equals(2));
    });

    testWidgets(
        'sin PF vinculado la superserie completa vuelve a la línea unida — el '
        'resumen no crece a N filas para nadie', (tester) async {
      // El desglose por miembro existe SOLO para que cada botón sepa a qué
      // ejercicio apunta. El atleta sin PF nunca ve el botón, así que pagarle
      // N líneas en un resumen COLAPSADO sería empeorarle la pantalla a cambio
      // de nada. Sin vínculo vuelve el "A · B" de joinNonEmpty (#550).
      final state = SessionState(
        session: makeSession(),
        day: makeDay(
          dayNumber: 1,
          slots: [
            makeSlot(
                exerciseId: 'e1',
                exerciseName: 'Remo',
                targetSets: 2,
                supersetGroup: 1),
            makeSlot(
                exerciseId: 'e2',
                exerciseName: 'Curl',
                targetSets: 2,
                supersetGroup: 1),
          ],
        ),
        setLogs: [
          for (final id in ['e1', 'e2'])
            for (var n = 1; n <= 2; n++)
              makeSetLog(id: '$id-$n', exerciseId: id, setNumber: n),
        ],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );
      await pumpPlayer(tester, state, linked: false);

      expect(find.byKey(const Key('exercise_feedback_open')), findsNothing);
      expect(find.text('REMO · CURL'), findsOneWidget);
    });
  });
}
