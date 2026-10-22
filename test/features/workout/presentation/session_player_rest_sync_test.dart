import 'dart:async';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/watch/application/watch_credential_providers.dart';
import 'package:treino/features/watch/data/watch_nudge_service.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/rest_state.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';
import 'package:treino/features/workout/presentation/widgets/rest_timer_bar.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../application/stub_factories.dart';

class _NudgeFalso extends Mock implements WatchNudgeService {}

/// Registra los `logSet` y los refleja en el estado, sin Firestore.
class _LoggingNotifier extends SessionNotifier {
  _LoggingNotifier(this._state);
  final SessionState _state;

  @override
  Future<SessionState> build(SessionInit arg) async => _state;

  @override
  Future<void> logSet(SetLog setLog) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(setLogs: [...current.setLogs, setLog]));
  }
}

/// Un repositorio real cuyo canal del descanso maneja el test: sirve para
/// mandar lo que Firestore no manda solo, como un error de red.
class _RepoConCanal extends SessionRepository {
  _RepoConCanal({required super.firestore});

  final canal = StreamController<RestState?>.broadcast();

  @override
  Stream<RestState?> watchRest({
    required String uid,
    required String sessionId,
  }) =>
      canal.stream;
}

/// El descanso del teléfono, COMPARTIDO con el reloj por la sesión (#1616).
///
/// Lo que importa del lado del teléfono son dos direcciones: lo que se toca
/// acá tiene que quedar anotado en la sesión —es lo único que ven los
/// relojes—, y lo que anota un reloj tiene que aparecer en la barra. Con el
/// mismo instante de fin en los dos lados, llegan a cero —y vibran— a la vez.
void main() {
  const uid = 'atleta-1';
  const sessionId = 's1';
  const init = FreshSession(routineId: 'r1', dayNumber: 1);

  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;
  late _NudgeFalso nudge;

  DocumentReference<Map<String, Object?>> doc() => firestore
      .collection('users')
      .doc(uid)
      .collection('sessions')
      .doc(sessionId);

  SessionState estado() => SessionState(
        session: makeSession(id: sessionId, uid: uid),
        day: makeDay(slots: [
          makeSlot(exerciseId: 'e1', targetSets: 3, restSeconds: 90),
        ]),
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
    await doc().set({'status': 'active', 'routineId': 'r1'});
    nudge = _NudgeFalso();
    when(() => nudge.nudge(reason: any(named: 'reason')))
        .thenAnswer((_) async => true);
  });

  Future<void> montar(
    WidgetTester tester, {
    SessionRepository? repositorio,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionNotifierProvider.overrideWith(
            () => _LoggingNotifier(estado()),
          ),
          sessionRepositoryProvider.overrideWithValue(repositorio ?? repo),
          currentUidProvider.overrideWithValue(uid),
          watchNudgeServiceProvider.overrideWithValue(nudge),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const Scaffold(body: SessionPlayerScreen(init: init)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Deja correr las escrituras y los snapshots del Firestore falso.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<Map<String, Object?>> crudo() async => (await doc().get()).data()!;

  /// El descanso que anota un reloj, que termina en [falta].
  RestState delReloj(Duration falta, {int total = 90}) => RestState(
        exerciseId: 'e1',
        setNumber: 1,
        totalSeconds: total,
        endsAt: DateTime.fromMillisecondsSinceEpoch(
          clock.now().toUtc().add(falta).millisecondsSinceEpoch,
          isUtc: true,
        ),
        owner: RestOwner.reloj,
      );

  RestTimerBar barra(WidgetTester tester) =>
      tester.widget<RestTimerBar>(find.byType(RestTimerBar));

  group('lo que se toca en el teléfono queda en la sesión', () {
    testWidgets('marcar una serie anota el descanso, con su identidad',
        (tester) async {
      await montar(tester);

      await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty).first);
      await asentar(tester);

      final leido = SessionRepository.restFromDoc(await crudo());
      expect(leido, isNotNull, reason: 'sin esto el reloj nunca se entera');
      expect(leido!.owner, RestOwner.telefono);
      expect(leido.exerciseId, 'e1');
      expect(leido.setNumber, 1);
      expect(leido.totalSeconds, 90);
      // El MISMO instante que cuenta la barra: si no, avisarían desfasados.
      expect(leido.endsAt, barra(tester).endsAt);
    });

    testWidgets('y al reloj de Apple se le avisa que relea', (tester) async {
      await montar(tester);

      await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty).first);
      await asentar(tester);

      verify(
        () => nudge.nudge(reason: WatchNudgeService.reasonRestChanged),
      ).called(1);
    });

    testWidgets('SALTAR lo borra de la sesión', (tester) async {
      await montar(tester);
      await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty).first);
      await asentar(tester);

      await tester.tap(find.text('SALTAR'));
      await asentar(tester);

      expect(find.byKey(const Key('rest_timer_bar')), findsNothing);
      expect(SessionRepository.restFromDoc(await crudo()), isNull);
    });

    testWidgets('+15 s reescribe el mismo descanso, más largo', (tester) async {
      await montar(tester);
      await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty).first);
      await asentar(tester);
      final antes = SessionRepository.restFromDoc(await crudo())!;

      await tester.tap(find.text('+15 s'));
      await asentar(tester);

      final despues = SessionRepository.restFromDoc(await crudo())!;
      expect(despues.totalSeconds, 105);
      expect(despues.endsAt, antes.endsAt.add(const Duration(seconds: 15)));
      expect(barra(tester).endsAt, despues.endsAt);
    });

    testWidgets('el eco de la escritura propia no reinicia la barra',
        (tester) async {
      // Control negativo de la regla de espejo: el teléfono lee de vuelta lo
      // que acaba de escribir. Si eso contara como un descanso nuevo, la
      // barra se recrearía —y el lector de pantalla anunciaría el descanso
      // otra vez— en cada escritura propia.
      await montar(tester);
      await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty).first);
      await tester.pump();
      final estadoAntes = tester.state(find.byType(RestTimerBar));

      await asentar(tester);

      expect(tester.state(find.byType(RestTimerBar)), same(estadoAntes));
    });
  });

  group('lo que anota el reloj aparece en el teléfono', () {
    testWidgets('un descanso del reloj se muestra con lo que falta',
        (tester) async {
      await montar(tester);
      expect(find.byKey(const Key('rest_timer_bar')), findsNothing);

      final remoto = delReloj(const Duration(seconds: 60));
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: remoto);
      await asentar(tester);

      expect(find.byKey(const Key('rest_timer_bar')), findsOneWidget);
      // 60 y no 90: lo que FALTA del instante de fin, no la duración entera.
      expect(find.text('1:00'), findsOneWidget);
      expect(barra(tester).endsAt, remoto.endsAt);
    });

    testWidgets('+15 s en el reloj corre el fin del teléfono', (tester) async {
      await montar(tester);
      final remoto = delReloj(const Duration(seconds: 60));
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: remoto);
      await asentar(tester);

      final estirado = remoto.extendedBy(15, now: clock.now().toUtc())!;
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: estirado);
      await asentar(tester);

      expect(barra(tester).endsAt, estirado.endsAt);
      expect(barra(tester).totalSeconds, 105);
      expect(find.text('1:15'), findsOneWidget);
    });

    testWidgets('SALTAR en el reloj saca la barra del teléfono',
        (tester) async {
      await montar(tester);
      await repo.writeRest(
        uid: uid,
        sessionId: sessionId,
        rest: delReloj(const Duration(seconds: 60)),
      );
      await asentar(tester);
      expect(find.byKey(const Key('rest_timer_bar')), findsOneWidget);

      await repo.clearRest(uid: uid, sessionId: sessionId);
      await asentar(tester);

      expect(find.byKey(const Key('rest_timer_bar')), findsNothing);
    });

    testWidgets('espejar no escribe: la sesión queda como la dejó el reloj',
        (tester) async {
      // Si el espejo escribiera, cada aparato le contestaría al otro y el
      // descanso rebotaría para siempre. El dueño tiene que seguir siendo el
      // reloj, y el aviso al Apple Watch no tiene que salir.
      await montar(tester);
      final remoto = delReloj(const Duration(seconds: 60));
      await repo.writeRest(uid: uid, sessionId: sessionId, rest: remoto);
      await asentar(tester);

      expect(SessionRepository.restFromDoc(await crudo()), remoto);
      verifyNever(() => nudge.nudge(reason: any(named: 'reason')));
    });

    testWidgets('un descanso ya vencido en la sesión no aparece',
        (tester) async {
      await montar(tester);
      await repo.writeRest(
        uid: uid,
        sessionId: sessionId,
        rest: delReloj(const Duration(seconds: -5)),
      );
      await asentar(tester);

      expect(find.byKey(const Key('rest_timer_bar')), findsNothing);
    });
  });

  group('sin red cada uno sigue solo', () {
    testWidgets('un error del canal NO corta el descanso del teléfono',
        (tester) async {
      // Un error de red no dice que el descanso se haya saltado. Leerlo como
      // "no hay" cortaría el descanso cada vez que la señal parpadea — lo
      // contrario de lo que #1616 promete sin red.
      final conCanal = _RepoConCanal(firestore: firestore);
      addTearDown(conCanal.canal.close);
      await montar(tester, repositorio: conCanal);

      await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty).first);
      await tester.pump();
      expect(find.byKey(const Key('rest_timer_bar')), findsOneWidget);

      conCanal.canal.addError(FirebaseException(plugin: 'cloud_firestore'));
      await asentar(tester);

      expect(find.byKey(const Key('rest_timer_bar')), findsOneWidget);
    });
  });
}
