import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/athlete_coach_view.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/features/reviews/data/review_repository.dart';
import 'package:treino/features/reviews/domain/review.dart';
import 'package:treino/features/reviews/presentation/widgets/review_bottom_sheet.dart';

class _MockReviewRepository extends Mock implements ReviewRepository {}

/// Active link with acceptedAt ≥ 30 days ago (31 days).
TrainerLink _makeOldLink() => TrainerLink(
      id: 'link-old',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.now().toUtc().subtract(const Duration(days: 32)),
      acceptedAt: DateTime.now().toUtc().subtract(const Duration(days: 31)),
      sharedWithTrainer: false,
    );

/// Active link with acceptedAt < 30 days ago (10 days).
TrainerLink _makeNewLink() => TrainerLink(
      id: 'link-new',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.now().toUtc().subtract(const Duration(days: 11)),
      acceptedAt: DateTime.now().toUtc().subtract(const Duration(days: 10)),
      sharedWithTrainer: false,
    );

UserPublicProfile _makePub() => UserPublicProfile(
      uid: 'trainer-1',
      displayName: 'Coach Ana',
      displayNameLowercase: 'coach ana',
    );

Review _makeReview() => Review(
      id: Review.idFor('link-old', 'athlete-1'),
      linkId: 'link-old',
      athleteId: 'athlete-1',
      trainerId: 'trainer-1',
      rating: 4,
      createdAt: DateTime.utc(2026, 4, 1),
      updatedAt: DateTime.utc(2026, 4, 1),
    );

Widget _wrap({
  required TrainerLink? link,
  Review? existingReview,
  _MockReviewRepository? mockRepo,
}) {
  final repo = mockRepo ?? _MockReviewRepository();
  final linkId = link?.id ?? 'link-old';
  final athleteId = link?.athleteId ?? 'athlete-1';
  final reviewKey = '$linkId:$athleteId';
  return ProviderScope(
    overrides: [
      currentAthleteLinkProvider.overrideWith((ref) async => link),
      if (link != null)
        userPublicProfileProvider(link.trainerId)
            .overrideWith((ref) => Stream.value(_makePub())),
      reviewRepositoryProvider.overrideWithValue(repo),
      userReviewForLinkProvider(reviewKey)
          .overrideWith((ref) => Stream.value(existingReview)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: AthleteCoachView()),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Trigger #2 — 30-day review prompt', () {
    testWidgets(
        'SCENARIO-610: active link + acceptedAt ≥30 days + no existing review + prefs key absent → sheet shown on first frame',
        (tester) async {
      await tester.pumpWidget(_wrap(link: _makeOldLink()));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewBottomSheet), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-610: prefs key already set → sheet NOT shown',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_shown_link-old': true,
      });

      await tester.pumpWidget(_wrap(link: _makeOldLink()));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewBottomSheet), findsNothing);
    });

    testWidgets(
        'SCENARIO-610: existing review present → sheet NOT shown',
        (tester) async {
      await tester.pumpWidget(_wrap(
        link: _makeOldLink(),
        existingReview: _makeReview(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewBottomSheet), findsNothing);
    });

    testWidgets(
        'SCENARIO-610: acceptedAt < 30 days → sheet NOT shown',
        (tester) async {
      await tester.pumpWidget(_wrap(link: _makeNewLink()));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewBottomSheet), findsNothing);
    });

    testWidgets(
        'SCENARIO-610: no active link → sheet NOT shown',
        (tester) async {
      await tester.pumpWidget(_wrap(link: null));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewBottomSheet), findsNothing);
    });
  });
}
