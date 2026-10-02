import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_vigencia.dart';
import 'package:treino/features/profile/application/user_providers.dart';

/// Lo más que espera el timer del próximo borde: un minuto. Hay dos motivos,
/// y los dos muerden.
///
/// 1. **La web.** Sin tope, una baja con un mes por delante la ROMPE. El
///    runtime JS de Dart le pasa `inMilliseconds` a `setTimeout` sin acotarlo
///    (`js_runtime/lib/async_patch.dart` del SDK), y `setTimeout` toma la
///    demora como entero de 32 bits con signo: 30 días son 2.592.000.000 ms,
///    que no entran. Medido el 2026-10-02 con Node: dispara al milisegundo,
///    con un `TimeoutOverflowWarning`. En el navegador el `timeout` es un
///    `long` de WebIDL, se va a negativo, y el spec de HTML lo lleva a 0. El
///    timer dispararía en el acto, la vigencia saldría igual, agendaría otro
///    timer idéntico, y así en loop.
/// 2. **El provider GUARDA la vigencia.** Reconstruir el widget ya no la
///    recalcula, como pasaba cuando cada build sacaba su foto. Si el timer
///    llega tarde por lo que sea, la única corrección es la próxima
///    re-evaluación. Con el tope, eso es a lo sumo un minuto. Con un tope de
///    un día, el chip podía quedar viejo horas aunque el PF navegara.
///
/// Re-evaluar cada minuto es barato, y los widgets miran sólo el tier con
/// `select`, así que no se reconstruyen hasta que cambia.
const Duration _kTopeDeEspera = Duration(minutes: 1);

/// Cuánto esperar, desde [ahora], para recalcular una vigencia que deja de
/// valer en [cambio]: lo que falta, sin pasarse de un minuto.
@visibleForTesting
Duration esperaHasta(DateTime cambio, {required DateTime ahora}) {
  final falta = cambio.difference(ahora);
  return falta < _kTopeDeEspera ? falta : _kTopeDeEspera;
}

/// La [VigenciaDelPlan] del PF logueado, que se recalcula SOLA al cruzar un
/// borde.
///
/// [VigenciaDelPlan.de] es una foto. Un widget que la calcula en su build y
/// sigue montado cuando vence la baja sigue mostrando el plan pago hasta que
/// algo lo reconstruya. Este provider espera hasta
/// [VigenciaDelPlan.proximoCambio] y se invalida a sí mismo ahí.
///
/// `autoDispose` y SIN `keepAlive`, a propósito: el timer se cancela en
/// `onDispose`. Con `keepAlive`, el provider no se descarta cuando se va el
/// último que lo mira y su timer le sobrevive. Copiar la ventana de gracia de
/// los vínculos a otro provider tumbó así un widget test ajeno, con
/// `!timersPending`.
final vigenciaDelPlanProvider = Provider.autoDispose<VigenciaDelPlan>((ref) {
  // Sólo la suscripción: que cambie el nombre o la foto del PF no tiene por
  // qué recalcular ni reagendar nada. `TrainerSubscription` es freezed, así
  // que el `select` compara por valor.
  final suscripcion = ref.watch(
    userProfileProvider.select((perfil) => perfil.valueOrNull?.subscription),
  );
  // El MISMO instante para calcular y para medir la espera: con dos lecturas
  // del reloj, la espera quedaría corrida por lo que tardó la primera.
  final ahora = AppClock.now();
  final vigencia = VigenciaDelPlan.de(suscripcion, now: ahora);

  final cambio = vigencia.proximoCambio;
  if (cambio != null) {
    final timer = Timer(esperaHasta(cambio, ahora: ahora), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return vigencia;
});
