import 'package:flutter_riverpod/flutter_riverpod.dart';

/// De dónde sale "ahora" para la UI del entreno.
///
/// ── Por qué existe ────────────────────────────────────────────────────────
///
/// El cronómetro de un ejercicio por tiempo cuenta contra el RELOJ DE PARED, no
/// por ticks (ver `DurationTimerRules`). Esa es justamente la propiedad que
/// arregla el bug —una plancha de 60s ya no dura 70 si el sistema estrangula la
/// app— y es imposible de demostrar sin poder mover el reloj de pared y los
/// ticks POR SEPARADO: el tiempo falso de `tester.pump` mueve los dos juntos.
///
/// Con esta costura un test puede decir "pasaron 70 segundos y corrió UN tick",
/// que es exactamente el escenario que rompía. Sin ella, la única forma de
/// probarlo sería esperar segundos reales en la suite.
///
/// En producción es `DateTime.now` y nadie lo toca.
final workoutClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
