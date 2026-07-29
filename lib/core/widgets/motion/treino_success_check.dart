import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';

/// Check dentro de un círculo que se DIBUJA one-shot al montarse — TREINO
/// Motion (cobertura total, B1). Feedback de un momento de éxito claro
/// (guardar medida, enviar review, completar un flujo) sin caer en badge de
/// achievement: un trazo, no un relleno — sobrio, estilo Hevy. Para el único
/// momento del producto que sí justifica algo más festivo (terminar un
/// entreno completo), ver [TreinoConfetti] — se usa junto a este widget, no
/// en su reemplazo.
///
/// **Trazo, no relleno**: el círculo y el check se pintan como stroke del
/// [color] (default `AppPalette.accent`) — nunca un ícono relleno tipo
/// badge. El círculo dibuja su contorno primero (0%→100% de arco, sentido
/// horario desde las 12) solapando con el check, que empieza a trazar su
/// primer segmento a mitad del arco del círculo y termina junto con él —
/// se percibe como un solo trazo continuo, no dos animaciones en serie.
///
/// **One-shot**: mismo contrato que [TreinoFadeSlideIn] — anima SOLO en el
/// primer mount del [State]; un rebuild no reinicia el dibujo.
///
/// **Implementación — controller one-shot + [CustomPainter]** (excepción
/// documentada a implicit-first, docs/performance.md, mismo precedente que
/// [TreinoFadeSlideIn]/`TreinoShimmer`): trazar un path parcial (el arco del
/// círculo, los segmentos del check) no tiene equivalente implícito — hace
/// falta [Canvas.drawArc] y [PathMetric.extractPath] recalculados por frame
/// según el progreso de la animación.
///
/// **Reduce-motion** ([AppMotion.reduceMotion]): dibuja el trazo completo
/// (círculo + check) de una, sin animar — mismo criterio que
/// [TreinoFadeSlideIn].
///
/// ```dart
/// const TreinoSuccessCheck(size: 72),
/// ```
class TreinoSuccessCheck extends StatefulWidget {
  const TreinoSuccessCheck({
    super.key,
    this.size = 64,
    this.color,
    this.strokeWidth = 4,
  });

  /// Lado del box cuadrado que ocupa el widget, en px.
  final double size;

  /// Color del trazo (círculo + check). `null` → `AppPalette.accent`.
  final Color? color;

  /// Grosor del trazo, en px.
  final double strokeWidth;

  @override
  State<TreinoSuccessCheck> createState() => _TreinoSuccessCheckState();
}

class _TreinoSuccessCheckState extends State<TreinoSuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _circleProgress;
  late final Animation<double> _checkProgress;

  /// One-shot: `true` una vez que el primer mount decidió animar (o saltar
  /// directo al final por reduce-motion). Los rebuilds no vuelven a entrar.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.slow);
    // El check arranca a mitad del arco del círculo (Interval solapado): se
    // siente como un solo trazo continuo, no dos animaciones en serie.
    _circleProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.6, curve: AppMotion.standard),
    );
    _checkProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 1, curve: AppMotion.standard),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se resuelve acá (no en initState) porque reduce-motion necesita
    // MediaQuery — mismo patrón que TreinoFadeSlideIn/TreinoShimmer.
    if (!_started) {
      _started = true;
      if (AppMotion.reduceMotion(context)) {
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
    final color = widget.color ?? AppPalette.of(context).accent;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _SuccessCheckPainter(
              circleProgress: _circleProgress.value,
              checkProgress: _checkProgress.value,
              color: color,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinta el arco del círculo y el trazo parcial del check. Progreso 0→1 en
/// ambos; ver [TreinoSuccessCheck] para el porqué del Interval solapado.
class _SuccessCheckPainter extends CustomPainter {
  const _SuccessCheckPainter({
    required this.circleProgress,
    required this.checkProgress,
    required this.color,
    required this.strokeWidth,
  });

  final double circleProgress;
  final double checkProgress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (circleProgress > 0) {
      final rect = Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      );
      // Arranca a las 12 (-90°) y avanza en sentido horario.
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * circleProgress,
        false,
        paint,
      );
    }

    if (checkProgress > 0) {
      canvas.drawPath(_partialCheckPath(size), paint);
    }
  }

  /// Extrae el primer [checkProgress] de la longitud total del check — mismo
  /// patrón que el cookbook de Flutter para "animated path drawing".
  Path _partialCheckPath(Size size) {
    final full = Path()
      ..moveTo(size.width * 0.24, size.height * 0.52)
      ..lineTo(size.width * 0.43, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.30);
    final partial = Path();
    for (final metric in full.computeMetrics()) {
      partial.addPath(
        metric.extractPath(0, metric.length * checkProgress),
        Offset.zero,
      );
    }
    return partial;
  }

  @override
  bool shouldRepaint(covariant _SuccessCheckPainter oldDelegate) =>
      oldDelegate.circleProgress != circleProgress ||
      oldDelegate.checkProgress != checkProgress ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
