import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';

/// Número que cuenta ascendiendo desde 0 hasta [value] al montarse — TREINO
/// Motion (cobertura total, B1). Para la cifra protagonista de un momento de
/// éxito (kg totales, sets, streak, PRs) — un [Text] normal alcanza para
/// cualquier otro número de la app; este widget es para el momento hero, no
/// para reemplazar cada cifra.
///
/// **Implícito** ([TweenAnimationBuilder], doctrina implicit-first
/// docs/performance.md): sin [AnimationController] propio. Si [value] cambia
/// entre rebuilds (p. ej. Riverpod re-emite con una cifra distinta),
/// [TweenAnimationBuilder] anima desde el valor actualmente en pantalla
/// hacia el nuevo — no vuelve a arrancar en 0.
///
/// **Reduce-motion** ([AppMotion.reduceMotion] vía [AppMotion.resolve]):
/// [duration] resuelve a [Duration.zero] → el valor final se muestra directo
/// (mismo criterio que [TreinoStateSwitcher]: con paso cero no hay frame
/// intermedio perceptible, solo hace falta un pump extra en tests).
///
/// ```dart
/// TreinoCountUp(
///   value: session.totalVolumeKg,
///   formatter: (v) => formatVolumeKg(v.round()),
///   style: statValueStyle,
/// ),
/// ```
class TreinoCountUp extends StatelessWidget {
  const TreinoCountUp({
    super.key,
    required this.value,
    this.duration = AppMotion.slow,
    this.style,
    this.textAlign,
    this.formatter,
  });

  /// Valor final al que cuenta. El conteo siempre arranca en 0.
  final num value;

  /// Duración del conteo completo (0 → [value]). Pasa por
  /// [AppMotion.resolve] — reduce-motion la fuerza a [Duration.zero].
  final Duration duration;

  final TextStyle? style;
  final TextAlign? textAlign;

  /// Formatea el valor animado a texto en cada frame — recibe el valor
  /// INTERPOLADO (fraccional, no solo el final), así que si el caller
  /// necesita enteros debe redondear adentro (`(v) => v.round().toString()`
  /// + unidad/separador). `null` → redondeado a entero plano, sin
  /// separadores de miles.
  final String Function(num value)? formatter;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: AppMotion.resolve(context, duration),
      curve: AppMotion.standard,
      builder: (context, animated, _) {
        final text = formatter != null
            ? formatter!(animated)
            : animated.round().toString();
        return Text(text, style: style, textAlign: textAlign);
      },
    );
  }
}
