import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/reviews/application/review_notifier.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/features/reviews/data/review_repository.dart';
import 'package:treino/features/reviews/domain/review.dart';

class _MockReviewRepository extends Mock implements ReviewRepository {}

/// Builds a container with ReviewNotifier and a mocked repository.
ProviderContainer _makeContainer(_MockReviewRepository mockRepo) {
  return ProviderContainer(
    overrides: [
      reviewRepositoryProvider.overrideWithValue(mockRepo),
    ],
  );
}

Review _makeReview({
  String linkId = 'link-1',
  String athleteId = 'athlete-1',
  String trainerId = 'trainer-1',
  int rating = 4,
  String? comment,
}) =>
    Review(
      id: Review.idFor(linkId, athleteId),
      linkId: linkId,
      athleteId: athleteId,
      trainerId: trainerId,
      rating: rating,
      comment: comment,
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
    );

void main() {
  late _MockReviewRepository mockRepo;

  setUp(() {
    mockRepo = _MockReviewRepository();
    registerFallbackValue(
      _makeReview(),
    );
  });

  group('ReviewNotifier', () {
    test(
        'SCENARIO-595: submit with rating==0 throws ArgumentError before calling repo',
        () async {
      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final notifier =
          container.read(reviewNotifierProvider(linkId: 'link-1', trainerId: 'trainer-1', athleteId: 'athlete-1').notifier);

      expect(
        () => notifier.submit(rating: 0, comment: null),
        throwsArgumentError,
      );
      verifyNever(() => mockRepo.upsert(any()));
    });

    test(
        'SCENARIO-595: submit with rating==6 throws ArgumentError before calling repo',
        () async {
      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final notifier =
          container.read(reviewNotifierProvider(linkId: 'link-1', trainerId: 'trainer-1', athleteId: 'athlete-1').notifier);

      expect(
        () => notifier.submit(rating: 6, comment: null),
        throwsArgumentError,
      );
      verifyNever(() => mockRepo.upsert(any()));
    });

    test(
        'SCENARIO-596: submit with comment.length > 500 throws ArgumentError before calling repo',
        () async {
      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final notifier =
          container.read(reviewNotifierProvider(linkId: 'link-1', trainerId: 'trainer-1', athleteId: 'athlete-1').notifier);

      expect(
        () => notifier.submit(rating: 4, comment: 'x' * 501),
        throwsArgumentError,
      );
      verifyNever(() => mockRepo.upsert(any()));
    });

    test(
        'SCENARIO-597: valid submit calls upsert with correct Review.idFor id and updatedAt set',
        () async {
      when(() => mockRepo.upsert(any())).thenAnswer((_) async {});

      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final notifier =
          container.read(reviewNotifierProvider(linkId: 'link-1', trainerId: 'trainer-1', athleteId: 'athlete-1').notifier);

      await notifier.submit(rating: 4, comment: 'Great!');

      final captured =
          verify(() => mockRepo.upsert(captureAny())).captured.single as Review;
      expect(captured.id, equals(Review.idFor('link-1', 'athlete-1')));
      expect(captured.rating, equals(4));
      expect(captured.comment, equals('Great!'));
      expect(captured.linkId, equals('link-1'));
      expect(captured.trainerId, equals('trainer-1'));
      expect(captured.athleteId, equals('athlete-1'));
      // updatedAt should be recent (within 1 minute of now)
      expect(
        DateTime.now().difference(captured.updatedAt).inSeconds.abs(),
        lessThan(60),
      );
    });

    test('SCENARIO-598: success → state is AsyncData(null)', () async {
      when(() => mockRepo.upsert(any())).thenAnswer((_) async {});

      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final notifier =
          container.read(reviewNotifierProvider(linkId: 'link-1', trainerId: 'trainer-1', athleteId: 'athlete-1').notifier);

      await notifier.submit(rating: 5);

      final state =
          container.read(reviewNotifierProvider(linkId: 'link-1', trainerId: 'trainer-1', athleteId: 'athlete-1'));
      expect(state, equals(const AsyncData<void>(null)));
    });

    test('SCENARIO-599: repo throws → state is AsyncError', () async {
      when(() => mockRepo.upsert(any()))
          .thenThrow(Exception('firestore error'));

      final container = _makeContainer(mockRepo);
      addTearDown(container.dispose);

      final notifier =
          container.read(reviewNotifierProvider(linkId: 'link-1', trainerId: 'trainer-1', athleteId: 'athlete-1').notifier);

      await notifier.submit(rating: 3);

      final state =
          container.read(reviewNotifierProvider(linkId: 'link-1', trainerId: 'trainer-1', athleteId: 'athlete-1'));
      expect(state, isA<AsyncError>());
    });
  });
}
