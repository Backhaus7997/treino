import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/watch_effort.dart';
import '../data/wear_workout_service.dart';

final wearWorkoutServiceProvider = Provider<WearWorkoutService>(
  (ref) => WearWorkoutService(),
);

/// Con qué frecuencia se relee el descanso desde el nativo.
///
/// 1 s es la granularidad que ve el atleta. Que el tick a veces no corra —con
/// la muñeca baja el SoC se suspende— no rompe nada: el nativo devuelve un
/// DEADLINE, no una cuenta regresiva, así que el próximo tick que sí corra ya
/// trae el número correcto.
const _pollEvery = Duration(seconds: 1);

/// Descanso en curso, o null si no hay ninguno.
///
/// ## Por qué polling y no un stream de eventos
///
/// Un `EventChannel` sería más elegante, pero durante la suspensión del SoC no
/// se entrega nada igual, así que no compraría puntualidad. Y agregaría un
/// segundo camino de datos que puede desincronizarse del deadline persistido,
/// que es la fuente de verdad. Releer el mismo lugar cada segundo es más
/// aburrido y más difícil de romper.
///
/// El aviso —la vibración— NO depende de este stream: lo dispara el nativo,
/// que sigue vivo aunque el isolate de Dart no corra. Ver `RestAlarm.kt`.
final wearRestProvider = StreamProvider.autoDispose<WearRestState?>((ref) {
  final service = ref.watch(wearWorkoutServiceProvider);

  final controller = StreamController<WearRestState?>();
  Timer? timer;

  Future<void> poll() async {
    try {
      if (!controller.isClosed) controller.add(await service.restState());
    } on Object catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    }
  }

  unawaited(poll());
  timer = Timer.periodic(_pollEvery, (_) => unawaited(poll()));

  // Cancelar en dispose es obligatorio por `docs/performance.md`: un timer
  // huérfano en un reloj no es sólo un leak, es batería del atleta.
  ref.onDispose(() {
    timer?.cancel();
    unawaited(controller.close());
  });

  return controller.stream;
});

/// Esfuerzo actual, ya filtrado por antigüedad.
///
/// ## Por qué el umbral es más CORTO que el del teléfono
///
/// `WatchEffortRules.maxAntiguedad` son 45 s, y es generoso a propósito: allá el
/// dato viene RELAYADO desde el reloj de Apple y la latencia de
/// WatchConnectivity se midió entre 2 y 24 segundos. Acá el dato es LOCAL —
/// Health Services lo mide en este mismo reloj— así que 45 s serían tapar un
/// sensor muerto durante casi un minuto.
///
/// 15 s es el mismo umbral que usa el companion de watchOS para su PROPIA
/// pantalla, que es exactamente el caso análogo.
const wearEffortMaxAge = Duration(seconds: 15);

final wearEffortProvider =
    StreamProvider.autoDispose<WatchEffortDisplay>((ref) {
  final service = ref.watch(wearWorkoutServiceProvider);

  final controller = StreamController<WatchEffortDisplay>();
  Timer? timer;

  Future<void> poll() async {
    try {
      final effort = await service.effort();
      if (controller.isClosed) return;
      final medido = effort?.measuredAt;
      // Se aplica la MISMA forma de la regla que el teléfono, con el umbral de
      // acá: si el dato está vencido no se muestra nada, ni el último valor
      // conocido. Un pulso viejo presentado como actual es peor que nada.
      final vencido = medido == null ||
          DateTime.now().toUtc().difference(medido) > wearEffortMaxAge;
      controller.add(
        (effort == null || vencido)
            ? const WatchEffortDisplay.nada()
            : WatchEffortDisplay(bpm: effort.bpm, kcal: effort.kcal),
      );
    } on Object catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    }
  }

  unawaited(poll());
  timer = Timer.periodic(_pollEvery, (_) => unawaited(poll()));

  ref.onDispose(() {
    timer?.cancel();
    unawaited(controller.close());
  });

  return controller.stream;
});
