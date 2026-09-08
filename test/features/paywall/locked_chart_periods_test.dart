// El gate del historial de gráficos: free mira hasta un mes, pago hasta un año.
//
// Los dos ejes que cubren estos tests:
//   1. Qué períodos quedan bloqueados y para quién.
//   2. Que el selector NO seleccione un período bloqueado — si lo hiciera, el
//      gráfico mostraría el año igual y el candado sería decorativo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart';
import 'package:treino/features/paywall/domain/athlete_entitlement.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_section.dart';

const _labels = ChartPeriodLabels(
  last30dLabel: 'Últimos 30 días',
  thisWeekLabel: 'Esta semana',
  monthLabel: 'Este mes',
  last3mLabel: '3 meses',
  last1yLabel: '1 año',
);

ProviderContainer _container({
  bool? paywallEnabled,
  AthleteEntitlement? entitlement,
}) {
  final c = ProviderContainer(
    overrides: [
      if (paywallEnabled != null)
        athletePaywallEnabledProvider.overrideWithValue(paywallEnabled),
      if (entitlement != null)
        athleteEntitlementProvider.overrideWithValue(entitlement),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _pumpSelector(
  WidgetTester tester, {
  required Set<ChartPeriod> locked,
  required void Function(ChartPeriod) onSelect,
  void Function(ChartPeriod)? onLockedTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: ChartPeriodSelector(
          selected: ChartPeriod.last30d,
          labels: _labels,
          onSelect: onSelect,
          lockedPeriods: locked,
          onLockedTap: onLockedTap,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('lockedChartPeriodsProvider', () {
    test('alumno free: 3 meses y 1 año bloqueados', () {
      final c = _container(
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );
      expect(c.read(lockedChartPeriodsProvider), kPaidChartPeriods);
    });

    test('los períodos cortos NUNCA se bloquean', () {
      // El free tiene que poder mirar su mes. Si esto cambiara, el gate
      // dejaría de ser "hasta un mes" y pasaría a ser "casi nada".
      final c = _container(
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );
      final locked = c.read(lockedChartPeriodsProvider);
      expect(locked.contains(ChartPeriod.last30d), isFalse);
      expect(locked.contains(ChartPeriod.thisWeek), isFalse);
      expect(locked.contains(ChartPeriod.month), isFalse);
    });

    test('el período por defecto nunca queda bloqueado', () {
      // Si el default cayera del lado pago, la pantalla abriría mostrando la
      // hoja de límite en la cara, sin que nadie haya tocado nada.
      final c = _container(
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );
      expect(
        c.read(lockedChartPeriodsProvider).contains(ChartPeriod.defaultPeriod),
        isFalse,
      );
    });

    test('alumno con derecho: nada bloqueado', () {
      final c = _container(
        paywallEnabled: true,
        entitlement: AthleteEntitlement.entitled,
      );
      expect(c.read(lockedChartPeriodsProvider), isEmpty);
    });

    test('entitlement unknown: nada bloqueado — falla ABIERTO', () {
      final c = _container(
        paywallEnabled: true,
        entitlement: AthleteEntitlement.unknown,
      );
      expect(c.read(lockedChartPeriodsProvider), isEmpty);
    });

    test('flag apagado: nada bloqueado, aunque sea free', () {
      // El estado en que esto shipea.
      final c = _container(
        paywallEnabled: false,
        entitlement: AthleteEntitlement.free,
      );
      expect(c.read(lockedChartPeriodsProvider), isEmpty);
    });
  });

  group('ChartPeriodSelector con períodos bloqueados', () {
    testWidgets('tocar uno bloqueado NO lo selecciona, y avisa',
        (tester) async {
      // El corazón del gate. Si `onSelect` se disparara, el período quedaría
      // elegido y el gráfico mostraría el año — el candado sería decorativo.
      final seleccionados = <ChartPeriod>[];
      final bloqueados = <ChartPeriod>[];

      await _pumpSelector(
        tester,
        locked: kPaidChartPeriods,
        onSelect: seleccionados.add,
        onLockedTap: bloqueados.add,
      );

      await tester.tap(find.byType(ChartPeriodSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 año').last);
      await tester.pumpAndSettle();

      expect(seleccionados, isEmpty, reason: 'no debe quedar seleccionado');
      expect(bloqueados, [ChartPeriod.last1y]);
    });

    testWidgets('tocar uno libre sí selecciona', (tester) async {
      final seleccionados = <ChartPeriod>[];
      final bloqueados = <ChartPeriod>[];

      await _pumpSelector(
        tester,
        locked: kPaidChartPeriods,
        onSelect: seleccionados.add,
        onLockedTap: bloqueados.add,
      );

      await tester.tap(find.byType(ChartPeriodSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Este mes').last);
      await tester.pumpAndSettle();

      expect(seleccionados, [ChartPeriod.month]);
      expect(bloqueados, isEmpty);
    });

    testWidgets('los bloqueados se muestran, no se esconden', (tester) async {
      // Esconderlos dejaría al alumno sin saber que existen, y acá el punto es
      // justamente mostrar qué da pagar.
      await _pumpSelector(
        tester,
        locked: kPaidChartPeriods,
        onSelect: (_) {},
      );
      await tester.tap(find.byType(ChartPeriodSelector));
      await tester.pumpAndSettle();

      expect(find.text('3 meses'), findsWidgets);
      expect(find.text('1 año'), findsWidgets);
    });

    testWidgets('sin bloqueados el selector se comporta como siempre',
        (tester) async {
      // El default del widget: es lo que ven las pantallas del PF, que no
      // pasan nada. El paywall del alumno no le recorta a su entrenador.
      final seleccionados = <ChartPeriod>[];
      await _pumpSelector(
        tester,
        locked: const {},
        onSelect: seleccionados.add,
      );

      await tester.tap(find.byType(ChartPeriodSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 año').last);
      await tester.pumpAndSettle();

      expect(seleccionados, [ChartPeriod.last1y]);
    });

    testWidgets('sin onLockedTap, tocar un bloqueado no explota',
        (tester) async {
      await _pumpSelector(
        tester,
        locked: kPaidChartPeriods,
        onSelect: (_) => fail('no debería seleccionar un bloqueado'),
      );
      await tester.tap(find.byType(ChartPeriodSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 meses').last);
      await tester.pumpAndSettle();
      // Sin expectativas: lo que se verifica es que no tira.
    });
  });
}
