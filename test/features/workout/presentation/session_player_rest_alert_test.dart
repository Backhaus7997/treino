// #1617: el player le avisa a `RestEndAlerts` cuándo termina el descanso, y la
// notificación del sistema sale cuando la app pasa a segundo plano.
//
// Acá se ejercita el CABLEADO de la pantalla —arranque, SALTAR, «+15 s», sesión
// completa, cierre de la pantalla— contra el servicio real y un plugin de
// mentira. Las reglas finas (modo de alarma, carreras, ciclo de vida) están en
// `rest_end_alerts_test.dart`.

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/notifications/application/notification_providers.dart';
import 'package:treino/features/notifications/data/local_notifications_service.dart';
import 'package:treino/features/workout/application/rest_end_alerts.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/domain/rest_state.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../notifications/data/plugin_falso.dart';
import '../application/ciclo_de_vida.dart';
import '../application/stub_factories.dart';

const _init = FreshSession(routineId: 'r1', dayNumber: 4);

/// Registra las series y las refleja en el estado, como el notifier real.
class _Notifier extends SessionNotifier {
  _Notifier(this._state);
  final SessionState _state;

  @override
  Future<SessionState> build(SessionInit arg) async => _state;

  @override
  Future<void> logSet(SetLog setLog) async => registrar(setLog);

  /// Una serie que se marca desde otro lado (el reloj): el estado cambia sin
  /// que el atleta toque nada.
  void registrar(SetLog setLog) {
    final actual = state.value;
    if (actual == null) return;
    state = AsyncData(actual.copyWith(setLogs: [...actual.setLogs, setLog]));
  }
}

SessionState _estado({required int series}) => SessionState(
      session: makeSession(),
      day: makeDay(dayNumber: 4, slots: [
        makeSlot(exerciseId: 'e1', targetSets: series, restSeconds: 90),
      ]),
      setLogs: const [],
      currentExerciseIndex: 0,
      elapsedSeconds: 0,
    );

/// Las DOS notificaciones del descanso: el aviso final y la cuenta regresiva.
const ambas = [kIdFinDeDescanso, kIdCuentaDeDescanso];

/// El fin del descanso de [segundos] arrancado en [inicio], tal como lo calcula
/// la pantalla.
///
/// Desde #1616 el fin se redondea al milisegundo —es la resolución con la que
/// viaja en la sesión y lo lee el reloj—, así que `inicio + 90 s` puede diferir
/// en una fracción de milisegundo del instante que se agenda. Se compara contra
/// la MISMA regla que usa la pantalla, no contra una suma a mano: la fábrica
/// [RestState.startedAt], que además trunca el inicio al milisegundo. Llamar a
/// `RestRules.endsAt` directo se salteaba ese truncado y difería en 1 ms en la
/// mitad de las corridas.
DateTime _fin(DateTime inicio, int segundos) => RestState.startedAt(
      exerciseId: 'e1',
      setNumber: 1,
      totalSeconds: segundos,
      start: inicio.toUtc(),
      owner: RestOwner.telefono,
    ).endsAt;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late PluginFalso falso;
  late _Notifier notifier;
  late ProviderContainer container;

  void segundoPlano() => aSegundoPlano(binding);
  void primerPlano() => aPrimerPlano(binding);

  /// Monta el player. [series] = series planificadas del único ejercicio.
  Future<void> montar(WidgetTester tester, {required int series}) async {
    primerPlano();
    addTearDown(primerPlano);
    falso = PluginFalso();
    notifier = _Notifier(_estado(series: series));
    final servicio = await falso.servicio();
    // El contenedor se crea a mano, igual que el de la app: vive MÁS que la
    // pantalla. Con un `ProviderScope` común se desharía junto con ella y el
    // `dispose` del controlador taparía lo que la pantalla tiene que hacer sola
    // al irse.
    container = ProviderContainer(overrides: [
      sessionNotifierProvider.overrideWith(() => notifier),
      localNotificationsServiceProvider.overrideWithValue(servicio),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: SessionPlayerScreen(init: _init)),
        ),
      ),
    );
    await tester.pump();
  }

  /// Marca la primera serie pendiente; arranca el descanso de 90 s.
  Future<DateTime> marcarSerie(WidgetTester tester) async {
    final inicio = clock.now();
    await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty).first);
    await tester.pump();
    expect(find.byKey(const Key('rest_timer_bar')), findsOneWidget);
    return inicio;
  }

  Future<void> irseAlSegundoPlano(WidgetTester tester) async {
    segundoPlano();
    await tester.pump();
  }

  Future<void> volver(WidgetTester tester) async {
    primerPlano();
    await tester.pump();
  }

  testWidgets(
      'marcar una serie y pasar a segundo plano agenda el aviso para el fin del '
      'descanso, por el canal y el id correctos', (tester) async {
    await montar(tester, series: 3);
    final inicio = await marcarSerie(tester);

    // Con la app a la vista NO se agenda nada: ya avisa la barra.
    expect(falso.eventos, isEmpty);

    await irseAlSegundoPlano(tester);

    expect(falso.agendados, hasLength(1));
    final a = falso.agendados.single;
    expect(a.id, kIdFinDeDescanso);
    expect(a.detalles.android!.channelId, kCanalDeAvisos);
    expect(a.cuando.isAtSameMomentAs(_fin(inicio, 90)), isTrue);
    expect(a.titulo, 'Terminó el descanso');
    expect(a.cuerpo, 'Volvé a la serie');

    // Y la cuenta regresiva en vivo, publicada YA y hasta el mismo instante.
    expect(falso.publicadas, hasLength(1));
    final cuenta = falso.publicadas.single;
    expect(cuenta.id, kIdCuentaDeDescanso);
    expect(cuenta.titulo, 'Descanso');
    expect(cuenta.cuerpo, 'Volvé a la serie cuando llegue a cero');
    final c = cuenta.detalles.android!;
    expect(c.when, _fin(inicio, 90).millisecondsSinceEpoch);
    expect(c.usesChronometer && c.chronometerCountDown && c.silent, isTrue);
  });

  testWidgets('volver a la app cancela el aviso: no se avisa dos veces',
      (tester) async {
    await montar(tester, series: 3);
    await marcarSerie(tester);
    await irseAlSegundoPlano(tester);

    await volver(tester);

    expect(falso.cancelados, ambas);
  });

  testWidgets(
      'SALTAR: irse después NO agenda el aviso de un descanso que ya no '
      'existe', (tester) async {
    await montar(tester, series: 3);
    await marcarSerie(tester);

    await tester.tap(find.text('SALTAR'));
    await tester.pump();
    await irseAlSegundoPlano(tester);

    expect(falso.agendados, isEmpty);
  });

  testWidgets('«+15 s» corre el aviso: se agenda para el instante nuevo',
      (tester) async {
    await montar(tester, series: 3);
    final inicio = await marcarSerie(tester);

    await tester.tap(find.text('+15 s'));
    await tester.pump();
    await irseAlSegundoPlano(tester);

    expect(falso.agendados, hasLength(1));
    expect(
        falso.agendados.single.cuando.isAtSameMomentAs(
            _fin(inicio, 90).add(const Duration(seconds: 15))),
        isTrue,
        reason: '90 s del slot + 15 s');
    expect(
        falso.publicadas.single.detalles.android!.when,
        _fin(inicio, 90)
            .add(const Duration(seconds: 15))
            .millisecondsSinceEpoch,
        reason: 'la cuenta regresiva también sale con el fin corrido');
  });

  testWidgets('sin descanso en curso, irse no agenda nada', (tester) async {
    await montar(tester, series: 3);

    await irseAlSegundoPlano(tester);

    expect(falso.eventos, isEmpty);
  });

  testWidgets(
      'la última serie de la sesión no deja avisar: no hay próxima serie que '
      'esperar', (tester) async {
    await montar(tester, series: 1);
    await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty).first);
    await tester.pump();
    // Con la sesión completa la barra no se dibuja.
    expect(find.byKey(const Key('rest_timer_bar')), findsNothing);

    await irseAlSegundoPlano(tester);

    expect(falso.agendados, isEmpty);
  });

  testWidgets(
      'si la sesión se completa estando en segundo plano (la serie la marcó el '
      'reloj), el aviso agendado se retira', (tester) async {
    await montar(tester, series: 2);
    await marcarSerie(tester);
    await irseAlSegundoPlano(tester);
    expect(falso.agendados, hasLength(1));

    notifier.registrar(makeSetLog(exerciseId: 'e1', setNumber: 2, id: 'l2'));
    await tester.pump();

    expect(falso.cancelados, ambas);
  });

  // Medido en un emulador: la barra llega a cero con la app en segundo plano
  // (o apenas se descongela el proceso) y su `onDone` cancelaba el aviso justo
  // antes de que el sistema lo publicara. Con el ciclo de vida REAL en `paused`
  // Flutter no arma frames, pero los timers corren: el tick de la barra llega al
  // cero igual.
  testWidgets(
      'el descanso llega a cero con la app en segundo plano: el aviso NO se '
      'cancela, y al volver sí', (tester) async {
    await montar(tester, series: 3);
    await marcarSerie(tester);
    await irseAlSegundoPlano(tester);
    expect(falso.agendados, hasLength(1));

    await tester.pump(const Duration(seconds: 91));

    expect(falso.cancelados, isEmpty,
        reason: 'el fin natural del descanso no retira el aviso');
    expect(falso.agendados, hasLength(1));

    await volver(tester);

    expect(falso.cancelados, ambas);
    // Y la barra se fue sola: el `onDone` sí corrió (el test no es vacuo).
    expect(find.byKey(const Key('rest_timer_bar')), findsNothing);
  });

  testWidgets(
      'terminar la sesión DESPUÉS de que el descanso terminó solo igual retira '
      'el aviso', (tester) async {
    await montar(tester, series: 3);
    await marcarSerie(tester);
    // Sólo el observador: con el ciclo de vida real en `paused` el árbol no se
    // puede reemplazar (ver el test de abajo).
    container
        .read(restEndAlertsProvider)
        .didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(falso.agendados, hasLength(1));

    await tester.pump(const Duration(seconds: 91));
    expect(find.byKey(const Key('rest_timer_bar')), findsNothing);
    expect(falso.cancelados, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(falso.cancelados, ambas);
  });

  testWidgets(
      'terminar o abandonar la sesión (la pantalla se va) retira el aviso',
      (tester) async {
    await montar(tester, series: 3);
    await marcarSerie(tester);

    // Con el ciclo de vida REAL en `paused` Flutter deja de armar frames y el
    // árbol no se puede reemplazar. Se le avisa al observador directamente, que
    // es lo que hace el binding: así la pantalla se desmonta con el aviso
    // agendado, que es el caso (el reloj cierra el entreno estando el teléfono
    // en el bolsillo).
    container
        .read(restEndAlertsProvider)
        .didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(falso.agendados, hasLength(1));

    // La ruta se reemplaza: es lo que hace `context.go` al terminar o abandonar.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(falso.cancelados, ambas);
  });
}
