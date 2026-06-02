import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/reviews/data/review_repository.dart';
import 'package:treino/features/reviews/domain/review.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ReviewRepository repo;

  final now = DateTime.utc(2026, 6, 1, 10, 0);

  Review buildReview({
    String linkId = 'link1',
    String athleteId = 'athlete1',
    String trainerId = 'trainer1',
    int rating = 4,
    String? comment = 'Good!',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final id = Review.idFor(linkId, athleteId);
    return Review(
      id: id,
      linkId: linkId,
      athleteId: athleteId,
      trainerId: trainerId,
      rating: rating,
      comment: comment,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ReviewRepository(firestore: firestore);
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-573 — upsert writes doc at deterministic id
  // ---------------------------------------------------------------------------
  group('ReviewRepository.upsert', () {
    test('SCENARIO-573: upsert writes doc at deterministic id', () async {
      final review = buildReview();
      await repo.upsert(review);

      final snap = await firestore
          .collection('reviews')
          .doc(Review.idFor('link1', 'athlete1'))
          .get();

      expect(snap.exists, isTrue);
      expect(snap.data()!['linkId'], 'link1');
      expect(snap.data()!['athleteId'], 'athlete1');
      expect(snap.data()!['rating'], 4);
    });

    test(
        'SCENARIO-573: upsert overwrites an existing review (update semantics)',
        () async {
      final original = buildReview(rating: 3, comment: 'OK');
      await repo.upsert(original);

      final updated = buildReview(rating: 5, comment: 'Amazing!');
      await repo.upsert(updated);

      final snap = await firestore
          .collection('reviews')
          .doc(Review.idFor('link1', 'athlete1'))
          .get();
      expect(snap.data()!['rating'], 5);
      expect(snap.data()!['comment'], 'Amazing!');
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-574 — getForPair returns null when absent; Review when present
  // ---------------------------------------------------------------------------
  group('ReviewRepository.getForPair', () {
    test('SCENARIO-574: getForPair returns null when doc absent', () async {
      final result =
          await repo.getForPair('nonexistent-link', 'nonexistent-athlete');
      expect(result, isNull);
    });

    test('SCENARIO-574: getForPair returns Review when present', () async {
      final review = buildReview();
      await repo.upsert(review);

      final result = await repo.getForPair('link1', 'athlete1');
      expect(result, isNotNull);
      expect(result!.id, Review.idFor('link1', 'athlete1'));
      expect(result.rating, 4);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-575,576 — watchForTrainer stream sorted by createdAt DESC
  // ---------------------------------------------------------------------------
  group('ReviewRepository.watchForTrainer', () {
    test('SCENARIO-575: watchForTrainer emits empty list when no reviews',
        () async {
      final stream = repo.watchForTrainer('trainer-with-no-reviews');
      final first = await stream.first;
      expect(first, isEmpty);
    });

    test('SCENARIO-576: watchForTrainer emits reviews sorted createdAt DESC',
        () async {
      // Seed 3 reviews for the same trainer, in non-sorted order
      final older = Review(
        id: Review.idFor('link1', 'athlete1'),
        linkId: 'link1',
        athleteId: 'athlete1',
        trainerId: 'trainer1',
        rating: 3,
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      final newer = Review(
        id: Review.idFor('link2', 'athlete2'),
        linkId: 'link2',
        athleteId: 'athlete2',
        trainerId: 'trainer1',
        rating: 5,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
      );

      await repo.upsert(older);
      await repo.upsert(newer);

      final result = await repo.watchForTrainer('trainer1').first;
      expect(result.length, 2);
      // Most recent first
      expect(result[0].createdAt.isAfter(result[1].createdAt), isTrue);
    });

    test('SCENARIO-576: watchForTrainer respects limit', () async {
      // Seed 12 reviews
      for (var i = 0; i < 12; i++) {
        final r = Review(
          id: Review.idFor('link$i', 'athlete$i'),
          linkId: 'link$i',
          athleteId: 'athlete$i',
          trainerId: 'trainer-limit',
          rating: (i % 5) + 1,
          createdAt: DateTime.utc(2026, 1, i + 1),
          updatedAt: DateTime.utc(2026, 1, i + 1),
        );
        await repo.upsert(r);
      }

      final result =
          await repo.watchForTrainer('trainer-limit', limit: 10).first;
      expect(result.length, lessThanOrEqualTo(10));
    });
  });

  // ---------------------------------------------------------------------------
  // watchForLink
  // ---------------------------------------------------------------------------
  group('ReviewRepository.watchForLink', () {
    test('watchForLink emits null when no review', () async {
      final stream = repo.watchForLink('no-link', 'no-athlete');
      final first = await stream.first;
      expect(first, isNull);
    });

    test('watchForLink emits Review after upsert', () async {
      final review = buildReview();
      await repo.upsert(review);

      final result = await repo.watchForLink('link1', 'athlete1').first;
      expect(result, isNotNull);
      expect(result!.rating, 4);
    });
  });
}
