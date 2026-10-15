// WU-02 (Fase 10) — tarifasResumenProvider: deriva TarifasResumen a partir de
// trainerBillingsProvider (overrideado con datos AthleteBilling in-memory,
// sin Firestore real — ver instrucciones WU-02).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/planes/tarifas_provider.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';

AthleteBilling _billing({
  required String athleteId,
  required int amountArs,
  required BillingCadence cadence,
}) =>
    AthleteBilling(
      trainerId: 'trainer-1',
      athleteId: athleteId,
      amountArs: amountArs,
      cadence: cadence,
      updatedAt: DateTime.utc(2026, 1, 5),
    );

void main() {
  group('SCENARIO-TP-01 — tarifasResumenProvider: loading', () {
    test('mientras trainerBillingsProvider no resolvió → AsyncValue.loading',
        () {
      final controller = StreamController<List<AthleteBilling>>();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [
          trainerBillingsProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(tarifasResumenProvider).isLoading, isTrue);
    });
  });

  group('SCENARIO-TP-02 — tarifasResumenProvider: data', () {
    test('agrupa los billings emitidos por trainerBillingsProvider', () async {
      final billings = [
        _billing(
          athleteId: 'a1',
          amountArs: 15000,
          cadence: BillingCadence.mensual,
        ),
        _billing(
          athleteId: 'a2',
          amountArs: 15000,
          cadence: BillingCadence.mensual,
        ),
        _billing(
          athleteId: 'a3',
          amountArs: 8000,
          cadence: BillingCadence.semanal,
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          trainerBillingsProvider.overrideWith(
            (ref) => Stream.value(billings),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        tarifasResumenProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      final result = container.read(tarifasResumenProvider);
      expect(result.hasValue, isTrue);
      final resumen = result.value!;

      expect(resumen.alumnosConTarifa, 3);
      expect(resumen.tarifasDistintas, 2);
      expect(resumen.grupos.first.alumnosCount, 2);
      expect(resumen.grupos.first.amountArs, 15000);
    });
  });

  group('SCENARIO-TP-03 — tarifasResumenProvider: vacío', () {
    test('sin billings → TarifasResumen vacío', () async {
      final container = ProviderContainer(
        overrides: [
          trainerBillingsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        tarifasResumenProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      final result = container.read(tarifasResumenProvider);
      expect(result.hasValue, isTrue);
      final resumen = result.value!;

      expect(resumen.grupos, isEmpty);
      expect(resumen.alumnosConTarifa, 0);
      expect(resumen.tarifasDistintas, 0);
      expect(resumen.masUsada, isNull);
    });
  });

  group(
      'SCENARIO-STALE — tarifasResumenProvider sostiene el resumen ante '
      'error transitorio (pulido-post-revision, ROOT-CAUSE)', () {
    // Regression: `tarifasResumenProvider` componía `trainerBillingsProvider`
    // vía `.whenData()`, que despacha por el SUBTIPO runtime del AsyncValue
    // (ignora `hasValue`). `trainerBillingsProvider` es un StreamProvider en
    // vivo — Riverpod 2.5+ preserva el valor previo dentro de un AsyncError
    // subsiguiente (copyWithPrevious/"seamless"), así que
    // `billingsAsync.hasValue == true` Y `hasError == true` pueden darse a
    // la vez tras un error transitorio del stream. En ese estado compuesto
    // `.whenData()` caía en la rama `error:` (hasValue: false explícito),
    // tirando el resumen ya calculado. Afecta tanto a `PlanesScreen` como a
    // cualquier otro consumidor de `tarifasResumenProvider`. Se chequea
    // `hasValue` explícitamente ANTES del error (mismo patrón que
    // `pagosBucketsProvider`, commit b3a14117).
    test(
        'el resumen persiste a través de un error transitorio del stream '
        'cuando ya había data cargada (stale-while-refresh)', () async {
      final billing = _billing(
        athleteId: 'a1',
        amountArs: 15000,
        cadence: BillingCadence.mensual,
      );
      final controller = StreamController<List<AthleteBilling>>();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [
          trainerBillingsProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        tarifasResumenProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      controller.add([billing]);
      await Future<void>.delayed(Duration.zero);

      final afterData = container.read(tarifasResumenProvider);
      expect(afterData.hasValue, isTrue);
      expect(afterData.value!.alumnosConTarifa, 1);

      controller.addError(Exception('transient stream hiccup'));
      await Future<void>.delayed(Duration.zero);

      final afterError = container.read(tarifasResumenProvider);
      expect(
        afterError.hasValue,
        isTrue,
        reason: 'a transient stream error must not blank the cached resumen',
      );
      expect(afterError.value!.alumnosConTarifa, 1);

      controller.add([billing]);
      await Future<void>.delayed(Duration.zero);

      final afterRecover = container.read(tarifasResumenProvider);
      expect(afterRecover.hasValue, isTrue);
      expect(afterRecover.value!.alumnosConTarifa, 1);
    });
  });
}
