/// El ÚNICO archivo de `lib/` que le habla a RevenueCat.
///
/// Todo lo que hay acá es traducción: de los tipos del SDK a los nuestros, y de
/// sus códigos de error a [AthleteStoreFalla]. **Ninguna decisión de producto
/// vive en este archivo.** Si alguna se cuela, está en el lugar equivocado —
/// el puerto existe justamente para que las decisiones queden del lado
/// testeable.
///
/// El día que TREINO cambie de proveedor, se reemplaza este archivo y nada
/// más. Los límites de esa promesa están escritos en `athlete_store.dart`, y
/// conviene leerlos antes de creerle: sacar los tipos abarata el reemplazo,
/// no lo vuelve gratis.
///
/// ─── Por qué las dos traducciones son funciones sueltas ───
///
/// [ofertasDesde] y [fallaDesde] son las dos únicas partes con lógica de
/// verdad, y `Purchases` habla por platform channel: un test de Dart puro no
/// tiene canal. Sacándolas de la clase se pueden probar contra modelos reales
/// del SDK sin dispositivo, y lo que queda en la clase son cuatro métodos tan
/// delgados que se verifican leyéndolos.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'athlete_checkout.dart' show AthletePlan;
import 'athlete_store.dart';

/// Traduce el Offering de RevenueCat a nuestras ofertas.
///
/// `null` o sin nuestros package types ⇒ lista vacía, que el puerto define como
/// «no hay oferta publicada».
List<AthletePlanOferta> ofertasDesde(Offering? offering) {
  if (offering == null) return const [];

  final out = <AthletePlanOferta>[];
  for (final plan in AthletePlan.values) {
    final p = offering.availablePackages
        .where((x) => x.packageType == _tipoDe(plan))
        .firstOrNull;
    if (p == null) continue;
    out.add(
      AthletePlanOferta(
        plan: plan,
        precio: p.storeProduct.priceString,
        // Sólo tiene sentido en el anual: en el mensual repetiría el mismo
        // número dos veces.
        precioPorMes: plan == AthletePlan.anual
            ? p.storeProduct.pricePerMonthString
            : null,
      ),
    );
  }
  return out;
}

/// Traduce un error del SDK a nuestro vocabulario.
///
/// Los tres primeros casos existen porque significan cosas MUY distintas para
/// el usuario, y mezclarlos es maltratarlo: al que cerró la hoja de pago no se
/// le muestra un cartel rojo, y al que eligió pagar en efectivo no se le dice
/// «listo».
AthleteStoreFalla fallaDesde(PlatformException e) {
  final codigo = PurchasesErrorHelper.getErrorCode(e);
  return switch (codigo) {
    PurchasesErrorCode.purchaseCancelledError => AthleteStoreFalla.cancelada,
    PurchasesErrorCode.paymentPendingError => AthleteStoreFalla.pendiente,
    PurchasesErrorCode.productNotAvailableForPurchaseError ||
    PurchasesErrorCode.configurationError =>
      AthleteStoreFalla.sinProducto,
    _ => AthleteStoreFalla.otra,
  };
}

PackageType _tipoDe(AthletePlan plan) => switch (plan) {
      AthletePlan.mensual => PackageType.monthly,
      AthletePlan.anual => PackageType.annual,
    };

/// El adaptador. Cuatro métodos, todos delgados.
final class RevenueCatStore implements AthleteStore {
  const RevenueCatStore();

  @override
  Future<void> identificar(String uid) => Purchases.logIn(uid);

  @override
  Future<List<AthletePlanOferta>> ofertas() async {
    try {
      return ofertasDesde((await Purchases.getOfferings()).current);
    } on PlatformException catch (e) {
      throw AthleteStoreException(fallaDesde(e), e.message);
    }
  }

  @override
  Future<Set<String>> comprar(AthletePlan plan) async {
    try {
      final offering = (await Purchases.getOfferings()).current;
      final package = offering?.availablePackages
          .where((x) => x.packageType == _tipoDe(plan))
          .firstOrNull;
      if (package == null) {
        throw const AthleteStoreException(
          AthleteStoreFalla.sinProducto,
          'el Offering current no publica este plan',
        );
      }
      // `Purchases.purchase(PurchaseParams)` y no `purchasePackage`: la
      // segunda quedó deprecada en el SDK 10.x.
      final r = await Purchases.purchase(PurchaseParams.package(package));
      return _activos(r.customerInfo);
    } on PlatformException catch (e) {
      throw AthleteStoreException(fallaDesde(e), e.message);
    }
  }

  @override
  Future<Set<String>> restaurar() async {
    try {
      return _activos(await Purchases.restorePurchases());
    } on PlatformException catch (e) {
      throw AthleteStoreException(fallaDesde(e), e.message);
    }
  }
}

/// Los entitlements que el SDK considera activos AHORA.
///
/// Se devuelven todos, no un booleano: cuál de ellos otorga acceso a TREINO es
/// una decisión nuestra y vive del lado testeado.
Set<String> _activos(CustomerInfo info) => info.entitlements.all.entries
    .where((e) => e.value.isActive)
    .map((e) => e.key)
    .toSet();

/// Clave pública del SDK de RevenueCat.
///
/// **No es un secreto.** Viaja en el binario de todos modos, es read-only por
/// diseño, y RevenueCat la publica como "public SDK key". Mismo caso que la
/// client key de Google Places, que este repo ya resolvió igual: default
/// committeado para que TODO build ande sin flags, y `--dart-define` que la
/// pisa para rotarla sin recompilar.
///
/// Hoy el default está VACÍO porque el proyecto de RevenueCat todavía no
/// existe. Mientras esté vacío no hay proveedor, y `resolveAthleteCheckout`
/// devuelve la variante que no sabe comprar — que es lo correcto: un botón sin
/// SDK configurado es una promesa rota.
const String kRevenueCatPublicKey = String.fromEnvironment(
  'REVENUECAT_PUBLIC_KEY',
);

/// El adaptador, o `null` si no hay clave.
///
/// Devolver `null` en vez de un adaptador roto es lo que deja que la decisión
/// «¿esta superficie puede cobrar?» la tome el tipo sellado y no un `if`
/// perdido adentro de una pantalla.
AthleteStore? crearRevenueCatStore() =>
    kRevenueCatPublicKey.isEmpty ? null : const RevenueCatStore();

/// Arranca el SDK. Se llama UNA vez, desde `lib/main.dart`.
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
/// En el momento en que corre esto el alumno puede no estar logueado. El SDK
/// arranca anónimo y se identifica en el `identificar` que hace
/// `AthleteCheckoutOnStore.start` justo antes de cobrar. Ese es el orden
/// correcto y además el que no se puede olvidar de cablear: el uid entra por
/// la firma de `start`, no por un listener en otro archivo.
///
/// Devuelve `false` si no había clave. No tira: un binario sin clave tiene que
/// arrancar igual y simplemente no ofrecer comprar.
Future<bool> configurarRevenueCat() async {
  if (kIsWeb || kRevenueCatPublicKey.isEmpty) return false;
  await Purchases.configure(PurchasesConfiguration(kRevenueCatPublicKey));
  return true;
}
