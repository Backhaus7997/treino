import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// La corona / bisel giratorio del reloj.
///
/// ## Por qué esto existe
///
/// **El engine de Flutter descarta los eventos de la corona.** No es un bug de
/// versión ni algo que arregle una actualización:
/// `AndroidTouchProcessor.onGenericMotionEvent` exige `SOURCE_CLASS_POINTER`, y
/// el rotary es `SOURCE_CLASS_NONE`, así que sale por el primer `if`. No hay una
/// sola mención de `SOURCE_ROTARY_ENCODER` en todo `flutter/flutter`, y el issue
/// de soporte para Wear OS está abierto desde 2016.
///
/// Por eso los eventos se capturan en `MainActivity.onGenericMotionEvent` y
/// viajan por un `EventChannel`.
class WearRotary {
  const WearRotary._();

  static const _events = EventChannel('treino/wear_rotary');

  /// Stream ÚNICO y compartido.
  ///
  /// **Ojo con hacer `receiveBroadcastStream()` en cada acceso**: cada llamada
  /// crea un stream NUEVO, y cada suscripción/cancelación dispara
  /// `onListen`/`onCancel` del lado Kotlin. Con varias pantallas vivas
  /// suscribiéndose y desuscribiéndose, un `cancel` —que además es
  /// asincrónico— llega DESPUÉS del `listen` nuevo y deja `rotarySink = null`.
  /// La corona dejaba de andar por completo.
  ///
  /// Con un stream único el canal se abre una sola vez y no se cierra nunca.
  static Stream<double>? _shared;

  /// Píxeles **físicos** a sumar al offset de scroll. Positivo = bajar.
  static Stream<double> get physicalPixels =>
      _shared ??= _events.receiveBroadcastStream().map((e) => e as double);
}

/// Conecta la corona a un [ScrollController].
///
/// ## Cómo se logra que se sienta igual que el dedo
///
/// **Alimentando el mismo camino que usa el dedo.** `ScrollPosition.drag()`
/// devuelve el objeto [Drag] que un gesto real usa para empujar la lista: pasa
/// por la física del scrollable, respeta los límites, y al soltar dispara la
/// simulación balística — el fling con su desaceleración.
///
/// Las versiones anteriores usaban `jumpTo`, que **saltea la física entera**:
/// setea la posición a mano, sin fricción, sin inercia y sin rebote. Se intentó
/// tapar eso interpolando entre destinos, ajustando la sensibilidad y agregando
/// refuerzo por velocidad, y el dueño lo siguió viendo: *"sigue bajando o
/// subiendo como por bloques y se ven los cortes"*. Tenía razón, y el problema
/// no era de ajuste: **ningún suavizado sobre `jumpTo` produce inercia, porque
/// la inercia no está**.
///
/// Con `drag()` no se PARECE al scroll con el dedo: **es** el scroll con el
/// dedo, alimentado por otro dispositivo de entrada.
///
/// **Uno solo por pantalla.** Si hay dos scrollables vivos, la corona no sabe a
/// cuál hablarle.
class WearRotaryScroll extends StatefulWidget {
  const WearRotaryScroll({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  final ScrollController controller;
  final Widget child;

  /// Si esta instancia escucha el hardware.
  ///
  /// En un pager las páginas quedan VIVAS aunque no se vean, así que sin este
  /// interruptor el giro movería listas que nadie está mirando.
  final bool enabled;

  @override
  State<WearRotaryScroll> createState() => _WearRotaryScrollState();
}

class _WearRotaryScrollState extends State<WearRotaryScroll>
    with SingleTickerProviderStateMixin {
  /// Cuánto scroll produce una muesca.
  ///
  /// Medido en el SM-L500: cada muesca da `axis = ±1.0`, que por el
  /// `scaledVerticalScrollFactor` son 136 píxeles FÍSICOS = 64 lógicos. En una
  /// pantalla de 206 dp eso ya es un tercio de pantalla, así que el
  /// multiplicador es CHICO: el recorrido largo lo aporta el fling, no el paso.
  static const double _sensitivity = 0.85;

  /// Cuánto silencio cuenta como "soltó la corona".
  ///
  /// Al vencer se cierra el arrastre con la velocidad acumulada, que es lo que
  /// dispara el fling. Corto para que el fling salga apenas se deja de girar,
  /// pero más largo que el intervalo entre muescas de un giro rápido — si no,
  /// un giro sostenido se partiría en varios arrastres y cada corte se sentiría
  /// como un frenazo.
  static const Duration _idleBeforeFling = Duration(milliseconds: 80);

  /// Constante de tiempo con la que se persigue el pendiente, en segundos.
  ///
  /// Cada frame se consume la fracción `1 - e^(-dt/tau)`. Expresarlo así y no
  /// como "un porcentaje por frame" hace que el movimiento se sienta IGUAL a 60
  /// y a 90 Hz: con un porcentaje fijo, una pantalla más rápida alcanzaría el
  /// destino antes y el mismo giro se sentiría distinto según el reloj.
  ///
  /// 35 ms es el compromiso medido: más bajo vuelve a escalonarse —el frame
  /// consume casi toda la muesca—, y más alto se siente elástico, como si la
  /// lista viniera atrasada respecto del dedo.
  static const double _followTau = 0.035;

  /// Por debajo de esto el resto se aplica de una y se considera alcanzado.
  /// Sin este piso, la persecución exponencial nunca llega a cero y el ticker
  /// quedaría vivo para siempre moviendo fracciones de píxel.
  static const double _epsilon = 0.2;

  StreamSubscription<double>? _sub;
  double _dpr = 1;

  /// Píxeles lógicos que la corona pidió y todavía no se aplicaron.
  ///
  /// ## Por qué existe: los tirones no eran falta de inercia
  ///
  /// El arrastre ya usaba `Drag`, así que el fling estaba. Lo que se seguía
  /// viendo era otra cosa: **cada muesca aplicaba su desplazamiento entero en
  /// un solo frame**. Medido en el SM-L500, una muesca son 136 px físicos = 64
  /// lógicos, y por la sensibilidad ~54: en una pantalla de 206 dp eso es un
  /// cuarto de pantalla de golpe. Girando despacio se ve exactamente como lo
  /// describió el dueño — un salto por muesca — porque ES un salto por muesca,
  /// por más física que haya después.
  ///
  /// La corona emite eventos discretos y la pantalla dibuja a 60/90 Hz. En vez
  /// de volcar la muesca entera en el frame en que llega, se acumula acá y un
  /// ticker la reparte entre los frames siguientes. El movimiento pasa de
  /// escalonado a continuo sin tocar la física: al `Drag` se le siguen dando
  /// updates, sólo que más chicos y más seguidos.
  double _pending = 0;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  /// Arrastre en curso. El MISMO tipo que produce un dedo.
  Drag? _drag;
  Timer? _idle;

  /// Velocidad suavizada, en píxeles lógicos por segundo.
  ///
  /// Es lo que se le pasa a [Drag.end]: sin velocidad no hay fling, y sin fling
  /// el scroll frena en seco apenas se deja de girar. Ese frenazo es justo lo
  /// que se leía como "bloques".
  double _velocity = 0;

  @override
  void initState() {
    super.initState();
    // Se suscribe SIEMPRE, y el filtro de `enabled` se hace al recibir. Alternar
    // la suscripción según la página rompía el canal — ver [WearRotary._shared].
    _sub = WearRotary.physicalPixels.listen(_apply);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dpr = MediaQuery.devicePixelRatioOf(context);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _idle?.cancel();
    _ticker?.dispose();
    _drag?.cancel();
    super.dispose();
  }

  void _apply(double physical) {
    // El filtro va acá y no en la suscripción: en un pager las páginas quedan
    // vivas aunque no se vean, y sin esto el giro movería listas que nadie mira.
    if (!widget.enabled) return;

    final c = widget.controller;
    if (!c.hasClients) return;

    // `scaledVerticalScrollFactor` viene en píxeles FÍSICOS; el offset de
    // Flutter es en píxeles LÓGICOS. Sin esta división, en el SM-L500
    // (devicePixelRatio 2.125) cada muesca scrollea el doble de lo que debería.
    final delta = physical / _dpr * _sensitivity;

    // La muesca NO se aplica acá. Se encola, y el ticker la reparte entre los
    // frames que siguen. Ver [_pending].
    _pending += delta;

    _drag ??= c.position.drag(
      DragStartDetails(globalPosition: Offset.zero),
      () => _drag = null,
    );

    final ticker = _ticker ??= createTicker(_onTick);
    if (!ticker.isActive) {
      _lastTick = Duration.zero;
      ticker.start();
    }

    // Cada muesca corre el vencimiento: un giro sostenido es UN arrastre largo,
    // no muchos cortos. Partirlo en pedazos es exactamente lo que producía los
    // frenazos entre bloques.
    _idle?.cancel();
    _idle = Timer(_idleBeforeFling, _cerrarSiYaLlego);
  }

  /// Reparte el pendiente, un poco por frame.
  void _onTick(Duration elapsed) {
    final drag = _drag;
    if (drag == null) {
      _pending = 0;
      _pararTicker();
      return;
    }

    // dt REAL entre frames, acotado: un frame perdido no puede producir un
    // salto grande, que es justo lo que se está tratando de eliminar.
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(1 / 240, 0.05);
    _lastTick = elapsed;

    var step = _pending * (1 - math.exp(-dt / _followTau));
    if (_pending.abs() < _epsilon) step = _pending;
    _pending -= step;

    if (step != 0) {
      // El signo se invierte: en el protocolo de arrastre, mover el dedo hacia
      // ARRIBA (delta negativo) baja por la lista.
      drag.update(
        DragUpdateDetails(
          globalPosition: Offset.zero,
          delta: Offset(0, -step),
          primaryDelta: -step,
        ),
      );

      // La velocidad sale de lo que se movió DE VERDAD en este frame, no del
      // intervalo entre muescas. Es la misma cuenta que hace un dedo, y por eso
      // el fling que sale al soltar tiene la magnitud que el atleta espera.
      final instant = -step / dt;
      _velocity = _velocity * 0.75 + instant * 0.25;
    }

    if (_pending.abs() < _epsilon) {
      _pending = 0;
      _pararTicker();
    }
  }

  void _pararTicker() {
    if (_ticker?.isActive ?? false) _ticker!.stop();
    _lastTick = Duration.zero;
  }

  /// Cierra el arrastre sólo cuando ya no queda nada por aplicar.
  ///
  /// Si venciera el silencio con pendiente en la mano, el fling arrancaría
  /// desde una posición que la lista todavía no alcanzó y se vería un salto
  /// justo al soltar — el tirón, mudado al final del gesto.
  void _cerrarSiYaLlego() {
    if (_pending.abs() >= _epsilon) {
      _idle = Timer(_idleBeforeFling, _cerrarSiYaLlego);
      return;
    }
    _endDrag();
  }

  /// Cierra el arrastre con velocidad, para que la física haga el fling.
  void _endDrag() {
    final drag = _drag;
    _drag = null;
    _pending = 0;
    _pararTicker();
    if (drag == null) return;
    drag.end(
      DragEndDetails(
        primaryVelocity: _velocity,
        velocity: Velocity(pixelsPerSecond: Offset(0, _velocity)),
      ),
    );
    _velocity = 0;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
