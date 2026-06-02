import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/features/reviews/domain/review.dart';
import 'package:treino/features/reviews/presentation/widgets/review_tile.dart';
import 'package:treino/features/reviews/presentation/widgets/trainer_reviews_section.dart';

const _trainerId = 'trainer-1';
const _athleteId = 'athlete-1';
const _linkId = 'link-1';

Review _makeReview({int rating = 4, String? comment = 'Genial!'}) => Review(
      id: Review.idFor(_linkId, _athleteId),
      linkId: _linkId,
      athleteId: _athleteId,
      trainerId: _trainerId,
      rating: rating,
      comment: comment,
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
    );

Widget _wrap({required List<Review> reviews}) => ProviderScope(
      overrides: [
        trainerReviewsProvider(_trainerId)
            .overrideWith((ref) => Stream.value(reviews)),
        // Provide a fallback profile so ReviewTile doesn't hang in loading
        userPublicProfileProvider(_athleteId).overrideWith(
          (ref) => Stream.value(const UserPublicProfile(
            uid: _athleteId,
            displayName: 'Test Athlete',
          )),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TrainerReviewsSection(trainerId: _trainerId),
          ),
        ),
      ),
    );

void main() {
  group('TrainerReviewsSection', () {
    testWidgets('SCENARIO-615: renders "RESEÑAS" header', (tester) async {
      await tester.pumpWidget(_wrap(reviews: []));
      await tester.pumpAndSettle();

      // i18n: Fase 6 Etapa 7
      expect(find.text('RESEÑAS'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-615: empty reviews → shows "Sin reseñas todavía" muted text',
        (tester) async {
      await tester.pumpWidget(_wrap(reviews: []));
      await tester.pumpAndSettle();

      // i18n: Fase 6 Etapa 7
      expect(find.text('Sin reseñas todavía'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-615: non-empty → shows list of ReviewTile widgets',
        (tester) async {
      final reviews = [_makeReview(), _makeReview()];
      await tester.pumpWidget(_wrap(reviews: reviews));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewTile), findsNWidgets(2));
      expect(find.text('Sin reseñas todavía'), findsNothing);
    });

    testWidgets(
        'SCENARIO-615: non-empty → "Sin reseñas todavía" is absent',
        (tester) async {
      await tester.pumpWidget(_wrap(reviews: [_makeReview()]));
      await tester.pumpAndSettle();

      expect(find.text('Sin reseñas todavía'), findsNothing);
    });
  });
}
