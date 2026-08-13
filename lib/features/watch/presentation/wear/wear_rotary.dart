import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
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
  /// La corona dejaba de andar por completo, que es exactamente lo que reportó
  /// el dueño: *"nada de la corona"*.
  ///
  /// Con un stream único el canal se abre una sola vez y no se cierra nunca.
  static Stream<double>? _shared;

  /// Píxeles **físicos** a sumar al offset de scroll. Positivo = bajar.
  static Stream<double> get physicalPixels =>
      _shared ??= _events.receiveBroadcastStream().map((e) => e as double);
}

/// Conecta la corona a un [ScrollController].
///
/// **Uno solo por pantalla.** Si hay dos scrollables vivos, la corona no sabe a
/// cuál hablarle. Es la razón de fondo por la que el companion usa UNA lista
/// vertical por pantalla en vez del pager horizontal que tenía antes.
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
  /// pantalla de 206 dp eso ya es casi un tercio de pantalla por muesca, así
  /// que el multiplicador tiene que ser CHICO.
  static const double _sensitivity = 1.5;

  /// Qué tan rápido persigue el destino, en unidades de 1/segundo.
  ///
  /// Más alto = más pegado a la muesca pero más brusco; más bajo = más suave
  /// pero se siente flotando. 18 llega al ~95% del destino en unos 165 ms, que
  /// es el punto donde el gesto se siente conectado y fluido a la vez.
  static const double _responsiveness = 18;

  /// Con menos de esto ya llegamos: perseguir décimas de píxel sólo gasta
  /// frames sin que se vea nada.
  static const double _epsilon = 0.5;

  late final Ticker _ticker = createTicker(_onTick);

  StreamSubscription<double>? _sub;
  double _dpr = 1;

  /// Adónde queremos llegar. Null = no hay nada pendiente.
  ///
  /// **Acá está la clave de la fluidez.** La versión anterior hacía `jumpTo` con
  /// el delta de cada muesca: aunque se agrupara por frame, cada muesca seguía
  /// siendo un ESCALÓN instantáneo de ~96 px. El dueño lo describió como *"a
  /// tirones"*, y tenía razón — no era un problema de frecuencia, era que no
  /// había interpolación.
  ///
  /// Ahora las muescas se suman a un DESTINO y un ticker desliza hacia él con
  /// suavizado exponencial. Girar rápido no encola saltos: corre el destino más
  /// lejos y el deslizamiento se acelera solo.
  double? _target;

  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Se suscribe SIEMPRE, y el filtro de `enabled` se hace al recibir. Alternar
    // la suscripción según la página era lo que rompía el canal — ver el doc de
    // [WearRotary._shared].
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
    _ticker.dispose();
    super.dispose();
  }

  void _apply(double physical) {
    // El filtro va acá y no en la suscripción: en un pager las páginas quedan
    // vivas aunque no se vean, y sin esto el giro movería listas que nadie mira.
    if (!widget.enabled) return;

    final c = widget.controller;
    if (!c.hasClients) return;
    final p = c.position;

    // `scaledVerticalScrollFactor` viene en píxeles FÍSICOS; el offset de
    // Flutter es en píxeles LÓGICOS. Sin esta división, en el SM-L500
    // (devicePixelRatio 2.125) cada muesca scrollea el doble de lo que debería.
    final delta = physical / _dpr * _sensitivity;

    // Se acumula sobre el destino ANTERIOR, no sobre la posición actual: si no,
    // girar rápido perdería las muescas que llegan mientras todavía desliza.
    final base = _target ?? p.pixels;
    _target = (base + delta).clamp(p.minScrollExtent, p.maxScrollExtent);

    if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final c = widget.controller;
    final target = _target;
    if (target == null || !c.hasClients) {
      _stop();
      return;
    }

    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    final current = c.position.pixels;
    final remaining = target - current;
    if (remaining.abs() < _epsilon || dt <= 0) {
      c.jumpTo(target);
      _stop();
      return;
    }

    // Suavizado exponencial con dt: si un frame se atrasa, el deslizamiento
    // avanza proporcionalmente más y no se siente distinto. Con un factor fijo
    // por frame, un hipo de render se notaría como un tirón.
    final t = 1 - math.exp(-_responsiveness * dt);
    c.jumpTo(current + remaining * t);
  }

  void _stop() {
    _target = null;
    if (_ticker.isActive) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
