import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// La capacidad de DAR DE BAJA la suscripción, como tipo sellado.
///
/// Espejo de `plan_checkout.dart`, y por el mismo motivo: la superficie que
/// puede hacerlo es una sola, y el tipo lo hace cumplir en compilación en vez
/// de con un `if` que alguien puede mover.
///
/// ── Por qué la baja también vive sólo en la web ──
///
/// No es la Guideline 3.1.3: dar de baja no es una compra, y Apple no prohíbe
/// cancelar dentro de la app —de hecho exige lo contrario cuando el cobro pasó
/// por la tienda—. El motivo es más simple y es de producto: **el PF contrata
/// en el Coach Hub, y la Res. 424/2020 exige que pueda darse de baja por el
/// mismo medio**. Ese medio es la web.
///
/// Ponerla además en el teléfono no estaría prohibido, pero sí obligaría a
/// mantener dos superficies para una acción irreversible, y la del teléfono no
/// tiene dónde mostrar el estado de la suscripción que la justifica.
sealed class PlanCancel {
  const PlanCancel._();
}

/// Lo que devuelve el servidor, traducido al vocabulario de la pantalla.
enum EstadoDeBaja {
  /// Se le pidió la baja a Mercado Pago y la aceptó.
  dadaDeBaja,

  /// No había nada que dar de baja. **No es un error.**
  sinSuscripcion,

  /// Mercado Pago no contestó. NO se escribió nada: se puede reintentar.
  noDisponible,

  /// El servidor cortó por cooldown y **no le preguntó a Mercado Pago**.
  ///
  /// ── Por qué esto necesita su propio estado ──
  ///
  /// El servidor devuelve `sin-suscripcion` con `enfriando: true` cuando la
  /// baja anterior fue hace menos de diez segundos. Sin distinguirlo, este
  /// camino termina mintiendo:
  ///
  ///   1. El PF aprieta DAR DE BAJA. El servidor marca el cooldown **antes**
  ///      de salir a MP (`cancel-my-subscription.ts`, es deliberado), llama, y
  ///      MP no contesta.
  ///   2. El diálogo dice bien: «tu suscripción SIGUE como estaba».
  ///   3. El PF hace exactamente lo que le dijimos y reintenta enseguida.
  ///   4. El servidor corta por cooldown → `sin-suscripcion`.
  ///   5. El diálogo diría «NO HAY NADA QUE DAR DE BAJA».
  ///
  /// El paso 5 es **falso**: la suscripción sigue viva y cobrando, y se le
  /// acaba de decir que se quede tranquilo. En el único camino de baja que la
  /// Res. 424/2020 obliga a tener.
  enfriando,
}

/// El resultado de pedir la baja.
class ResultadoDeBaja {
  const ResultadoDeBaja({required this.estado, this.accesoHasta});

  final EstadoDeBaja estado;

  /// Hasta cuándo conserva el acceso. Es lo que la pantalla tiene que decir, y
  /// lo que hace verdadera la promesa del §7 de los Términos de Suscripción.
  ///
  /// Puede ser `null` aunque la baja haya salido bien: un plan recién creado
  /// cuyo `auto_recurring` MP todavía no completó no tiene de dónde derivarla.
  /// La pantalla tiene que poder decir «se dio de baja» sin la fecha.
  final DateTime? accesoHasta;
}

/// Superficie que SÍ puede dar de baja: el Coach Hub web.
final class PlanCancelAvailable extends PlanCancel {
  const PlanCancelAvailable._() : super._();

  /// Le pide la baja al servidor.
  ///
  /// **No manda ningún parámetro, y eso es la cerradura.** Si un `planId`
  /// viajara en el request, cualquiera podría darle de baja la suscripción a
  /// otro — y en Mercado Pago eso no se deshace: un preapproval cancelado no se
  /// reactiva, hay que crear uno nuevo con otro id.
  ///
  /// Total: nunca tira. Un fallo sale como [EstadoDeBaja.noDisponible], que la
  /// pantalla traduce a «probá de nuevo» sin mentirle al PF sobre si se dio de
  /// baja o no.
  Future<ResultadoDeBaja> cancelar() async {
    try {
      return await (debugPlanCancelCaller ?? _cancelar)();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('plan_cancel: el servidor rechazó la baja (${e.code})');
      return const ResultadoDeBaja(estado: EstadoDeBaja.noDisponible);
    } catch (_) {
      return const ResultadoDeBaja(estado: EstadoDeBaja.noDisponible);
    }
  }
}

/// Superficie que NO da de baja: la app móvil.
///
/// No tiene `cancelar`, ni un `enabled`, ni un callback nullable: no hay nada
/// que encender. Ver el encabezado.
final class PlanCancelOnWebOnly extends PlanCancel {
  const PlanCancelOnWebOnly._() : super._();
}

const String _kRegion = 'southamerica-east1';

Future<ResultadoDeBaja> _cancelar() async {
  final res = await FirebaseFunctions.instanceFor(region: _kRegion)
      .httpsCallable('cancelMySubscription')
      .call<Map<String, dynamic>>();

  return resultadoDesde(res.data);
}

/// Traduce la respuesta cruda del servidor.
///
/// ── Por qué esto es una función aparte y no está adentro de `_cancelar` ──
///
/// Porque `debugPlanCancelCaller` reemplaza la llamada ENTERA, parseo incluido.
/// Mientras esto vivió adentro, ningún test tocaba una sola línea de este
/// código: los tests inyectaban un `ResultadoDeBaja` ya armado.
///
/// No es una hipótesis. Cuando se agregó [EstadoDeBaja.enfriando] se escribieron
/// dos tests, los dos pasaron, y **borrar el chequeo de `enfriando` no rompió
/// ninguno**: verificaban que el diálogo sabe dibujar el estado, no que el
/// parseo sepa producirlo. Con el parseo acá afuera, el mismo experimento pone
/// tests en rojo.
@visibleForTesting
ResultadoDeBaja resultadoDesde(Map<String, dynamic> data) {
  // `enfriando` se mira ANTES que el estado: el servidor manda
  // `sin-suscripcion` junto con la bandera, y quedarse con el estado a secas
  // es justo el bug que documenta `EstadoDeBaja.enfriando`.
  if (data['enfriando'] == true) {
    return const ResultadoDeBaja(estado: EstadoDeBaja.enfriando);
  }

  final estado = switch (data['estado']) {
    'dada-de-baja' => EstadoDeBaja.dadaDeBaja,
    'sin-suscripcion' => EstadoDeBaja.sinSuscripcion,
    // Cualquier valor que no conozcamos cae en `noDisponible` y NO en
    // `dadaDeBaja`: decirle a alguien que se dio de baja cuando no sabemos si
    // pasó es la peor de las tres respuestas posibles.
    _ => EstadoDeBaja.noDisponible,
  };

  final iso = data['accesoHastaIso'];
  return ResultadoDeBaja(
    estado: estado,
    accesoHasta: iso is String ? DateTime.tryParse(iso) : null,
  );
}

/// Resuelve la superficie. `kIsWeb` es constante de COMPILACIÓN, así que el
/// árbol de la otra rama ni siquiera entra al binario.
PlanCancel resolvePlanCancel() =>
    debugPlanCancel ?? planCancelFor(isWeb: kIsWeb);

@visibleForTesting
PlanCancel planCancelFor({required bool isWeb}) =>
    isWeb ? const PlanCancelAvailable._() : const PlanCancelOnWebOnly._();

/// Inyecta la llamada al servidor. SÓLO para tests.
///
/// El seam va acá y no sobre `FirebaseFunctions` por el mismo motivo que en
/// `plan_checkout.dart`: a la pantalla le importa «se dio de baja, o no», y esa
/// es la frontera que conviene mover — la de la red, no la del SDK.
@visibleForTesting
Future<ResultadoDeBaja> Function()? debugPlanCancelCaller;

/// Fuerza la superficie. SÓLO para tests: bajo `flutter test` `kIsWeb` es
/// `false`, así que sin esto el camino web sería inalcanzable en la suite.
@visibleForTesting
PlanCancel? debugPlanCancel;
