/// El PUERTO contra la tienda. **Cero tipos de terceros.**
///
/// ═══════════════════════════════════════════════════════════════════════════
///  POR QUÉ ESTE ARCHIVO EXISTE
/// ═══════════════════════════════════════════════════════════════════════════
///
/// La primera versión del puerto vivía adentro de `athlete_checkout.dart` y
/// devolvía tipos de RevenueCat: `Offering?`, `CustomerInfo`, `Package`. Se
/// midió: eran **41 referencias al SDK** en el archivo que tiene toda la
/// lógica, contando las de error (`PurchasesErrorCode`, `PlatformException`,
/// `PurchasesErrorHelper`), que eran las que más se escondían.
///
/// Eso hacía que «cambiar de proveedor» no fuera reemplazar una clase: era
/// reescribir el archivo que decide cuándo alguien tiene derecho a algo, más
/// sus dos suites de tests (que construyen *value objects* reales del SDK, no
/// mocks).
///
/// Ahora el SDK vive en UN solo archivo —`revenuecat_store.dart`— y este
/// puerto habla en nuestro vocabulario. Reemplazar el proveedor es escribir
/// otro adaptador que implemente estos cuatro métodos.
///
/// ─── Por qué se hizo AHORA y no cuando hiciera falta ───
///
/// Porque hoy el puerto tiene **cero consumidores de producción**: la pantalla
/// y el cableado están en PRs que todavía no mergearon. Nunca va a estar más
/// barato que ahora, y se encarece con cada pantalla que lo consuma.
///
/// No es que se planee migrar. Es que quedarse deja de ser una decisión que
/// encierra y pasa a ser una que se puede revisar.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  LO QUE ESTE PUERTO **NO** RESUELVE, Y HAY QUE SABERLO ANTES DE MIGRAR
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Sacar los tipos abarata el reemplazo, pero no lo vuelve gratis. Tres cosas
/// que un adaptador contra `in_app_purchase` (el plugin oficial) tendría que
/// resolver y que **no son firmas**:
///
///   1. **La forma es request/response y el plugin oficial no lo es.**
///      `buyNonConsumable()` devuelve `Future<bool>` y el resultado llega por
///      un `purchaseStream` GLOBAL, que además entrega compras de sesiones
///      ANTERIORES al arrancar la app. Implementar [comprar] contra eso pide
///      una capa de correlación (Completer + match por product id + timeout).
///
///   2. **[identificar] no tiene equivalente.** Es una línea acá y es el
///      problema más caro del camino propio: Google manda su notificación sin
///      ningún identificador de usuario, y Apple consulta por `transactionId`.
///      El reemplazo es un UUID por alumno + índice inverso + un camino de
///      rescate. Y falla en SILENCIO: si el `appAccountToken` no parsea como
///      UUID, el plugin lo descarta sin excepción y la compra sale igual.
///      (Los uid de Firebase son 28 caracteres alfanuméricos: **no** son UUID.)
///
///   3. **`comprado` vs `pendiente` hoy se decide leyendo un entitlement.** En
///      el plugin oficial no existe ese concepto: habría que re-derivarlo de
///      `PurchaseStatus` + plataforma. Es justo la distinción que cubre el pago
///      diferido en efectivo, que en Argentina no es un caso de borde.
///
/// Se dejan escritas acá, y no en un ticket, porque el que lea este puerto el
/// día que evalúe migrar va a leer esto primero.
library;

import 'athlete_checkout.dart' show AthletePlan;

/// Un plan tal como la tienda lo cotiza HOY.
///
/// El precio viene **ya formateado por la tienda**, con su moneda y su
/// separador. Nunca se arma a mano: Apple exige que el importe a facturar sea
/// el elemento de precio más prominente, y armarlo nosotros abre la puerta a
/// que la pantalla diga algo distinto de lo que cobra la hoja de pago.
final class AthletePlanOferta {
  const AthletePlanOferta({
    required this.plan,
    required this.precio,
    this.precioPorMes,
  });

  final AthletePlan plan;
  final String precio;

  /// Lo que sale por mes el plan anual. Va SUBORDINADO al [precio], nunca en
  /// su lugar — la doc de Apple pide que estos desgloses vayan «in a
  /// subordinate position and size».
  final String? precioPorMes;
}

/// Por qué falló una operación contra la tienda.
///
/// Traduce los códigos del proveedor a nuestro vocabulario. Que esta traducción
/// viva en el ADAPTADOR y no acá es todo el punto del puerto: el día que el
/// proveedor cambie sus códigos, cambia un archivo.
enum AthleteStoreFalla {
  /// El usuario cerró la hoja de pago. **No es un error**: es una decisión.
  cancelada,

  /// Pago diferido: efectivo en Android, o un «Ask to Buy» esperando al adulto.
  /// La compra todavía no está hecha y va a llegar por el webhook.
  pendiente,

  /// El plan pedido no está publicado. Es un error de CONFIGURACIÓN nuestro,
  /// no del usuario.
  sinProducto,

  /// Red caída, tienda rota, la cuenta con un problema de facturación.
  otra,
}

/// Lo que tira el puerto cuando algo sale mal. Sin tipos de terceros.
final class AthleteStoreException implements Exception {
  const AthleteStoreException(this.falla, [this.detalle]);

  final AthleteStoreFalla falla;
  final String? detalle;

  @override
  String toString() =>
      'AthleteStoreException($falla${detalle == null ? '' : ': $detalle'})';
}

/// El puerto. Cuatro métodos, todos en nuestro vocabulario.
abstract interface class AthleteStore {
  /// Identifica al comprador ANTES de cobrarle.
  ///
  /// Sin esto la compra queda a nombre de un id anónimo, el webhook recibe ESE
  /// id, no encuentra `users/{uid}` y contesta 200 sin acreditar nada. El
  /// alumno paga y no tiene nada, y no hay ningún error en ningún log.
  Future<void> identificar(String uid);

  /// Los planes que la tienda cotiza hoy.
  ///
  /// Lista vacía = no hay oferta publicada. Es un error de configuración del
  /// dashboard, y la pantalla tiene que mostrar eso y no un paywall vacío.
  Future<List<AthletePlanOferta>> ofertas();

  /// Compra [plan] y devuelve los entitlements ACTIVOS después de comprar.
  ///
  /// Devuelve identificadores y no un booleano a propósito: la decisión de
  /// cuál de ellos otorga acceso a TREINO es nuestra, no del proveedor, y por
  /// eso vive del lado testeado.
  ///
  /// Tira [AthleteStoreException] si el usuario cancela, si el plan no está
  /// publicado, o si la tienda falla.
  Future<Set<String>> comprar(AthletePlan plan);

  /// Restaura lo ya comprado y devuelve los entitlements activos.
  ///
  /// Apple lo EXIGE para suscripciones: una app que cobra y no ofrece
  /// restaurar es rechazo.
  Future<Set<String>> restaurar();
}
