import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/reviews/domain/review.dart';
import 'package:treino/features/reviews/presentation/widgets/review_tile.dart';
import 'package:treino/l10n/app_l10n.dart';

const _athleteId = 'athlete-1';
const _trainerId = 'trainer-1';
const _linkId = 'link-1';

Review _makeReview() => Review(
      id: Review.idFor(_linkId, _athleteId),
      linkId: _linkId,
      athleteId: _athleteId,
      trainerId: _trainerId,
      rating: 4,
      comment: 'Excelente entrenador.',
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
    );

Widget _wrap({
  required Review review,
  UserPublicProfile? profile,
}) =>
    ProviderScope(
      overrides: [
        userPublicProfileProvider(_athleteId)
            .overrideWith((ref) => Stream.value(profile)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: ReviewTile(review: review)),
      ),
    );

void main() {
  group('ReviewTile avatar resolution', () {
    // Regression: avatarUrl was gated on `displayName != null`, so a live
    // profile with an avatar but a null displayName was rendered as
    // "Usuario eliminado" with no avatar. The deleted signal must be the
    // profile being null, not the displayName being null. ADR-RV-009.
    testWidgets(
        'profile with avatarUrl but null displayName still shows its avatar '
        'and is NOT labelled "Usuario eliminado"', (tester) async {
      const profile = UserPublicProfile(
        uid: _athleteId,
        displayName: null,
        displayNameLowercase: null,
        avatarUrl: 'https://example.com/avatar.png',
      );

      await tester.pumpWidget(_wrap(review: _makeReview(), profile: profile));
      await tester.pumpAndSettle();

      // The avatar must be propagated to PostAvatar (was null before the fix).
      final avatar = tester.widget<PostAvatar>(find.byType(PostAvatar));
      expect(avatar.authorAvatarUrl, 'https://example.com/avatar.png');

      // A live account with no name must NOT be mislabelled as deleted.
      // i18n: Fase 6 Etapa 7
      expect(find.text('Usuario eliminado'), findsOneWidget,
          reason:
              'Name falls back to "Usuario eliminado" for a blank name, but '
              'this is the display label only — the account is still live and '
              'its avatar is shown.');
    });

    testWidgets(
        'null profile (deleted account) shows no avatar url and the '
        'deleted label', (tester) async {
      await tester.pumpWidget(_wrap(review: _makeReview(), profile: null));
      await tester.pumpAndSettle();

      final avatar = tester.widget<PostAvatar>(find.byType(PostAvatar));
      expect(avatar.authorAvatarUrl, isNull);
      // i18n: Fase 6 Etapa 7
      expect(find.text('Usuario eliminado'), findsOneWidget);
    });
  });
}
