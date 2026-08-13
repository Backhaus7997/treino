/// SPIKE DE MEDICIÓN — supervivencia del entreno en Wear OS. **Throwaway.**
///
/// Contesta la pregunta más riesgosa del ciclo: **¿la app sigue corriendo con la
/// pantalla apagada / la muñeca baja?** Es el "descanso congelado" de F0 en
/// watchOS, que allá necesitó DOS mitades (`HKWorkoutSession` **y** el
/// background mode) y con una sola se seguía muriendo.
///
/// ## Por qué esta versión reemplaza a la primera
///
/// La primera pasada midió "85 ticks perdidos" y eso resultó ser un número que
/// mezcla dos cosas. Dos correcciones que cambian el instrumento:
///
/// 1. **`Timer.periodic` de Dart NO pierde ticks lógicos.** Cuando se atrasa,
///    calcula `missedTicks`, avanza `_tick` por esa cantidad y ejecuta el
///    callback UNA sola vez. Contar a mano con `n++` mide invocaciones del
///    callback; `t.tick` mide tiempo lógico transcurrido. **La diferencia entre
///    los dos es exactamente "cuántos callbacks se saltearon"**, y antes era
///    indistinguible.
/// 2. **Ni `Stopwatch` ni `DateTime.now()` sirven para detectar suspensión.**
///    `Stopwatch` es `clock_gettime(CLOCK_MONOTONIC)`, que NO cuenta el tiempo
///    suspendido; `DateTime.now()` es wall clock, que salta cuando el teléfono
///    le sincroniza la hora al reloj. El único reloj monotónico Y suspend-aware
///    es `SystemClock.elapsedRealtime()` (`CLOCK_BOOTTIME`), y a ése sólo se
///    llega por platform channel.
///
/// ## Cómo se lee el resultado
///
/// | observación | diagnóstico |
/// |---|---|
/// | `boot` avanza, `uptime` avanza, faltan callbacks | proceso DESPIERTO pero hambreado (freezer / throttling) |
/// | `boot` avanza, `uptime` NO avanza | **suspensión real del SoC** |
/// | `boot ≈ uptime ≈ wall`, sin callbacks faltantes | verde |
/// | `wall` salta y `boot` no | sync de hora con el teléfono, no suspensión |
///
/// El emulador NO hace suspend-to-RAM, así que la fila de suspensión real sólo
/// se puede observar en un reloj físico. Lo que el emulador SÍ reproduce con
/// fidelidad es el freezer de procesos cacheados (`use_freezer=true` verificado
/// en el propio AVD), que es la causa del escenario "app en background".
///
/// ## Cómo correr
///
/// ```
/// # ROJO — sin mecanismo
/// flutter run -d emulator-5554 -t lib/main_wear_liveness_spike.dart
///
/// # VERDE esperado — con foreground service
/// flutter run -d emulator-5554 -t lib/main_wear_liveness_spike.dart \
///   --dart-define=FGS=true
/// ```
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cada cuánto late. 1 s es la granularidad de un descanso real.
const Duration _tickEvery = Duration(seconds: 1);

/// Duración del descanso de prueba.
///
/// El default **tiene que ser MENOR que la ventana de medición**: las primeras
/// corridas usaron 600 s sobre ventanas de ~500 s, así que el deadline nunca
/// llegaba a cero y el camino que importa —vencer con la pantalla apagada—
/// quedaba sin tocar. 90 s es un descanso realista entre series.
const int _restSeconds = int.fromEnvironment('REST_SECONDS', defaultValue: 90);

/// Interruptor del mecanismo. Es lo que permite poner ROJO por separado sin
/// tocar el manifest — sacar `foregroundServiceType` del manifest no sirve como
/// control: tira `IllegalArgumentException` y entonces medís un crash, no
/// supervivencia.
const bool _useForegroundService = bool.fromEnvironment('FGS');

/// Si además se publica la Ongoing Activity. Segunda mitad, medible aparte.
const bool _useOngoing = bool.fromEnvironment('ONGOING', defaultValue: true);

const MethodChannel _ch = MethodChannel('com.treino.app/wear_workout/methods');

/// Verde cuando el mecanismo está puesto, ámbar cuando corre el control rojo.
/// Es const porque [_useForegroundService] es `bool.fromEnvironment`, o sea
/// constante de compilación: el color queda resuelto en el build.
const TextStyle _fgsStyle = TextStyle(
  color: _useForegroundService ? Colors.greenAccent : Colors.amberAccent,
  fontSize: 10,
  fontWeight: FontWeight.w700,
);

void main() {
  runApp(const _LivenessApp());
}

/// Los tres relojes del sistema, leídos de una sola vez para que no se separen.
typedef _Clocks = ({int bootMs, int uptimeMs, int wallMs});

Future<_Clocks?> _readClocks() async {
  try {
    final r = await _ch.invokeMapMethod<String, dynamic>('clocks');
    if (r == null) return null;
    return (
      bootMs: r['bootMs'] as int,
      uptimeMs: r['uptimeMs'] as int,
      wallMs: r['wallMs'] as int,
    );
  } on PlatformException catch (e) {
    debugPrint('[LIVE] ERROR clocks: $e');
    return null;
  } on MissingPluginException {
    debugPrint('[LIVE] ERROR clocks: plugin no registrado');
    return null;
  }
}

class _LivenessApp extends StatefulWidget {
  const _LivenessApp();

  @override
  State<_LivenessApp> createState() => _LivenessAppState();
}

class _LivenessAppState extends State<_LivenessApp>
    with WidgetsBindingObserver {
  Timer? _timer;

  /// Invocaciones REALES del callback. Distinto de `t.tick`.
  int _n = 0;

  _Clocks? _base;
  String _last = 'arrancando';
  String _fgs = 'sin arrancar';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final base = await _readClocks();
    if (base == null) {
      setState(() => _last = 'SIN CANAL NATIVO');
      return;
    }
    _base = base;

    if (_useForegroundService) {
      try {
        final r = await _ch.invokeMapMethod<String, dynamic>(
          'startForegroundService',
          {'withOngoing': _useOngoing},
        );
        _fgs = (r?['ok'] as bool? ?? false)
            ? 'ON ongoing=$_useOngoing'
            : 'FALLO ${r?['error']}';
      } catch (e) {
        _fgs = 'EXCEPCION $e';
      }
    } else {
      _fgs = 'OFF (control rojo)';
    }
    debugPrint('[LIVE] fgs=$_fgs');

    // Descanso por DEADLINE, del lado nativo. La prueba de que funciona es que
    // al despertar muestre el número correcto AUNQUE no haya corrido un tick.
    //
    // Sólo se arranca si NO había uno en curso. Reiniciarlo en cada arranque
    // haría la persistencia indemostrable: el control es matar el proceso a
    // mitad del descanso (`adb shell am force-stop com.treino.app`), reabrir, y
    // ver que el número sigue donde correspondía. Un contador de ticks arranca
    // de cero ahí; el deadline no.
    final existing = await _ch.invokeMapMethod<String, dynamic>('restState');
    final resumed = existing?['restEndsAtElapsedMs'] != null;
    if (!resumed) {
      await _ch.invokeMapMethod<String, dynamic>(
        'startRest',
        {'seconds': _restSeconds},
      );
    }
    debugPrint(
      '[LIVE] descanso ${resumed ? "RESTAURADO" : "nuevo"} '
      'restante=${existing?['remainingMs'] ?? _restSeconds * 1000}ms',
    );

    debugPrint(
      '[LIVE] start boot=${base.bootMs} uptime=${base.uptimeMs} '
      'wall=${base.wallMs} fgs=$_useForegroundService ongoing=$_useOngoing',
    );

    _timer = Timer.periodic(_tickEvery, _onTick);
  }

  Future<void> _onTick(Timer t) async {
    _n++;
    final c = await _readClocks();
    final b = _base;
    if (c == null || b == null) return;

    final boot = c.bootMs - b.bootMs;
    final uptime = c.uptimeMs - b.uptimeMs;
    final wall = c.wallMs - b.wallMs;

    // `boot - uptime` creciendo = el SoC estuvo suspendido de verdad.
    // `t.tick - _n` = callbacks que el scheduler de Dart se salteó.
    final suspend = boot - uptime;
    final skipped = t.tick - _n;

    final rest = await _ch.invokeMapMethod<String, dynamic>('restState');
    final restRemaining = rest?['remainingMs'] as int?;

    debugPrint(
      '[LIVE] n=$_n tick=${t.tick} skipped=$skipped '
      'boot=$boot uptime=$uptime wall=$wall suspend=$suspend '
      'rest=${restRemaining ?? -1}',
    );

    if (mounted) {
      setState(() => _last = 'n=$_n t=${t.tick} sk=$skipped\n'
          'boot=${boot ~/ 1000}s susp=${suspend}ms\n'
          'rest=${(restRemaining ?? 0) ~/ 1000}s');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[LIVE] lifecycle=$state n=$_n');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (_useForegroundService) {
      unawaited(_ch.invokeMethod<void>('stopForegroundService'));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'FGS $_fgs',
                  textAlign: TextAlign.center,
                  style: _fgsStyle,
                ),
                const SizedBox(height: 6),
                Text(
                  _last,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
