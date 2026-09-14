// store_falso.dart — el doble del puerto contra la tienda.
//
// ─── Miralo y comparalo con lo que había antes ──────────────────────────────
//
// Este archivo reemplaza a `rc_models.dart`, que construía a mano `Package`,
// `StoreProduct`, `PresentedOfferingContext`, `Offering`, `EntitlementInfo`,
// `EntitlementInfos` y `CustomerInfo` —unos 35 argumentos posicionales de
// andamio— sólo para poder probar que el `logIn` pasa antes que la compra.
//
// Ese andamio existía por una sola razón: el puerto devolvía tipos de
// RevenueCat. Ahora habla en nuestro vocabulario, y el doble es esto.
//
// El andamio no se perdió: se mudó a `revenuecat_store_test.dart`, donde SÍ
// corresponde, porque ahí se prueba justamente la traducción desde esos tipos.

import 'package:treino/features/paywall/application/athlete_checkout.dart';

/// El doble. Registra el ORDEN de las llamadas, que es lo que hace falta para
/// probar que la identificación pasa antes que la compra.
final class StoreFalso implements AthleteStore {
  StoreFalso({
    this.ofrece = const [],
    this.activosAlComprar,
    this.activosAlRestaurar = const {},
    this.tira,
  });

  /// Los planes que esta tienda publica.
  final List<AthletePlanOferta> ofrece;

  /// Los entitlements activos que devuelve la compra. Por defecto, el nuestro.
  final Set<String>? activosAlComprar;

  final Set<String> activosAlRestaurar;

  /// Si está, [comprar] tira esto en vez de comprar.
  final AthleteStoreException? tira;

  final List<String> llamadas = <String>[];
  final List<AthletePlan> comprados = <AthletePlan>[];
  String? uidIdentificado;

  @override
  Future<void> identificar(String uid) async {
    llamadas.add('identificar');
    uidIdentificado = uid;
  }

  @override
  Future<List<AthletePlanOferta>> ofertas() async {
    llamadas.add('ofertas');
    return ofrece;
  }

  @override
  Future<Set<String>> comprar(AthletePlan plan) async {
    llamadas.add('comprar');
    comprados.add(plan);
    if (tira != null) throw tira!;
    return activosAlComprar ?? {kAthleteEntitlement};
  }

  @override
  Future<Set<String>> restaurar() async {
    llamadas.add('restaurar');
    return activosAlRestaurar;
  }
}

/// Una oferta de mentira, con el precio que le pidas.
AthletePlanOferta ofertaDe(
  AthletePlan plan, {
  String precio = 'USD 2,99',
  String? porMes,
}) =>
    AthletePlanOferta(plan: plan, precio: precio, precioPorMes: porMes);

/// Atajo: un checkout que puede comprar, con estas ofertas.
AthleteCheckoutOnStore checkoutCon(StoreFalso store) =>
    resolveAthleteCheckout(store: store) as AthleteCheckoutOnStore;
