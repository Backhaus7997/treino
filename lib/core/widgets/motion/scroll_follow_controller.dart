import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lleva un valor de 0 a 1 que SIGUE AL SCROLL, sin dejar que un scroll muy
/// rápido lo haga saltar.
///
/// Lo usan las dos barras que acompañan al scroll: la nav bar del shell (que
/// se compacta) y [TreinoCollapsingTopBar] (que aparece). El problema que
/// resuelve es el mismo en las dos: seguir 1:1 está bien mientras el scroll
/// es de lectura, pero un fling recorre los 64-72 px de carrera de la barra
/// en dos o tres frames, y la barra se ve aparecer o desaparecer de golpe.
///
/// La regla es una sola, por frame:
///
/// - Si llegar al valor que pide el scroll ([target]) no supera
///   [maxTrackingSpeed], la barra va EXACTAMENTE ahí. Es el 1:1 de siempre:
///   frenar a mitad la deja a mitad.
/// - Si lo supera, la barra no salta: lo persigue con un resorte críticamente
///   amortiguado ([chaseSpring]) que arranca desde donde está y con la
///   velocidad que traía. Un target nuevo a mitad de camino re-apunta el
///   resorte sin cortar la velocidad, así que no hay frenazo al cambiar de
///   dirección.
///
/// Con «reducir movimiento» no hay persecución: el valor va directo a
/// [target], igual que antes de este controller.
///
/// El estado vive en [animation] (un [AnimationController]) y no en
/// `setState`: quien dibuja la barra la escucha con un `AnimatedBuilder` o un
/// `ValueListenableBuilder`, y el resto de la pantalla no se reconstruye.
class ScrollFollowController {
  ScrollFollowController({
    required TickerProvider vsync,
    required this.range,
    double value = 0,
    Duration Function()? clock,
  })  : _clock = clock ?? _frameClock,
        _target = value,
        _anchorValue = value,
        animation = AnimationController(vsync: vsync, value: value);

  /// Velocidad máxima, en px de scroll por segundo, a la que la barra sigue
  /// 1:1.
  ///
  /// Un scroll de lectura con el dedo anda en 100-600 px/s; un fling en iOS
  /// suelta a 1500-6000. A 1200 px/s los 64 px de la nav bar se recorren en
  /// ~53 ms (6 frames a 120 Hz): por debajo se ve el seguimiento, por encima
  /// ya es un salto. Es el punto donde 1:1 deja de leerse como movimiento.
  static const double maxTrackingSpeed = 1200;

  /// Resorte de la persecución: amortiguamiento crítico (sin rebote: la barra
  /// es cromo, no algo que el usuario tiró) y una respuesta de 0,25 s, que
  /// asienta al 99 % en ~260 ms. Rigidez = (2π / respuesta)².
  static final SpringDescription chaseSpring =
      SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: math.pow(2 * math.pi / 0.25, 2).toDouble(),
    ratio: 1,
  );

  /// Si entre dos frames pasó más que esto, el scroll estuvo quieto: la
  /// velocidad se mide como si hubiera pasado este tiempo, para que el primer
  /// evento después de una pausa no cuente como lento ni como rápido de más.
  static const double _maxFrameGap = 0.1;

  /// Frame nominal para el primer evento, cuando todavía no hay uno anterior
  /// contra el que medir.
  static const double _nominalFrame = 1 / 60;

  /// Px de scroll que lleva pasar de 0 a 1.
  final double range;

  /// El valor que se dibuja. 0..1.
  final AnimationController animation;

  final Duration Function() _clock;

  double _target;
  bool _chasing = false;

  // Lo que había al empezar el frame actual. Varios eventos de scroll pueden
  // caer en el mismo frame: la velocidad se mide contra el frame anterior, no
  // contra el evento anterior, así un frame con tres eventos chicos cuenta lo
  // mismo que uno con un evento grande.
  Duration? _frameStamp;
  Duration? _anchorStamp;
  double _anchorValue;

  static Duration _frameClock() =>
      SchedulerBinding.instance.currentFrameTimeStamp;

  double get value => animation.value;

  /// A dónde quiere llevar el scroll la barra. Es distinto de [value] sólo
  /// mientras persigue.
  double get target => _target;

  /// `true` mientras un scroll rápido la tiene persiguiendo a [target].
  bool get isChasing => _chasing && animation.isAnimating;

  /// Pide que la barra muestre [next] (se acota a 0..1).
  void follow(double next, {required bool reduceMotion}) {
    final target = next.clamp(0.0, 1.0).toDouble();
    final now = _clock();
    if (now != _frameStamp) {
      _anchorStamp = _frameStamp;
      _anchorValue = animation.value;
      _frameStamp = now;
    }
    final unchanged = target == _target;
    _target = target;

    if (reduceMotion) {
      _jump(target);
      return;
    }
    // El resorte ya va para ahí: dejarlo terminar. Cortarlo al llegar cerca
    // le comería la cola, que es justo lo que lo hace suave.
    if (isChasing && unchanged) return;

    final anchor = _anchorStamp;
    final dt = anchor == null
        ? _nominalFrame
        : math.min((now - anchor).inMicroseconds / 1e6, _maxFrameGap);
    final speed =
        dt <= 0 ? double.infinity : (target - _anchorValue).abs() * range / dt;

    if (speed <= maxTrackingSpeed) {
      _jump(target);
    } else {
      _chase(target);
    }
  }

  /// Asienta la barra en [to] (0 o 1) al soltar. Si está persiguiendo,
  /// re-apunta el resorte y conserva la velocidad; si no, anima con
  /// [duration] y [curve] desde donde quedó.
  void settleTo(double to, {required Duration duration, required Curve curve}) {
    // Ya va para ahí (se llama en cada evento dentro de la zona del tope).
    if (to == _target && animation.isAnimating) return;
    _target = to;
    if (isChasing && duration > Duration.zero) {
      _chase(to);
      return;
    }
    _chasing = false;
    if (animation.value == to && !animation.isAnimating) return;
    if (duration == Duration.zero) {
      _jump(to);
      return;
    }
    animation.animateTo(to, duration: duration, curve: curve);
  }

  /// Pone el valor de una, sin animar (cambio de tab, pantalla nueva).
  void jumpTo(double to) {
    _target = to;
    _jump(to);
  }

  void _jump(double to) {
    _chasing = false;
    if (animation.isAnimating) animation.stop();
    animation.value = to;
  }

  void _chase(double to) {
    _chasing = true;
    animation.animateWith(
      SpringSimulation(
        chaseSpring,
        animation.value,
        to,
        // Hereda la velocidad que traía: re-apuntar no frena en seco.
        animation.isAnimating ? animation.velocity : 0,
        snapToEnd: true,
      ),
    );
  }

  void dispose() => animation.dispose();
}
