import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/commercial_plan.dart';

void main() {
  group('CommercialPlan — JSON roundtrip', () {
    test('full plan roundtrips through Firestore Timestamp converter', () {
      final created = DateTime.utc(2026, 5, 27, 12, 0);
      final updated = DateTime.utc(2026, 5, 27, 14, 30);

      // Firestore reads return Timestamp for @TimestampConverter fields,
      // so simulate that on the fromJson side.
      final plan = CommercialPlan(
        id: 'p1',
        trainerId: 'trainer-1',
        name: 'Premium',
        shortDescription: 'Coaching completo',
        priceArs: 24000,
        durationMonths: 3,
        billingFrequency: BillingFrequency.quarterly,
        includes: const [
          PlanInclude.routines,
          PlanInclude.nutrition,
          PlanInclude.chat,
        ],
        status: CommercialPlanStatus.active,
        createdAt: created,
        updatedAt: updated,
      );

      final json = plan.toJson();
      // toJson must emit Timestamps for the converter fields.
      expect(json['createdAt'], isA<Timestamp>());
      expect(json['updatedAt'], isA<Timestamp>());

      final roundtripped = CommercialPlan.fromJson(json);
      expect(roundtripped, plan);
    });

    test('wire string for billingFrequency.oneTime is "one_time"', () {
      final plan = CommercialPlan(
        id: 'p2',
        trainerId: 'trainer-1',
        name: 'Plan inicio',
        priceArs: 8000,
        billingFrequency: BillingFrequency.oneTime,
        createdAt: DateTime.utc(2026, 5, 27),
        updatedAt: DateTime.utc(2026, 5, 27),
      );
      final json = plan.toJson();
      expect(json['billingFrequency'], 'one_time');
    });

    test('wire string for includes uses snake_case for compound names', () {
      final plan = CommercialPlan(
        id: 'p3',
        trainerId: 'trainer-1',
        name: 'Presencial',
        priceArs: 30000,
        includes: const [
          PlanInclude.presentialSessions,
          PlanInclude.progressTracking,
        ],
        createdAt: DateTime.utc(2026, 5, 27),
        updatedAt: DateTime.utc(2026, 5, 27),
      );
      final json = plan.toJson();
      expect(
        json['includes'],
        ['presential_sessions', 'progress_tracking'],
      );
    });

    test('default values applied for optional fields', () {
      final plan = CommercialPlan(
        id: 'p4',
        trainerId: 'trainer-1',
        name: 'Mínimo',
        priceArs: 10000,
        createdAt: DateTime.utc(2026, 5, 27),
        updatedAt: DateTime.utc(2026, 5, 27),
      );
      expect(plan.shortDescription, '');
      expect(plan.durationMonths, 1);
      expect(plan.billingFrequency, BillingFrequency.monthly);
      expect(plan.includes, isEmpty);
      expect(plan.status, CommercialPlanStatus.active);
    });
  });

  group('BillingFrequency.label', () {
    test('Spanish labels', () {
      expect(BillingFrequency.monthly.label, 'Mensual');
      expect(BillingFrequency.quarterly.label, 'Trimestral');
      expect(BillingFrequency.yearly.label, 'Anual');
      expect(BillingFrequency.oneTime.label, 'Pago único');
    });
  });

  group('PlanInclude.label', () {
    test('Spanish labels', () {
      expect(PlanInclude.routines.label, 'Rutinas personalizadas');
      expect(PlanInclude.nutrition.label, 'Plan nutricional');
      expect(PlanInclude.chat.label, 'Chat ilimitado');
      expect(PlanInclude.presentialSessions.label, 'Sesiones presenciales');
      expect(PlanInclude.onlineSessions.label, 'Sesiones online');
      expect(PlanInclude.progressTracking.label, 'Seguimiento de progreso');
    });
  });
}
