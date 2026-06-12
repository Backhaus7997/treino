import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/presentation/trainer_public_profile_screen.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_stats_row.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/features/reviews/presentation/widgets/trainer_reviews_section.dart';
import 'package:treino/l10n/app_l10n.dart';

const _trainerUid = 'trainer-reviews-ui';
const _athleteId = 'athlete-1';

TrainerPublicProfile _makeProfile({
  double? averageRating,
  int reviewCount = 0,
}) =>
    TrainerPublicProfile(
      uid: _trainerUid,
      displayName: 'Coach Reviews',
      trainerBio: 'Great coach!',
      averageRating: averageRating,
      reviewCount: reviewCount,
    );

Widget _wrap({required TrainerPublicProfile profile}) => ProviderScope(
      overrides: [
        trainerByIdProvider(_trainerUid).overrideWith((ref) async => profile),
        currentAthleteLinkProvider.overrideWith((ref) async => null),
        trainerReviewsProvider(_trainerUid)
            .overrideWith((ref) => Stream.value(const [])),
        // Fallback profile for any athlete uid queries from ReviewTile
        userPublicProfileProvider(_athleteId)
            .overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const TrainerPublicProfileScreen(uid: _trainerUid),
      ),
    );

void main() {
  group('TrainerPublicProfileScreen — SCENARIO-618 T48/T49 reviews integration',
      () {
    testWidgets(
        'SCENARIO-618: TrainerReviewsSection is present in the widget tree below CTA',
        (tester) async {
      await tester.pumpWidget(_wrap(profile: _makeProfile()));
      await tester.pumpAndSettle();

      expect(find.byType(TrainerReviewsSection), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-618: TrainerStatsRow is present and wired to TrainerPublicProfile',
        (tester) async {
      await tester.pumpWidget(_wrap(profile: _makeProfile()));
      await tester.pumpAndSettle();

      expect(find.byType(TrainerStatsRow), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-618: TrainerStatsRow shows "4.2" when profile has averageRating 4.2',
        (tester) async {
      await tester.pumpWidget(
        _wrap(profile: _makeProfile(averageRating: 4.2, reviewCount: 5)),
      );
      await tester.pumpAndSettle();

      // Stats row should show the formatted rating
      expect(find.text('4.2'), findsOneWidget);
    });

    testWidgets('SCENARIO-618: TrainerStatsRow shows "—" when reviewCount is 0',
        (tester) async {
      await tester.pumpWidget(_wrap(profile: _makeProfile()));
      await tester.pumpAndSettle();

      // The placeholder should appear at least once (RESEÑAS slot + experience + students)
      expect(find.text('—'), findsWidgets);
    });

    testWidgets(
        'SCENARIO-618: TrainerReviewsSection shows "Sin reseñas todavía" when empty',
        (tester) async {
      await tester.pumpWidget(_wrap(profile: _makeProfile()));
      await tester.pumpAndSettle();

      // i18n: Fase 6 Etapa 7
      expect(find.text('Sin reseñas todavía'), findsOneWidget);
    });
  });
}
