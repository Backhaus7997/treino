// free_plan_limit_sheet_pro_test.dart — la tarjeta de TREINO Pro de la hoja.
//
// ─── Qué cuida este archivo ─────────────────────────────────────────────────
//
// La hoja de límite, además de explicar el tope, describe TREINO Pro. Tres
// cosas de esa descripción se pueden romper sin que nada más se entere:
//
//   1. **Que responda al tope que se tocó.** El beneficio que corresponde va
//      primero y con la etiqueta. Si el mapeo se corre, el alumno que quiso
//      un cuarto día lee «Gráficos de 3 meses» arriba de todo.
//   2. **Que los números salgan de las constantes.** Un tope escrito a mano en
//      el `.arb` ya quedó mintiendo una vez.
//   3. **Que la animación TERMINE.** Un loop infinito quema batería y cuelga el
//      `pumpAndSettle` de cada test que abre la hoja; con reduce-motion no
//      tiene que animar nada.
//
// Que la tarjeta no ANUNCIE el mail ni ofrezca comprar no se prueba acá: eso lo
// cuidan los guards de `superficie_de_cobro_alumno_test.dart`, que escanean la
// carpeta entera.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/paywall/domain/athlete_entitlement.dart';
import 'package:treino/features/paywall/presentation/free_plan_limit_sheet.dart';
import 'package:treino/features/paywall/presentation/treino_pro_showcase.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Monta un botón que abre la hoja con [limit]. Sin uid, así la anotación del
/// tope no corre: la cuida `free_plan_limit_sheet_registro_test.dart`.
Future<void> _montar(WidgetTester tester, FreePlanLimit limit) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentUidProvider.overrideWithValue(null)],
      child: MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFreePlanLimitSheet(
                context,
                limit: limit,
                actual: 5,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
}

Finder _fila(TreinoProBenefit b) =>
    find.byKey(Key('treino_pro_benefit_${b.name}'));

const _etiqueta = Key('treino_pro_match_tag');

/// Lo que la hoja tiene que resaltar para cada tope. Escrito a mano, y a
/// propósito: si se copiara el `switch` de la hoja, este test confirmaría lo
/// que sea que la hoja haga.
const _esperado = <FreePlanLimit, TreinoProBenefit>{
  FreePlanLimit.days: TreinoProBenefit.days,
  FreePlanLimit.shapeDays: TreinoProBenefit.days,
  FreePlanLimit.weeks: TreinoProBenefit.weeks,
  FreePlanLimit.shapeWeeks: TreinoProBenefit.weeks,
  FreePlanLimit.premiumTemplate: TreinoProBenefit.templates,
  FreePlanLimit.customizeTemplate: TreinoProBenefit.customize,
  FreePlanLimit.routineCount: TreinoProBenefit.routines,
  FreePlanLimit.chartHistory: TreinoProBenefit.charts,
};

void main() {
  test('la tabla del test cubre todos los topes', () {
    // Si se suma un tope y nadie lo agrega acá, el grupo de abajo no lo
    // prueba y queda verde igual.
    expect(_esperado.keys.toSet(), FreePlanLimit.values.toSet());
  });

  group('el beneficio que responde al tope va primero y con etiqueta', () {
    for (final MapEntry(key: limit, value: beneficio) in _esperado.entries) {
      testWidgets('${limit.name} → ${beneficio.name}', (tester) async {
        await _montar(tester, limit);
        await tester.pumpAndSettle();

        // Están los seis, no sólo el resaltado.
        for (final b in TreinoProBenefit.values) {
          expect(_fila(b), findsOneWidget, reason: 'falta ${b.name}');
        }

        // Una sola etiqueta, y adentro de la fila que corresponde.
        expect(find.byKey(_etiqueta), findsOneWidget);
        expect(
          find.descendant(
              of: _fila(beneficio), matching: find.byKey(_etiqueta)),
          findsOneWidget,
        );

        // Y arriba de todas las demás.
        final arriba = tester.getTopLeft(_fila(beneficio)).dy;
        for (final b in TreinoProBenefit.values.where((b) => b != beneficio)) {
          expect(
            tester.getTopLeft(_fila(b)).dy,
            greaterThan(arriba),
            reason: '${b.name} quedó arriba del resaltado',
          );
        }
      });
    }
  });

  testWidgets('los números de TREINO Pro salen de las constantes',
      (tester) async {
    await _montar(tester, FreePlanLimit.days);
    await tester.pumpAndSettle();

    expect(find.text('Rutinas de hasta $kMaxRoutineDays días'), findsOneWidget);
    expect(
      find.text('Hasta $kMaxRoutineWeeks semanas, con periodización'),
      findsOneWidget,
    );
    expect(find.text('Hasta $kMaxOwnRoutines rutinas propias'), findsOneWidget);
  });

  testWidgets('la coreografía anima y TERMINA, y la salida cierra la hoja',
      (tester) async {
    await _montar(tester, FreePlanLimit.days);
    // Hasta que la hoja termina de subir.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // La etiqueta es lo último de la coreografía: con la hoja recién subida
    // todavía no llegó a opacidad plena. Mirar `hasScheduledFrame` acá no
    // probaría nada — el ripple del botón que abrió la hoja también agenda
    // cuadros.
    expect(_opacidadMinimaDeLaEtiqueta(tester), lessThan(1));

    // Y se apaga sola. Si algo quedara en loop, `pumpAndSettle` no volvería.
    await tester.pumpAndSettle();
    expect(_opacidadMinimaDeLaEtiqueta(tester), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.tap(find.byKey(const Key('free_plan_limit_dismiss')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('con reduce-motion todo está en su lugar apenas sube la hoja',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _montar(tester, FreePlanLimit.weeks);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // El mismo instante en que, sin reduce-motion, la etiqueta todavía no
    // llegó: acá ya está plena.
    expect(_opacidadMinimaDeLaEtiqueta(tester), 1);

    // Y no queda nada animando. Un segundo alcanza para que se apague el
    // ripple del botón y queda lejos de los ~1,9 s de la coreografía: si la
    // tarjeta estuviera animando, seguiría agendando cuadros.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

/// La opacidad efectiva de la etiqueta: el mínimo entre todos los fundidos que
/// la envuelven (la tarjeta, la fila y el de la etiqueta misma).
double _opacidadMinimaDeLaEtiqueta(WidgetTester tester) {
  final fundidos = tester.widgetList<FadeTransition>(
    find.ancestor(
      of: find.byKey(_etiqueta),
      matching: find.byType(FadeTransition),
    ),
  );
  expect(fundidos, isNotEmpty);
  return fundidos.map((f) => f.opacity.value).reduce((a, b) => a < b ? a : b);
}
