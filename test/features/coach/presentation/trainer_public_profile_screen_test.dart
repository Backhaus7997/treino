// Coverage for the thousands-separator display on TrainerPublicProfileScreen
// (fix/coach-amount-thousands-separator). Mirrors the _wrap pattern from the
// sibling suite trainer_public_profile_screen_reviews_integration_test.dart —
// same provider overrides, same MaterialApp scaffold.
//
// The screen renders trainerMonthlyRate via fmtArs (payment_format.dart),
// which already groups by thousands ("100000" → "$100.000") — this test pins
// that the grouped form is what actually shows on screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/presentation/trainer_public_profile_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _trainerUid = 'trainer-thousands-1';
const _athleteId = 'athlete-1';

TrainerPublicProfile _makeProfile({required int? monthlyRate}) =>
    TrainerPublicProfile(
      uid: _trainerUid,
      displayName: 'Coach Miles',
      trainerBio: 'Great coach!',
      trainerMonthlyRate: monthlyRate,
    );

Widget _wrap({required TrainerPublicProfile profile}) => ProviderScope(
      overrides: [
        trainerByIdProvider(_trainerUid).overrideWith((ref) async => profile),
        currentAthleteLinkProvider.overrideWith((ref) async => null),
        trainerReviewsProvider(_trainerUid)
            .overrideWith((ref) => Stream.value(const [])),
        // Fallback profile for any athlete uid queries from ReviewTile.
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
  group('TrainerPublicProfileScreen — thousands separator on monthly rate', () {
    testWidgets(
        'trainerMonthlyRate crossing the thousands boundary renders grouped '
        '("100.000"), not ungrouped ("100000")', (tester) async {
      await tester.pumpWidget(
        _wrap(profile: _makeProfile(monthlyRate: 100000)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('100.000'), findsOneWidget);
      expect(find.textContaining('100000'), findsNothing);
    });
  });
}
