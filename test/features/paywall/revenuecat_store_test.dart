// revenuecat_store_test.dart — la traducción desde el SDK de RevenueCat.
//
// ─── Por qué el andamio de modelos vive ACÁ y no en el test de la lógica ────
//
// Antes, construir a mano `Package`, `StoreProduct`, `PresentedOfferingContext`,
// `Offering`, `EntitlementInfo`, `EntitlementInfos` y `CustomerInfo` —unos 35
// argumentos posicionales— era el precio de probar que el `logIn` pasaba antes
// que la compra. Eso estaba mal ubicado: la lógica no tenía por qué saber de
// esos tipos.
//
// Ahora el puerto habla nuestro vocabulario y el andamio quedó donde
// corresponde: acá, donde lo que se prueba ES la traducción.
//
// Y esto también contesta una pregunta que conviene tener contestada: **¿qué
// se rompe el día que RevenueCat cambie un modelo?** Este archivo. Sólo este.
// Que se rompa es la señal de que el SDK movió algo que consumimos — arreglalo
// mirando el cambio, no comentando el test.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:treino/features/paywall/application/athlete_checkout.dart';
import 'package:treino/features/paywall/application/revenuecat_store.dart';

Package _paquete(
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

Offering _oferta(List<Package> paquetes) =>
    Offering('default', 'El offering de prueba', const {}, paquetes);

/// Un `PlatformException` como los que tira el SDK: el código es el ÍNDICE del
/// enum, en texto. Así lo lee `PurchasesErrorHelper.getErrorCode`.
PlatformException _falla(PurchasesErrorCode codigo) =>
    PlatformException(code: '${codigo.index}', message: codigo.name);

void main() {
  group('ofertasDesde', () {
    test('sin offering devuelve vacío', () {
      expect(ofertasDesde(null), isEmpty);
    });

    test('mapea los dos planes con su precio de la tienda', () {
      final r = ofertasDesde(_oferta([
        _paquete(PackageType.monthly, precio: 'USD 2,99'),
        _paquete(PackageType.annual, precio: 'USD 29,90', porMes: 'USD 2,49'),
      ]));

      expect(r.map((o) => o.plan), [AthletePlan.mensual, AthletePlan.anual]);
      expect(r.first.precio, 'USD 2,99');
      expect(r.last.precio, 'USD 29,90');
    });

    test('el precio por mes SÓLO va en el anual', () {
      // En el mensual repetiría el mismo número dos veces.
      final r = ofertasDesde(_oferta([
        _paquete(PackageType.monthly, porMes: 'NO-DEBERIA-PASAR'),
        _paquete(PackageType.annual, porMes: 'USD 2,49'),
      ]));

      expect(r.first.precioPorMes, isNull);
      expect(r.last.precioPorMes, 'USD 2,49');
    });

    test('ignora los package types que no son nuestros', () {
      // Un Offering puede publicar semanales o lifetime. No son nuestros
      // planes y no tienen que aparecer en el paywall.
      final r = ofertasDesde(_oferta([
        _paquete(PackageType.weekly),
        _paquete(PackageType.lifetime),
        _paquete(PackageType.monthly),
      ]));

      expect(r.map((o) => o.plan), [AthletePlan.mensual]);
    });

    test('un Offering vacío devuelve vacío', () {
      expect(ofertasDesde(_oferta(const [])), isEmpty);
    });
  });

  group('fallaDesde — la traducción que más importa', () {
    test('cancelar es su propia falla, no "otra"', () {
      // Si esto se mezcla con `otra`, el alumno que cierra la hoja de pago
      // recibe un cartel de error por haber tomado una decisión.
      expect(
        fallaDesde(_falla(PurchasesErrorCode.purchaseCancelledError)),
        AthleteStoreFalla.cancelada,
      );
    });

    test('pago pendiente es su propia falla', () {
      expect(
        fallaDesde(_falla(PurchasesErrorCode.paymentPendingError)),
        AthleteStoreFalla.pendiente,
      );
    });

    test('los dos códigos de configuración caen en sinProducto', () {
      for (final c in [
        PurchasesErrorCode.productNotAvailableForPurchaseError,
        PurchasesErrorCode.configurationError,
      ]) {
        expect(fallaDesde(_falla(c)), AthleteStoreFalla.sinProducto,
            reason: '$c es de configuración nuestra, no del alumno');
      }
    });

    test('cualquier otro código cae en otra', () {
      expect(
        fallaDesde(_falla(PurchasesErrorCode.storeProblemError)),
        AthleteStoreFalla.otra,
      );
      expect(
        fallaDesde(_falla(PurchasesErrorCode.networkError)),
        AthleteStoreFalla.otra,
      );
    });
  });

  group('crearRevenueCatStore', () {
    test('sin clave devuelve null, no un adaptador roto', () {
      // Devolver null es lo que deja que la decisión «¿esta superficie puede
      // cobrar?» la tome el tipo sellado y no un `if` perdido en una pantalla.
      expect(kRevenueCatPublicKey, isEmpty,
          reason: 'los tests corren sin --dart-define');
      expect(crearRevenueCatStore(), isNull);
    });
  });
}
