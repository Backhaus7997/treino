import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/application/watch_credential_providers.dart';
import 'package:treino/features/watch/application/watch_effort_notifier.dart';
import 'package:treino/features/watch/application/watch_timer_control_notifier.dart';
import 'package:treino/features/watch/data/watch_bridge.dart';
import 'package:treino/features/watch/domain/watch_effort.dart';
import 'package:treino/features/workout/application/duration_timer_providers.dart';
import 'package:treino/features/workout/application/workout_clock.dart';
import 'package:treino/features/workout/domain/duration_timer.dart';
import 'package:treino/features/workout/domain/duration_timer_owner.dart';
import 'package:treino/features/workout/domain/duration_timer_state.dart';
import 'package:treino/features/workout/presentation/widgets/duration_set_row.dart';

import '../../../helpers/test_app_wrapper.dart';

class _MockBridge extends Mock implements WatchBridge {}

class _AnotadorFalso extends Mock implements DurationTimerRecorder {}

void main() {
  late _MockBridge bridge;

  /// Lo que esta fila deja anotado en la sesión, que es por donde lo lee un
  /// reloj de Wear OS.
  late _AnotadorFalso anotador;

  setUpAll(() {
    registerFallbackValue(
      DurationTimerState(
        exerciseId: 'x',
        setNumber: 1,
        totalSeconds: 1,
        endsAt: DateTime.utc(2030),
        owner: DurationTimerOwner.telefono,
      ),
    );
  });

  /// Reloj de pared controlable. La fila lo lee en cada tick.
  late DateTime ahora;

  setUp(() {
    bridge = _MockBridge();
    anotador = _AnotadorFalso();
    ahora = DateTime.utc(2027, 1, 15, 10);
    when(() => bridge.isSupported).thenAnswer((_) async => true);
    when(() => bridge.isPaired).thenAnswer((_) async => true);
    when(() => bridge.isReachable).thenAnswer((_) async => true);
    when(() => bridge.sendMessage(any())).thenAnswer((_) async {});
  });

  /// Lo que el RELOJ está publicando en este momento, si algo.
  ///
  /// Se inyecta como el notifier real con un stream vacío: lo que importa para
  /// la fila es el `value`, y así el test ejercita el mismo tipo que corre en
  /// producción en vez de un doble.
  late WatchEffortNotifier relojNotifier;

  /// El canal por el que el RELOJ pide cortar la cuenta del teléfono.
  late WatchTimerControlNotifier control;

  /// Un payload como el que manda el reloj cuando cronometra una serie.
  WatchEffort delReloj({
    String exerciseId = 'plancha',
    int setNumber = 2,
    int totalSeconds = 60,
    required Duration falta,
  }) =>
      WatchEffort(
        measuredAt: ahora,
        timerExerciseId: exerciseId,
        timerSetNumber: setNumber,
        timerTotalSeconds: totalSeconds,
        timerEndsAt: ahora.add(falta),
      );

  Future<void> montar(
    WidgetTester tester, {
    required VoidCallback? onDone,
    int targetSeconds = 60,
    WatchEffort? enElReloj,
    DurationTimerState? enLaSesion,
  }) async {
    relojNotifier = WatchEffortNotifier(
      contextStream: const Stream<Map<String, dynamic>>.empty(),
    );
    control = WatchTimerControlNotifier(
      messageStream: const Stream<Map<String, dynamic>>.empty(),
    );
    if (enElReloj != null) relojNotifier.value = enElReloj;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchBridgeProvider.overrideWithValue(bridge),
          workoutClockProvider.overrideWithValue(() => ahora),
          watchEffortNotifierProvider.overrideWithValue(relojNotifier),
          watchTimerControlNotifierProvider.overrideWithValue(control),
          // El otro camino hacia la muñeca: lo anotado en la sesión, que es
          // por donde cruza un reloj de WEAR OS. Su Data Layer exige
          // emparejamiento con ESE teléfono —medido en hardware— así que un
          // mensaje no llega nunca.
          sessionDurationTimerProvider
              .overrideWith((ref) => Stream.value(enLaSesion)),
          durationTimerRecorderProvider.overrideWithValue(anotador),
        ],
        child: TestAppWrapper(
          child: DurationSetRow(
            exerciseId: 'plancha',
            setNumber: 2,
            targetSeconds: targetSeconds,
            isDone: false,
            onDone: onDone,
          ),
        ),
      ),
    );
    // Un pump de más, y hace falta: lo anotado en la sesión llega por un stream
    // y no está en el primer frame. Sin esto, los tests del espejo de Wear
    // pasaban sin dibujar nada — verde por ausencia, que es la peor clase de
    // verde.
    await tester.pump();
  }

  Future<void> arrancar(WidgetTester tester) async {
    await tester.tap(find.text('Iniciar'));
    await tester.pump();
  }

  testWidgets('antes de arrancar muestra el objetivo', (tester) async {
    await montar(tester, onDone: () {});
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('Iniciar'), findsOneWidget);
  });

  testWidgets('la cuenta NO depende de cuántos ticks corrieron',
      (tester) async {
    // Este es el test que justifica el cambio entero.
    //
    // La fila contaba decrementando un contador una vez por tick. Con la app
    // estrangulada —pantalla bloqueada, batería baja, otra app adelante— los
    // ticks no corren y NO se recuperan: una plancha de 60 segundos terminaba
    // durando 70, y el atleta no tenía cómo notarlo.
    //
    // Acá se simula exactamente eso: pasan 70 segundos de RELOJ DE PARED y
    // corre UN SOLO tick. Con la implementación vieja el contador estaría en
    // 59 y la serie sin marcar.
    var marcada = false;
    await montar(tester, onDone: () => marcada = true);
    await arrancar(tester);
    expect(find.text('01:00'), findsOneWidget);

    ahora = ahora.add(const Duration(seconds: 70));
    await tester.pump(DurationTimerRules.tickInterval);

    expect(marcada, isTrue,
        reason: 'la serie tiene que marcarse: el tiempo ya pasó');
    expect(find.text('00:00'), findsNothing,
        reason: 'terminada, vuelve a mostrar el objetivo');
  });

  testWidgets('mientras corre, la cuenta baja con el reloj de pared',
      (tester) async {
    await montar(tester, onDone: () {});
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 25));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(find.text('00:35'), findsOneWidget);

    // Redondeo hacia ARRIBA: con una fracción de segundo por delante la serie
    // NO terminó. Mostrar 0 con tiempo restante invita a cortar antes.
    ahora = ahora.add(const Duration(milliseconds: 34600));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(find.text('00:01'), findsOneWidget);
  });

  testWidgets('arrancar le manda al reloj el INSTANTE de fin', (tester) async {
    await montar(tester, onDone: () {});
    await arrancar(tester);
    await tester.pump();

    final sent = verify(() => bridge.sendMessage(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(sent['kind'], 'watchTimer');
    expect(sent['action'], 'start');
    expect(sent['exerciseId'], 'plancha');
    expect(sent['setNumber'], 2);
    expect(
      sent['endsAtMs'],
      ahora.add(const Duration(seconds: 60)).millisecondsSinceEpoch,
      reason: 'el reloj deriva su cuenta de este instante, no de los segundos '
          'que faltan',
    );
  });

  testWidgets('cancelar corta la cuenta, no marca la serie, y avisa al reloj',
      (tester) async {
    var marcada = false;
    await montar(tester, onDone: () => marcada = true);
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 25));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(find.text('00:35'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pump();

    expect(find.text('01:00'), findsOneWidget,
        reason: 'vuelve al objetivo, lista para arrancar de nuevo');
    expect(find.text('Iniciar'), findsOneWidget);

    // Y sobre todo: pasar el tiempo NO marca una serie cancelada.
    ahora = ahora.add(const Duration(seconds: 300));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(marcada, isFalse);

    final mensajes = verify(() => bridge.sendMessage(captureAny()))
        .captured
        .cast<Map<String, dynamic>>();
    expect(mensajes.last['action'], 'cancel',
        reason: 'sin este aviso el reloj sigue contando algo que ya no existe');
  });

  testWidgets('sin reloj alcanzable el cronómetro del teléfono anda igual',
      (tester) async {
    // El espejo en la muñeca es una mejora, no el mecanismo. El dueño de la
    // serie es el teléfono, y tiene que contar aunque el reloj no exista.
    when(() => bridge.isReachable).thenAnswer((_) async => false);
    var marcada = false;
    await montar(tester, onDone: () => marcada = true);
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 61));
    await tester.pump(DurationTimerRules.tickInterval);

    expect(marcada, isTrue);
    verifyNever(() => bridge.sendMessage(any()));
  });

  group('la cuenta que arrancó en el RELOJ', () {
    // Esto NUNCA funcionó. El dato del reloj llegaba al teléfono desde el
    // primer día —y el commit eaf700a6 arregló que llegara incluso fuera del
    // player— pero el único consumidor era un MM:SS de 12px en la card de
    // arriba de la pantalla. La fila del ejercicio, que es donde el atleta
    // mira, no tenía ningún cable de entrada: seguía ofreciendo "Iniciar"
    // sobre una serie que ya se estaba cronometrando en la muñeca.
    //
    // `timerExerciseId` y `timerTotalSeconds` se parseaban y no los leía NADIE
    // en toda la app. Esa es la prueba de que la fila nunca estuvo conectada.

    testWidgets('se ve en la fila, sin tocar nada', (tester) async {
      await montar(
        tester,
        onDone: () {},
        enElReloj: delReloj(falta: const Duration(seconds: 45)),
      );

      expect(find.text('00:45'), findsOneWidget);
      expect(find.text('corriendo en el reloj'), findsOneWidget);
      expect(
        find.text('Iniciar'),
        findsNothing,
        reason: 'ofrecer arrancar una serie que ya se está cronometrando es lo '
            'que produce dos cronómetros sobre la misma serie',
      );
    });

    testWidgets('baja sola, sin que el reloj mande nada nuevo', (tester) async {
      // El reloj publica cada ~5 segundos. Si el teléfono solo repintara al
      // recibir, el número quedaría congelado entre envío y envío. La cuenta se
      // deriva del instante de fin, así que baja sola.
      await montar(
        tester,
        onDone: () {},
        enElReloj: delReloj(falta: const Duration(seconds: 45)),
      );
      expect(find.text('00:45'), findsOneWidget);

      ahora = ahora.add(const Duration(seconds: 20));
      await tester.pump(DurationTimerRules.tickInterval);

      expect(find.text('00:25'), findsOneWidget);
    });

    testWidgets('el teléfono NO marca la serie: el dueño es el reloj',
        (tester) async {
      // El invariante que evita el duplicado. El reloj carga la serie al llegar
      // a cero; si el teléfono también la cargara quedarían dos documentos con
      // ids distintos y el atleta la vería repetida.
      var marcada = false;
      await montar(
        tester,
        onDone: () => marcada = true,
        enElReloj: delReloj(falta: const Duration(seconds: 45)),
      );

      ahora = ahora.add(const Duration(seconds: 90));
      await tester.pump(DurationTimerRules.tickInterval);

      expect(marcada, isFalse);
    });

    testWidgets('no le manda ninguna orden al reloj', (tester) async {
      // Un `start` acá sería un eco: el reloj arrancó la cuenta y el teléfono
      // se la devolvería. Un `cancel` sería peor — cancelaría del otro lado un
      // cronómetro que este teléfono nunca arrancó.
      await montar(
        tester,
        onDone: () {},
        enElReloj: delReloj(falta: const Duration(seconds: 45)),
      );

      ahora = ahora.add(const Duration(seconds: 20));
      await tester.pump(DurationTimerRules.tickInterval);

      verifyNever(() => bridge.sendMessage(any()));
    });

    testWidgets('una cuenta sobre OTRA serie no se dibuja acá', (tester) async {
      // La fila es la serie 2. Sin `timerSetNumber` en el payload, el teléfono
      // solo sabría el ejercicio y pintaría la cuenta en las tres series.
      await montar(
        tester,
        onDone: () {},
        enElReloj: delReloj(setNumber: 3, falta: const Duration(seconds: 45)),
      );

      expect(find.text('00:45'), findsNothing);
      expect(find.text('01:00'), findsOneWidget);
      expect(find.text('Iniciar'), findsOneWidget);
    });

    testWidgets('una cuenta ya vencida no se dibuja', (tester) async {
      // El último contexto recibido puede describir una cuenta que ya terminó.
      await montar(
        tester,
        onDone: () {},
        enElReloj: delReloj(falta: const Duration(seconds: -5)),
      );

      expect(find.text('corriendo en el reloj'), findsNothing);
      expect(find.text('Iniciar'), findsOneWidget);
    });
  });

  testWidgets('el RELOJ puede cortar la cuenta que corre en el teléfono',
      (tester) async {
    // El camino que faltaba entero: hasta ahora el reloj nunca le había mandado
    // un mensaje al teléfono, y del lado Dart `messageStream` existía sin que lo
    // escuchara nadie.
    var marcada = false;
    await montar(tester, onDone: () => marcada = true);
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 25));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(find.text('00:35'), findsOneWidget);

    // El reloj pide cortar ESA serie.
    control.value = const WatchTimerCancelRequest(
      secuencia: 1,
      exerciseId: 'plancha',
      setNumber: 2,
    );
    await tester.pump();

    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('Iniciar'), findsOneWidget);

    // Y sobre todo: pasar el tiempo NO marca una serie cancelada desde la
    // muñeca.
    ahora = ahora.add(const Duration(seconds: 300));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(marcada, isFalse);

    // Se le CONTESTA al reloj. No es un eco: es el acuse. `WCSession` no da
    // callback de éxito, así que sin esto la muñeca no sabe si llegó.
    final mensajes = verify(() => bridge.sendMessage(captureAny()))
        .captured
        .cast<Map<String, dynamic>>();
    expect(
      mensajes.where((m) => m['action'] == 'cancel'),
      hasLength(1),
      reason: 'el teléfono acusa la cancelación; el reloj no responde a eso',
    );
  });

  testWidgets('un pedido del reloj para OTRA serie no toca esta fila',
      (tester) async {
    // El notifier es uno solo y todas las filas montadas lo escuchan. Sin
    // comparar identidad, cancelar en la muñeca cortaría también la plancha que
    // el atleta está aguantando en otra fila.
    await montar(tester, onDone: () {});
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 25));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(find.text('00:35'), findsOneWidget);

    control.value = const WatchTimerCancelRequest(
      secuencia: 1,
      exerciseId: 'plancha',
      setNumber: 3,
    );
    await tester.pump();

    expect(find.text('00:35'), findsOneWidget,
        reason: 'la cuenta de ESTA serie sigue corriendo');
  });

  testWidgets('si el log falla, "Iniciar" sigue sirviendo', (tester) async {
    // Gimnasio sin señal. La cuenta llega a cero, se llama `onDone`, y el write
    // a Firestore falla: `SessionNotifier.logSet` atrapa el error A PROPÓSITO y
    // NO toca `setLogs`, para que la fila quede usable y el atleta reintente.
    //
    // O sea que la serie NO queda marcada, la ValueKey no cambia y este State
    // sobrevive con su instante de fin vencido. Si no se limpia, `_startTimer`
    // corta con `if (_endsAt != null) return` y el botón queda muerto: se ve
    // "Iniciar", se toca, y no pasa nada. Para siempre.
    var marcadas = 0;
    await montar(tester, onDone: () => marcadas++);
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 61));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(marcadas, 1);

    // El log falló: `isDone` sigue false y la fila vuelve a ofrecer arrancar.
    expect(find.text('Iniciar'), findsOneWidget);

    await arrancar(tester);
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget,
        reason: 'la cuenta arrancó de verdad, el botón no está muerto');

    ahora = ahora.add(const Duration(seconds: 61));
    await tester.pump(DurationTimerRules.tickInterval);
    expect(marcadas, 2, reason: 'el reintento también marca');
  });

  testWidgets('desmontarse a mitad de cuenta le avisa al reloj',
      (tester) async {
    // El player mete los ejercicios en un `ListView` sin keep-alive: si el
    // atleta scrollea, la fila sale del viewport y su State se destruye. La
    // cuenta muere ahí y nadie va a marcar la serie.
    //
    // El reloj no tiene cómo enterarse solo: su espejo llegaría a cero, VIBRA
    // "terminaste" por una serie que nadie cargó, y encima bloquea arrancarla
    // de nuevo desde la muñeca.
    await montar(tester, onDone: () {});
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 25));
    await tester.pump(DurationTimerRules.tickInterval);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final mensajes = verify(() => bridge.sendMessage(captureAny()))
        .captured
        .cast<Map<String, dynamic>>();
    expect(mensajes.last['action'], 'cancel');
  });

  testWidgets('desmontarse DESPUÉS de terminar NO le avisa al reloj',
      (tester) async {
    // El desmontaje normal: al marcarse la serie cambia la ValueKey y este
    // State se destruye. Mandar `cancel` acá le cortaría al reloj el háptico de
    // fin de una serie que se completó bien.
    await montar(tester, onDone: () {});
    await arrancar(tester);

    ahora = ahora.add(const Duration(seconds: 61));
    await tester.pump(DurationTimerRules.tickInterval);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final mensajes = verify(() => bridge.sendMessage(captureAny()))
        .captured
        .cast<Map<String, dynamic>>();
    expect(
      mensajes.where((m) => m['action'] == 'cancel'),
      isEmpty,
      reason: 'la serie terminó bien: no hay nada que cancelar',
    );
  });

  testWidgets('una fila no interactiva no arranca nada', (tester) async {
    await montar(tester, onDone: null);
    await tester.tap(find.text('Iniciar'));
    await tester.pump();

    ahora = ahora.add(const Duration(seconds: 120));
    await tester.pump(DurationTimerRules.tickInterval);

    expect(find.text('01:00'), findsOneWidget);
    verifyNever(() => bridge.sendMessage(any()));
  });

  group('lo que esta fila deja anotado en la SESIÓN', () {
    // Es el único canal que cruza hacia un reloj de Wear OS: su Data Layer
    // exige emparejamiento con ESE teléfono —medido en hardware, el envío muere
    // en «no hay nodos conectados»— y encima un mensaje se pierde si el otro no
    // está escuchando. El caso real es arrancar acá y mirar la muñeca un rato
    // después, y para eso hace falta ESTADO, no un aviso.

    DurationTimerState anotado() {
      final capturado =
          verify(() => anotador.anotar(captureAny())).captured.single;
      return capturado as DurationTimerState;
    }

    testWidgets('arrancar lo anota con identidad, fin y dueño', (tester) async {
      await montar(tester, onDone: () {}, targetSeconds: 60);

      await arrancar(tester);

      final t = anotado();
      expect(t.exerciseId, 'plancha');
      expect(t.setNumber, 2);
      expect(t.totalSeconds, 60);
      // El INSTANTE de fin, no lo que falta: así el reloj deriva la cuenta
      // contra su propio reloj de pared y una lectura que llega tarde sigue
      // dando el número correcto.
      expect(t.endsAt, ahora.add(const Duration(seconds: 60)));
      // Y el dueño, que es lo que evita que los dos carguen la misma serie.
      expect(t.owner, DurationTimerOwner.telefono);
    });

    testWidgets('cancelar lo borra', (tester) async {
      await montar(tester, onDone: () {});
      await arrancar(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pump();

      verify(anotador.borrar).called(1);
    });

    testWidgets('al vencer también lo borra', (tester) async {
      // Es estado persistido, no un aviso: si queda ahí, el próximo aparato que
      // lea la sesión encuentra un cronómetro fantasma.
      await montar(tester, onDone: () {}, targetSeconds: 60);
      await arrancar(tester);

      ahora = ahora.add(const Duration(seconds: 61));
      await tester.pump(DurationTimerRules.tickInterval);

      verify(anotador.borrar).called(1);
    });

    testWidgets('desmontarse a mitad de cuenta lo borra', (tester) async {
      // La fila murió con la cuenta corriendo —el atleta scrolleó— y nadie va a
      // marcar la serie. Si la anotación queda, el espejo del reloj llega a
      // cero, vibra "terminaste" por una serie que nadie cargó, y encima le
      // bloquea arrancarla de nuevo desde la muñeca.
      await montar(tester, onDone: () {});
      await arrancar(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      verify(anotador.borrar).called(1);
    });

    testWidgets('sin Firebase inicializado, la fila arranca igual',
        (tester) async {
      // Sin los overrides: el anotador REAL, sobre una app donde Firebase no
      // existe. Es el contexto de cualquier test de widget del player, y antes
      // reventaba con `FirebaseException` apenas se tocaba el botón.
      //
      // Una sincronización que no sale degrada el espejo. Un botón que tira no
      // deja entrenar.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            watchBridgeProvider.overrideWithValue(bridge),
            workoutClockProvider.overrideWithValue(() => ahora),
            watchEffortNotifierProvider.overrideWithValue(
              WatchEffortNotifier(
                contextStream: const Stream<Map<String, dynamic>>.empty(),
              ),
            ),
            watchTimerControlNotifierProvider.overrideWithValue(
              WatchTimerControlNotifier(
                messageStream: const Stream<Map<String, dynamic>>.empty(),
              ),
            ),
          ],
          child: TestAppWrapper(
            child: DurationSetRow(
              exerciseId: 'plancha',
              setNumber: 2,
              targetSeconds: 60,
              isDone: false,
              onDone: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      await arrancar(tester);

      expect(find.text('00:60'), findsNothing);
      expect(find.text('01:00'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('la cuenta que arrancó en un reloj de WEAR OS', () {
    // El de Apple publica su cronómetro dentro del payload de esfuerzo. El de
    // Wear no puede: lo deja anotado en la sesión. Son dos entradas para UN
    // concepto —"el reloj está cronometrando esta serie"— y la fila las resuelve
    // a un solo shape antes de preguntarle a la regla de propiedad, para que la
    // regla no tenga que enterarse de por dónde llegó el dato.

    DurationTimerState enElRelojWear({
      String exerciseId = 'plancha',
      int setNumber = 2,
      required Duration falta,
    }) =>
        DurationTimerState(
          exerciseId: exerciseId,
          setNumber: setNumber,
          totalSeconds: 60,
          endsAt: ahora.add(falta),
          owner: DurationTimerOwner.reloj,
        );

    testWidgets('se ve en la fila, sin tocar nada', (tester) async {
      await montar(
        tester,
        onDone: () {},
        enLaSesion: enElRelojWear(falta: const Duration(seconds: 45)),
      );

      expect(find.text('00:45'), findsOneWidget);
      expect(find.text('corriendo en el reloj'), findsOneWidget);
      expect(
        find.text('Iniciar'),
        findsNothing,
        reason: 'ofrecer arrancar una serie que ya se está cronometrando es lo '
            'que produce dos cronómetros sobre la misma serie',
      );
    });

    testWidgets('el teléfono NO marca la serie: el dueño es el reloj',
        (tester) async {
      var marcada = false;
      await montar(
        tester,
        onDone: () => marcada = true,
        enLaSesion: enElRelojWear(falta: const Duration(seconds: 45)),
      );

      ahora = ahora.add(const Duration(seconds: 90));
      await tester.pump(DurationTimerRules.tickInterval);

      expect(marcada, isFalse);
    });

    testWidgets('la anotación de ESTE teléfono no se toma por del reloj',
        (tester) async {
      // El documento es COMPARTIDO: lo que esta fila anota vuelve por el mismo
      // canal. Sin mirar el dueño, la fila se vería a sí misma como un espejo
      // ajeno y se quedaría sin poder cancelar su propia cuenta.
      await montar(
        tester,
        onDone: () {},
        enLaSesion: DurationTimerState(
          exerciseId: 'plancha',
          setNumber: 2,
          totalSeconds: 60,
          endsAt: ahora.add(const Duration(seconds: 45)),
          owner: DurationTimerOwner.telefono,
        ),
      );

      expect(find.text('corriendo en el reloj'), findsNothing);
      expect(find.text('Iniciar'), findsOneWidget);
    });

    testWidgets('una cuenta sobre OTRA serie no se dibuja acá', (tester) async {
      await montar(
        tester,
        onDone: () {},
        enLaSesion: enElRelojWear(
          setNumber: 3,
          falta: const Duration(seconds: 45),
        ),
      );

      expect(find.text('00:45'), findsNothing);
      expect(find.text('Iniciar'), findsOneWidget);
    });

    testWidgets('una cuenta ya vencida no se dibuja', (tester) async {
      await montar(
        tester,
        onDone: () {},
        enLaSesion: enElRelojWear(falta: const Duration(seconds: -5)),
      );

      expect(find.text('corriendo en el reloj'), findsNothing);
      expect(find.text('Iniciar'), findsOneWidget);
    });
  });
}
