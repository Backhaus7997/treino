import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/presentation/trainer_public_profile_screen.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/features/reviews/data/review_repository.dart';
import 'package:treino/features/reviews/domain/review.dart';
import 'package:treino/features/reviews/presentation/widgets/review_bottom_sheet.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockReviewRepository extends Mock implements ReviewRepository {}

const _trainerUid = 'trainer-1';
const _athleteId = 'athlete-1';
const _linkId = 'link-active';

TrainerPublicProfile _makeProfile() => const TrainerPublicProfile(
      uid: _trainerUid,
      displayName: 'Coach Ana',
      displayNameLowercase: 'coach ana',
      trainerBio: 'Great coach!',
    );

TrainerLink _makeActiveLink() => TrainerLink(
      id: _linkId,
      trainerId: _trainerUid,
      athleteId: _athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 5, 18),
      acceptedAt: DateTime.utc(2026, 5, 18),
      sharedWithTrainer: false,
    );

Review _makeReview() => Review(
      id: Review.idFor(_linkId, _athleteId),
      linkId: _linkId,
      athleteId: _athleteId,
      trainerId: _trainerUid,
      rating: 4,
      comment: 'Great!',
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
    );

Widget _wrap({
  required TrainerLink? link,
  Review? existingReview,
}) {
  final mockRepo = _MockReviewRepository();
  const reviewKey = '$_linkId:$_athleteId';
  return ProviderScope(
    overrides: [
      trainerByIdProvider(_trainerUid)
          .overrideWith((ref) async => _makeProfile()),
      currentAthleteLinkProvider.overrideWith((ref) async => link),
      reviewRepositoryProvider.overrideWithValue(mockRepo),
      if (link != null)
        userReviewForLinkProvider(reviewKey)
            .overrideWith((ref) => Stream.value(existingReview)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: const TrainerPublicProfileScreen(uid: _trainerUid),
    ),
  );
}

void main() {
  group('TrainerPublicProfileScreen — Edit CTA', () {
    testWidgets(
        'SCENARIO-611: when athlete has existing review, shows "EDITAR MI RESEÑA"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        link: _makeActiveLink(),
        existingReview: _makeReview(),
      ));
      await tester.pumpAndSettle();

      // i18n: Fase 6 Etapa 7
      expect(find.text('EDITAR MI RESEÑA'), findsOneWidget);
      expect(find.text('DEJAR UNA RESEÑA'), findsNothing);
    });

    testWidgets(
        'SCENARIO-611: when athlete has no review, shows "DEJAR UNA RESEÑA"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        link: _makeActiveLink(),
        existingReview: null,
      ));
      await tester.pumpAndSettle();

      // i18n: Fase 6 Etapa 7
      expect(find.text('DEJAR UNA RESEÑA'), findsOneWidget);
      expect(find.text('EDITAR MI RESEÑA'), findsNothing);
    });

    testWidgets(
        'SCENARIO-611: tapping "DEJAR UNA RESEÑA" opens ReviewBottomSheet',
        (tester) async {
      await tester.pumpWidget(_wrap(
        link: _makeActiveLink(),
        existingReview: null,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('DEJAR UNA RESEÑA'));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewBottomSheet), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-611: tapping "EDITAR MI RESEÑA" opens ReviewBottomSheet pre-populated',
        (tester) async {
      final review = _makeReview();
      await tester.pumpWidget(_wrap(
        link: _makeActiveLink(),
        existingReview: review,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('EDITAR MI RESEÑA'));
      await tester.pumpAndSettle();

      expect(find.byType(ReviewBottomSheet), findsOneWidget);
      // Pre-populated stars should match the existing review rating
      final sheet = tester.widget<ReviewBottomSheet>(
        find.byType(ReviewBottomSheet),
      );
      expect(sheet.existing?.rating, equals(4));
    });
  });
}
