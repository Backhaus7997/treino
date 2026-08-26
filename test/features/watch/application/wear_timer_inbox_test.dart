import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/watch/application/wear_rest_providers.dart';
import 'package:treino/features/watch/application/wear_timer_sync_providers.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';
import 'package:treino/features/workout/domain/duration_timer_owner.dart';
import 'package:treino/features/workout/domain/duration_timer_state.dart';

class _ServicioFalso extends Mock implements WearWorkoutService {}

/// El buzón que refleja en el reloj el cronómetro anotado en la sesión.
///
/// Espeja SIEMPRE —el atleta quiere ver la cuenta y sentir la vibración en la
/// muñeca aunque la haya arrancado en el teléfono— y marca cuáles son AJENOS,
/// que es lo único que decide quién carga la serie al llegar a cero.
void main() {
  late _ServicioFalso service;
  late StreamController<DurationTimerState?> sesion;
  late ProviderContainer container;

  /// El instante contra el que se arma cada `endsAt`.
  ///
  /// Sale del reloj CONGELADO, y eso es lo que vuelve determinístico al
  /// archivo. Lo que falta es una resta entre este `ahora` y el que lee el
  /// provider: con la hora real, esa resta valía 40 o 39 según lo que la
  /// máquina hubiera tardado en llegar hasta la llamada, y bastaba un runner
  /// cargado para cruzar el segundo entero. Congelar los dos lados en el mismo
  /// instante hace que la resta dé siempre lo mismo.
  ///
  /// Vale la aclaración porque el reloj congelado NO avanza: si algún día un
  /// test de acá necesita ver pasar el tiempo, se vuelve a congelar en otro
  /// instante, y ese salto queda como una línea visible del test.
  late DateTime ahora;

  setUp(() {
    // Local, no UTC: `AppClock` reemplaza a `DateTime.now()` y lo asegura con
    // un assert. El `.toUtc()` va del lado del consumidor, igual que en
    // producción.
    AppClock.freeze(DateTime(2026, 3, 17, 10, 30));
    addTearDown(AppClock.unfreeze);
    ahora = AppClock.now().toUtc();
    service = _ServicioFalso();
    sesion = StreamController<DurationTimerState?>();
    when(() => service.startExerciseTimer(any())).thenAnswer((_) async {});
    when(service.cancelExerciseTimer).thenAnswer((_) async {});
    when(service.exerciseTimerState).thenAnswer((_) async => null);

    container = ProviderContainer(
      overrides: [
        wearWorkoutServiceProvider.overrideWithValue(service),
        wearSessionTimerProvider.overrideWith((ref) => sesion.stream),
      ],
    );
    // Eager, igual que en `main_wear.dart`: sin esto no escucha nadie.
    container.read(wearTimerInboxProvider);
    addTearDown(container.dispose);
    addTearDown(sesion.close);
  });

  /// Deja correr los `await` del espejado. Son varios saltos de microtask
  /// porque `_espejar` consulta el nativo antes y después de arrancar.
  Future<void> asentar() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  DurationTimerState cronometro({
    required DurationTimerOwner owner,
    int totalSeconds = 60,
    Duration falta = const Duration(seconds: 60),
  }) =>
      DurationTimerState(
        exerciseId: 'plancha',
        setNumber: 2,
        totalSeconds: totalSeconds,
        endsAt: ahora.add(falta),
        owner: owner,
      );

  WearExerciseTimer nativo({
    int endsAtElapsedMs = 555000,
    bool finished = false,
  }) =>
      (
        endsAtElapsedMs: endsAtElapsedMs,
        totalMs: 60000,
        remainingMs: finished ? 0 : 30000,
        finished: finished,
      );

  group('espeja lo que dice la sesión', () {
    test('un cronómetro del teléfono arranca el temporizador nativo', () async {
      sesion.add(cronometro(
        owner: DurationTimerOwner.telefono,
        falta: const Duration(seconds: 40),
      ));
      await asentar();

      // 40 y no 60: lo que FALTA, derivado del instante de fin. Si arrancara
      // con la duración completa, las dos pantallas quedarían corridas por lo
      // que tardó en cruzar — y los dos números están a la vista al mismo
      // tiempo, uno en la muñeca y otro en la mano.
      verify(() => service.startExerciseTimer(40)).called(1);
    });

    test('uno que ya venció no arranca nada', () async {
      // Arrancar uno de cero sería peor que ignorarlo: el atleta vería una
      // plancha nueva que nadie pidió.
      sesion.add(cronometro(
        owner: DurationTimerOwner.telefono,
        falta: const Duration(seconds: -5),
      ));
      await asentar();

      verifyNever(() => service.startExerciseTimer(any()));
    });

    test('si acá YA hay uno corriendo, no se pisa', () async {
      // Pisar el deadline nativo lo CAMBIA, y como ocultar se recuerda por
      // deadline, el temporizador oculto dejaba de coincidir y la pantalla
      // reaparecía sola con el tiempo movido.
      when(service.exerciseTimerState).thenAnswer((_) async => nativo());

      sesion.add(cronometro(owner: DurationTimerOwner.telefono));
      await asentar();

      verifyNever(() => service.startExerciseTimer(any()));
    });

    test('que no haya nada anotado cancela el nativo', () async {
      sesion.add(null);
      await asentar();

      verify(service.cancelExerciseTimer).called(1);
    });
  });

  group('marca cuáles NO son de este reloj', () {
    test('uno del teléfono queda marcado como ajeno, por su deadline',
        () async {
      // Antes de arrancar no hay nada; después, el nativo devuelve el deadline
      // que acaba de fijar. Ese es el que hay que recordar.
      var arrancado = false;
      when(service.exerciseTimerState)
          .thenAnswer((_) async => arrancado ? nativo() : null);
      when(() => service.startExerciseTimer(any())).thenAnswer((_) async {
        arrancado = true;
      });

      sesion.add(cronometro(owner: DurationTimerOwner.telefono));
      await asentar();

      expect(container.read(wearTimerAjenoProvider), nativo().endsAtElapsedMs);
    });

    test('uno de ESTE reloj no se marca: es suyo y él carga la serie',
        () async {
      var arrancado = false;
      when(service.exerciseTimerState)
          .thenAnswer((_) async => arrancado ? nativo() : null);
      when(() => service.startExerciseTimer(any())).thenAnswer((_) async {
        arrancado = true;
      });

      sesion.add(cronometro(owner: DurationTimerOwner.reloj));
      await asentar();

      expect(container.read(wearTimerAjenoProvider), isNull);
    });

    test('la marca NO se borra cuando el documento desaparece', () async {
      // Es la carrera que importa: el teléfono —dueño— borra el documento al
      // llegar a cero. Si eso limpiara la marca antes de que este reloj note su
      // propio vencimiento, el reloj se creería dueño y cargaría la serie por
      // segunda vez. Un valor viejo es inofensivo: apunta a un deadline que ya
      // no existe.
      var arrancado = false;
      when(service.exerciseTimerState)
          .thenAnswer((_) async => arrancado ? nativo() : null);
      when(() => service.startExerciseTimer(any())).thenAnswer((_) async {
        arrancado = true;
      });

      sesion.add(cronometro(owner: DurationTimerOwner.telefono));
      await asentar();
      expect(container.read(wearTimerAjenoProvider), isNotNull);

      sesion.add(null);
      await asentar();

      expect(container.read(wearTimerAjenoProvider), nativo().endsAtElapsedMs);
    });
  });
}
