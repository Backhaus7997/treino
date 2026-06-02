import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/reviews/domain/review.dart';

void main() {
  group('Review — model fields (SCENARIO-571)', () {
    test('Review has all required fields', () {
      final now = DateTime.utc(2026, 6, 1, 10, 0);
      final review = Review(
        id: 'link1_athlete1',
        linkId: 'link1',
        athleteId: 'athlete1',
        trainerId: 'trainer1',
        rating: 4,
        comment: 'Great trainer!',
        createdAt: now,
        updatedAt: now,
      );

      expect(review.id, 'link1_athlete1');
      expect(review.linkId, 'link1');
      expect(review.athleteId, 'athlete1');
      expect(review.trainerId, 'trainer1');
      expect(review.rating, 4);
      expect(review.comment, 'Great trainer!');
      expect(review.createdAt, now);
      expect(review.updatedAt, now);
    });

    test('Review comment is nullable', () {
      final now = DateTime.utc(2026, 6, 1);
      final review = Review(
        id: 'link1_athlete1',
        linkId: 'link1',
        athleteId: 'athlete1',
        trainerId: 'trainer1',
        rating: 3,
        createdAt: now,
        updatedAt: now,
      );
      expect(review.comment, isNull);
    });
  });

  group('Review.idFor — deterministic id (SCENARIO-572)', () {
    test('idFor returns linkId_athleteId', () {
      expect(Review.idFor('link-abc', 'athlete-xyz'), 'link-abc_athlete-xyz');
    });

    test('idFor is consistent across calls', () {
      final id1 = Review.idFor('link1', 'user1');
      final id2 = Review.idFor('link1', 'user1');
      expect(id1, equals(id2));
    });
  });

  group('Review JSON round-trip', () {
    test('full record with comment round-trips correctly', () {
      final now = DateTime.utc(2026, 6, 1, 10, 0);
      final review = Review(
        id: 'link1_athlete1',
        linkId: 'link1',
        athleteId: 'athlete1',
        trainerId: 'trainer1',
        rating: 5,
        comment: 'Excellent!',
        createdAt: now,
        updatedAt: now,
      );
      final decoded = Review.fromJson(review.toJson());
      expect(decoded, equals(review));
    });

    test('record without comment round-trips correctly', () {
      final now = DateTime.utc(2026, 6, 1, 10, 0);
      final review = Review(
        id: 'link2_athlete2',
        linkId: 'link2',
        athleteId: 'athlete2',
        trainerId: 'trainer1',
        rating: 2,
        createdAt: now,
        updatedAt: now,
      );
      final decoded = Review.fromJson(review.toJson());
      expect(decoded.comment, isNull);
      expect(decoded, equals(review));
    });
  });
}
