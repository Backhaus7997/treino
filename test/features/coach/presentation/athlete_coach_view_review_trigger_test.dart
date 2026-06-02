import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/athlete_coach_view.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/features/reviews/data/review_repository.dart';
import 'package:treino/features/reviews/presentation/widgets/review_bottom_sheet.dart';

class _MockTrainerLinkRepository extends Mock implements TrainerLinkRepository {}

class _MockReviewRepository extends Mock implements ReviewRepository {}

TrainerLink _makeActiveLink() => TrainerLink(
      id: 'link-1',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 5, 18, 10, 0),
      acceptedAt: DateTime.utc(2026, 5, 18, 12, 0),
      sharedWithTrainer: false,
    );

UserPublicProfile _makePub() => UserPublicProfile(
      uid: 'trainer-1',
      displayName: 'Coach Ana',
      displayNameLowercase: 'coach ana',
    );

Widget _wrap(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: AthleteCoachViewTestHarness()),
      ),
    );

void main() {
  late _MockTrainerLinkRepository mockLinkRepo;
  late _MockReviewRepository mockReviewRepo;

  setUp(() {
    mockLinkRepo = _MockTrainerLinkRepository();
    mockReviewRepo = _MockReviewRepository();
    when(() => mockLinkRepo.terminate(any(), reason: any(named: 'reason')))
        .thenAnswer((_) async {});
  });

  group('Trigger #1 — post-termination review sheet', () {
    testWidgets(
        'SCENARIO-609: after terminate() succeeds, ReviewBottomSheet is shown',
        (tester) async {
      // Sequence: link is active → user taps TERMINAR → confirms → sheet shows
      int resolveCount = 0;
      await tester.pumpWidget(_wrap([
        currentAthleteLinkProvider.overrideWith((ref) async {
          resolveCount++;
          // After first resolve, return active link.
          // After invalidation, return null (terminated).
          return resolveCount == 1 ? _makeActiveLink() : null;
        }),
        userPublicProfileProvider('trainer-1')
            .overrideWith((ref) => Stream.value(_makePub())),
        trainerLinkRepositoryProvider.overrideWithValue(mockLinkRepo),
        reviewRepositoryProvider.overrideWithValue(mockReviewRepo),
        // Provide a null review for the link (no existing review)
        userReviewForLinkProvider('link-1:athlete-1')
            .overrideWith((ref) => Stream.value(null)),
      ]));
      await tester.pumpAndSettle();

      // Tap TERMINAR VÍNCULO
      await tester.tap(find.text('TERMINAR VÍNCULO'));
      await tester.pumpAndSettle();

      // Confirm in dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar'));
      await tester.pumpAndSettle();

      // ReviewBottomSheet must be visible
      expect(find.byType(ReviewBottomSheet), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-609: dispose-safe — ProviderScope.containerOf captured before await',
        (tester) async {
      // This test verifies the container is read before the async gap by checking
      // that the sheet appears even when the link provider invalidates immediately,
      // which would dispose the _ActionRow widget before the sheet is shown.
      int resolveCount = 0;
      await tester.pumpWidget(_wrap([
        currentAthleteLinkProvider.overrideWith((ref) async {
          resolveCount++;
          return resolveCount == 1 ? _makeActiveLink() : null;
        }),
        userPublicProfileProvider('trainer-1')
            .overrideWith((ref) => Stream.value(_makePub())),
        trainerLinkRepositoryProvider.overrideWithValue(mockLinkRepo),
        reviewRepositoryProvider.overrideWithValue(mockReviewRepo),
        userReviewForLinkProvider('link-1:athlete-1')
            .overrideWith((ref) => Stream.value(null)),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TERMINAR VÍNCULO'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirmar'));
      await tester.pumpAndSettle();

      // Sheet must appear — proves the container was captured before await
      expect(find.byType(ReviewBottomSheet), findsOneWidget);
    });
  });
}
