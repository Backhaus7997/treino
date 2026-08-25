import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/watch/application/wear_rest_providers.dart';
import 'package:treino/features/watch/application/wear_timer_sync_providers.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';
import 'package:treino/features/watch/domain/watch_effort.dart';
import 'package:treino/features/watch/presentation/wear/wear_workout_screen.dart';
import 'package:treino/features/watch/presentation/wear/wear_workout_view_model.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

class _ServicioFalso extends Mock implements WearWorkoutService {}

class _SyncFalso extends Mock implements WearTimerSync {}

/// **El lado que arranca el cronómetro es el dueño de la serie. El otro la
/// espeja y no la carga.**
///
/// Es la regla que evita el bug, y hasta acá el reloj no la tenía: marcaba la
/// serie por su cuenta al vencer el temporizador nativo, sin preguntarse quién
/// lo había arrancado. Con el teléfono anotando el suyo en la misma sesión, eso
/// deja DOS documentos para la misma serie —cada cliente genera su propio id,
/// así que el que llega tarde no puede deduplicar— y el atleta la ve repetida.
///
/// Se monta en el tamaño real del reloj: Flutter tira ante cualquier overflow, y
/// esta pantalla ya tuvo dos defectos que sólo se veían en la muñeca.
void main() {
  /// Samsung SM-L500: 438 px físicos, densidad 2.125 → 206 dp de lado.
  const fisico = Size(438, 438);
  const densidad = 2.125;

  late _ServicioFalso service;
  late _SyncFalso sync;
  late StreamController<WearExerciseTimer?> temporizador;
  late List<({String exerciseId, int setNumber})> marcadas;

  /// El deadline nativo del temporizador de estos tests.
  const deadline = 555000;

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = fisico;
    view.devicePixelRatio = densidad;

    service = _ServicioFalso();
    sync = _SyncFalso();
    temporizador = StreamController<WearExerciseTimer?>.broadcast();
    marcadas = [];
    when(() => service.startRest(any())).thenAnswer((_) async {});
    when(sync.cancelar).thenAnswer((_) async {});
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    unawaited(temporizador.close());
  });

  WearExerciseTimer nativo({bool finished = false}) => (
        endsAtElapsedMs: deadline,
        totalMs: 60000,
        remainingMs: finished ? 0 : 30000,
        finished: finished,
      );

  const snapshot = WearWorkoutSnapshot(
    exerciseId: 'plancha',
    exerciseName: 'Plancha',
    exerciseIndex: 0,
    exerciseCount: 1,
    dayName: 'Core',
    sets: [SetSpec(durationSeconds: 60)],
    loggedSetNumbers: {},
    restSeconds: 60,
    isFullyCompleted: false,
  );

  /// [ajeno] es el deadline que el buzón marcó como "no es de este reloj".
  Future<void> montar(WidgetTester tester, {int? ajeno}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wearWorkoutServiceProvider.overrideWithValue(service),
          wearTimerSyncProvider.overrideWithValue(sync),
          wearExerciseTimerProvider.overrideWith((ref) => temporizador.stream),
          wearRestProvider.overrideWith((ref) => Stream.value(null)),
          wearEffortProvider.overrideWith(
            (ref) => Stream.value(const WatchEffortDisplay.nada()),
          ),
          wearTimerAjenoProvider.overrideWith((ref) => ajeno),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [AppPalette.mintMagenta]),
          home: WearWorkoutScreen(
            snapshot: snapshot,
            onLogSet: (exerciseId, setNumber) =>
                marcadas.add((exerciseId: exerciseId, setNumber: setNumber)),
            onFinish: () {},
            onAbandon: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lo hace correr hasta el final. El `listen` dispara en la TRANSICIÓN, así
  /// que hace falta un valor previo: un temporizador que nace vencido no
  /// notifica a nadie.
  Future<void> vencer(WidgetTester tester) async {
    temporizador.add(nativo());
    await tester.pump();
    temporizador.add(nativo(finished: true));
    await tester.pump();
  }

  group('al vencer, sólo el DUEÑO carga la serie', () {
    testWidgets('el cronómetro propio marca la serie y arranca el descanso',
        (tester) async {
      await montar(tester);

      await vencer(tester);

      expect(marcadas, [(exerciseId: 'plancha', setNumber: 1)]);
      // Terminar de aguantar es terminar la serie: el descanso arranca igual
      // que en una serie normal.
      verify(() => service.startRest(60)).called(1);
    });

    testWidgets('un cronómetro del TELÉFONO no marca nada', (tester) async {
      await montar(tester, ajeno: deadline);

      await vencer(tester);

      // El teléfono es el dueño y ya la marcó. Si este reloj la marcara
      // también, el atleta la vería repetida en el historial.
      expect(marcadas, isEmpty);
      verifyNever(() => service.startRest(any()));
    });

    testWidgets('una marca vieja, de OTRO deadline, no bloquea la serie propia',
        (tester) async {
      // La marca no se limpia nunca a propósito —limpiarla abre una carrera con
      // el borrado del documento—, así que tiene que quedar obsoleta sola. Un
      // temporizador nuevo tiene otro deadline y no coincide.
      await montar(tester, ajeno: deadline - 12345);

      await vencer(tester);

      expect(marcadas, [(exerciseId: 'plancha', setNumber: 1)]);
    });
  });

  /// Muestra el temporizador y BAJA hasta el final de la lista.
  ///
  /// Bajar no es opcional: el andamio es un `ListView` y no construye lo que no
  /// se ve, así que en 206 dp los botones del fondo directamente no existen en
  /// el árbol. Buscarlos sin scrollear da "no está" siempre —también cuando SÍ
  /// está— y el test pasaría diciendo lo que no probó. Es el mismo mecanismo
  /// que ya dejó a «Cancelar» inalcanzable en la muñeca.
  Future<void> mostrarBotones(WidgetTester tester) async {
    temporizador.add(nativo());
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
  }

  group('un cronómetro ajeno se mira, no se maneja', () {
    testWidgets('el propio ofrece Cancelar', (tester) async {
      await montar(tester);

      await mostrarBotones(tester);

      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Ocultar'), findsOneWidget);
    });

    testWidgets('el del teléfono NO ofrece Cancelar, pero sí Ocultar',
        (tester) async {
      await montar(tester, ajeno: deadline);

      await mostrarBotones(tester);

      // Cancelar acá borraría el espejo de esta muñeca mientras el teléfono
      // —dueño— sigue contando y marca la serie igual. Ocultar sí: esconder el
      // espejo no le hace nada a la cuenta.
      expect(find.text('Ocultar'), findsOneWidget);
      expect(find.text('Cancelar'), findsNothing);
    });

    testWidgets('sin el botón, la pantalla sigue entrando en 206 dp',
        (tester) async {
      // Flutter tira ante cualquier overflow. Sacar un botón de la fila cambia
      // el layout, y esta pantalla ya tuvo dos defectos que sólo se veían acá.
      // Se scrollea primero para que la fila de botones exista de verdad.
      await montar(tester, ajeno: deadline);

      await mostrarBotones(tester);

      expect(find.text('Ocultar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
