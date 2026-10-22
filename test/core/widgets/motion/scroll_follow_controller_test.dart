// La regla de ScrollFollowController, sin pantalla de por medio: 1:1 mientras
// el scroll es de lectura, resorte cuando es un fling. El reloj se inyecta para
// que cada test diga a qué velocidad scrollea; el resorte lo mueve el ticker
// del test (`tester.pump`).

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/core/widgets/motion/scroll_follow_controller.dart';

const _range = 64.0;
const _frame = Duration(milliseconds: 8); // 120 Hz, como un iPhone Pro

class _Harness {
  _Harness(WidgetTester tester, {double value = 1})
      : controller = ScrollFollowController(
          vsync: tester,
          range: _range,
          value: value,
          clock: () => _now,
        );

  static Duration _now = Duration.zero;
  final ScrollFollowController controller;

  /// Un frame nuevo: avanza el reloj del scroll y el del ticker juntos.
  Future<void> frame(WidgetTester tester) async {
    _now += _frame;
    await tester.pump(_frame);
  }

  /// Un evento de scroll de [px] (positivo = compacta), en el frame actual.
  void scroll(double px, {bool reduceMotion = false}) => controller.follow(
        controller.target - px / _range,
        reduceMotion: reduceMotion,
      );
}

/// Cada test con su controller, desechado ANTES de que el test termine: un
/// resorte a medias es un ticker activo, y el framework lo reporta como fuga
/// si el dispose queda para el tearDown.
void _testFollow(
  String description,
  Future<void> Function(WidgetTester tester, _Harness h) body,
) {
  testWidgets(description, (tester) async {
    final h = _Harness(tester);
    await body(tester, h);
    h.controller.dispose();
  });
}

void main() {
  setUp(() => _Harness._now = Duration.zero);

  _testFollow('scroll de lectura: la barra va exacto a donde manda el dedo',
      (tester, h) async {
    // 4 px por frame de 8 ms = 500 px/s.
    for (var i = 1; i <= 8; i++) {
      await h.frame(tester);
      h.scroll(4);
      expect(h.controller.value, closeTo(1 - 4 * i / _range, 1e-9),
          reason: 'frame $i: 1:1, sin retraso');
      expect(h.controller.isChasing, isFalse);
    }
  });

  _testFollow('justo en el umbral todavía sigue 1:1', (tester, h) async {
    await h.frame(tester);
    h.scroll(1);
    await h.frame(tester);

    // Exactamente maxTrackingSpeed durante un frame.
    // (Un pelo menos, para no depender del redondeo de la división.)
    final px = ScrollFollowController.maxTrackingSpeed *
        0.999 *
        _frame.inMicroseconds /
        1e6;
    h.scroll(px);

    expect(h.controller.value, closeTo(1 - (1 + px) / _range, 1e-9));
    expect(h.controller.isChasing, isFalse);
  });

  _testFollow('fling: no salta en un frame, persigue y llega',
      (tester, h) async {
    await h.frame(tester);
    h.scroll(1);

    // 48 px en un frame de 8 ms = 6000 px/s: la carrera entera en 2 frames.
    final dibujado = <double>[];
    for (var i = 0; i < 2; i++) {
      await h.frame(tester);
      h.scroll(48);
      dibujado.add(h.controller.value);
    }
    expect(h.controller.target, 0, reason: 'el scroll ya pidió compacta');
    expect(h.controller.isChasing, isTrue);
    expect(dibujado.last, greaterThan(0.5),
        reason: 'a 1:1 ya estaría en 0; con el resorte recién arranca');

    // Ningún frame mueve más de un cuarto de carrera.
    var antes = h.controller.value;
    var frames = 0;
    while (h.controller.value > 0) {
      await h.frame(tester);
      expect(antes - h.controller.value, lessThan(0.25),
          reason: 'frame $frames: sin escalones');
      antes = h.controller.value;
      frames++;
      expect(frames, lessThan(60), reason: 'tiene que terminar');
    }
    expect(h.controller.value, 0, reason: 'llega exacto, no a 0.0004');
    expect(frames * _frame.inMilliseconds, inInclusiveRange(150, 400),
        reason: 'la persecución dura lo que un resorte de 0,25 s');
  });

  _testFollow('scroll lento en pleno resorte: no lo corta de golpe',
      (tester, h) async {
    await h.frame(tester);
    h.scroll(1);
    await h.frame(tester);
    h.scroll(60); // fling: arranca el resorte
    await h.frame(tester);
    final antes = h.controller.value;
    expect(h.controller.isChasing, isTrue);

    // El fling decelera: el target casi no cambia, pero el dibujado está
    // lejos. Saltar al target sería el escalón que esto vino a sacar.
    h.scroll(1);
    expect((antes - h.controller.value).abs(), lessThan(0.25));
    expect(h.controller.isChasing, isTrue);
  });

  _testFollow('re-apuntar no frena: la velocidad sigue al cambiar de target',
      (tester, h) async {
    await h.frame(tester);
    h.scroll(1);
    await h.frame(tester);
    h.scroll(63); // va a 0
    for (var i = 0; i < 4; i++) {
      await h.frame(tester);
    }
    final velocidad = h.controller.animation.velocity;
    expect(velocidad, lessThan(0));

    h.controller
        .settleTo(0, duration: AppMotion.fast, curve: AppMotion.standard);
    expect(h.controller.animation.velocity, velocidad,
        reason: 'mismo target: el resorte sigue como venía');
  });

  _testFollow('soltar a medias asienta del lado más cercano',
      (tester, h) async {
    for (var i = 0; i < 5; i++) {
      await h.frame(tester);
      h.scroll(4); // 20 px lentos: queda en ~0,69
    }
    final t = h.controller.target;
    h.controller.settleTo(
      t < 0.5 ? 0 : 1,
      duration: AppMotion.fast,
      curve: AppMotion.standard,
    );
    expect(h.controller.animation.isAnimating, isTrue,
        reason: 'el asentado se anima, no salta');
    await tester.pumpAndSettle();
    expect(h.controller.value, 1);
  });

  _testFollow('con «reducir movimiento» el fling va directo, sin resorte',
      (tester, h) async {
    await h.frame(tester);
    h.scroll(64, reduceMotion: true);

    expect(h.controller.value, 0);
    expect(h.controller.animation.isAnimating, isFalse);
  });

  _testFollow('varios eventos en el mismo frame cuentan como uno grande',
      (tester, h) async {
    await h.frame(tester);
    h.scroll(1);
    await h.frame(tester);
    // Cuatro eventos de 10 px en el mismo frame = 40 px en 8 ms = 5000 px/s.
    // Medidos de a uno (10 px) serían 1250 px/s: casi en el umbral.
    for (var i = 0; i < 4; i++) {
      h.scroll(10);
    }
    expect(h.controller.isChasing, isTrue);
  });

  _testFollow('jumpTo pone el valor de una y corta la persecución',
      (tester, h) async {
    await h.frame(tester);
    h.scroll(1);
    await h.frame(tester);
    h.scroll(63);
    expect(h.controller.isChasing, isTrue);

    h.controller.jumpTo(1);
    expect(h.controller.value, 1);
    expect(h.controller.animation.status, AnimationStatus.completed);
    expect(h.controller.isChasing, isFalse);
  });
}
