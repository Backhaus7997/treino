import 'dart:async';

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

class _WearRotaryScrollState extends State<WearRotaryScroll> {
  /// Multiplicador de sensibilidad.
  ///
  /// `scaledVerticalScrollFactor` está calibrado para la rueda de un mouse en
  /// un teléfono, no para la corona de un reloj. Aplicado tal cual, el dueño lo
  /// describió como *"anda pero lento"*: hay que girar media vuelta para mover
  /// la lista un renglón.
  ///
  /// Medido en el SM-L500: cada muesca da `axis = ±1.0`, que por el
  /// `scaledVerticalScrollFactor` son 136 píxeles FÍSICOS = 64 lógicos. En una
  /// pantalla de 206 dp eso ya es casi un tercio de pantalla por muesca, así
  /// que el multiplicador tiene que ser CHICO.
  static const double _sensitivity = 1.5;

  StreamSubscription<double>? _sub;
  double _dpr = 1;

  /// Delta acumulado que todavía no se aplicó.
  ///
  /// La corona emite decenas de eventos por segundo. Llamar `jumpTo` en cada
  /// uno hace que el scroll se sienta TRABADO: cada salto reinicia la posición
  /// y el render no llega. Se acumulan los eventos y se aplican UNA vez por
  /// frame, que es lo máximo que la pantalla puede mostrar igual.
  double _pending = 0;
  bool _scheduled = false;

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
    super.dispose();
  }

  void _apply(double physical) {
    // El filtro va acá y no en la suscripción: en un pager las páginas quedan
    // vivas aunque no se vean, y sin esto el giro movería listas que nadie mira.
    if (!widget.enabled) return;
    // `scaledVerticalScrollFactor` viene en píxeles FÍSICOS; el offset de
    // Flutter es en píxeles LÓGICOS. Sin esta división, en el SM-L500
    // (devicePixelRatio 2.125) cada muesca scrollea el doble de lo que debería.
    _pending += physical / _dpr * _sensitivity;
    if (_scheduled) return;
    _scheduled = true;
    // `addPostFrameCallback` corre después del PRÓXIMO frame — y una pantalla
    // quieta no produce frames, así que sin `scheduleFrame()` el callback queda
    // esperando para siempre y la corona no hace absolutamente nada. Fue
    // exactamente el bug: el log mostraba los eventos llegando y la lista no se
    // movía.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final delta = _pending;
      _pending = 0;
      final c = widget.controller;
      if (!c.hasClients || delta == 0) return;
      final p = c.position;
      final target =
          (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
      // `jumpTo` y no `animateTo`: animar cada lote es cancelar la animación
      // anterior en el frame siguiente. `jumpTo` da el 1:1 que se siente nativo.
      c.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
