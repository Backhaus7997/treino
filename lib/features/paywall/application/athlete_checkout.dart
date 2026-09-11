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
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Qué está comprando el alumno.
///
/// Son los dos package types estándar de RevenueCat, y se usan los estándar a
/// propósito: la doc recomienda no inventar identifiers custom, porque los
/// estándar son los que el dashboard entiende para armar los Offerings.
enum AthletePlan {
  mensual(PackageType.monthly),
  anual(PackageType.annual);

  const AthletePlan(this.packageType);

  final PackageType packageType;
}

/// Un plan tal como la tienda lo cotiza HOY.
///
/// Existe para que la PANTALLA no tenga que importar `purchases_flutter`. No es
/// una capa de abstraccion por gusto: el guard de `superficie_de_cobro_alumno_test.dart`
/// marca cualquier archivo que importe el SDK, y una pantalla no deberia estar
/// nunca en esa lista — tiene que hablarle a este archivo, no a la tienda.
final class AthletePlanOferta {
  const AthletePlanOferta({
    required this.plan,
    required this.precio,
    this.precioPorMes,
  });

  final AthletePlan plan;

  /// El precio **ya formateado por la tienda**, con su moneda y su separador.
  ///
  /// Nunca se arma a mano. Apple exige que el importe que se va a facturar sea
  /// el elemento de precio mas prominente del layout, y armarlo nosotros abre
  /// la puerta a que diga algo distinto de lo que cobra la hoja de pago del
  /// sistema — que es el peor lugar posible para una discrepancia.
  final String precio;

  /// Lo que sale por mes el plan anual, formateado por la tienda.
  ///
  /// Va SUBORDINADO al [precio], nunca en su lugar: la doc de Apple dice que
  /// estos desgloses «should be displayed in a subordinate position and size».
  final String? precioPorMes;
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

/// Clave pública del SDK de RevenueCat.
///
/// **No es un secreto.** Viaja en el binario de todos modos, es read-only por
/// diseño, y RevenueCat la publica como "public SDK key". Mismo caso que la
/// client key de Google Places, que este repo ya resolvió igual: default
/// committeado para que TODO build ande sin flags, y `--dart-define` que la
/// pisa para rotarla sin recompilar.
///
/// Hoy el default está VACÍO porque el proyecto de RevenueCat todavía no
/// existe. Mientras esté vacío, [resolveAthleteCheckout] devuelve
/// [AthleteCheckoutUnavailable] y la app no ofrece comprar — que es lo
/// correcto: un botón sin SDK configurado es una promesa rota.
const String kRevenueCatPublicKey = String.fromEnvironment(
  'REVENUECAT_PUBLIC_KEY',
);

/// El puerto contra RevenueCat.
///
/// Existe por una sola razón: `Purchases` habla por platform channel, y un
/// test de Dart puro no tiene canal. Sin esta costura, toda la lógica de
/// arriba —elegir el package, traducir el error de cancelación, distinguir un
/// pago diferido— sólo se podría probar en un dispositivo.
abstract interface class AthleteStore {
  /// Identifica al comprador ANTES de cobrarle. Ver el encabezado.
  Future<void> logIn(String uid);

  /// El Offering marcado como `current` en el dashboard.
  Future<Offering?> currentOffering();

  /// Dispara la compra. Tira si la tienda falla o si el alumno cancela.
  Future<CustomerInfo> purchase(Package package);

  /// Le devuelve al alumno lo que ya habia comprado, en un telefono nuevo o
  /// despues de reinstalar.
  Future<CustomerInfo> restore();
}

/// La implementación real. Delgada a propósito: acá no hay decisiones.
final class RevenueCatStore implements AthleteStore {
  const RevenueCatStore();

  @override
  Future<void> logIn(String uid) => Purchases.logIn(uid);

  @override
  Future<Offering?> currentOffering() async =>
      (await Purchases.getOfferings()).current;

  // `Purchases.purchase(PurchaseParams)` y no `purchasePackage`: la segunda
  // quedo deprecada en el SDK 10.x y usarla deja un warning en cada build.
  @override
  Future<CustomerInfo> purchase(Package package) async =>
      (await Purchases.purchase(PurchaseParams.package(package))).customerInfo;

  @override
  Future<CustomerInfo> restore() => Purchases.restorePurchases();
}

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
  /// Apple lo EXIGE para suscripciones: una app que cobra y no ofrece
  /// restaurar es rechazo. Y no es burocracia — el alumno que cambia de
  /// telefono, reinstala, o entra desde el iPad de la casa necesita esto.
  ///
  /// El `logIn` va antes por el MISMO motivo que en [start]: sin el, la
  /// restauracion se aplica sobre un id anonimo y no le devuelve nada.
  ///
  /// Devuelve `true` si despues de restaurar el alumno tiene el entitlement.
  Future<bool> restaurar({required String uid}) async {
    try {
      await _store.logIn(uid);
      final info = await _store.restore();
      return info.entitlements.all[kAthleteEntitlement]?.isActive ?? false;
    } catch (e) {
      debugPrint('athlete_checkout: no se pudo restaurar — $e');
      return false;
    }
  }

  /// Los planes que la tienda cotiza hoy, con su precio ya formateado.
  ///
  /// Lista vacia = el Offering `current` no existe o no tiene ninguno de
  /// nuestros package types. Es un error de CONFIGURACION del dashboard, y la
  /// pantalla tiene que mostrar eso y no un paywall vacio.
  Future<List<AthletePlanOferta>> planes() async {
    try {
      final offering = await _store.currentOffering();
      if (offering == null) {
        debugPrint('athlete_checkout: no hay Offering `current` en RevenueCat');
        return const [];
      }
      final out = <AthletePlanOferta>[];
      for (final plan in AthletePlan.values) {
        final p = offering.availablePackages
            .where((x) => x.packageType == plan.packageType)
            .firstOrNull;
        if (p == null) continue;
        out.add(
          AthletePlanOferta(
            plan: plan,
            precio: p.storeProduct.priceString,
            // Solo tiene sentido en el anual: en el mensual repetiria el mismo
            // numero dos veces.
            precioPorMes: plan == AthletePlan.anual
                ? p.storeProduct.pricePerMonthString
                : null,
          ),
        );
      }
      return out;
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
  /// del lado servidor, después de re-consultarle la verdad a RevenueCat con
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
      await _store.logIn(uid);

      final offering = await _store.currentOffering();
      if (offering == null) {
        debugPrint('athlete_checkout: no hay Offering `current` en RevenueCat');
        return AthletePurchaseOutcome.sinProducto;
      }

      final package = offering.availablePackages
          .where((p) => p.packageType == plan.packageType)
          .firstOrNull;
      if (package == null) {
        debugPrint(
            'athlete_checkout: el Offering no tiene ${plan.packageType}');
        return AthletePurchaseOutcome.sinProducto;
      }

      final info = await _store.purchase(package);
      final entitlement = info.entitlements.all[kAthleteEntitlement];

      if (entitlement != null && entitlement.isActive) {
        return AthletePurchaseOutcome.comprado;
      }

      // Compró, la tienda no tiró, pero el entitlement todavía no está activo.
      // En Android es el caso del pago diferido; en iOS, un "Ask to Buy" que
      // espera al adulto. En los dos, la compra llega despues por el webhook.
      return AthletePurchaseOutcome.pendiente;
    } on PlatformException catch (e) {
      final codigo = PurchasesErrorHelper.getErrorCode(e);

      // Cerrar el diálogo de pago NO es un error. Ver el enum.
      if (codigo == PurchasesErrorCode.purchaseCancelledError) {
        return AthletePurchaseOutcome.cancelado;
      }
      if (codigo == PurchasesErrorCode.paymentPendingError) {
        return AthletePurchaseOutcome.pendiente;
      }
      if (codigo == PurchasesErrorCode.productNotAvailableForPurchaseError ||
          codigo == PurchasesErrorCode.configurationError) {
        debugPrint('athlete_checkout: producto no disponible ($codigo)');
        return AthletePurchaseOutcome.sinProducto;
      }

      debugPrint('athlete_checkout: la compra falló ($codigo)');
      return AthletePurchaseOutcome.error;
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
  if (kRevenueCatPublicKey.isEmpty && store == null) {
    return const AthleteCheckoutUnavailable._('falta REVENUECAT_PUBLIC_KEY');
  }
  return AthleteCheckoutOnStore._(store ?? const RevenueCatStore());
}

/// Arranca el SDK de RevenueCat. Se llama UNA vez, desde `lib/main.dart`.
///
/// ─── Por qué acá y no en el entry point web ───
///
/// RevenueCat es móvil-only, y el repo ya tiene el precedente exacto:
/// `main_coach_hub.dart` NO inicializa Google Sign-In y lo dice en un
/// comentario. Hay 7 entry points en `lib/*.dart` y sólo `main.dart` necesita
/// esto.
///
/// ─── Por qué NO recibe el uid ───
///
/// En el momento en que corre esto el alumno puede no estar logueado todavía.
/// RevenueCat arranca anónimo y se identifica en el `logIn` que hace
/// [AthleteCheckoutOnStore.start] justo antes de cobrar. Ese es el orden
/// correcto y además el que no se puede olvidar de cablear: el uid entra por
/// la firma de `start`, no por un listener en otro archivo.
///
/// Devuelve `false` si no había clave. No tira: un binario sin clave tiene que
/// arrancar igual y simplemente no ofrecer comprar.
Future<bool> configurarRevenueCat() async {
  if (kIsWeb || kRevenueCatPublicKey.isEmpty) return false;
  await Purchases.configure(
    PurchasesConfiguration(kRevenueCatPublicKey),
  );
  return true;
}

/// La capacidad de comprar, para la UI.
///
/// Existe para que las pantallas no llamen a [resolveAthleteCheckout] en cada
/// `build` y —sobre todo— para que los tests la puedan pisar sin tener que
/// inyectar un [AthleteStore] a mano por toda la jerarquia de widgets.
final athleteCheckoutProvider =
    Provider<AthleteCheckout>((ref) => resolveAthleteCheckout());
