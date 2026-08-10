import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session.dart';

/// El teléfono tiene que enterarse de lo que escribe EL RELOJ.
///
/// El historial se lee con `listByUid`, un `.get()` de una sola vez. Cuando el
/// único que escribía era el teléfono alcanzaba, porque `SessionNotifier`
/// invalida la caché a mano al terminar. Desde que el reloj también escribe
/// sesiones —y nadie invalida por él— el atleta terminaba el entreno en la
/// muñeca y la app seguía mostrando lo de antes hasta cerrarla.
///
/// ⚠️ CÓMO SE MIDE, que es lo que hace que estos tests sirvan:
///
/// Se afirma sobre lo que le llega SOLO al listener, nunca sobre un
/// `read(...future)` posterior. Un `read` nuevo dispara una lectura fresca y
/// devuelve el dato correcto aunque el refresco automático no exista — la
/// primera versión de estos tests hacía justamente eso y pasaba en verde con
/// el arreglo REMOVIDO. Verde sin el fix es un test que no prueba nada.
///
/// Comprobado a mano: quitando los `ref.watch(sessionsRevisionProvider(...))`
/// de session_providers.dart, los dos tests se ponen rojos.
void main() {
  late FakeFirebaseFirestore firestore;
  late ProviderContainer container;

  const uid = 'atleta-1';

  Future<void> writeSession({
    required String id,
    required DateTime startedAt,
    DateTime? finishedAt,
  }) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(id)
        .set({
      'id': id,
      'uid': uid,
      'routineId': 'r1',
      'routineName': 'Rutina',
      'startedAt': startedAt,
      'finishedAt': finishedAt,
      'status': finishedAt == null ? 'active' : 'finished',
      'totalVolumeKg': 100.0,
      'durationMin': 30,
      'dayNumber': 1,
      'weekNumber': 0,
    });
  }

  /// Espera a que el listener reciba un valor que cumpla [matches], o falla.
  ///
  /// Sondea el ÚLTIMO valor que llegó por el listener; no vuelve a leer el
  /// provider. Sin refresco automático nunca se cumple y el test explota por
  /// timeout, que es exactamente lo que tiene que pasar sin el arreglo.
  Future<void> waitFor(
    List<AsyncValue<Object?>> received,
    bool Function(Object? value) matches, {
    String reason = '',
  }) async {
    for (var attempt = 0; attempt < 50; attempt++) {
      final last = received.isEmpty ? null : received.last;
      if (last != null && last.hasValue && matches(last.value)) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('el listener nunca recibió el valor esperado. $reason');
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider
            .overrideWithValue(SessionRepository(firestore: firestore)),
      ],
    );
  });

  tearDown(() => container.dispose());

  test(
    'el historial avisa solo cuando aparece una sesion escrita por fuera',
    () async {
      await writeSession(
        id: 's1',
        startedAt: DateTime.utc(2026, 8, 1),
        finishedAt: DateTime.utc(2026, 8, 1, 1),
      );

      final received = <AsyncValue<List<Session>>>[];
      final sub = container.listen(
        sessionsByUidProvider(uid),
        (_, next) => received.add(next),
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await waitFor(
        received,
        (v) => (v! as List<Session>).length == 1,
        reason: 'ni siquiera cargó el estado inicial',
      );

      // El RELOJ escribe una sesión nueva por REST. Nadie invalida nada, y
      // acá NO se vuelve a leer el provider.
      await writeSession(
        id: 's2-del-reloj',
        startedAt: DateTime.utc(2026, 8, 2),
        finishedAt: DateTime.utc(2026, 8, 2, 1),
      );

      await waitFor(
        received,
        (v) => (v! as List<Session>).any((s) => s.id == 's2-del-reloj'),
        reason: 'sin la señal de revisión el historial se queda en la lectura '
            'inicial y el atleta tiene que cerrar la app',
      );
    },
  );

  test(
    'la sesion activa se limpia sola cuando el reloj la termina',
    () async {
      await writeSession(id: 'en-curso', startedAt: DateTime.utc(2026, 8, 3));

      final received = <AsyncValue<Session?>>[];
      final sub = container.listen(
        activeSessionProvider(uid),
        (_, next) => received.add(next),
        fireImmediately: true,
      );
      addTearDown(sub.close);

      await waitFor(
        received,
        (v) => (v as Session?)?.id == 'en-curso',
        reason: 'no vio la sesión activa inicial',
      );

      // El reloj la cierra. En el teléfono no corre ningún notifier.
      await writeSession(
        id: 'en-curso',
        startedAt: DateTime.utc(2026, 8, 3),
        finishedAt: DateTime.utc(2026, 8, 3, 1),
      );

      await waitFor(
        received,
        (v) => v == null,
        reason: 'el teléfono seguía ofreciendo retomar un entreno que el reloj '
            'ya había cerrado',
      );
    },
  );
}
