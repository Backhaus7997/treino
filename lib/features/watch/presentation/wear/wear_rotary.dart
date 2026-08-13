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

  /// Píxeles **físicos** a sumar al offset de scroll. Positivo = bajar.
  static Stream<double> get physicalPixels =>
      _events.receiveBroadcastStream().map((e) => e as double);
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
  });

  final ScrollController controller;
  final Widget child;

  @override
  State<WearRotaryScroll> createState() => _WearRotaryScrollState();
}

class _WearRotaryScrollState extends State<WearRotaryScroll> {
  StreamSubscription<double>? _sub;
  double _dpr = 1;

  @override
  void initState() {
    super.initState();
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
    final c = widget.controller;
    if (!c.hasClients) return;
    final p = c.position;
    // `scaledVerticalScrollFactor` viene en píxeles FÍSICOS; el offset de
    // Flutter es en píxeles LÓGICOS. Sin esta división, en el SM-L500
    // (devicePixelRatio 2.125) cada muesca scrollea el doble de lo que debería
    // y la lista se siente incontrolable.
    final target = (p.pixels + physical / _dpr)
        .clamp(p.minScrollExtent, p.maxScrollExtent);
    // `jumpTo` y no `animateTo`: la corona ya emite muchos eventos chicos, y
    // animar cada uno es cancelar la animación anterior decenas de veces por
    // segundo. `jumpTo` da el 1:1 que se siente nativo.
    c.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
