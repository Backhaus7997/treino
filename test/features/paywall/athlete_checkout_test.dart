// athlete_checkout_test.dart — la capacidad de comprar del ALUMNO.
//
// LOCAL, sin dispositivo y sin platform channels: el SDK entra por el puerto
// `AthleteStore`.
//
// Lo que estos tests cuidan son cinco cosas, y ninguna es "que ande":
//
//   1. Que el `logIn` con el uid pase SIEMPRE ANTES de cobrar. Si la compra
//      sale anónima, RevenueCat le inventa un id, el webhook recibe ESE id, no
//      encuentra `users/{uid}`, y contesta 200 sin acreditar nada. El alumno
//      pagó y no tiene nada — y el bug no hace ruido: falla en silencio, en
//      producción, después de que alguien puso plata.
//
//   2. Que cancelar NO sea un error. El alumno que cierra la hoja de pago tomó
//      una decisión; mostrarle un cartel rojo por eso es maltratarlo.
//
//   3. Que "la tienda cobró" y "el alumno tiene el derecho" sean cosas
//      distintas. El entitlement lo escribe el webhook del lado servidor; este
//      código NUNCA escribe en Firestore.
//
//   4. Que un problema de CONFIGURACIÓN del dashboard (falta el Offering, falta
//      el package) no se confunda con un problema del alumno.
//
//   5. Que sin clave del SDK la app NO ofrezca comprar. Un botón sin SDK
//      configurado es una promesa rota.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:treino/features/paywall/application/athlete_checkout.dart';

// ---------------------------------------------------------------------------
// Andamio: los modelos del SDK, armados a mano
// ---------------------------------------------------------------------------

/// Un [Package] con lo mínimo que este código mira: su `packageType`.
Package _paquete(PackageType tipo) => Package(
      'paq_${tipo.name}',
      tipo,
      StoreProduct(
        'treino_alumno_${tipo.name}',
        'Suscripción TREINO',
        'TREINO',
        2.99,
        'USD 2,99',
        'USD',
      ),
      const PresentedOfferingContext('default', null, null),
    );

Offering _oferta(List<PackageType> tipos) => Offering(
      'default',
      'El offering de prueba',
      const {},
      tipos.map(_paquete).toList(),
    );

/// Un [CustomerInfo] con el entitlement [nombre] en el estado [activo].
///
/// `null` en [nombre] = el cliente no tiene NINGÚN entitlement.
CustomerInfo _cliente({String? nombre, bool activo = true}) {
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
PlatformException _falla(PurchasesErrorCode codigo) =>
    PlatformException(code: '${codigo.index}', message: codigo.name);

/// El doble del SDK. Registra el ORDEN de las llamadas, que es lo que hace
/// falta para probar que el `logIn` va antes que la compra.
final class _StoreFalso implements AthleteStore {
  _StoreFalso({this.offering, this.alComprar, this.tiraAlComprar});

  final Offering? offering;
  final CustomerInfo Function(Package)? alComprar;
  final Object? tiraAlComprar;

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
    return offering;
  }

  @override
  Future<CustomerInfo> purchase(Package package) async {
    llamadas.add('purchase');
    comprados.add(package);
    if (tiraAlComprar != null) throw tiraAlComprar!;
    return (alComprar ?? (_) => _cliente(nombre: kAthleteEntitlement))(package);
  }
}

AthleteCheckoutOnStore _checkout(_StoreFalso store) =>
    resolveAthleteCheckout(store: store) as AthleteCheckoutOnStore;

// ---------------------------------------------------------------------------

void main() {
  group('resolveAthleteCheckout — quién puede comprar', () {
    test('sin clave del SDK NO se puede comprar, y dice por qué', () {
      // Es el estado de HOY: el proyecto de RevenueCat todavía no existe.
      // Un botón de compra sin SDK configurado prometería una salida que no
      // está, que es exactamente lo que el dartdoc de la hoja de límite dice
      // que hay que evitar.
      final r = resolveAthleteCheckout();
      expect(r, isA<AthleteCheckoutUnavailable>());
      expect((r as AthleteCheckoutUnavailable).motivo, contains('KEY'));
    });

    test('con un store inyectado sí se puede — es el camino de los tests', () {
      expect(
        resolveAthleteCheckout(store: _StoreFalso()),
        isA<AthleteCheckoutOnStore>(),
      );
    });

    test('el sealed cubre los dos casos y nada más', () {
      // Si alguien agrega una tercera variante, este switch deja de compilar.
      // Es el mismo recordatorio que el tipo del PF: la compra no es un
      // booleano, es una capacidad.
      final AthleteCheckout r = resolveAthleteCheckout();
      final nombre = switch (r) {
        AthleteCheckoutOnStore() => 'compra',
        AthleteCheckoutUnavailable() => 'no compra',
      };
      expect(nombre, 'no compra');
    });
  });

  group('start — EL ORDEN: identificar antes de cobrar', () {
    test('EL TEST QUE IMPORTA: logIn pasa ANTES de purchase', () async {
      final store = _StoreFalso(offering: _oferta([PackageType.monthly]));

      await _checkout(store).start(uid: 'alumno-42', plan: AthletePlan.mensual);

      expect(store.llamadas, ['logIn', 'currentOffering', 'purchase']);
      expect(store.uidIdentificado, 'alumno-42');
      // Si este test se pone rojo porque alguien movió el `logIn` después de
      // la compra —o lo sacó— la compra va a salir a nombre de un id anónimo,
      // el webhook no va a encontrar a quién acreditarle, y el alumno va a
      // pagar sin recibir nada. No lo arregles moviendo el expect.
      expect(store.llamadas.indexOf('logIn'),
          lessThan(store.llamadas.indexOf('purchase')));
    });

    test('si no hay Offering NO se cobra', () async {
      final store = _StoreFalso();

      final r = await _checkout(store)
          .start(uid: 'alumno-1', plan: AthletePlan.mensual);

      expect(r, AthletePurchaseOutcome.sinProducto);
      expect(store.llamadas, isNot(contains('purchase')));
    });

    test('si el Offering no tiene el plan pedido NO se cobra', () async {
      // El alumno toca "anual" y el dashboard sólo publicó el mensual. Es un
      // error de configuración nuestro, y cobrarle el mensual sería peor que
      // no cobrarle nada.
      final store = _StoreFalso(offering: _oferta([PackageType.monthly]));

      final r = await _checkout(store)
          .start(uid: 'alumno-1', plan: AthletePlan.anual);

      expect(r, AthletePurchaseOutcome.sinProducto);
      expect(store.llamadas, isNot(contains('purchase')));
    });

    test('compra el package del plan pedido, no el primero de la lista',
        () async {
      final store = _StoreFalso(
        offering: _oferta([PackageType.monthly, PackageType.annual]),
      );

      await _checkout(store).start(uid: 'alumno-1', plan: AthletePlan.anual);

      expect(store.comprados.single.packageType, PackageType.annual);
    });
  });

  group('start — cómo termina', () {
    test('entitlement activo → comprado', () async {
      final store = _StoreFalso(offering: _oferta([PackageType.monthly]));

      expect(
        await _checkout(store)
            .start(uid: 'alumno-1', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.comprado,
      );
    });

    test('cobró pero el entitlement NO está activo → pendiente', () async {
      // Android con pago diferido, o un "Ask to Buy" de iOS esperando al
      // adulto. Decirle "listo" sería mentir; decirle "error" también.
      final store = _StoreFalso(
        offering: _oferta([PackageType.monthly]),
        alComprar: (_) => _cliente(nombre: kAthleteEntitlement, activo: false),
      );

      expect(
        await _checkout(store)
            .start(uid: 'alumno-1', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.pendiente,
      );
    });

    test('cobró y no vino NINGÚN entitlement → pendiente', () async {
      final store = _StoreFalso(
        offering: _oferta([PackageType.monthly]),
        alComprar: (_) => _cliente(),
      );

      expect(
        await _checkout(store)
            .start(uid: 'alumno-1', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.pendiente,
      );
    });

    test('vino OTRO entitlement, no el nuestro → pendiente', () async {
      // Un alumno que compró otra cosa en otra app del mismo proyecto de
      // RevenueCat. No le da acceso a TREINO.
      final store = _StoreFalso(
        offering: _oferta([PackageType.monthly]),
        alComprar: (_) => _cliente(nombre: 'otra_cosa'),
      );

      expect(
        await _checkout(store)
            .start(uid: 'alumno-1', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.pendiente,
      );
    });

    test('EL OTRO TEST QUE IMPORTA: cancelar NO es un error', () async {
      final store = _StoreFalso(
        offering: _oferta([PackageType.monthly]),
        tiraAlComprar: _falla(PurchasesErrorCode.purchaseCancelledError),
      );

      expect(
        await _checkout(store)
            .start(uid: 'alumno-1', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.cancelado,
      );
    });

    test('pago pendiente de la tienda → pendiente', () async {
      final store = _StoreFalso(
        offering: _oferta([PackageType.monthly]),
        tiraAlComprar: _falla(PurchasesErrorCode.paymentPendingError),
      );

      expect(
        await _checkout(store)
            .start(uid: 'alumno-1', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.pendiente,
      );
    });

    test('producto mal configurado → sinProducto, no error', () async {
      for (final codigo in [
        PurchasesErrorCode.productNotAvailableForPurchaseError,
        PurchasesErrorCode.configurationError,
      ]) {
        final store = _StoreFalso(
          offering: _oferta([PackageType.monthly]),
          tiraAlComprar: _falla(codigo),
        );

        expect(
          await _checkout(store)
              .start(uid: 'alumno-1', plan: AthletePlan.mensual),
          AthletePurchaseOutcome.sinProducto,
          reason: 'el código $codigo es de configuración, no del alumno',
        );
      }
    });

    test('la tienda falla de verdad → error', () async {
      final store = _StoreFalso(
        offering: _oferta([PackageType.monthly]),
        tiraAlComprar: _falla(PurchasesErrorCode.storeProblemError),
      );

      expect(
        await _checkout(store)
            .start(uid: 'alumno-1', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.error,
      );
    });

    test('un error que NO es del SDK tampoco explota', () async {
      final store = _StoreFalso(
        offering: _oferta([PackageType.monthly]),
        tiraAlComprar: StateError('algo raro'),
      );

      expect(
        await _checkout(store)
            .start(uid: 'alumno-1', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.error,
      );
    });
  });

  group('el contrato con el servidor', () {
    test('el entitlement es el MISMO string que espera el webhook', () {
      // `ENTITLEMENT_ALUMNO` en functions/src/subscriptions/rc/webhook.ts.
      // Si estos dos se separan, el cliente compra y el servidor no acredita
      // — y nada falla ruidosamente.
      expect(kAthleteEntitlement, 'alumno_pro');
    });
  });
}
