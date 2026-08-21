import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/application/watch_credential_providers.dart';
import 'package:treino/features/watch/application/watch_effort_notifier.dart';
import 'package:treino/features/watch/application/watch_timer_control_notifier.dart';
import 'package:treino/features/watch/data/watch_bridge.dart';
import 'package:treino/features/watch/domain/watch_effort.dart';
import 'package:treino/features/workout/application/workout_clock.dart';
import 'package:treino/features/workout/domain/duration_timer.dart';
import 'package:treino/features/workout/presentation/widgets/duration_set_row.dart';

import '../../../helpers/test_app_wrapper.dart';

class _MockBridge extends Mock implements WatchBridge {}

void main() {
  late _MockBridge bridge;

  /// Reloj de pared controlable. La fila lo lee en cada tick.
  late DateTime ahora;

  setUp(() {
    bridge = _MockBridge();
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
    bool enabled = true,
    int targetSeconds = 60,
    WatchEffort? enElReloj,
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
        ],
        child: TestAppWrapper(
          child: DurationSetRow(
            exerciseId: 'plancha',
            setNumber: 2,
            targetSeconds: targetSeconds,
            isDone: false,
            enabled: enabled,
          ),
        ),
      ),
    );
  }

  Future<void> arrancar(WidgetTester tester) async {
    await tester.tap(find.text('Iniciar'));
    await tester.pump();
  }

  testWidgets('la cuenta SOBREVIVE a que la fila se desmonte', (tester) async {
    // Este es el test que justifica sacar el cronómetro del `State` del widget.
    //
    // Los ejercicios del player cuelgan de un `ListView` sin keep-alive: al
    // scrollear, la fila sale del viewport y su `State` se destruye. Cuando el
    // cronómetro vivía ahí adentro, eso MATABA la cuenta — el tiempo se perdía,
    // nadie marcaba la serie, y el atleta volvía a una fila que decía "Iniciar"
    // como si nunca hubiera pasado nada.
    //
    // Acá se simula exactamente eso: se saca la fila del árbol y se vuelve a
    // poner, con el mismo `ProviderScope` vivo, igual que en un scroll.
    var visible = true;
    late void Function(void Function()) refrescar;

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
        ],
        child: TestAppWrapper(
          child: StatefulBuilder(
            builder: (context, setState) {
              refrescar = setState;
              return visible
                  ? const DurationSetRow(
                      exerciseId: 'plancha',
                      setNumber: 2,
                      targetSeconds: 60,
                      isDone: false,
                      enabled: true,
                    )
                  : const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Iniciar'));
    await tester.pump();
    expect(find.text('01:00'), findsOneWidget);

    // El atleta scrollea: la fila se desmonta.
    refrescar(() => visible = false);
    await tester.pump();
    expect(find.text('Iniciar'), findsNothing);

    // Pasan 25 segundos con la fila FUERA del árbol.
    ahora = ahora.add(const Duration(seconds: 25));
    await tester.pump(DurationTimerRules.tickInterval);

    // Vuelve a scrollear hasta el ejercicio: la cuenta siguió corriendo.
    refrescar(() => visible = true);
    await tester.pump();
    expect(find.text('00:35'), findsOneWidget,
        reason: 'la cuenta siguió viva mientras la fila no estaba montada');
    expect(find.text('Iniciar'), findsNothing,
        reason: 'no puede ofrecer arrancar algo que ya está corriendo');
  });

  testWidgets('antes de arrancar muestra el objetivo', (tester) async {
    await montar(tester);
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('Iniciar'), findsOneWidget);
  });

  testWidgets('mientras corre, la cuenta baja con el reloj de pared',
      (tester) async {
    await montar(tester);
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
    await montar(tester);
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
    await montar(
      tester,
    );
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

    final mensajes = verify(() => bridge.sendMessage(captureAny()))
        .captured
        .cast<Map<String, dynamic>>();
    expect(mensajes.last['action'], 'cancel',
        reason: 'sin este aviso el reloj sigue contando algo que ya no existe');
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
      await montar(
        tester,
        enElReloj: delReloj(falta: const Duration(seconds: 45)),
      );

      ahora = ahora.add(const Duration(seconds: 90));
      await tester.pump(DurationTimerRules.tickInterval);
    });

    testWidgets('no le manda ninguna orden al reloj', (tester) async {
      // Un `start` acá sería un eco: el reloj arrancó la cuenta y el teléfono
      // se la devolvería. Un `cancel` sería peor — cancelaría del otro lado un
      // cronómetro que este teléfono nunca arrancó.
      await montar(
        tester,
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
        enElReloj: delReloj(falta: const Duration(seconds: -5)),
      );

      expect(find.text('corriendo en el reloj'), findsNothing);
      expect(find.text('Iniciar'), findsOneWidget);
    });
  });

  testWidgets('un pedido del reloj para OTRA serie no toca esta fila',
      (tester) async {
    // El notifier es uno solo y todas las filas montadas lo escuchan. Sin
    // comparar identidad, cancelar en la muñeca cortaría también la plancha que
    // el atleta está aguantando en otra fila.
    await montar(tester);
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

  testWidgets('una fila no interactiva no arranca nada', (tester) async {
    await montar(tester, enabled: false);
    await tester.tap(find.text('Iniciar'));
    await tester.pump();

    ahora = ahora.add(const Duration(seconds: 120));
    await tester.pump(DurationTimerRules.tickInterval);

    expect(find.text('01:00'), findsOneWidget);
    verifyNever(() => bridge.sendMessage(any()));
  });
}
