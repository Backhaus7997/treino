// #1616 × #1617: el descanso que llega del RELOJ también mueve la notificación
// de fin de descanso del teléfono.
//
// Los dos cambios se encuentran en un solo punto, `_ponerDescanso`, por el
// que pasan las cuatro fuentes de descanso: arranque, «+15 s» y SALTAR
// locales, y lo que el reloj anota en la sesión. Acá se ejercita la cuarta
// contra el controlador REAL (`RestEndAlerts`) y el plugin de mentira de
// #1617, con el reloj escribiendo en un Firestore falso. Los caminos locales
// los cubre `session_player_rest_alert_test.dart`.

import 'package:clock/clock.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/notifications/application/notification_providers.dart';
import 'package:treino/features/notifications/data/local_notifications_service.dart';
import 'package:treino/features/watch/application/watch_credential_providers.dart';
import 'package:treino/features/watch/data/watch_nudge_service.dart';
import 'package:treino/features/workout/application/rest_end_alerts.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/rest_state.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../notifications/data/plugin_falso.dart';
import '../application/stub_factories.dart';

class _NudgeFalso extends Mock implements WatchNudgeService {}

class _Notifier extends SessionNotifier {
  _Notifier(this._state);
  final SessionState _state;

  @override
  Future<SessionState> build(SessionInit arg) async => _state;
}

/// Las DOS notificaciones del descanso: el aviso final y la cuenta regresiva.
const ambas = [kIdFinDeDescanso, kIdCuentaDeDescanso];

void main() {
  const uid = 'atleta-1';
  const sessionId = 's1';
  const init = FreshSession(routineId: 'r1', dayNumber: 1);

  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;
  late PluginFalso falso;
  late ProviderContainer container;

  Future<void> montar(WidgetTester tester) async {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .set({'status': 'active'});

    final nudge = _NudgeFalso();
    when(() => nudge.nudge(reason: any(named: 'reason')))
        .thenAnswer((_) async => true);

    falso = PluginFalso();
    final servicio = await falso.servicio();
    // Contenedor a mano, como el de la app: vive MÁS que la pantalla (mismo
    // motivo que en `session_player_rest_alert_test.dart`).
    container = ProviderContainer(overrides: [
      sessionNotifierProvider.overrideWith(
        () => _Notifier(SessionState(
          session: makeSession(id: sessionId, uid: uid),
          day: makeDay(slots: [
            makeSlot(exerciseId: 'e1', targetSets: 3, restSeconds: 90),
          ]),
          setLogs: const [],
          currentExerciseIndex: 0,
          elapsedSeconds: 0,
        )),
      ),
      sessionRepositoryProvider.overrideWithValue(repo),
      currentUidProvider.overrideWithValue(uid),
      watchNudgeServiceProvider.overrideWithValue(nudge),
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
          home: const Scaffold(body: SessionPlayerScreen(init: init)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// La app pasa a segundo plano. Se le avisa al observador directo —es lo
  /// que hace el binding— para que el árbol siga armando frames y la barra
  /// pueda llegar a cero (con el ciclo de vida REAL en `paused` no hay frames).
  Future<void> alSegundoPlano(WidgetTester tester) async {
    container
        .read(restEndAlertsProvider)
        .didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
  }

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  /// El descanso que anota el reloj, que termina en [falta].
  RestState delReloj(Duration falta) => RestState(
        exerciseId: 'e1',
        setNumber: 1,
        totalSeconds: 90,
        endsAt: DateTime.fromMillisecondsSinceEpoch(
          clock.now().toUtc().add(falta).millisecondsSinceEpoch,
          isUtc: true,
        ),
        owner: RestOwner.reloj,
      );

  Future<void> anotaElReloj(RestState descanso) =>
      repo.writeRest(uid: uid, sessionId: sessionId, rest: descanso);

  testWidgets('un descanso que arranca el reloj agenda el aviso para su fin',
      (tester) async {
    await montar(tester);
    await alSegundoPlano(tester);
    // Control: sin descanso en curso, irse no agenda nada.
    expect(falso.agendados, isEmpty);

    final remoto = delReloj(const Duration(seconds: 60));
    await anotaElReloj(remoto);
    await asentar(tester);

    expect(falso.agendados, hasLength(1));
    expect(falso.agendados.last.id, kIdFinDeDescanso);
    expect(falso.agendados.last.cuando.isAtSameMomentAs(remoto.endsAt), isTrue,
        reason: 'el MISMO instante que el reloj: avisan juntos');
  });

  testWidgets('+15 s en el reloj corre el aviso al fin nuevo', (tester) async {
    await montar(tester);
    await alSegundoPlano(tester);
    final remoto = delReloj(const Duration(seconds: 60));
    await anotaElReloj(remoto);
    await asentar(tester);

    final estirado = remoto.extendedBy(15, now: clock.now().toUtc())!;
    await anotaElReloj(estirado);
    await asentar(tester);

    expect(
        falso.agendados.last.cuando.isAtSameMomentAs(estirado.endsAt), isTrue);
    expect(
      falso.agendados.last.cuando.isAtSameMomentAs(remoto.endsAt),
      isFalse,
      reason: 'si quedara el fin viejo, el teléfono avisaría 15 s antes que la '
          'muñeca',
    );
  });

  testWidgets(
      'SALTAR en el reloj, con el fin todavía por venir, retira el aviso del '
      'teléfono', (tester) async {
    await montar(tester);
    await alSegundoPlano(tester);
    await anotaElReloj(delReloj(const Duration(seconds: 60)));
    await asentar(tester);
    expect(falso.agendados, hasLength(1));
    expect(falso.cancelados, isEmpty);

    await repo.clearRest(uid: uid, sessionId: sessionId);
    await asentar(tester);

    expect(falso.cancelados, ambas,
        reason: 'un descanso saltado no puede avisar «volvé a la serie»');
    expect(find.byKey(const Key('rest_timer_bar')), findsNothing);
  });

  testWidgets(
      'el fin NATURAL de un descanso que vino del reloj NO retira el aviso',
      (tester) async {
    // Control negativo del caso de arriba: llegar a cero también saca la barra
    // y llega al controlador como `update(null)`, pero con el fin YA vencido.
    // Si eso cancelara, el aviso moriría justo cuando el sistema lo publica.
    await montar(tester);
    await alSegundoPlano(tester);
    await anotaElReloj(delReloj(const Duration(seconds: 60)));
    await asentar(tester);
    expect(falso.agendados, hasLength(1));

    await tester.pump(const Duration(seconds: 61));
    await asentar(tester);

    // La barra se fue sola: el `onDone` corrió, el test no es vacuo.
    expect(find.byKey(const Key('rest_timer_bar')), findsNothing);
    expect(falso.cancelados, isEmpty,
        reason: 'el fin natural del descanso no retira el aviso');
  });
}
