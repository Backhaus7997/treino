import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';

/// Barrido de brillo ("shimmer") para skeletons de carga — TREINO Motion PR2.
///
/// Envuelve el root de un skeleton existente y le desplaza en loop un
/// [LinearGradient] diagonal sutil por encima (vía [ShaderMask] con
/// [BlendMode.srcATop], que respeta el alpha del child: solo brillan las
/// cajas pintadas del skeleton, nunca el fondo transparente).
///
/// **Excepción documentada a la doctrina implicit-first**
/// (`docs/performance.md`): un loop infinito no se puede expresar con
/// widgets implícitos, así que este widget hoja usa un [AnimationController]
/// en `repeat()` — el caso que performance.md permite explícitamente,
/// siempre que el controller se libere en `dispose()` (se hace).
///
/// **Reduce-motion**: si el usuario pidió reducir movimiento
/// ([AppMotion.reduceMotion]), el controller NO corre y se devuelve el
/// child estático tal cual (sin [ShaderMask]). El chequeo vive en
/// [didChangeDependencies] — necesita `context` y además reacciona si la
/// preferencia cambia en runtime.
///
/// **[enabled]**: apagalo (`false`) cuando el mismo skeleton se reusa para
/// un estado que NO es "cargando" — error de stream, dato null estable. Un
/// barrido infinito ahí quema batería y miente ("sigue cargando" cuando ya
/// falló). Con `enabled: false` el controller nunca arranca (o se frena si
/// el flag cambia en runtime) y se devuelve el child tal cual.
class TreinoShimmer extends StatefulWidget {
  const TreinoShimmer({super.key, this.enabled = true, required this.child});

  /// `false` → sin animación ni [ShaderMask]: child estático. Para usos del
  /// skeleton en estados de error/null, donde nada está cargando.
  final bool enabled;

  /// El contenido skeleton a iluminar (cajas estáticas ya existentes).
  final Widget child;

  @override
  State<TreinoShimmer> createState() => _TreinoShimmerState();
}

class _TreinoShimmerState extends State<TreinoShimmer>
    with SingleTickerProviderStateMixin {
  /// Período del loop del barrido. NO es un token de `AppMotion` a
  /// propósito: los tokens del sistema son duraciones de *transición*
  /// (micro/fast/base/slow, 120–320ms); esto es el período de un *loop
  /// ambiental* — otra categoría semántica, con otra escala (~1.4s). Meterlo
  /// en la escala de transiciones la contaminaría.
  static const Duration _loopPeriod = Duration(milliseconds: 1400);

  /// Alpha del highlight sobre el color base del skeleton. Sutil (0.06–0.10
  /// per spec de PR2) — un brillo que se percibe, no una discoteca.
  static const double _highlightAlpha = 0.08;

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _loopPeriod);

  /// `true` cuando el barrido no debe correr: `enabled: false` del caller o
  /// reduce-motion del sistema.
  bool _static = false;

  void _syncAnimation() {
    _static = !widget.enabled || AppMotion.reduceMotion(context);
    if (_static) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se resuelve acá (no en initState) porque necesita MediaQuery, y se
    // re-evalúa si la preferencia de accesibilidad cambia mientras el
    // skeleton está montado.
    _syncAnimation();
  }

  @override
  void didUpdateWidget(TreinoShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // [enabled] puede cambiar entre rebuilds (p. ej. el caller reusa el
    // mismo skeleton para loading y error): frena/arranca el loop sin
    // esperar a un cambio de dependencias.
    if (oldWidget.enabled != widget.enabled) _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Deshabilitado o reduce-motion → skeleton estático tal cual, sin
    // ShaderMask siquiera.
    if (_static) return widget.child;

    final palette = AppPalette.of(context);
    final highlight = palette.textPrimary.withValues(alpha: _highlightAlpha);
    // Bordes del mismo color con alpha 0 (no `Colors.transparent`, que es
    // negro-transparente y ensuciaría la interpolación del gradiente).
    final edge = highlight.withValues(alpha: 0);

    // RepaintBoundary: RenderShaderMask NO es repaint boundary, así que sin
    // esto cada tick del loop repintaría también a los ancestros/siblings
    // del skeleton (p. ej. el shimmer de exercise_detail envuelve un
    // SingleChildScrollView entero dentro de un Stack). Con el boundary, el
    // repaint por frame queda scopeado al skeleton.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              return LinearGradient(
                // Diagonal suave (leve inclinación vertical del barrido).
                begin: const Alignment(-1.0, -0.3),
                end: const Alignment(1.0, 0.3),
                colors: [edge, highlight, edge],
                stops: const [0.35, 0.5, 0.65],
                transform:
                    _SlidingGradientTransform(percent: _controller.value),
              ).createShader(bounds);
            },
            child: child,
          );
        },
      ),
    );
  }
}

/// Traslada el gradiente de izquierda (fuera de pantalla) a derecha (fuera
/// de pantalla) según [percent] ∈ [0, 1] — el patrón del cookbook oficial de
/// Flutter para shimmer, sin repintar el gradiente en sí.
class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.percent});

  final double percent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // percent 0 → banda totalmente a la izquierda (-width); 1 → derecha.
    final dx = bounds.width * (percent * 2 - 1);
    return Matrix4.translationValues(dx, 0, 0);
  }
}
