/// Gate de regresión visual — dashboard del Coach Hub (#761).
///
/// ## Por qué el dashboard
///
/// Es la composición más densa del Hub y la primera pantalla que ve el PF cada
/// mañana: banner de alerta, welcome card con anillo de adherencia, tira de
/// KPIs, sección de pendientes y columna derecha con la agenda del día. Cinco
/// bloques que se acomodan entre sí — cualquier cambio de altura en uno
/// reordena a los otros cuatro, y eso es invisible en un diff.
///
/// ## Y por qué es la que EXIGE el reloj congelado
///
/// La card de próximas sesiones filtra los turnos con `startsAt.isAfter(now)`. Sin el
/// seam de `AppClock`, este golden pasa a la mañana y falla a la tarde: el
/// turno de las 11:30 del seed entra o no entra según la hora del runner. Es
/// el caso que justificó tocar `lib/` en este cambio — está sembrado a
/// propósito con un turno antes y dos después de las 10:30 congeladas, así el
/// golden cubre las dos ramas del filtro.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_kpi_strip.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_pending.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_right_column.dart';

import 'gate_environment.dart';
import 'gate_harness.dart';
import 'gate_seed.dart';

void main() {
  group(
    'Visual gate — Coach Hub dashboard',
    skip: gateSkipReason(),
    () {
      useGateEnvironment();

      for (final theme in GateTheme.values) {
        testWidgets('desktop 1440x900 — ${theme.slug}', (tester) async {
          await pumpGate(
            tester,
            theme: theme,
            viewport: GateViewport.desktop,
            route: '/dashboard',
          );

          // ── El baseline es válido ANTES de mirar píxeles ─────────────────
          //
          // Un PNG solo dice "esto salió". No sabe si el seed llegó o si la
          // pantalla se rindió a medias. Sin estas aserciones, regenerar
          // goldens sobre un dashboard vacío congelaría la pantalla rota como
          // referencia — y el gate quedaría verde para siempre sobre el
          // defecto. Es la misma lección que docs/security.md §1.4 midió con
          // la suite de reglas: una suite que nadie mira no distingue "cambió
          // porque quisimos" de "se rompió".
          expect(find.byType(CoachHubDashboardScreen), findsOneWidget);
          expect(find.byType(DashboardKpiStrip), findsOneWidget);
          // Las CUATRO cards de la grilla, una por una.
          //
          // Antes acá iba `DashboardRightColumn`, que en desktop ya no se
          // renderiza: sus tres cards van de a pares en filas junto con
          // pendientes. Y pedir las cuatro por separado es más fuerte que
          // pedir el contenedor — el contenedor podía estar y tener adentro
          // una card rendida a medias.
          expect(find.byType(DashboardPendingSection), findsOneWidget);
          expect(find.byType(DashboardProximasSesionesCard), findsOneWidget);
          expect(find.byType(DashboardVencimientos7dCard), findsOneWidget);
          expect(find.byType(DashboardInactivosCard), findsOneWidget);

          expect(
            find.text(kGateTrainerName),
            findsWidgets,
            reason: 'el seed del PF llegó al árbol',
          );
          expect(
            find.textContaining(kGateAthletes[2].name),
            findsWidgets,
            reason:
                'Camila entrena 11:30, después de las 10:30 congeladas: si no '
                'aparece, el filtro de próximas sesiones se comió el turno y '
                'el reloj no quedó congelado',
          );

          expectGatePalette(tester, theme);
          expectGateNoOverflow(tester);

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(gateGoldenName(
              screen: 'dashboard',
              theme: theme,
              viewport: GateViewport.desktop,
            )),
          );
        });
      }
    },
  );
}
