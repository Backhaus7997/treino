import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_motion.dart';

/// Ráfaga de confetti one-shot para el momento más celebratorio del flujo:
/// terminar un entreno completo — TREINO Motion (cobertura total, extensión
/// post-revisión).
///
/// **Puramente decorativo, sin gamificación**: no otorga puntos, XP ni
/// desbloquea nada — es celebración visual del cierre de una sesión completa
/// (`session.wasFullyCompleted`), el mismo gate que ya usa
/// [TreinoSuccessCheck]. Zona de scope confirmada explícitamente con el
/// producto antes de implementarse (Retos/Missions/Bets/Levels/XP siguen
/// fuera; esto no agrega ninguno de esos sistemas).
///
/// **Colores — excepción deliberada a "nunca HEX literal"**: a diferencia
/// del resto del kit, las partículas usan [_confettiColors], una paleta
/// fija y variada (no `AppPalette.accent`/`highlight`). Decisión de producto
/// explícita: un festejo con dos tonos de la marca se sentía chico — un
/// confetti de verdad necesita variedad de color que la paleta de dos
/// acentos de TREINO no tiene. Ver [_confettiColors] para el detalle.
///
/// **One-shot**: mismo contrato que [TreinoSuccessCheck] — genera las
/// partículas y arranca la caída SOLO en el primer mount del [State]; un
/// rebuild no vuelve a lanzar la ráfaga.
///
/// **Excepción documentada a implicit-first** (docs/performance.md, mismo
/// precedente que [TreinoSuccessCheck]/`TreinoShimmer`): física de N
/// partículas cayendo con drift lateral y rotación no tiene equivalente
/// implícito — hace falta [CustomPainter] recalculado por frame contra un
/// único [AnimationController].
///
/// **Reduce-motion** ([AppMotion.reduceMotion]): a diferencia del check, acá
/// no hay un "estado final" con sentido que mostrar de una — es movimiento
/// puro, así que con la preferencia activa el widget no renderiza nada (ni
/// arranca el controller). Si se activa a mitad de vuelo, la ráfaga se
/// detiene y desaparece en el frame siguiente.
///
/// **Duración**: [AppMotion.celebration] (1400ms) — deliberadamente fuera de
/// la escala micro/fast/base/slow, que mide feedback de UI, no un festejo
/// que nadie espera para seguir interactuando.
///
/// Se coloca con [Positioned.fill] por encima del contenido en un [Stack];
/// [IgnorePointer] interno asegura que nunca bloquea taps mientras cae.
///
/// ```dart
/// Stack(
///   children: [
///     summaryContent,
///     if (session.wasFullyCompleted)
///       const Positioned.fill(child: TreinoConfetti()),
///   ],
/// )
/// ```
class TreinoConfetti extends StatefulWidget {
  const TreinoConfetti({super.key, this.particleCount = 60, this.random});

  /// Cantidad de partículas de la ráfaga.
  final int particleCount;

  /// Generador de aleatoriedad. `null` → `math.Random()` no determinístico.
  /// Inyectable para tests que necesiten un resultado reproducible.
  final math.Random? random;

  @override
  State<TreinoConfetti> createState() => _TreinoConfettiState();
}

class _TreinoConfettiState extends State<TreinoConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<_ConfettiParticle> _particles = const [];

  /// One-shot: `true` una vez que el primer mount resolvió reduce-motion y
  /// (si aplica) generó las partículas. Los rebuilds no vuelven a entrar.
  bool _initialized = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.celebration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se resuelve acá (no en initState) porque reduce-motion necesita
    // MediaQuery — mismo patrón que TreinoSuccessCheck/TreinoShimmer.
    if (!_initialized) {
      _initialized = true;
      if (AppMotion.reduceMotion(context)) {
        _reduceMotion = true;
        return;
      }
      final rnd = widget.random ?? math.Random();
      _particles = List.generate(
        widget.particleCount,
        (_) => _ConfettiParticle.random(rnd),
      );
      _controller.forward();
    } else if (AppMotion.reduceMotion(context) && !_reduceMotion) {
      // La preferencia se activó en pleno vuelo → se corta, no hay estado
      // final con sentido para un festejo (a diferencia del check).
      setState(() {
        _reduceMotion = true;
        _controller.stop();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ConfettiPainter(
              progress: _controller.value,
              particles: _particles,
            ),
          ),
        ),
      ),
    );
  }
}

// intentional: excepción documentada a "nunca HEX literal" — ver el
// dartdoc de TreinoConfetti. Set fijo y variado, no ligado a AppPalette;
// deliberadamente NO usa Mint Magenta para que el festejo no se sienta como
// "dos tonos de la marca otra vez".
const _confettiColors = <Color>[
  Color(0xFFFF6B6B), // rojo coral
  Color(0xFFFFD93D), // amarillo
  Color(0xFF6BCB77), // verde
  Color(0xFF4D96FF), // azul
  Color(0xFFB983FF), // violeta
  Color(0xFFFF9F45), // naranja
  Color(0xFFFF6FB5), // rosa
];

/// Parámetros congelados de una partícula al momento de generarse — la
/// física en sí (posición/rotación/opacidad por frame) se resuelve en
/// [_ConfettiPainter.paint] a partir de estos valores + el progreso 0→1.
@immutable
class _ConfettiParticle {
  const _ConfettiParticle({
    required this.startX,
    required this.driftAmplitude,
    required this.driftPhase,
    required this.fallDelay,
    required this.fallDuration,
    required this.rotationSpeed,
    required this.size,
    required this.color,
  });

  factory _ConfettiParticle.random(math.Random rnd) {
    // Arranca la ráfaga escalonada dentro del primer cuarto del total — se
    // siente como una explosión, no como una fila prolija.
    final fallDelay = rnd.nextDouble() * 0.25;
    // fallDuration es una fracción de lo que QUEDA después de fallDelay
    // (nunca del total): así fallDelay + fallDuration <= 1.0 siempre, y
    // cada partícula termina su caída (incluido el fade) dentro de la
    // ventana del controller — ninguna queda a mitad de vuelo "clavada" en
    // pantalla cuando el controller se detiene en 1.0.
    final remaining = 1.0 - fallDelay;
    final fallDuration = remaining * (0.7 + rnd.nextDouble() * 0.3);
    return _ConfettiParticle(
      startX: rnd.nextDouble(),
      driftAmplitude: 12 + rnd.nextDouble() * 18,
      driftPhase: rnd.nextDouble() * 2 * math.pi,
      fallDelay: fallDelay,
      fallDuration: fallDuration,
      rotationSpeed:
          (rnd.nextBool() ? 1 : -1) * (2 + rnd.nextDouble() * 3) * math.pi,
      size: 6 + rnd.nextDouble() * 5,
      color: _confettiColors[rnd.nextInt(_confettiColors.length)],
    );
  }

  /// 0..1 — posición horizontal de origen, fracción del ancho disponible.
  final double startX;

  /// Amplitud en px del vaivén horizontal (sway) mientras cae.
  final double driftAmplitude;

  /// Offset de fase (radianes) del seno que genera el vaivén — desincroniza
  /// a las partículas entre sí aunque compartan amplitud/duración.
  final double driftPhase;

  /// 0..1 — fracción del progreso total del controller antes de que esta
  /// partícula empiece a caer.
  final double fallDelay;

  /// 0..1 — fracción del progreso total que esta partícula tarda en
  /// completar su caída desde [fallDelay].
  final double fallDuration;

  /// Radianes totales que rota la partícula a lo largo de toda su caída.
  final double rotationSpeed;

  /// Lado aproximado del rectángulo de la partícula, en px.
  final double size;

  final Color color;
}

/// Pinta cada partícula según su progreso local de caída, derivado del
/// progreso global del controller y los parámetros congelados en
/// [_ConfettiParticle]. Sin estado propio — todo el cómputo es puro por
/// frame a partir de [progress].
class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({required this.progress, required this.particles});

  /// 0..1 — valor actual del [AnimationController] compartido.
  final double progress;
  final List<_ConfettiParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final local = ((progress - particle.fallDelay) / particle.fallDuration)
          .clamp(0.0, 1.0);
      if (local <= 0) continue; // todavía no le toca arrancar

      // easeIn: acelera como si cayera por gravedad, no a velocidad constante.
      final eased = Curves.easeIn.transform(local);
      final y = eased * (size.height + particle.size);
      final x = particle.startX * size.width +
          math.sin(local * 2 * math.pi + particle.driftPhase) *
              particle.driftAmplitude;
      final rotation = local * particle.rotationSpeed;
      // Se desvanece en el último 15% de SU caída, no del total — cada
      // partícula "aterriza" con su propio fade, no todas de golpe.
      final opacity = local < 0.85 ? 1.0 : (1 - (local - 0.85) / 0.15);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      final paint = Paint()
        ..color = particle.color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size,
            height: particle.size * 0.55,
          ),
          Radius.circular(particle.size * 0.2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
