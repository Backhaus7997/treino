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
import 'package:treino/core/widgets/treino_collapsing_top_bar.dart';
import 'package:treino/features/coach/presentation/trainer_public_profile_screen.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_profile_hero.dart';
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
        currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
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

  // #1559: el AppBar transparente pintaba una banda (scrolled-under de
  // Material 3) que cortaba el avatar. Ahora es la barra que aparece al
  // scrollear, como el resto de los detalles.
  group('TrainerPublicProfileScreen — barra superior', () {
    Future<void> pumpConNotch(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 59);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(profile: _makeProfile(monthlyRate: 1)));
      await tester.pumpAndSettle();
    }

    testWidgets('no usa AppBar: usa TreinoCollapsingTopBar', (tester) async {
      await pumpConNotch(tester);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(TreinoCollapsingTopBar), findsOneWidget);
    });

    testWidgets('en offset 0 el avatar arranca debajo de la flecha',
        (tester) async {
      await pumpConNotch(tester);
      final back = tester.getRect(
        find.byKey(const Key('treino-top-bar-back')),
      );
      final hero = tester.getRect(find.byType(TrainerProfileHero));
      expect(hero.top, greaterThanOrEqualTo(back.bottom));
    });
  });
}
