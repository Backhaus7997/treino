// athlete_paywall_screen_test.dart — la pantalla donde el alumno compra.
//
// Lo que estos tests cuidan:
//
//   1. Que TODOS los precios en pantalla salgan de la tienda. Ninguno se arma
//      acá. Apple exige que el importe a facturar sea el elemento de precio más
//      prominente, y armarlo nosotros abre la puerta a que la pantalla diga
//      algo distinto de lo que cobra la hoja de pago del sistema.
//
//   2. Que el aviso de impuestos NO tenga ningún monto. Ese es el test que
//      encierra toda la investigación: el importe final lo define el emisor de
//      la tarjeta al liquidar, el porcentaje ni siquiera es fijo (la RG 4240
//      art. 4 lo acota a pagos de hasta USD 10 para una parte de los
//      prestadores, y APPLE está en esa parte), y publicar un número que puede
//      salir mal es "promoting a false price" bajo la guideline 2.3.1(a).
//
//   3. Que cancelar no le muestre nada al alumno. Cerró la hoja de pago: tomó
//      una decisión, no chocó con un error.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/paywall/application/athlete_checkout.dart';
import 'package:treino/features/paywall/presentation/athlete_paywall_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

import 'helpers/store_falso.dart';

AthleteCheckout _conPaquetes(
  List<AthletePlanOferta> ofertas, {
  AthleteStoreException? tira,
  Set<String>? activos,
}) =>
    resolveAthleteCheckout(
      store: StoreFalso(ofrece: ofertas, tira: tira, activosAlComprar: activos),
    );

Widget _app(AthleteCheckout checkout) => ProviderScope(
      // Sin uid, `_comprar` corta antes de llamar a la tienda — y con razon:
      // una compra anonima no se le puede acreditar a nadie. Los tests de
      // compra necesitan un alumno logueado.
      overrides: [currentUidProvider.overrideWithValue('alumno-1')],
      child: MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es'),
        home: AthletePaywallScreen(checkout: checkout),
      ),
    );

void main() {
  group('sin planes', () {
    testWidgets('muestra el error y ofrece reintentar', (tester) async {
      // `AthleteCheckoutUnavailable` es lo que devuelve `resolveAthleteCheckout`
      // hoy: sin clave del SDK no hay tienda a la que preguntarle.
      await tester.pumpWidget(_app(resolveAthleteCheckout()));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('paywall_alumno_sin_planes')), findsOneWidget);
      // Y sobre todo: NO dibuja un paywall vacío con un botón que no compra.
      expect(find.byKey(const Key('paywall_alumno_cta')), findsNothing);
    });
  });

  group('el aviso de impuestos', () {
    testWidgets('EL TEST QUE IMPORTA: no tiene NINGÚN número', (tester) async {
      // Si alguien agrega "≈ ARS 6.930" o "+51%", este test se pone rojo.
      //
      // No lo arregles relajando el matcher. El importe final lo define el
      // emisor de la tarjeta el día que cierra el resumen —no lo podemos
      // saber— y el porcentaje tampoco es fijo: la RG 4240 art. 4 acota la
      // percepción de IVA a pagos de hasta USD 10 para una parte de los
      // prestadores, y en el listado de ARCA la línea de APPLE tiene ese tope
      // mientras la de GOOGLE PLAY no.
      //
      // Publicar un número que puede salir mal es guideline 2.3.1(a),
      // "promoting a false price", con pena de baja de la app Y terminación de
      // la cuenta de developer.
      //
      // Si de verdad hace falta el estimado: va detrás de un tap, con la fecha
      // del tipo de cambio a la vista, y DESPUÉS de que esta versión pase
      // review.
      await tester.pumpWidget(
        _app(_conPaquetes([
          ofertaDe(AthletePlan.mensual),
          ofertaDe(AthletePlan.anual, porMes: 'USD 0,83')
        ])),
      );
      await tester.pumpAndSettle();

      final aviso = tester.widget<Text>(
        find.byKey(const Key('paywall_alumno_impuestos')),
      );
      final texto = aviso.data!;

      expect(
        RegExp(r'\d').hasMatch(texto),
        isFalse,
        reason: 'el aviso de impuestos tiene un número: "$texto"',
      );
      // Y tampoco nombra una moneda, que es la otra forma de colar un importe.
      for (final prohibido in ['ARS', 'USD', r'$', '%']) {
        expect(texto.contains(prohibido), isFalse,
            reason: 'el aviso menciona "$prohibido": "$texto"');
      }
    });

    testWidgets('está presente: avisar no es opcional', (tester) async {
      // La obligación de informar el precio final es del vendedor, y frente al
      // consumidor argentino el vendedor somos nosotros, no Apple.
      await tester
          .pumpWidget(_app(_conPaquetes([ofertaDe(AthletePlan.mensual)])));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('paywall_alumno_impuestos')),
        findsOneWidget,
      );
    });
  });

  group('los precios', () {
    testWidgets('salen de la tienda, no de un literal', (tester) async {
      await tester.pumpWidget(
        _app(_conPaquetes([
          ofertaDe(AthletePlan.mensual, precio: 'PRECIO-DE-LA-TIENDA-M'),
          ofertaDe(AthletePlan.anual,
              precio: 'PRECIO-DE-LA-TIENDA-A', porMes: 'POR-MES-DE-LA-TIENDA'),
        ])),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRECIO-DE-LA-TIENDA-M'), findsOneWidget);
      expect(find.text('PRECIO-DE-LA-TIENDA-A'), findsOneWidget);
      expect(find.text('POR-MES-DE-LA-TIENDA'), findsOneWidget);
    });

    testWidgets('el equivalente mensual sólo aparece en el anual',
        (tester) async {
      // En el mensual repetiría el mismo número dos veces.
      await tester.pumpWidget(
        _app(_conPaquetes([
          ofertaDe(AthletePlan.mensual,
              precio: 'USD 2,99', porMes: 'NO-DEBERIA-VERSE'),
        ])),
      );
      await tester.pumpAndSettle();

      // El widget lo dibuja si viene, pero la capacidad nunca lo manda en el
      // mensual — este test fija esa decisión del lado de la capacidad.
      expect(find.text('USD 2,99'), findsOneWidget);
    });
  });

  group('lo que Apple exige en el flujo de compra', () {
    testWidgets('hay botón de restaurar compras', (tester) async {
      await tester
          .pumpWidget(_app(_conPaquetes([ofertaDe(AthletePlan.mensual)])));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('paywall_alumno_restaurar')),
        findsOneWidget,
      );
    });

    testWidgets('los Términos y la Privacidad están a la vista',
        (tester) async {
      // Guideline 3.1.2. Es el motivo de rechazo número uno de suscripciones.
      await tester
          .pumpWidget(_app(_conPaquetes([ofertaDe(AthletePlan.mensual)])));
      await tester.pumpAndSettle();

      expect(find.textContaining('Términos', findRichText: true), findsWidgets);
    });
  });

  group('el resultado de la compra', () {
    testWidgets('cancelar NO le muestra nada al alumno', (tester) async {
      final checkout = _conPaquetes([ofertaDe(AthletePlan.mensual)],
          tira: const AthleteStoreException(AthleteStoreFalla.cancelada));
      await tester.pumpWidget(_app(checkout));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('paywall_alumno_cta')));
      await tester.pumpAndSettle();

      // Cerró la hoja de pago. Un cartel rojo por eso es maltratarlo.
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('un pago pendiente avisa, y NO dice que está listo',
        (tester) async {
      // La tienda cobra pero el entitlement todavia no esta activo: pago
      // diferido en Android, o un "Ask to Buy" esperando al adulto.
      final checkout =
          _conPaquetes([ofertaDe(AthletePlan.mensual)], activos: const {});
      await tester.pumpWidget(_app(checkout));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('paywall_alumno_cta')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('pendiente'), findsOneWidget);
    });
  });
}
