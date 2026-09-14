// athlete_checkout_test.dart — la capacidad de comprar del ALUMNO.
//
// LOCAL, sin dispositivo y sin platform channels. Y desde que el puerto habla
// nuestro vocabulario, **sin un solo tipo de RevenueCat**: la traducción desde
// el SDK se prueba aparte, en `revenuecat_store_test.dart`.
//
// Lo que estos tests cuidan son cinco cosas, y ninguna es "que ande":
//
//   1. Que la identificación con el uid pase SIEMPRE ANTES de cobrar. Si la
//      compra sale anónima, el proveedor le inventa un id, el webhook recibe
//      ESE id, no encuentra `users/{uid}`, y contesta 200 sin acreditar nada.
//      El alumno pagó y no tiene nada — y el bug no hace ruido: falla en
//      silencio, en producción, después de que alguien puso plata.
//
//   2. Que cancelar NO sea un error. El alumno que cierra la hoja de pago tomó
//      una decisión; mostrarle un cartel rojo por eso es maltratarlo.
//
//   3. Que "la tienda cobró" y "el alumno tiene el derecho" sean cosas
//      distintas. El entitlement lo escribe el webhook del lado servidor; este
//      código NUNCA escribe en Firestore.
//
//   4. Que un problema de CONFIGURACIÓN del dashboard no se confunda con un
//      problema del alumno.
//
//   5. Que sin proveedor configurado la app NO ofrezca comprar. Un botón sin
//      SDK es una promesa rota.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/paywall/application/athlete_checkout.dart';

import 'helpers/store_falso.dart';

StoreFalso _conPlanes(
  List<AthletePlan> planes, {
  Set<String>? activos,
  AthleteStoreException? tira,
}) =>
    StoreFalso(
      ofrece: planes.map(ofertaDe).toList(),
      activosAlComprar: activos,
      tira: tira,
    );

void main() {
  group('resolveAthleteCheckout — quién puede comprar', () {
    test('sin proveedor configurado NO se puede comprar, y dice por qué', () {
      // Es el estado de HOY: el proyecto de RevenueCat todavía no existe, así
      // que `crearRevenueCatStore()` devuelve null.
      final r = resolveAthleteCheckout();
      expect(r, isA<AthleteCheckoutUnavailable>());
      expect((r as AthleteCheckoutUnavailable).motivo, contains('proveedor'));
    });

    test('el motivo NO nombra al proveedor', () {
      // El archivo de la capacidad no debería saber contra quién habla. Si
      // este test se pone rojo, algo del adaptador se filtró a la lógica.
      final r = resolveAthleteCheckout() as AthleteCheckoutUnavailable;
      expect(r.motivo.toLowerCase(), isNot(contains('revenuecat')));
    });

    test('con un store inyectado sí se puede — es el camino de los tests', () {
      expect(
        resolveAthleteCheckout(store: StoreFalso()),
        isA<AthleteCheckoutOnStore>(),
      );
    });

    test('el sealed cubre los dos casos y nada más', () {
      // Si alguien agrega una tercera variante, este switch deja de compilar.
      final AthleteCheckout r = resolveAthleteCheckout();
      final nombre = switch (r) {
        AthleteCheckoutOnStore() => 'compra',
        AthleteCheckoutUnavailable() => 'no compra',
      };
      expect(nombre, 'no compra');
    });
  });

  group('start — EL ORDEN: identificar antes de cobrar', () {
    test('EL TEST QUE IMPORTA: identificar pasa ANTES de comprar', () async {
      final store = _conPlanes([AthletePlan.mensual]);

      await checkoutCon(store)
          .start(uid: 'alumno-42', plan: AthletePlan.mensual);

      expect(store.llamadas, ['identificar', 'comprar']);
      expect(store.uidIdentificado, 'alumno-42');
      // Si este test se pone rojo porque alguien movió la identificación
      // después de la compra —o la sacó— la compra va a salir a nombre de un
      // id anónimo, el webhook no va a encontrar a quién acreditarle, y el
      // alumno va a pagar sin recibir nada. No lo arregles moviendo el expect.
      expect(
        store.llamadas.indexOf('identificar'),
        lessThan(store.llamadas.indexOf('comprar')),
      );
    });

    test('compra el plan pedido, no otro', () async {
      final store = _conPlanes([AthletePlan.mensual, AthletePlan.anual]);

      await checkoutCon(store).start(uid: 'a', plan: AthletePlan.anual);

      expect(store.comprados.single, AthletePlan.anual);
    });

    test('restaurar también identifica primero', () async {
      final store = StoreFalso(activosAlRestaurar: {kAthleteEntitlement});

      expect(await checkoutCon(store).restaurar(uid: 'alumno-7'), isTrue);
      expect(store.llamadas, ['identificar', 'restaurar']);
      expect(store.uidIdentificado, 'alumno-7');
    });

    test('restaurar sin nuestro entitlement devuelve false', () async {
      final store = StoreFalso(activosAlRestaurar: const {'otra_cosa'});
      expect(await checkoutCon(store).restaurar(uid: 'a'), isFalse);
    });
  });

  group('start — cómo termina', () {
    test('el entitlement vino activo → comprado', () async {
      expect(
        await checkoutCon(_conPlanes([AthletePlan.mensual]))
            .start(uid: 'a', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.comprado,
      );
    });

    test('cobró y no vino nuestro entitlement → pendiente', () async {
      // Android con pago diferido, o un "Ask to Buy" de iOS esperando al
      // adulto. Decirle "listo" sería mentir; decirle "error" también.
      final store = _conPlanes([AthletePlan.mensual], activos: const {});

      expect(
        await checkoutCon(store).start(uid: 'a', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.pendiente,
      );
    });

    test('vino OTRO entitlement, no el nuestro → pendiente', () async {
      final store =
          _conPlanes([AthletePlan.mensual], activos: const {'otra_cosa'});

      expect(
        await checkoutCon(store).start(uid: 'a', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.pendiente,
      );
    });

    test('EL OTRO TEST QUE IMPORTA: cancelar NO es un error', () async {
      final store = _conPlanes(
        [AthletePlan.mensual],
        tira: const AthleteStoreException(AthleteStoreFalla.cancelada),
      );

      expect(
        await checkoutCon(store).start(uid: 'a', plan: AthletePlan.mensual),
        AthletePurchaseOutcome.cancelado,
      );
    });

    test('cada falla del puerto mapea a su outcome', () async {
      const esperado = {
        AthleteStoreFalla.cancelada: AthletePurchaseOutcome.cancelado,
        AthleteStoreFalla.pendiente: AthletePurchaseOutcome.pendiente,
        AthleteStoreFalla.sinProducto: AthletePurchaseOutcome.sinProducto,
        AthleteStoreFalla.otra: AthletePurchaseOutcome.error,
      };
      // Exhaustivo a propósito: si alguien agrega una falla nueva al puerto y
      // se olvida de mapearla, este test lo dice.
      expect(esperado.keys.toSet(), AthleteStoreFalla.values.toSet());

      for (final e in esperado.entries) {
        final store = _conPlanes(
          [AthletePlan.mensual],
          tira: AthleteStoreException(e.key),
        );
        expect(
          await checkoutCon(store).start(uid: 'a', plan: AthletePlan.mensual),
          e.value,
          reason: 'la falla ${e.key} tiene que dar ${e.value}',
        );
      }
    });
  });

  group('planes', () {
    test('devuelve lo que publica la tienda', () async {
      final store = StoreFalso(
        ofrece: [
          ofertaDe(AthletePlan.mensual, precio: 'USD 2,99'),
          ofertaDe(AthletePlan.anual, precio: 'USD 29,90', porMes: 'USD 2,49'),
        ],
      );

      final planes = await checkoutCon(store).planes();

      expect(
          planes.map((p) => p.plan), [AthletePlan.mensual, AthletePlan.anual]);
      expect(planes.last.precioPorMes, 'USD 2,49');
    });

    test('sin oferta publicada devuelve vacío, no explota', () async {
      expect(await checkoutCon(StoreFalso()).planes(), isEmpty);
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
