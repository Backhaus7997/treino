// El cartel que le cuenta al PF en qué estado quedó su pago al volver de
// Mercado Pago.
//
// Lo que estos tests fijan NO es que el cartel se vea: es CUÁNDO se calla. Tres
// de los cuatro estados posibles no muestran nada, y cada silencio tiene un
// motivo distinto — si alguno se convierte en un cartel, el PF que sólo entró a
// mirar precios se come una alarma que no le corresponde.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/acreditacion_al_volver.dart';

final _kBanner = find.byKey(const Key('acreditacion_al_volver_banner'));

Widget _harness(AcreditacionChecker checker) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AcreditacionAlVolverBanner(checker: checker),
          ),
        ),
      ),
    );

/// Un checker que cuenta cuántas veces lo llamaron y puede cambiar de respuesta
/// entre llamadas — hace falta para el caso del reintento.
class _Checker {
  _Checker(this._respuestas);
  final List<EstadoAcreditacion> _respuestas;
  int llamadas = 0;

  Future<EstadoAcreditacion> call() async {
    final i = llamadas < _respuestas.length ? llamadas : _respuestas.length - 1;
    llamadas++;
    return _respuestas[i];
  }
}

void main() {
  group('lo que NO muestra, que es la mitad del diseño', () {
    testWidgets('`sinCheckout` no dice nada: entró a mirar precios', (t) async {
      await t.pumpWidget(
          _harness(_Checker([EstadoAcreditacion.sinCheckout]).call));
      await t.pumpAndSettle();

      expect(_kBanner, findsNothing);
    });

    testWidgets('`acreditado` tampoco: la grilla lo cuenta sola', (t) async {
      // `acreditado` NO significa "se acreditó recién" — un PF que ya tenía
      // plan y entra a mirar precios resuelve igual. Un cartel de éxito acá
      // sería felicitarlo por algo que no acaba de pasar.
      await t
          .pumpWidget(_harness(_Checker([EstadoAcreditacion.acreditado]).call));
      await t.pumpAndSettle();

      expect(_kBanner, findsNothing);
    });

    testWidgets(
      'un fallo que NADIE pidió se calla — y es lo que deja quietos los goldens',
      (t) async {
        // El PF no preguntó nada: que no podamos hablar con Mercado Pago es un
        // problema nuestro, no suyo, y el barrido nocturno lo cubre igual.
        await t.pumpWidget(
          _harness(_Checker([EstadoAcreditacion.noDisponible]).call),
        );
        await t.pumpAndSettle();

        expect(_kBanner, findsNothing);
      },
    );

    testWidgets('un checker que EXPLOTA no rompe la pantalla ni grita',
        (t) async {
      await t.pumpWidget(_harness(() async => throw Exception('sin red')));
      await t.pumpAndSettle();

      // El try/catch del widget lo tiene que tragar: si escapara, el binding
      // lo registraria y `takeException` lo devolveria.
      expect(t.takeException(), isNull);
      expect(_kBanner, findsNothing);
    });
  });

  group('lo que SÍ muestra', () {
    testWidgets('`pendiente` avisa que el pago se está confirmando', (t) async {
      await t
          .pumpWidget(_harness(_Checker([EstadoAcreditacion.pendiente]).call));
      await t.pumpAndSettle();

      expect(_kBanner, findsOneWidget);
      expect(find.text('ESTAMOS CONFIRMANDO TU PAGO'), findsOneWidget);
      expect(find.text('CONSULTAR DE NUEVO'), findsOneWidget);
    });

    testWidgets(
      'el fallo SÍ se muestra cuando el PF tocó «consultar de nuevo»',
      (t) async {
        // Acá sí preguntó, y no contestarle sería peor que la alarma.
        final checker = _Checker([
          EstadoAcreditacion.pendiente,
          EstadoAcreditacion.noDisponible,
        ]);
        await t.pumpWidget(_harness(checker.call));
        await t.pumpAndSettle();

        await t.tap(find.text('CONSULTAR DE NUEVO'));
        await t.pumpAndSettle();

        expect(_kBanner, findsOneWidget);
        expect(
            find.text('NO PUDIMOS CONSULTAR A MERCADO PAGO'), findsOneWidget);
      },
    );

    testWidgets('si el reintento acredita, el cartel desaparece', (t) async {
      final checker = _Checker([
        EstadoAcreditacion.pendiente,
        EstadoAcreditacion.acreditado,
      ]);
      await t.pumpWidget(_harness(checker.call));
      await t.pumpAndSettle();
      expect(_kBanner, findsOneWidget);

      await t.tap(find.text('CONSULTAR DE NUEVO'));
      await t.pumpAndSettle();

      expect(_kBanner, findsNothing);
    });
  });

  group('cuántas veces se le pregunta al servidor', () {
    testWidgets('UNA sola vez al montar, no una por rebuild', (t) async {
      // Sin el latch de instancia, cada `setState` volvería a preguntar y un
      // cartel se convertiría en un loop contra la API de Mercado Pago.
      final checker = _Checker([EstadoAcreditacion.pendiente]);
      await t.pumpWidget(_harness(checker.call));
      await t.pumpAndSettle();

      // Varios frames más: nada debería volver a disparar.
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();

      expect(checker.llamadas, 1);
    });

    testWidgets('el botón pregunta exactamente una vez por tap', (t) async {
      final checker = _Checker([EstadoAcreditacion.pendiente]);
      await t.pumpWidget(_harness(checker.call));
      await t.pumpAndSettle();

      await t.tap(find.text('CONSULTAR DE NUEVO'));
      await t.pumpAndSettle();

      expect(checker.llamadas, 2);
    });
  });
}
