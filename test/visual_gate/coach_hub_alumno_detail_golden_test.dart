/// Gate de regresión visual — ficha de alumno del Coach Hub (#761).
///
/// ## Por qué la ficha
///
/// Es la superficie más data-bound del Hub: header con el alumno, métricas de
/// resumen, tabs. Todo lo que muestra sale de datos, así que es la que más
/// formas distintas puede tomar — y la que más fácil se descuadra cuando un
/// valor viene más largo de lo que alguien supuso.
///
/// Se captura la ficha de **Maximiliano Etcheverry Paz** (26 caracteres) a
/// propósito: es el nombre más largo del seed. Si el header trunca, el golden
/// lo muestra; con "Ana Ruiz" no se enteraría nadie.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gate_environment.dart';
import 'gate_harness.dart';
import 'gate_seed.dart';

void main() {
  group(
    'Visual gate — Coach Hub ficha de alumno',
    skip: gateSkipReason(),
    () {
      useGateEnvironment();

      final alumno = kGateAthletes[3];

      for (final theme in GateTheme.values) {
        testWidgets('desktop 1440x900 — ${theme.slug}', (tester) async {
          await pumpGate(
            tester,
            theme: theme,
            viewport: GateViewport.desktop,
            route: '/alumnos/${alumno.id}',
          );

          expect(
            find.textContaining(alumno.name),
            findsWidgets,
            reason: 'la ficha del alumno con el nombre más largo del seed (26 '
                'caracteres) — si no llegó, la captura no ejercita el truncado',
          );
          expect(
            find.text('No se pudo cargar el resumen.'),
            findsNothing,
            reason:
                'la ficha trata un error en mediciones o rutinas como error del '
                'resumen entero. Ese estado sale igual de determinístico que el '
                'bueno, así que sin esta aserción un baseline de mensaje de '
                'error pasaría por baseline válido',
          );
          expectGatePalette(tester, theme);
          expectGateNoOverflow(tester);

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(gateGoldenName(
              screen: 'alumno-detail',
              theme: theme,
              viewport: GateViewport.desktop,
            )),
          );
        });
      }
    },
  );
}
