import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/watch/application/wear_rest_providers.dart';
import 'package:treino/features/watch/application/wear_rest_sync_providers.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';
import 'package:treino/features/workout/domain/rest_state.dart';

class _ServicioFalso extends Mock implements WearWorkoutService {}

/// El buzón que refleja en el descanso NATIVO del Wear lo que dice la sesión
/// (#1616).
///
/// El nativo cuenta en `elapsedRealtime`, que no significa nada en otro
/// aparato; la sesión trae un instante de fin en tiempo de pared. El buzón
/// traduce por lo que FALTA y decide con la misma regla que el teléfono y el
/// Apple Watch: adoptar, cortar o no tocar. Lo caro de equivocarse acá es la
/// alarma nativa — reprogramarla de más la corre, no reprogramarla deja a la
/// muñeca vibrando en otro instante que el teléfono.
void main() {
  late _ServicioFalso service;
  late StreamController<RestState?> sesion;
  late ProviderContainer container;
  late DateTime ahora;

  /// Lo que el nativo dice que falta. Null = no hay descanso.
  int? nativoFaltaMs;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    // Congelado: lo que se le pasa al nativo es una resta contra el reloj de
    // pared, y con la hora real daría un número u otro según la máquina.
    AppClock.freeze(DateTime(2026, 3, 17, 10, 30));
    addTearDown(AppClock.unfreeze);
    ahora = AppClock.now().toUtc();

    nativoFaltaMs = null;
    service = _ServicioFalso();
    sesion = StreamController<RestState?>();
    when(service.restState).thenAnswer(
      (_) async => nativoFaltaMs == null
          ? null
          : (
              endsAtElapsedMs: 900000 + nativoFaltaMs!,
              remainingMs: nativoFaltaMs!,
              finished: nativoFaltaMs! <= 0,
            ),
    );
    when(() => service.startRestFor(any())).thenAnswer((inv) async {
      nativoFaltaMs =
          (inv.positionalArguments.first as Duration).inMilliseconds;
    });
    when(service.cancelRest).thenAnswer((_) async {
      nativoFaltaMs = null;
    });

    container = ProviderContainer(
      overrides: [
        wearWorkoutServiceProvider.overrideWithValue(service),
        wearSessionRestProvider.overrideWith((ref) => sesion.stream),
      ],
    );
    // Eager, igual que en `main_wear.dart`: sin esto no escucha nadie.
    container.read(wearRestInboxProvider);
    addTearDown(container.dispose);
    addTearDown(sesion.close);
  });

  /// Deja correr la cola del buzón: cada vuelta consulta el nativo antes de
  /// arrancar o cortar.
  Future<void> asentar() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  RestState descanso(Duration falta, {RestOwner owner = RestOwner.telefono}) =>
      RestState(
        exerciseId: 'press-banca',
        setNumber: 2,
        totalSeconds: 90,
        endsAt: ahora.add(falta),
        owner: owner,
      );

  group('el descanso de la sesión llega a la muñeca', () {
    test('uno que arrancó el teléfono arranca el nativo con lo que FALTA',
        () async {
      sesion.add(descanso(const Duration(seconds: 61, milliseconds: 250)));
      await asentar();

      // 61 250 ms y no 90 s ni 62 s: al milisegundo, para que la alarma
      // nativa caiga en el MISMO instante que el aviso del teléfono.
      verify(() => service.startRestFor(const Duration(milliseconds: 61250)))
          .called(1);
    });

    test('+15 s del teléfono corre la alarma nativa', () async {
      final original = descanso(const Duration(seconds: 60));
      sesion.add(original);
      await asentar();

      sesion.add(original.extendedBy(15, now: ahora));
      await asentar();

      verify(() => service.startRestFor(const Duration(seconds: 75))).called(1);
    });

    test('SALTAR en el teléfono corta el nativo', () async {
      sesion.add(descanso(const Duration(seconds: 60)));
      await asentar();

      sesion.add(null);
      await asentar();

      verify(service.cancelRest).called(1);
    });
  });

  group('lo que NO tiene que tocar', () {
    test('el eco de la escritura propia no reprograma la alarma', () async {
      // El reloj marcó, arrancó su nativo y escribió: la sesión le devuelve
      // su propio descanso. Reprogramar acá correría la alarma en cada eco.
      nativoFaltaMs = 90000;
      sesion.add(descanso(const Duration(seconds: 90), owner: RestOwner.reloj));
      await asentar();

      verifyNever(() => service.startRestFor(any()));
      verifyNever(service.cancelRest);
    });

    test('unos ms de diferencia por la conversión siguen siendo el mismo',
        () async {
      // El nativo cuenta en `elapsedRealtime`; pasarlo a tiempo de pared
      // corre unos milisegundos. Dentro de la tolerancia no se toca.
      nativoFaltaMs = 89700;
      sesion.add(descanso(const Duration(seconds: 90)));
      await asentar();

      verifyNever(() => service.startRestFor(any()));
    });

    test('sin descanso en ningún lado no corta nada', () async {
      sesion.add(null);
      await asentar();

      verifyNever(service.cancelRest);
      verifyNever(() => service.startRestFor(any()));
    });

    test('uno ya vencido en la sesión no arranca nada', () async {
      // Arrancar uno de cero haría vibrar la muñeca por un descanso que ya
      // terminó.
      sesion.add(descanso(const Duration(seconds: -5)));
      await asentar();

      verifyNever(() => service.startRestFor(any()));
    });

    test('un error del canal no corta el descanso de la muñeca', () async {
      // Sin red el reloj sigue solo: un error no dice que lo hayan saltado.
      nativoFaltaMs = 50000;
      sesion.addError(StateError('sin red'));
      await asentar();

      verifyNever(service.cancelRest);
      expect(nativoFaltaMs, 50000);
    });
  });

  test('dos cambios seguidos llegan al nativo EN ORDEN', () async {
    // El teléfono marcó y enseguida sumó +15 s. Sin cola, el segundo espejado
    // corre en paralelo con el primero: si la primera lectura del nativo
    // tarda más que la segunda, el primero arranca DESPUÉS y deja la alarma en
    // el valor viejo. Acá la primera lectura tarda a propósito.
    var lecturas = 0;
    when(service.restState).thenAnswer((_) async {
      lecturas += 1;
      if (lecturas == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    });

    final original = descanso(const Duration(seconds: 60));
    sesion
      ..add(original)
      ..add(original.extendedBy(15, now: ahora));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await asentar();

    expect(nativoFaltaMs, 75000);
  });
}
