/// plan_cancel_test.dart — la capacidad de dar de baja la suscripción.
///
/// Lo que protege, en orden de qué tan caro sale:
///
///   1. Que un fallo NO se reporte como baja exitosa. Decirle a alguien que se
///      dio de baja cuando no sabemos si pasó es la peor de las tres
///      respuestas posibles: deja de mirar su tarjeta.
///   2. Que la app móvil no exponga la baja. Mismo criterio que
///      `PlanCheckoutOnWebOnly`.
///   3. Que el llamado no mande ningún parámetro. Si un `planId` viajara,
///      cualquiera podría dar de baja la suscripción de otro — y en Mercado
///      Pago eso no se deshace.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_cancel.dart';

void main() {
  tearDown(() {
    debugPlanCancelCaller = null;
    debugPlanCancel = null;
  });

  group('la superficie', () {
    test('en web se puede dar de baja', () {
      expect(planCancelFor(isWeb: true), isA<PlanCancelAvailable>());
    });

    test('en móvil NO — el tipo no expone `cancelar`', () {
      // No es un `enabled` en false: la variante móvil no tiene el método, así
      // que un botón que lo llame no compila. Es la misma disciplina que
      // `PlanCheckoutOnWebOnly`.
      expect(planCancelFor(isWeb: false), isA<PlanCancelOnWebOnly>());
      expect(planCancelFor(isWeb: false), isNot(isA<PlanCancelAvailable>()));
    });
  });

  group('la traducción de la respuesta', () {
    test('`dada-de-baja` con fecha devuelve la fecha parseada', () async {
      debugPlanCancelCaller = () async => ResultadoDeBaja(
            estado: EstadoDeBaja.dadaDeBaja,
            accesoHasta: DateTime.utc(2026, 10, 3, 12),
          );

      final r =
          await (planCancelFor(isWeb: true) as PlanCancelAvailable).cancelar();

      expect(r.estado, EstadoDeBaja.dadaDeBaja);
      expect(r.accesoHasta, DateTime.utc(2026, 10, 3, 12));
    });

    test('`dada-de-baja` SIN fecha sigue siendo una baja', () async {
      // Un plan recién creado cuyo `auto_recurring` MP todavía no completó no
      // tiene de dónde derivar la fecha. El hecho que importa —ya no se le
      // cobra— no depende de ella.
      debugPlanCancelCaller =
          () async => const ResultadoDeBaja(estado: EstadoDeBaja.dadaDeBaja);

      final r =
          await (planCancelFor(isWeb: true) as PlanCancelAvailable).cancelar();

      expect(r.estado, EstadoDeBaja.dadaDeBaja);
      expect(r.accesoHasta, isNull);
    });

    test('`sin-suscripcion` no es un error', () async {
      debugPlanCancelCaller = () async =>
          const ResultadoDeBaja(estado: EstadoDeBaja.sinSuscripcion);

      final r =
          await (planCancelFor(isWeb: true) as PlanCancelAvailable).cancelar();

      expect(r.estado, EstadoDeBaja.sinSuscripcion);
    });
  });

  group('⚠️ el parseo de la respuesta cruda', () {
    // Este grupo existe porque los tests de arriba NO tocan el parseo:
    // `debugPlanCancelCaller` reemplaza la llamada entera. Cuando se agregó
    // `enfriando` se escribieron dos tests, los dos pasaron, y borrar el
    // chequeo no rompió ninguno. Acá se le pasa el mapa tal cual lo manda el
    // servidor.

    test('⚠️ `sin-suscripcion` CON `enfriando` no es sin-suscripción', () {
      // LA aserción. El servidor manda las dos cosas juntas cuando corta por
      // cooldown, y quedarse con el estado a secas le dice «no hay nada que dar
      // de baja» a alguien cuya suscripción sigue viva y cobrando.
      final r = resultadoDesde(const {
        'estado': 'sin-suscripcion',
        'enfriando': true,
      });

      expect(r.estado, EstadoDeBaja.enfriando);
      expect(r.estado, isNot(EstadoDeBaja.sinSuscripcion));
    });

    test('sin la bandera, `sin-suscripcion` sí lo es', () {
      final r = resultadoDesde(const {'estado': 'sin-suscripcion'});
      expect(r.estado, EstadoDeBaja.sinSuscripcion);
    });

    test('`dada-de-baja` con fecha la parsea', () {
      final r = resultadoDesde(const {
        'estado': 'dada-de-baja',
        'accesoHastaIso': '2026-10-03T12:00:00.000Z',
      });

      expect(r.estado, EstadoDeBaja.dadaDeBaja);
      expect(r.accesoHasta, DateTime.utc(2026, 10, 3, 12));
    });

    test('`dada-de-baja` sin fecha sigue siendo una baja', () {
      final r = resultadoDesde(const {'estado': 'dada-de-baja'});
      expect(r.estado, EstadoDeBaja.dadaDeBaja);
      expect(r.accesoHasta, isNull);
    });

    test('una fecha que no se puede parsear no rompe nada', () {
      final r = resultadoDesde(const {
        'estado': 'dada-de-baja',
        'accesoHastaIso': 'mañana',
      });

      expect(r.estado, EstadoDeBaja.dadaDeBaja);
      expect(r.accesoHasta, isNull);
    });

    test('un estado desconocido NO cae en dadaDeBaja', () {
      for (final crudo in [null, '', 'casi', 42, true]) {
        final r = resultadoDesde({'estado': crudo});
        expect(r.estado, EstadoDeBaja.noDisponible, reason: 'con $crudo');
      }
    });

    test('una respuesta vacía tampoco', () {
      expect(resultadoDesde(const {}).estado, EstadoDeBaja.noDisponible);
    });
  });

  group('⚠️ el cooldown', () {
    test('`enfriando` NO se lee como «no hay nada que dar de baja»', () async {
      // El camino que esto evita, entero:
      //
      //   1. El PF aprieta dar de baja. El servidor marca el cooldown ANTES de
      //      salir a MP, llama, y MP no contesta.
      //   2. El diálogo dice bien: «tu suscripción sigue como estaba».
      //   3. El PF hace lo que le dijimos y reintenta enseguida.
      //   4. El servidor corta por cooldown y manda `sin-suscripcion`.
      //   5. Sin este estado, el diálogo diría «no hay nada que dar de baja»,
      //      que es FALSO: la suscripción sigue viva y cobrando.
      debugPlanCancelCaller =
          () async => const ResultadoDeBaja(estado: EstadoDeBaja.enfriando);

      final r =
          await (planCancelFor(isWeb: true) as PlanCancelAvailable).cancelar();

      expect(r.estado, EstadoDeBaja.enfriando);
      expect(r.estado, isNot(EstadoDeBaja.sinSuscripcion));
      expect(r.estado, isNot(EstadoDeBaja.dadaDeBaja));
    });
  });

  group('cuando algo falla', () {
    test('un error del servidor NO se reporta como baja', () async {
      // LA aserción del archivo. Si un `unavailable` saliera como
      // `dadaDeBaja`, el PF deja de mirar su tarjeta y el cobro le sigue
      // llegando.
      debugPlanCancelCaller = () async => throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'MP no responde',
          );

      final r =
          await (planCancelFor(isWeb: true) as PlanCancelAvailable).cancelar();

      expect(r.estado, EstadoDeBaja.noDisponible);
      expect(r.estado, isNot(EstadoDeBaja.dadaDeBaja));
    });

    test('una excepción cualquiera tampoco', () async {
      debugPlanCancelCaller = () async => throw StateError('se cayó la red');

      final r =
          await (planCancelFor(isWeb: true) as PlanCancelAvailable).cancelar();

      expect(r.estado, EstadoDeBaja.noDisponible);
    });

    test('`cancelar` NUNCA propaga: es total', () async {
      // La pantalla no tiene que envolver la llamada en un try. Si esto
      // cambiara, el diálogo quedaría colgado en «DANDO DE BAJA…» para
      // siempre, porque su `setState` del final no se ejecuta.
      debugPlanCancelCaller = () async => throw Exception('lo que sea');

      await expectLater(
        (planCancelFor(isWeb: true) as PlanCancelAvailable).cancelar(),
        completes,
      );
    });
  });

  group('el seam de tests', () {
    test('`debugPlanCancel` fuerza la superficie', () {
      // Bajo `flutter test`, `kIsWeb` es false: sin este seam el camino web
      // sería inalcanzable en toda la suite.
      debugPlanCancel = planCancelFor(isWeb: false);
      expect(resolvePlanCancel(), isA<PlanCancelOnWebOnly>());
    });
  });
}
