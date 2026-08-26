/// Gate de regresión visual — shell del Coach Hub (#761).
///
/// ## Por qué el shell es la primera pantalla del gate
///
/// Es la única que se hereda: sidebar, top bar y el marco de contenido salen
/// del mismo `CoachHubScaffold` para las once secciones. Una regresión acá no
/// rompe una pantalla, las rompe todas — y es la que más barato sale
/// fotografiar, porque no depende de datos de negocio.
///
/// ## Por qué las tres anchuras se capturan ACÁ y no en cada sección
///
/// `viewportFor()` vive en el shell: `< 768` cambia el scaffold entero por
/// `MobileBanner`, `768–1279` fuerza el sidebar a colapsado, `>= 1280` respeta
/// la preferencia guardada. Son tres ramas de UNA decisión, y esa decisión es
/// del shell. Capturarlas en las cinco pantallas serían quince goldens de la
/// misma rama: quince que regenerar cada vez que cambia un padding del
/// sidebar, y así es como un gate se vuelve un peaje y termina apagado.
///
/// Las secciones se capturan sólo en desktop, que es la superficie real del
/// Coach Hub. Si mañana una sección adquiere un layout propio por debajo de
/// 1280, ESA sección suma su viewport acá — deliberadamente, con su porqué
/// escrito, no por simetría.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_sidebar.dart';
import 'package:treino/features/coach_hub/presentation/shell/coach_hub_top_bar.dart';
import 'package:treino/features/coach_hub/presentation/shell/mobile_banner.dart';

import 'gate_environment.dart';
import 'gate_harness.dart';
import 'gate_seed.dart';

void main() {
  group(
    'Visual gate — Coach Hub shell',
    skip: gateSkipReason(),
    () {
      useGateEnvironment();
      testGateEnvironmentIsPinned();

      for (final theme in GateTheme.values) {
        // SIN golden, y no es un olvido.
        //
        // El shell a >= 1280 muestra la sección activa adentro, así que su
        // captura sale byte a byte idéntica a `dashboard__<tema>__desktop.png`
        // — verificado con sha256. Dos archivos para una sola imagen es deuda
        // pura: dos PNG que regenerar en cada cambio del sidebar, y uno de los
        // dos siempre va a quedar desactualizado sin que nadie se entere.
        //
        // El cromo de desktop ya viaja dentro del golden de CADA sección. Lo
        // que no viaja en ninguna es el CONTRATO de la rama expandida, y eso
        // es lo que se afirma acá.
        testWidgets('desktop 1440x900 — contrato expandido — ${theme.slug}',
            (tester) async {
          await pumpGate(
            tester,
            theme: theme,
            viewport: GateViewport.desktop,
          );

          _expectShellRendered(tester, theme);
          expect(
            find.text('DASHBOARD'),
            findsWidgets,
            reason: 'a >= 1280 el sidebar está expandido y muestra labels',
          );
          expect(
            find.text(kGateTrainerName),
            findsWidgets,
            reason: 'expandido, el footer del sidebar muestra el nombre entero',
          );
        });

        testWidgets('compact 1024x900 — ${theme.slug}', (tester) async {
          await pumpGate(
            tester,
            theme: theme,
            viewport: GateViewport.compact,
          );

          _expectShellRendered(tester, theme);
          expect(
            find.byType(CoachHubSidebar),
            findsOneWidget,
            reason:
                'entre 768 y 1279 el sidebar sigue ahí, forzado a colapsado — '
                'no desaparece',
          );
          expect(
            find.text(kGateTrainerName),
            findsNothing,
            reason:
                'colapsado el footer deja SOLO el avatar (_ProfileRow). Que el '
                'nombre entero aparezca acá significa que el force-collapse de '
                'viewportFor() dejó de aplicarse, y esta captura estaría '
                'fotografiando la rama desktop con otro ancho',
          );

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(gateGoldenName(
              screen: 'shell',
              theme: theme,
              viewport: GateViewport.compact,
            )),
          );
        });

        testWidgets('mobile 420x900 — ${theme.slug}', (tester) async {
          await pumpGate(
            tester,
            theme: theme,
            viewport: GateViewport.mobile,
          );

          expect(
            find.byType(MobileBanner),
            findsOneWidget,
            reason:
                'abajo de 768 el banner REEMPLAZA al scaffold (ADR-CHW-004)',
          );
          expect(find.byType(CoachHubSidebar), findsNothing);
          expectGatePalette(tester, theme);
          expectGateNoOverflow(tester);

          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(gateGoldenName(
              screen: 'shell',
              theme: theme,
              viewport: GateViewport.mobile,
            )),
          );
        });
      }
    },
  );
}

/// Lo que tiene que ser cierto en la captura ANTES de comparar píxeles.
///
/// Esta es la diferencia entre un gate y un corpus heredado. Un PNG solo dice
/// "esto fue lo que salió"; no distingue un baseline correcto de uno que
/// alguien aceptó sin mirar. Si mañana el seed se rompe y el shell rinde vacío,
/// regenerar goldens congelaría la pantalla rota como verdad nueva — y el gate
/// quedaría verde para siempre sobre un defecto. Estas aserciones son el
/// candado: fallan antes de llegar a los píxeles.
void _expectShellRendered(WidgetTester tester, GateTheme theme) {
  expect(find.byType(CoachHubScaffold), findsOneWidget);
  expect(find.byType(CoachHubSidebar), findsOneWidget);
  expect(find.byType(CoachHubTopBar), findsOneWidget);
  // La inicial y no el nombre entero: colapsado, el sidebar deja sólo el
  // avatar. La "M" de Mateo sale del seed igual, así que sirve de sonda en las
  // dos ramas; el nombre completo lo afirma el test de desktop, que es donde
  // corresponde que se vea.
  expect(
    find.text('M'),
    findsWidgets,
    reason: 'el seed llegó al árbol: la inicial del PF sale de su displayName',
  );
  expectGatePalette(tester, theme);
  expectGateNoOverflow(tester);
}
