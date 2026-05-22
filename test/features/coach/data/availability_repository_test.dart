import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AvailabilityRepository repo;

  const trainerId = 'tA';

  AvailabilityRule makeRule(String id) => AvailabilityRule(
        id: id,
        trainerId: trainerId,
        dayOfWeek: 1,
        startHour: 9,
        startMinute: 0,
        endHour: 11,
        endMinute: 0,
        slotDurationMin: 60,
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = AvailabilityRepository(firestore: firestore);
  });

  // ─── Rule CRUD (SCENARIO-485..487) ───────────────────────────────────────

  group('addRule', () {
    test(
      'SCENARIO-485: persists doc at coach_availability_rules/{id}',
      () async {
        final rule = makeRule('r1');
        await repo.addRule(rule);

        final snap = await firestore
            .collection('coach_availability_rules')
            .doc('r1')
            .get();
        expect(snap.exists, isTrue);
        expect(snap.data()!['trainerId'], trainerId);
        expect(snap.data()!['dayOfWeek'], 1);
      },
    );
  });

  group('deleteRule', () {
    test('SCENARIO-486: removes doc at coach_availability_rules/{id}', () async {
      final rule = makeRule('r1');
      await repo.addRule(rule);

      await repo.deleteRule(trainerId, 'r1');

      final snap = await firestore
          .collection('coach_availability_rules')
          .doc('r1')
          .get();
      expect(snap.exists, isFalse);
    });
  });

  group('watchRules', () {
    test(
      'SCENARIO-487: only emits rules for the requesting trainer',
      () async {
        final ruleA1 = makeRule('r-a1');
        final ruleA2 = makeRule('r-a2');
        final ruleB = AvailabilityRule(
          id: 'r-b1',
          trainerId: 'tB',
          dayOfWeek: 2,
          startHour: 10,
          startMinute: 0,
          endHour: 12,
          endMinute: 0,
          slotDurationMin: 60,
        );
        await repo.addRule(ruleA1);
        await repo.addRule(ruleA2);
        await repo.addRule(ruleB);

        final rules = await repo.watchRules(trainerId).first;
        expect(rules, hasLength(2));
        expect(rules.map((r) => r.trainerId).toSet(), equals({trainerId}));
      },
    );
  });

  group('updateRule', () {
    test('updates existing rule in Firestore', () async {
      final rule = makeRule('r1');
      await repo.addRule(rule);

      final updated = rule.copyWith(slotDurationMin: 30);
      await repo.updateRule(updated);

      final snap = await firestore
          .collection('coach_availability_rules')
          .doc('r1')
          .get();
      expect(snap.data()!['slotDurationMin'], 30);
    });
  });

  // ─── Override CRUD (SCENARIO-488) ────────────────────────────────────────

  group('watchOverrides', () {
    test(
      'SCENARIO-488: returns overrides within date range only',
      () async {
        final june1 = DateTime.utc(2026, 6, 1);
        final june15 = DateTime.utc(2026, 6, 15);

        final blockJune1 = AvailabilityOverride.block(
          id: 'o-block-1',
          trainerId: trainerId,
          date: june1,
        );
        final extraJune15 = AvailabilityOverride.extra(
          id: 'o-extra-15',
          trainerId: trainerId,
          date: june15,
          startHour: 7,
          startMinute: 0,
          endHour: 8,
          endMinute: 0,
          slotDurationMin: 60,
        );
        await repo.addOverride(blockJune1);
        await repo.addOverride(extraJune15);

        // Query range: June 1 to June 10 (inclusive).
        final overrides = await repo
            .watchOverrides(trainerId, june1, DateTime.utc(2026, 6, 10))
            .first;

        expect(overrides, hasLength(1));
        expect((overrides.single as AvailabilityOverrideBlock).id, 'o-block-1');
      },
    );
  });

  group('deleteOverride', () {
    test('removes override doc', () async {
      final june1 = DateTime.utc(2026, 6, 1);
      final override = AvailabilityOverride.block(
        id: 'o1',
        trainerId: trainerId,
        date: june1,
      );
      await repo.addOverride(override);
      await repo.deleteOverride(trainerId, 'o1');

      final snap = await firestore
          .collection('coach_availability_overrides')
          .doc('o1')
          .get();
      expect(snap.exists, isFalse);
    });
  });
}
