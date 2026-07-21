// WU-02 (Fase 10) — agruparTarifas: lógica pura de agrupación de
// AthleteBilling por (amountArs, cadence) para la sección Planes comerciales.
//
// RED → GREEN: sin UI, solo el modelo/función pura (ver instrucciones WU-02).
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/planes/tarifas_model.dart';
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
  group('SCENARIO-TM-01 — agruparTarifas: lista vacía', () {
    test('resumen vacío, masUsada null', () {
      final resumen = agruparTarifas(const []);

      expect(resumen.grupos, isEmpty);
      expect(resumen.precioPromedio, 0);
      expect(resumen.alumnosConTarifa, 0);
      expect(resumen.tarifasDistintas, 0);
      expect(resumen.masUsada, isNull);
    });
  });

  group('SCENARIO-TM-02 — agruparTarifas: un solo billing', () {
    test(
        'un grupo con alumnosCount 1, promedio == monto, masUsada == único grupo',
        () {
      final resumen = agruparTarifas([
        _billing(
          athleteId: 'a1',
          amountArs: 15000,
          cadence: BillingCadence.mensual,
        ),
      ]);

      expect(resumen.grupos, hasLength(1));
      expect(resumen.grupos.single.amountArs, 15000);
      expect(resumen.grupos.single.cadence, BillingCadence.mensual);
      expect(resumen.grupos.single.alumnosCount, 1);
      expect(resumen.precioPromedio, 15000);
      expect(resumen.alumnosConTarifa, 1);
      expect(resumen.tarifasDistintas, 1);
      expect(resumen.masUsada, resumen.grupos.single);
    });
  });

  group('SCENARIO-TM-03 — agruparTarifas: mismo (amount, cadence) agrupa', () {
    test('varios billings con el mismo monto+cadencia caen en un solo grupo',
        () {
      final resumen = agruparTarifas([
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
          amountArs: 15000,
          cadence: BillingCadence.mensual,
        ),
      ]);

      expect(resumen.grupos, hasLength(1));
      expect(resumen.grupos.single.alumnosCount, 3);
      expect(resumen.tarifasDistintas, 1);
      expect(resumen.alumnosConTarifa, 3);
    });

    test('mismo monto pero distinta cadencia NO agrupa', () {
      final resumen = agruparTarifas([
        _billing(
          athleteId: 'a1',
          amountArs: 15000,
          cadence: BillingCadence.mensual,
        ),
        _billing(
          athleteId: 'a2',
          amountArs: 15000,
          cadence: BillingCadence.semanal,
        ),
      ]);

      expect(resumen.grupos, hasLength(2));
      expect(resumen.tarifasDistintas, 2);
    });
  });

  group('SCENARIO-TM-04 — agruparTarifas: orden por alumnosCount DESC', () {
    test('el grupo con más alumnos queda primero', () {
      final resumen = agruparTarifas([
        _billing(
          athleteId: 'a1',
          amountArs: 10000,
          cadence: BillingCadence.mensual,
        ),
        _billing(
          athleteId: 'a2',
          amountArs: 20000,
          cadence: BillingCadence.semanal,
        ),
        _billing(
          athleteId: 'a3',
          amountArs: 20000,
          cadence: BillingCadence.semanal,
        ),
        _billing(
          athleteId: 'a4',
          amountArs: 20000,
          cadence: BillingCadence.semanal,
        ),
      ]);

      expect(resumen.grupos.first.amountArs, 20000);
      expect(resumen.grupos.first.cadence, BillingCadence.semanal);
      expect(resumen.grupos.first.alumnosCount, 3);
      expect(resumen.masUsada, resumen.grupos.first);
    });

    test('empate en alumnosCount desempata por amountArs DESC', () {
      final resumen = agruparTarifas([
        _billing(
          athleteId: 'a1',
          amountArs: 10000,
          cadence: BillingCadence.mensual,
        ),
        _billing(
          athleteId: 'a2',
          amountArs: 30000,
          cadence: BillingCadence.mensual,
        ),
      ]);

      expect(resumen.grupos, hasLength(2));
      expect(resumen.grupos.first.amountArs, 30000);
      expect(resumen.grupos.last.amountArs, 10000);
    });
  });

  group('SCENARIO-TM-05 — agruparTarifas: precioPromedio', () {
    test(
        'media entera de amountArs sobre TODOS los billings (mezcla cadencias)',
        () {
      final resumen = agruparTarifas([
        _billing(
          athleteId: 'a1',
          amountArs: 10000,
          cadence: BillingCadence.mensual,
        ),
        _billing(
          athleteId: 'a2',
          amountArs: 20000,
          cadence: BillingCadence.semanal,
        ),
        _billing(
          athleteId: 'a3',
          amountArs: 30000,
          cadence: BillingCadence.porSesion,
        ),
      ]);

      // (10000 + 20000 + 30000) / 3 = 20000
      expect(resumen.precioPromedio, 20000);
    });

    test('división entera trunca hacia abajo', () {
      final resumen = agruparTarifas([
        _billing(
          athleteId: 'a1',
          amountArs: 10000,
          cadence: BillingCadence.mensual,
        ),
        _billing(
          athleteId: 'a2',
          amountArs: 10001,
          cadence: BillingCadence.mensual,
        ),
      ]);

      // (10000 + 10001) / 2 = 10000.5 → trunca a 10000
      expect(resumen.precioPromedio, 10000);
    });
  });

  group('SCENARIO-TM-06 — agruparTarifas: tarifasDistintas', () {
    test('cuenta la cantidad de grupos, no de billings', () {
      final resumen = agruparTarifas([
        _billing(
          athleteId: 'a1',
          amountArs: 10000,
          cadence: BillingCadence.mensual,
        ),
        _billing(
          athleteId: 'a2',
          amountArs: 10000,
          cadence: BillingCadence.mensual,
        ),
        _billing(
          athleteId: 'a3',
          amountArs: 20000,
          cadence: BillingCadence.suelto,
        ),
      ]);

      expect(resumen.tarifasDistintas, 2);
      expect(resumen.alumnosConTarifa, 3);
    });
  });

  group('SCENARIO-TM-07 — TarifaGroup: igualdad de valor', () {
    test('dos TarifaGroup con los mismos campos son ==', () {
      const a = TarifaGroup(
        amountArs: 15000,
        cadence: BillingCadence.mensual,
        alumnosCount: 3,
      );
      const b = TarifaGroup(
        amountArs: 15000,
        cadence: BillingCadence.mensual,
        alumnosCount: 3,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('difieren si cambia cualquier campo', () {
      const base = TarifaGroup(
        amountArs: 15000,
        cadence: BillingCadence.mensual,
        alumnosCount: 3,
      );
      const otroMonto = TarifaGroup(
        amountArs: 16000,
        cadence: BillingCadence.mensual,
        alumnosCount: 3,
      );

      expect(base, isNot(otroMonto));
    });
  });
}
