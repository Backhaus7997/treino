/// Dónde puede el ALUMNO comprar su suscripción a TREINO.
///
/// Este archivo es el espejo de `plan_checkout.dart` —el del entrenador— con
/// **la polaridad invertida**, y esa inversión es todo el diseño:
///
///   | | Entrenador | Alumno |
///   |---|---|---|
///   | Cobra en | la web (Coach Hub) | la app móvil (IAP) |
///   | Comisión | ~4-6% de Mercado Pago | 15% de la tienda |
///   | La regla | 3.1.3(f) lo exime | 3.1.1 lo obliga |
///
/// ─── Por qué al alumno SÍ le cobramos por IAP y al profe no ───
///
/// La Guideline 3.1.3(f) exime del in-app purchase a una *"free app acting as
/// a stand-alone companion to a paid web based tool"*. El Coach Hub **es** esa
/// herramienta web paga: el profe arma rutinas, gestiona alumnos y factura
/// ahí. La exención le aplica de verdad.
///
/// Para el ALUMNO no existe ninguna superficie web. Sin web no hay
/// *"paid web based tool"* de la cual ser companion, y sin eso no hay exención
/// que invocar: cae 3.1.1 y la compra tiene que pasar por la tienda.
///
/// No es una preferencia. Es la única puerta que quedaba abierta.
///
/// ─── Por qué un tipo sellado, otra vez ───
///
/// El del profe ya sobrevivió a su cableado real: *"el CTA cobra de verdad
/// desde que se cableó Mercado Pago, y el cableado fue exactamente eso:
/// cambiar el cuerpo de `start` y nada más"*. Se usa el mismo patrón acá, con
/// los constructores privados a esta librería: desde `lib/` la única forma de
/// conseguir un [AthleteCheckoutOnStore] es [resolveAthleteCheckout].
///
/// Pero acá el sellado cuida algo distinto, y conviene decirlo para que nadie
/// lo copie por analogía y falle: en el del profe el tipo impide que la app
/// móvil VENDA. Acá impide lo contrario — que se intente vender desde una
/// superficie que **no puede cobrar**: el build web, o un binario sin la clave
/// del SDK configurada. En los dos casos el resultado sería un botón que
/// promete una salida que no existe.
///
/// ─── El uid no es opcional, y por eso entra por la firma ───
///
/// RevenueCat identifica al comprador con un `app_user_id`. Si la compra se
/// hace de forma anónima, RevenueCat le inventa un id, el webhook recibe ESE
/// id, no encuentra ningún `users/{uid}` que le corresponda, y contesta 200
/// sin acreditar nada. El alumno pagó y no tiene nada.
///
/// Es un bug que no falla ruidosamente: falla en silencio, en producción, y
/// después de que alguien puso plata. Por eso [AthleteCheckoutOnStore.start]
/// **exige el uid como parámetro** y hace el `logIn` antes de comprar, en vez
/// de dejarlo colgando de un `initState` en otro archivo que alguien puede
/// olvidarse de cablear.
library;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Se re-exporta a proposito: quien consume la capacidad necesita tambien
// `AthletePlanOferta`, y pedirle dos imports para una sola idea es ruido.
export 'athlete_store.dart';

import 'athlete_store.dart';
import 'revenuecat_store.dart' show crearRevenueCatStore;

/// Qué está comprando el alumno.
///
/// Son los dos package types estándar de RevenueCat, y se usan los estándar a
/// propósito: la doc recomienda no inventar identifiers custom, porque los
/// estándar son los que el dashboard entiende para armar los Offerings.
enum AthletePlan {
  mensual,
  anual,
}

/// Cómo terminó un intento de compra.
///
/// `cancelado` NO es un error y por eso tiene su propio caso: el alumno que
/// cierra la hoja de pago de Apple tomó una decisión, no chocó con una falla.
/// Mezclarlo con `error` hace que la UI le muestre un cartel rojo a alguien
/// que simplemente dijo que no.
enum AthletePurchaseOutcome {
  /// La tienda cobró y RevenueCat ya reconoce el entitlement.
  comprado,

  /// El alumno cerró el diálogo de pago.
  cancelado,

  /// Android, pago diferido: el alumno eligió pagar en efectivo o el emisor
  /// pidió una confirmación. La compra NO está hecha todavía, y va a llegar
  /// por el webhook cuando se concrete. No mostrar "listo", tampoco un error.
  pendiente,

  /// El plan pedido no está en el Offering actual. Es un error de
  /// CONFIGURACIÓN del dashboard, no del alumno.
  sinProducto,

  /// Cualquier otra cosa: red caída, tienda rota, la cuenta del alumno con un
  /// problema de facturación.
  error,
}

/// El entitlement que otorga el paywall del alumno.
///
/// Tiene que coincidir carácter por carácter con el lookup key del dashboard de
/// RevenueCat **y** con `ENTITLEMENT_ALUMNO` de `functions/src/subscriptions/rc/webhook.ts`.
///
/// Este string queda COMPILADO en el binario instalado: renombrarlo rompe a
/// todo el que tenga una versión vieja de la app. Por eso describe el ACCESO y
/// no el plan que lo vende.
const String kAthleteEntitlement = 'alumno_pro';

/// Dónde puede comprar el alumno. Sellada: ver el encabezado.
sealed class AthleteCheckout {
  const AthleteCheckout._();
}

/// La superficie que NO puede cobrar.
///
/// Dos casos, y los dos son legítimos:
///   - el build **web** (Coach Hub), donde no hay tienda que cobre;
///   - un binario móvil **sin la clave del SDK**, que es el estado de hoy.
///
/// No expone `start`. No es la compra apagada: es un tipo que no sabe comprar.
final class AthleteCheckoutUnavailable extends AthleteCheckout {
  const AthleteCheckoutUnavailable._(this.motivo) : super._();

  /// Por qué no se puede comprar acá. Va al log, nunca a la pantalla: al
  /// alumno no le sirve saber que falta una variable de entorno.
  final String motivo;
}

/// La superficie que SÍ puede cobrar: la app móvil, contra App Store o Play.
final class AthleteCheckoutOnStore extends AthleteCheckout {
  const AthleteCheckoutOnStore._(this._store) : super._();

  final AthleteStore _store;

  /// Restaura las compras del alumno [uid].
  ///
  /// Apple lo EXIGE para suscripciones. Y no es burocracia: el alumno que
  /// cambia de teléfono, reinstala, o entra desde el iPad de la casa necesita
  /// esto.
  ///
  /// El `identificar` va antes por el MISMO motivo que en [start]: sin él, la
  /// restauración se aplica sobre un id anónimo y no le devuelve nada.
  Future<bool> restaurar({required String uid}) async {
    try {
      await _store.identificar(uid);
      return (await _store.restaurar()).contains(kAthleteEntitlement);
    } catch (e) {
      debugPrint('athlete_checkout: no se pudo restaurar — $e');
      return false;
    }
  }

  /// Los planes que la tienda cotiza hoy, con su precio ya formateado.
  ///
  /// Lista vacía = no hay oferta publicada. Es un error de CONFIGURACIÓN del
  /// dashboard, y la pantalla tiene que mostrar eso y no un paywall vacío.
  Future<List<AthletePlanOferta>> planes() async {
    try {
      return await _store.ofertas();
    } catch (e) {
      debugPrint('athlete_checkout: no se pudieron leer los planes — $e');
      return const [];
    }
  }

  /// Compra [plan] para el alumno [uid]. ÚNICO camino a un cobro del alumno en
  /// toda la app.
  ///
  /// Es un `Future` y no puede no serlo: habla con la tienda por red. Es la
  /// misma lección que dejó escrita `PlanCheckoutAvailable.start` — *"un método
  /// que habla por red no puede no serlo, y eso no se puede esconder detrás de
  /// una firma"*.
  ///
  /// **No escribe nada en Firestore.** El entitlement lo escribe `rcWebhook`
  /// del lado servidor, después de re-consultarle la verdad al proveedor con
  /// nuestra key. Que el cliente diga "compré" no alcanza y no tiene por qué:
  /// el SDK puede otorgar un entitlement localmente sin haber hablado con el
  /// servidor, y ese es exactamente el camino que un cliente modificado
  /// falsifica.
  ///
  /// Devolver [AthletePurchaseOutcome.comprado] significa "la tienda cobró",
  /// no "el alumno ya tiene el derecho en Firestore". El derecho llega cuando
  /// llega el webhook, y la UI tiene que esperar al provider, no a este valor.
  Future<AthletePurchaseOutcome> start({
    required String uid,
    required AthletePlan plan,
  }) async {
    try {
      // Antes de cobrar. Ver el encabezado: sin esto la compra queda a nombre
      // de un id anónimo y el webhook no encuentra a quién acreditarle.
      await _store.identificar(uid);

      final activos = await _store.comprar(plan);

      // Compró y el derecho ya está: listo.
      if (activos.contains(kAthleteEntitlement)) {
        return AthletePurchaseOutcome.comprado;
      }
      // Cobró, la tienda no tiró, pero el entitlement todavía no está activo.
      // En Android es el pago diferido; en iOS, un "Ask to Buy" que espera al
      // adulto. En los dos, la compra llega después por el webhook.
      return AthletePurchaseOutcome.pendiente;
    } on AthleteStoreException catch (e) {
      // La traducción de los códigos del proveedor vive en el ADAPTADOR. Acá
      // sólo se decide qué hacer con cada caso, que es lo que de verdad es una
      // decisión de producto.
      if (e.falla != AthleteStoreFalla.cancelada) {
        debugPrint('athlete_checkout: la compra no se completó — $e');
      }
      return switch (e.falla) {
        // Cerrar el diálogo de pago NO es un error. Ver el enum.
        AthleteStoreFalla.cancelada => AthletePurchaseOutcome.cancelado,
        AthleteStoreFalla.pendiente => AthletePurchaseOutcome.pendiente,
        AthleteStoreFalla.sinProducto => AthletePurchaseOutcome.sinProducto,
        AthleteStoreFalla.otra => AthletePurchaseOutcome.error,
      };
    } catch (e) {
      debugPrint('athlete_checkout: error inesperado — $e');
      return AthletePurchaseOutcome.error;
    }
  }
}

/// El ÚNICO fabricante de [AthleteCheckoutOnStore] en todo `lib/`.
///
/// [store] existe para los tests. Desde `lib/` nadie lo pasa, y aunque lo
/// pasara no podría construir la variante que cobra por su cuenta: los
/// constructores son privados a esta librería.
AthleteCheckout resolveAthleteCheckout({AthleteStore? store}) {
  if (kIsWeb) {
    return const AthleteCheckoutUnavailable._('el alumno no compra por web');
  }
  // Lo unico que este archivo sabe del proveedor: como pedirle uno, y que
  // puede no haberlo. El nombre del proveedor no aparece ni en el motivo.
  final elegido = store ?? crearRevenueCatStore();
  if (elegido == null) {
    return const AthleteCheckoutUnavailable._(
      'no hay proveedor de compras configurado',
    );
  }
  return AthleteCheckoutOnStore._(elegido);
}

/// La capacidad de comprar, para la UI.
///
/// Existe para que las pantallas no llamen a [resolveAthleteCheckout] en cada
/// `build` y —sobre todo— para que los tests la puedan pisar sin tener que
/// inyectar un [AthleteStore] a mano por toda la jerarquia de widgets.
final athleteCheckoutProvider =
    Provider<AthleteCheckout>((ref) => resolveAthleteCheckout());
