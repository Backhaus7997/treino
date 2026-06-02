import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/reviews/domain/review.dart';
import 'package:treino/features/reviews/presentation/widgets/review_tile.dart';
import 'package:treino/features/reviews/presentation/widgets/star_rating_display.dart';

const _athleteId = 'athlete-1';
const _trainerId = 'trainer-1';
const _linkId = 'link-1';

Review _makeReview({Object? comment = _sentinel}) => Review(
      id: Review.idFor(_linkId, _athleteId),
      linkId: _linkId,
      athleteId: _athleteId,
      trainerId: _trainerId,
      rating: 4,
      comment:
          comment == _sentinel ? 'Excelente entrenador.' : comment as String?,
      createdAt: DateTime.utc(2026, 5, 1),
      updatedAt: DateTime.utc(2026, 5, 1),
    );

// Sentinel object to distinguish "not passed" from explicit null.
const _sentinel = Object();

UserPublicProfile _makeProfile() => const UserPublicProfile(
      uid: _athleteId,
      displayName: 'María López',
      displayNameLowercase: 'maría lópez',
      avatarUrl: null,
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
        home: Scaffold(body: ReviewTile(review: review)),
      ),
    );

void main() {
  group('ReviewTile', () {
    testWidgets(
        'SCENARIO-613: renders athlete name + StarRatingDisplay + comment + date',
        (tester) async {
      final review = _makeReview();
      await tester.pumpWidget(_wrap(review: review, profile: _makeProfile()));
      await tester.pumpAndSettle();

      // Athlete name
      expect(find.text('María López'), findsOneWidget);
      // StarRatingDisplay present
      expect(find.byType(StarRatingDisplay), findsOneWidget);
      // Comment text
      expect(find.text('Excelente entrenador.'), findsOneWidget);
      // Some date text rendered (relative or absolute)
      final dateTexts = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) =>
              t.data != null &&
              (t.data!.contains('hace') ||
                  t.data!.contains('/') ||
                  t.data!.contains('día') ||
                  t.data!.contains('mes') ||
                  t.data!.contains('año')))
          .toList();
      expect(dateTexts.isNotEmpty, isTrue,
          reason: 'Expected some date text rendered');
    });

    testWidgets(
        'SCENARIO-614: when userPublicProfileProvider returns null → shows "Usuario eliminado"',
        (tester) async {
      final review = _makeReview();
      await tester.pumpWidget(_wrap(review: review, profile: null));
      await tester.pumpAndSettle();

      // i18n: Fase 6 Etapa 7
      expect(find.text('Usuario eliminado'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-614: deleted athlete → avatar initial shows "U" (first letter of "Usuario eliminado")',
        (tester) async {
      final review = _makeReview();
      await tester.pumpWidget(_wrap(review: review, profile: null));
      await tester.pumpAndSettle();

      // PostAvatar computes initial from first character of displayName.
      // "Usuario eliminado" → "U". This is the neutral avatar for deleted accounts.
      expect(find.text('U'), findsOneWidget);
    });

    testWidgets('SCENARIO-613: when comment is null → comment row is hidden',
        (tester) async {
      final review = _makeReview(comment: null);
      await tester.pumpWidget(_wrap(review: review, profile: _makeProfile()));
      await tester.pumpAndSettle();

      // Neither "Excelente entrenador." nor any comment text should be visible
      // (no comment field shown when null)
      final contentTexts = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.data == 'Excelente entrenador.')
          .toList();
      expect(contentTexts.isEmpty, isTrue,
          reason: 'Comment row should be absent when comment is null');
    });
  });
}
