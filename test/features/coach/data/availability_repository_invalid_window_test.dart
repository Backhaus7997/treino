import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';

/// Guards the fix for: availability rule editor lets a trainer save an
/// end-time <= start-time (or a window narrower than one slot), silently
/// producing zero bookable slots in compute_free_slots.
void main() {
  late FakeFirebaseFirestore firestore;
  late AvailabilityRepository repo;

  const trainerId = 'tA';

  AvailabilityRule rule({
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    int slotDurationMin = 60,
  }) =>
      AvailabilityRule(
        id: 'r1',
        trainerId: trainerId,
        dayOfWeek: 1,
        startHour: startHour,
        startMinute: startMinute,
        endHour: endHour,
        endMinute: endMinute,
        slotDurationMin: slotDurationMin,
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = AvailabilityRepository(firestore: firestore);
  });

  Future<bool> docExists() async => (await firestore
          .collection('coach_availability_rules')
          .doc('r1')
          .get())
      .exists;

  group('addRule rejects non-bookable windows', () {
    test('end before start throws and persists nothing', () async {
      final invalid =
          rule(startHour: 11, startMinute: 0, endHour: 9, endMinute: 0);

      await expectLater(repo.addRule(invalid), throwsArgumentError);
      expect(await docExists(), isFalse);
    });

    test('zero-width window (start == end) throws', () async {
      final invalid =
          rule(startHour: 9, startMinute: 0, endHour: 9, endMinute: 0);

      await expectLater(repo.addRule(invalid), throwsArgumentError);
      expect(await docExists(), isFalse);
    });

    test('window narrower than one slot throws', () async {
      final invalid = rule(
        startHour: 9,
        startMinute: 0,
        endHour: 9,
        endMinute: 30,
        slotDurationMin: 60,
      );

      await expectLater(repo.addRule(invalid), throwsArgumentError);
      expect(await docExists(), isFalse);
    });

    test('window exactly one slot wide is accepted', () async {
      final valid = rule(
        startHour: 9,
        startMinute: 0,
        endHour: 10,
        endMinute: 0,
        slotDurationMin: 60,
      );

      await repo.addRule(valid);
      expect(await docExists(), isTrue);
    });
  });

  group('updateRule rejects non-bookable windows', () {
    test('updating to an inverted window throws', () async {
      final valid =
          rule(startHour: 9, startMinute: 0, endHour: 11, endMinute: 0);
      await repo.addRule(valid);

      final inverted = valid.copyWith(endHour: 8, endMinute: 0);
      await expectLater(repo.updateRule(inverted), throwsArgumentError);
    });
  });
}
