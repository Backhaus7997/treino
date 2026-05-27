import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/commercial_plan_repository.dart';
import 'package:treino/features/coach/domain/commercial_plan.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late CommercialPlanRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = CommercialPlanRepository(firestore: firestore);
  });

  group('create', () {
    test('persists a plan with auto-generated id and active status', () async {
      final plan = await repo.create(
        trainerId: 'trainer-1',
        name: 'Premium',
        priceArs: 24000,
        shortDescription: 'Coaching completo',
        durationMonths: 1,
        billingFrequency: BillingFrequency.monthly,
        includes: const [PlanInclude.routines, PlanInclude.chat],
      );

      expect(plan.id, isNotEmpty);
      expect(plan.status, CommercialPlanStatus.active);

      // Doc was actually written under the auto-generated id.
      final snap = await firestore.collection('commercialPlans').doc(plan.id).get();
      expect(snap.exists, isTrue);
      final data = snap.data()!;
      expect(data['trainerId'], 'trainer-1');
      expect(data['name'], 'Premium');
      expect(data['priceArs'], 24000);
      expect(data['billingFrequency'], 'monthly');
      // The id is NOT persisted inside the doc body (it's the doc id).
      expect(data.containsKey('id'), isFalse);
    });
  });

  group('watchForTrainer', () {
    test('streams plans for the trainer in createdAt desc order', () async {
      // Older plan first
      await repo.create(
        trainerId: 'trainer-1',
        name: 'Antiguo',
        priceArs: 10000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.create(
        trainerId: 'trainer-1',
        name: 'Nuevo',
        priceArs: 20000,
      );

      final stream = repo.watchForTrainer('trainer-1');
      final plans = await stream.first;
      expect(plans, hasLength(2));
      expect(plans[0].name, 'Nuevo'); // createdAt desc → newest first
      expect(plans[1].name, 'Antiguo');
    });

    test('returns only the asked trainer plans', () async {
      await repo.create(
        trainerId: 'trainer-1',
        name: 'Mío',
        priceArs: 1000,
      );
      await repo.create(
        trainerId: 'trainer-2',
        name: 'De otro',
        priceArs: 2000,
      );

      final plans = await repo.watchForTrainer('trainer-1').first;
      expect(plans, hasLength(1));
      expect(plans.single.name, 'Mío');
    });
  });

  group('update', () {
    test('persists changes and bumps updatedAt', () async {
      final original = await repo.create(
        trainerId: 'trainer-1',
        name: 'Original',
        priceArs: 15000,
      );
      // Force a measurable updatedAt delta.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.update(original.copyWith(name: 'Renombrado', priceArs: 18000));

      final snap = await firestore
          .collection('commercialPlans')
          .doc(original.id)
          .get();
      final data = snap.data()!;
      expect(data['name'], 'Renombrado');
      expect(data['priceArs'], 18000);
    });
  });

  group('archive', () {
    test('flips status to archived, plan still readable via stream', () async {
      final plan = await repo.create(
        trainerId: 'trainer-1',
        name: 'A archivar',
        priceArs: 5000,
      );
      await repo.archive(plan.id);

      final plans = await repo.watchForTrainer('trainer-1').first;
      expect(plans.single.status, CommercialPlanStatus.archived);
    });
  });
}
