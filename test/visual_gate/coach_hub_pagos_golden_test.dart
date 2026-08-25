/// Gate de regresión visual — Pagos del Coach Hub (#761).
///
/// ## Por qué Pagos
///
/// Es la superficie de plata, y estructuralmente la más frágil: tira de KPIs
/// arriba, tabla abajo, chips de estado por fila. Una columna que crece unos
/// píxeles desborda la de al lado, y eso no se ve en un diff.
///
/// El seed le da montos de cuatro, cinco y seis cifras — `fmtArs` agrupa de a
/// tres con puntos, así que `$170.500` es medio caracter más ancho que
/// `$42.000` y ahí es donde una columna angosta se parte primero.
///
/// ## Los buckets se calculan de verdad
///
/// El harness stubea `trainerPaymentsProvider` con los pagos CRUDOS: quién está
/// vencido y quién por vencer lo decide el `pagosBucketsProvider` real,
/// clasificando en ART contra el reloj congelado. Si mañana alguien rompe ese
/// bucketing, un pago salta de columna y el golden lo muestra.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/pagos_web_screen.dart';

import 'gate_environment.dart';
import 'gate_harness.dart';
import 'gate_seed.dart';

void main() {
  group(
    'Visual gate — Coach Hub pagos',
    skip: gateSkipReason(),
    () {
      useGateEnvironment();

      for (final theme in GateTheme.values) {
        testWidgets('desktop 1440x900 — ${theme.slug}', (tester) async {
          await pumpGate(
            tester,
            theme: theme,
            viewport: GateViewport.desktop,
            route: '/pagos',
          );

          expect(find.byType(PagosScreen), findsOneWidget);
          expect(
            find.textContaining('170.500'),
            findsWidgets,
            reason: 'los dos vencidos del seed suman \$170.500. Si no está, el '
                'bucketing contra el reloj congelado los clasificó en otro '
                'lado y esta captura no es la que el gate cree que es',
          );
          expect(
            find.textContaining(kGateAthletes[1].name),
            findsWidgets,
            reason:
                'el pago por vencer del seed es de Bruno. Si la fila dice el '
                'fallback "Alumno", la resolución de nombres se rompió — y esa '
                'captura es igual de determinística, así que sólo la atrapa una '
                'aserción',
          );
          expectGatePalette(tester, theme);
          expectGateNoOverflow(tester);

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(gateGoldenName(
              screen: 'pagos',
              theme: theme,
              viewport: GateViewport.desktop,
            )),
          );
        });
      }
    },
  );
}
