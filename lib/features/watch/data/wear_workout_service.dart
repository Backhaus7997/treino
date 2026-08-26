import 'package:flutter/services.dart';

import '../domain/watch_effort.dart';

/// Estado del descanso tal como lo reporta el lado nativo.
///
/// Trae el DEADLINE y el `ahora` con el que se leyó, nunca una cuenta
/// regresiva. Así, cuántas veces corrió el timer de Dart deja de importar: lo
/// que queda se deriva restando, y si la app no ejecutó un solo tick durante
/// todo el descanso, al volver muestra el número correcto igual.
///
/// Medido en un Samsung SM-L500 (Wear OS 6): en una ventana de 522 s con la
/// muñeca baja, la app ejecutó 108 de 522 callbacks. Un contador de ticks
/// habría mostrado ~8 minutos restantes cuando quedaba 1:18.
typedef WearRestState = ({
  /// Instante de fin en el reloj de `SystemClock.elapsedRealtime`
  /// (`CLOCK_BOOTTIME`): monotónico Y sobrevive a la suspensión del SoC.
  int endsAtElapsedMs,
  int remainingMs,
  bool finished,
});

/// Puente Dart → Android para el entreno en el reloj.
///
/// Envoltorio delgado sobre el `MethodChannel`, por los mismos dos motivos que
/// `WatchBridge` del lado de Apple: **testeabilidad** (un MethodChannel no
/// responde en tests; una costura propia se mockea) y **contención** (cambiar
/// el canal toca un solo archivo).
/// Lo que el reloj necesita saber del temporizador de ejercicio.
///
/// [totalMs] va además de [remainingMs] porque la pantalla dibuja un anillo de
/// progreso: sin el total no hay fracción que mostrar.
typedef WearExerciseTimer = ({
  int endsAtElapsedMs,
  int totalMs,
  int remainingMs,
  bool finished,
});

class WearWorkoutService {
  WearWorkoutService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.treino.app/wear_workout/methods';

  final MethodChannel _channel;

  /// Arranca el foreground service que mantiene vivo el proceso durante el
  /// entreno. Sin esto la app se muere: medido, 22.6% de cobertura contra
  /// 100.0% con el servicio puesto.
  ///
  /// Devuelve false —en vez de tirar— cuando el servicio no está declarado en
  /// el manifest de este build. Es un modo de falla real: `startForegroundService`
  /// devuelve null sin excepción, y taparlo hace que el keep-alive degrade en
  /// silencio.
  Future<bool> startWorkout() async {
    final r = await _channel.invokeMapMethod<String, dynamic>(
      'startForegroundService',
      {'withOngoing': true},
    );
    return r?['ok'] as bool? ?? false;
  }

  Future<void> stopWorkout() =>
      _channel.invokeMethod<void>('stopForegroundService');

  /// Arranca un descanso de [seconds].
  ///
  /// `wakeLock: true` mantiene despierto el SoC mientras dura. No es un
  /// capricho: sin eso el dispositivo entra en Doze y la alarma se difiere
  /// —medido, +21m10s—, así que el aviso nunca llega. Con el wakelock acotado
  /// al descanso, el error medido fue de 8 ms.
  ///
  /// Con [seconds] en cero o menos NO arranca nada: cancela el que hubiera.
  ///
  /// No es defensa de más, es un bug que se vio en la muñeca. Un ejercicio sin
  /// descanso configurado llega acá con 0, y el nativo persistía igual un
  /// deadline —que nace VENCIDO—. Como `restState()` sólo devuelve null cuando
  /// no hay deadline guardado, la barra aparecía en estado "terminado" apenas
  /// se marcaba una serie, y se quedaba ahí. El dueño lo describió como que
  /// "se buguea, como si quisiese aparecer".
  ///
  /// Cancelar y no simplemente ignorar es a propósito: si venía corriendo el
  /// descanso del ejercicio anterior, marcar una serie del que no tiene
  /// descanso significa que el atleta ya volvió a entrenar.
  Future<void> startRest(int seconds) {
    if (seconds <= 0) return cancelRest();
    return _channel.invokeMethod<void>(
      'startRest',
      {'seconds': seconds, 'wakeLock': true},
    );
  }

  Future<void> cancelRest() => _channel.invokeMethod<void>('cancelRest');

  // ── Temporizador del ejercicio por tiempo ─────────────────────────────────
  //
  // Es OTRO temporizador, no el descanso con otro nombre. Comparten la
  // maquinaria nativa —deadline persistido, alarma exacta, vibración— pero no
  // el estado: con un solo store, arrancar un ejercicio por tiempo cancelaría
  // el descanso en curso sin decir nada.

  /// Arranca el temporizador del ejercicio actual.
  ///
  /// Con [seconds] en cero o menos no arranca nada y cancela el que hubiera,
  /// por el mismo motivo que [startRest]: un temporizador que nace vencido sólo
  /// ensucia la pantalla.
  Future<void> startExerciseTimer(int seconds) {
    if (seconds <= 0) return cancelExerciseTimer();
    return _channel.invokeMethod<void>(
      'startExerciseTimer',
      {'seconds': seconds},
    );
  }

  Future<void> cancelExerciseTimer() =>
      _channel.invokeMethod<void>('cancelExerciseTimer');

  /// El temporizador en curso, o null si no hay ninguno.
  ///
  /// A diferencia del descanso, esto sigue devolviendo estado DESPUÉS de vencer
  /// —con `finished: true`— y no se borra solo. El descanso desaparece porque
  /// su cartel ya no aporta nada; acá el atleta tiene que ver que el tiempo
  /// terminó para recién entonces marcar la serie.
  Future<WearExerciseTimer?> exerciseTimerState() async {
    final r =
        await _channel.invokeMapMethod<String, dynamic>('exerciseTimerState');
    final endsAt = r?['endsAtElapsedMs'] as int?;
    if (r == null || endsAt == null) return null;
    return (
      endsAtElapsedMs: endsAt,
      totalMs: r['totalMs'] as int? ?? 0,
      remainingMs: r['remainingMs'] as int? ?? 0,
      finished: r['finished'] as bool? ?? false,
    );
  }

  /// Pulso y calorías del ejercicio en curso, o null si todavía no hay nada.
  ///
  /// El nativo emite el MISMO shape que Swift (`kind: 'watchEffort'`), así que
  /// se parsea con `WatchEffort.tryParse` — el mismo parser que usa el teléfono
  /// para el reloj de Apple. Un solo modelo para las dos plataformas: si el
  /// contrato cambia, rompe en un solo lugar y no diverge en silencio.
  Future<WatchEffort?> effort() async {
    final r = await _channel.invokeMapMethod<String, dynamic>('effort');
    if (r == null) return null;
    return WatchEffort.tryParse(r);
  }

  /// Estado actual, o null si no hay descanso en curso.
  ///
  /// El nativo ya descarta un deadline que sobrevivió a un reboot: como
  /// `elapsedRealtime` cuenta desde el arranque, tras reiniciar apuntaría a un
  /// futuro imposible.
  Future<WearRestState?> restState() async {
    final r = await _channel.invokeMapMethod<String, dynamic>('restState');
    final endsAt = r?['restEndsAtElapsedMs'] as int?;
    if (r == null || endsAt == null) return null;
    return (
      endsAtElapsedMs: endsAt,
      remainingMs: r['remainingMs'] as int? ?? 0,
      finished: r['finished'] as bool? ?? false,
    );
  }
}
