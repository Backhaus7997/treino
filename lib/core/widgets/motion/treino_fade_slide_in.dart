import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';

/// Entrada one-shot fade + slide-up para contenido que aparece — TREINO
/// Motion PR3.
///
/// Al montarse, el child arranca invisible y desplazado [distance] px hacia
/// abajo, y tras esperar [delay] anima a visible/posición final con
/// [AppMotion.base] + [AppMotion.standard]. Para stagger entre hermanos:
/// `delay: AppMotion.stagger(index)`.
///
/// **One-shot**: anima SOLO en el primer mount del [State]. Un rebuild (p.
/// ej. Riverpod re-emite data y el caller reconstruye con otro child) NO
/// re-anima — el flag vive en el State, que sobrevive al rebuild mientras
/// runtimeType/posición no cambien.
///
/// **Implementación elegida — controller one-shot + [Interval]** (excepción
/// documentada a implicit-first, docs/performance.md — contenida y con
/// `dispose()`, mismo precedente que `TreinoShimmer`):
/// - `Transform.translate` da px EXACTOS ([AppMotion.slideMd] = 12px),
///   mientras que `AnimatedSlide` es fraccional al tamaño del child — una
///   card alta se movería el doble que una fila, rompiendo la escala
///   `8·12·20` de slides del sistema.
/// - El [delay] se codifica como [Interval] dentro de la duración total del
///   controller (`delay + base`), NO como `Future.delayed` + `setState`:
///   sin timers sueltos no hay carrera con el desmonte (nada que hacer con
///   `mounted`), y desmontar durante el delay simplemente descarta el ticker
///   en `dispose()`.
///
/// **Reduce-motion** ([AppMotion.reduceMotion]): visible inmediato — sin
/// animación NI delay (el controller salta a `1.0` antes del primer frame).
///
/// **PROHIBIDO en builders lazy** (`ListView.builder`/`.separated`): los
/// ítems reciclados re-montan su State al re-entrar al viewport y la
/// entrada re-animaría en cada scroll. Solo para children construidos
/// eager (columns, `ListView(children: [...])`).
class TreinoFadeSlideIn extends StatefulWidget {
  const TreinoFadeSlideIn({
    super.key,
    this.delay = Duration.zero,
    this.distance = AppMotion.slideMd,
    required this.child,
  });

  /// Espera antes de arrancar la animación (para stagger:
  /// `AppMotion.stagger(index)`). Con reduce-motion se ignora.
  final Duration delay;

  /// Desplazamiento inicial hacia abajo, en px exactos. Usar la escala del
  /// sistema: [AppMotion.slideSm]/[AppMotion.slideMd]/[AppMotion.slideLg].
  final double distance;

  final Widget child;

  @override
  State<TreinoFadeSlideIn> createState() => _TreinoFadeSlideInState();
}

class _TreinoFadeSlideInState extends State<TreinoFadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  /// One-shot: `true` una vez que el primer mount decidió animar (o saltar
  /// directo al final por reduce-motion). Los rebuilds no vuelven a entrar.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Duración total = delay + entrada. El delay es la porción muerta del
    // Interval (progress se queda en 0), la entrada es el resto con la
    // curva standard.
    final total = widget.delay + AppMotion.base;
    _controller = AnimationController(vsync: this, duration: total);
    final begin = widget.delay == Duration.zero
        ? 0.0
        : widget.delay.inMicroseconds / total.inMicroseconds;
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, 1, curve: AppMotion.standard),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se resuelve acá (no en initState) porque reduce-motion necesita
    // MediaQuery — mismo patrón que TreinoShimmer.
    if (!_started) {
      _started = true;
      if (AppMotion.reduceMotion(context)) {
        // Visible al primer frame, sin delay ni ticker.
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else if (AppMotion.reduceMotion(context) && !_controller.isCompleted) {
      // La preferencia se activó en pleno vuelo → snap al final.
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // El wrapper se mantiene también después de completar: sacarlo cambiaría
    // la profundidad del árbol y re-montaría el child (perdería su State).
    // FadeTransition con opacity 1.0 y translate 0 son no-ops baratos.
    return FadeTransition(
      opacity: _progress,
      child: AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.distance * (1 - _progress.value)),
          child: child,
        ),
      ),
    );
  }
}
