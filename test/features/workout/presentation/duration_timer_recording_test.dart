import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/watch/application/watch_credential_providers.dart';
import 'package:treino/features/watch/application/watch_effort_notifier.dart';
import 'package:treino/features/watch/application/watch_timer_control_notifier.dart';
import 'package:treino/features/watch/data/watch_bridge.dart';
import 'package:treino/features/workout/application/duration_timer_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/workout_clock.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/presentation/widgets/duration_set_row.dart';

import '../../../helpers/test_app_wrapper.dart';

class _MockBridge extends Mock implements WatchBridge {}

/// Un repositorio real, salvo que `getActive` NO RESPONDE NUNCA.
///
/// Es el gimnasio sin señal: esa lectura va al servidor primero y no tiene
/// timeout. Y además cuenta las veces que la llamaron, porque acá lo que se
/// prueba es que no la llame NADIE.
class _RepoConGetActiveColgado extends SessionRepository {
  _RepoConGetActiveColgado({required super.firestore});

  int llamadasAGetActive = 0;

  @override
  Future<Session?> getActive(String uid, {DateTime? now}) {
    llamadasAGetActive += 1;
    // Un `Completer` que nadie completa, y no un `Future.delayed`: así no
    // queda un timer pendiente que haga fallar el test por otra razón.
    return Completer<Session?>().future;
  }
}

/// Adónde escribe la fila el cronómetro, y de qué depende.
///
/// ## El bug que este archivo existe para que no vuelva
///
/// La fila deducía la sesión con `activeSessionProvider`, que envuelve a
/// `getActive`. Hasta que esa lectura resolviera, el destino era `null` y el
/// cronómetro NO SE ANOTABA — con la cuenta del teléfono andando igual, así que
/// no había ningún síntoma de este lado: el reloj simplemente nunca se
/// enteraba. Medido: con `getActive` demorado, `timerEndsAtMs` quedaba nulo.
///
/// Ahora la sesión la PROVEE el player, que ya sabe cuál es, por un
/// `ProviderScope` acotado a su subárbol. Los dos datos del destino salen de
/// providers síncronos y ninguno toca la red.
void main() {
  late FakeFirebaseFirestore firestore;
  late _RepoConGetActiveColgado repo;
  late _MockBridge bridge;
  late Session sesion;

  const uid = 'atleta-1';

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    repo = _RepoConGetActiveColgado(firestore: firestore);
    bridge = _MockBridge();
    // Sin reloj de Apple a la vista: acá se mide el otro canal.
    when(() => bridge.isSupported).thenAnswer((_) async => false);

    sesion = await repo.create(
      uid: uid,
      routineId: 'r1',
      routineName: 'Core',
      startedAt: DateTime.now().toUtc(),
    );
  });

  Future<Map<String, dynamic>?> docDeSesion() async => (await firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(sesion.id)
          .get())
      .data();

  /// [enElScope] simula estar —o no— adentro del subárbol del player.
  Future<void> montar(WidgetTester tester, {required bool enElScope}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(repo),
          currentUidProvider.overrideWithValue(uid),
          if (enElScope) playerSessionIdProvider.overrideWithValue(sesion.id),
          watchBridgeProvider.overrideWithValue(bridge),
          workoutClockProvider.overrideWithValue(() => DateTime.now().toUtc()),
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
        child: const TestAppWrapper(
          child: DurationSetRow(
            exerciseId: 'plancha',
            setNumber: 2,
            targetSeconds: 60,
            isDone: false,
            enabled: true,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Toca «Iniciar» APENAS monta, sin darle tiempo a nada.
  ///
  /// La prisa es el punto: el bug vivía justo en esa ventana.
  Future<void> arrancarYa(WidgetTester tester) async {
    await tester.tap(find.text('Iniciar'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('la anotación llega aunque la red no conteste', (tester) async {
    await montar(tester, enElScope: true);

    await arrancarYa(tester);

    final doc = await docDeSesion();
    expect(
      doc?[SessionRepository.fieldTimerEndsAt],
      isNotNull,
      reason: 'si esto es null, el reloj nunca se entera del cronómetro y no '
          'hay ningún síntoma de este lado: la cuenta del teléfono anda igual',
    );
    expect(doc?[SessionRepository.fieldTimerExerciseId], 'plancha');
    expect(doc?[SessionRepository.fieldTimerSetNumber], 2);
    expect(
        doc?[SessionRepository.fieldTimerOwner], SessionRepository.ownerPhone);
  });

  testWidgets('y no depende de getActive: nadie la llama', (tester) async {
    // No es sólo latencia. `getActive` CIERRA sesiones colgadas de paso, y
    // colgar el cronómetro de una lectura con efectos laterales en la pantalla
    // más caliente de la app es pedirlo.
    await montar(tester, enElScope: true);

    await arrancarYa(tester);

    expect(repo.llamadasAGetActive, 0);
  });

  testWidgets('fuera del scope del player no anota nada, y no revienta',
      (tester) async {
    // El default es `null` a propósito: una fila montada suelta —un test de
    // widget, una preview— no tiene que saber que el scope existe.
    await montar(tester, enElScope: false);

    await arrancarYa(tester);

    // Se miran TODAS las sesiones, no sólo ésta: "no anota nada" tiene que
    // significar eso. Mirando un solo documento, una version que escribiera en
    // una sesion inventada pasaria el test igual — probado mutando.
    final todas = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .get();
    for (final d in todas.docs) {
      expect(
        d.data()[SessionRepository.fieldTimerEndsAt],
        isNull,
        reason: 'escribio el cronometro en ${d.id}',
      );
    }
    // Y la cuenta del teléfono arranca igual: la sincronización es el espejo,
    // no la serie.
    expect(find.text('Cancelar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
