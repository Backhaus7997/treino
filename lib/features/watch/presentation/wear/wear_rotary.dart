import 'dart:async';

import 'package:flutter/gestures.dart';
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

class _WearRotaryScrollState extends State<WearRotaryScroll> {
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

  StreamSubscription<double>? _sub;
  double _dpr = 1;

  /// Arrastre en curso. El MISMO tipo que produce un dedo.
  Drag? _drag;
  Timer? _idle;

  /// Velocidad suavizada, en píxeles lógicos por segundo.
  ///
  /// Es lo que se le pasa a [Drag.end]: sin velocidad no hay fling, y sin fling
  /// el scroll frena en seco apenas se deja de girar. Ese frenazo es justo lo
  /// que se leía como "bloques".
  double _velocity = 0;

  final _sinceLastNotch = Stopwatch();

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

    // Velocidad a partir del intervalo REAL entre muescas: la corona no emite a
    // frecuencia fija. Se acota y se suaviza para que una muesca fuera de
    // tiempo no dispare un fling desproporcionado.
    final gap = _sinceLastNotch.isRunning
        ? (_sinceLastNotch.elapsedMicroseconds / 1e6).clamp(0.008, 0.5)
        : 0.5;
    _sinceLastNotch
      ..reset()
      ..start();

    // El signo se invierte: en el protocolo de arrastre, mover el dedo hacia
    // ARRIBA (delta negativo) baja por la lista.
    final instant = -delta / gap;
    _velocity = _drag == null ? instant : _velocity * 0.7 + instant * 0.3;

    _drag ??= c.position.drag(
      DragStartDetails(globalPosition: Offset.zero),
      () => _drag = null,
    );
    _drag!.update(
      DragUpdateDetails(
        globalPosition: Offset.zero,
        delta: Offset(0, -delta),
        primaryDelta: -delta,
      ),
    );

    // Cada muesca corre el vencimiento: un giro sostenido es UN arrastre largo,
    // no muchos cortos. Partirlo en pedazos es exactamente lo que producía los
    // frenazos entre bloques.
    _idle?.cancel();
    _idle = Timer(_idleBeforeFling, _endDrag);
  }

  /// Cierra el arrastre con velocidad, para que la física haga el fling.
  void _endDrag() {
    final drag = _drag;
    _drag = null;
    _sinceLastNotch.stop();
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
