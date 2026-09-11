// rc_models.dart — los modelos de RevenueCat, armados a mano para los tests.
//
// Viven acá y no en cada test porque los usan DOS suites: la de la capacidad
// (`athlete_checkout_test.dart`) y la de la pantalla
// (`athlete_paywall_screen_test.dart`).
//
// Que este archivo se rompa cuando RevenueCat cambie la forma de un modelo NO
// es un problema del andamio: es la señal de que el SDK movió algo que
// consumimos. Arreglalo mirando el cambio, no comentando el test.
//
// Ojo: importar `purchases_flutter` desde `test/` está bien. El guard de
// `superficie_de_cobro_alumno_test.dart` escanea `lib/` — la regla es que
// ninguna PANTALLA le hable a la tienda, no que los tests no puedan.

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:treino/features/paywall/application/athlete_checkout.dart';

/// Un [Package] con lo mínimo que el código mira: su `packageType` y el precio.
Package paquete(
  PackageType tipo, {
  String precio = 'USD 2,99',
  String? porMes,
}) =>
    Package(
      'paq_${tipo.name}',
      tipo,
      StoreProduct(
        'treino_alumno_${tipo.name}',
        'Suscripción TREINO',
        'TREINO',
        2.99,
        precio,
        'USD',
        pricePerMonthString: porMes,
      ),
      const PresentedOfferingContext('default', null, null),
    );

Offering oferta(List<Package> paquetes) => Offering(
      'default',
      'El offering de prueba',
      const {},
      paquetes,
    );

/// Un [CustomerInfo] con el entitlement [nombre] en el estado [activo].
///
/// `null` en [nombre] = el cliente no tiene NINGÚN entitlement.
CustomerInfo cliente({String? nombre, bool activo = true}) {
  final infos = <String, EntitlementInfo>{
    if (nombre != null)
      nombre: EntitlementInfo(
        nombre,
        activo,
        true,
        '2026-09-10T12:00:00Z',
        '2026-09-10T12:00:00Z',
        'treino_alumno_monthly',
        true,
      ),
  };
  return CustomerInfo(
    EntitlementInfos(
      infos,
      {
        for (final e in infos.entries)
          if (e.value.isActive) e.key: e.value
      },
    ),
    const {},
    const [],
    const [],
    const [],
    '2026-09-10T12:00:00Z',
    'alumno-1',
    const {},
    '2026-09-10T12:00:00Z',
  );
}

/// Un `PlatformException` como los que tira el SDK: el código es el ÍNDICE del
/// enum, en texto. Así lo lee `PurchasesErrorHelper.getErrorCode`.
PlatformException falla(PurchasesErrorCode codigo) =>
    PlatformException(code: '${codigo.index}', message: codigo.name);

/// El doble del SDK. Registra el ORDEN de las llamadas, que es lo que hace
/// falta para probar que el `logIn` va antes que la compra.
final class StoreFalso implements AthleteStore {
  StoreFalso({
    this.offering,
    this.alComprar,
    this.tiraAlComprar,
    this.alRestaurar,
    this.tiraAlListar,
  });

  final Offering? offering;
  final CustomerInfo Function(Package)? alComprar;
  final Object? tiraAlComprar;
  final CustomerInfo Function()? alRestaurar;
  final Object? tiraAlListar;

  final List<String> llamadas = <String>[];
  final List<Package> comprados = <Package>[];
  String? uidIdentificado;

  @override
  Future<void> logIn(String uid) async {
    llamadas.add('logIn');
    uidIdentificado = uid;
  }

  @override
  Future<Offering?> currentOffering() async {
    llamadas.add('currentOffering');
    if (tiraAlListar != null) throw tiraAlListar!;
    return offering;
  }

  @override
  Future<CustomerInfo> purchase(Package package) async {
    llamadas.add('purchase');
    comprados.add(package);
    if (tiraAlComprar != null) throw tiraAlComprar!;
    return (alComprar ?? (_) => cliente(nombre: kAthleteEntitlement))(package);
  }

  @override
  Future<CustomerInfo> restore() async {
    llamadas.add('restore');
    return (alRestaurar ?? () => cliente())();
  }
}
