import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/reviews/presentation/widgets/star_rating_display.dart';
import 'package:treino/features/workout/application/template_rating_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/template_rating.dart';
import 'package:treino/features/workout/presentation/widgets/template_ratings_section.dart';
import 'package:treino/l10n/app_l10n.dart';

class _FakeUser extends Mock implements User {}

const _routineId = 'tpl-1';
const _authorId = 'trainer-9';
const _viewerId = 'viewer-1';

Routine makeTemplate({double? ratingAvg, int? ratingsCount}) => Routine(
      id: _routineId,
      name: 'PPL de Juan',
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerTemplate,
      assignedBy: _authorId,
      visibility: RoutineVisibility.public,
      ratingAvg: ratingAvg,
      ratingsCount: ratingsCount,
    );

TemplateRating makeRating({
  required String userId,
  int rating = 4,
  String? comment,
}) =>
    TemplateRating(
      userId: userId,
      rating: rating,
      comment: comment,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 1),
    );

User _userWithUid(String uid) {
  final user = _FakeUser();
  when(() => user.uid).thenReturn(uid);
  return user;
}

Widget _wrap(
  Routine routine, {
  String? viewerUid = _viewerId,
  List<TemplateRating> ratings = const [],
  TemplateRating? myRating,
  Map<String, UserPublicProfile> profiles = const {},
  bool ratingsError = false,
}) =>
    ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith(
          (ref) =>
              Stream.value(viewerUid == null ? null : _userWithUid(viewerUid)),
        ),
        templateRatingsProvider(_routineId).overrideWith(
          (ref) => ratingsError
              ? Stream<List<TemplateRating>>.error(Exception('boom'))
              : Stream.value(ratings),
        ),
        myTemplateRatingProvider(_routineId)
            .overrideWith((ref) => Stream.value(myRating)),
        userPublicProfilesBatchProvider(
          (ratings.map((r) => r.userId).toSet().toList()..sort()).join(','),
        ).overrideWith((ref) async => profiles),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TemplateRatingsSection(routine: routine),
          ),
        ),
      ),
    );

void main() {
  group('TemplateRatingsSection — promedio', () {
    testWidgets('shows the CF-written average and how many rated it',
        (tester) async {
      await tester.pumpWidget(
        _wrap(makeTemplate(ratingAvg: 4.5, ratingsCount: 3)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('template_rating_average')), findsOneWidget);
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('3 calificaciones'), findsOneWidget);
    });

    testWidgets('singular copy with exactly one rating', (tester) async {
      await tester.pumpWidget(
        _wrap(makeTemplate(ratingAvg: 5, ratingsCount: 1)),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 calificación'), findsOneWidget);
    });

    testWidgets('no ratings yet → dignified empty state, no hollow 0.0',
        (tester) async {
      await tester.pumpWidget(_wrap(makeTemplate()));
      await tester.pumpAndSettle();

      expect(
        find.text('Todavía nadie calificó esta plantilla. ¡Sé el primero!'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('template_rating_average')), findsNothing);
      expect(find.text('0.0'), findsNothing);
    });
  });

  group('TemplateRatingsSection — mi calificación', () {
    testWidgets('without my rating: invites me to rate', (tester) async {
      await tester.pumpWidget(
        _wrap(makeTemplate(ratingAvg: 4, ratingsCount: 2)),
      );
      await tester.pumpAndSettle();

      expect(find.text('¿Qué te pareció?'), findsOneWidget);
      expect(find.text('CALIFICAR'), findsOneWidget);
      expect(find.byKey(const Key('template_rating_mine')), findsNothing);
    });

    testWidgets('my existing rating is pre-loaded and editable',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          makeTemplate(ratingAvg: 4, ratingsCount: 2),
          myRating: makeRating(userId: _viewerId, rating: 3),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tu calificación'), findsOneWidget);
      expect(find.text('EDITAR'), findsOneWidget);
      final mine = tester.widget<StarRatingDisplay>(
        find.byKey(const Key('template_rating_mine')),
      );
      expect(mine.rating, 3.0);
    });

    testWidgets('the template AUTHOR never sees the rating input',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          makeTemplate(ratingAvg: 4, ratingsCount: 2),
          viewerUid: _authorId,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('template_rating_cta')), findsNothing);
      // The average is still visible to them.
      expect(find.byKey(const Key('template_rating_average')), findsOneWidget);
    });

    testWidgets('a signed-out viewer sees no input either', (tester) async {
      await tester.pumpWidget(
        _wrap(makeTemplate(ratingAvg: 4, ratingsCount: 2), viewerUid: null),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('template_rating_cta')), findsNothing);
    });
  });

  group('TemplateRatingsSection — comentarios', () {
    testWidgets('renders comments with author name and stars', (tester) async {
      await tester.pumpWidget(
        _wrap(
          makeTemplate(ratingAvg: 4, ratingsCount: 2),
          ratings: [
            makeRating(userId: 'u1', rating: 5, comment: 'Muy completa'),
            makeRating(userId: 'u2', rating: 3, comment: 'Me costó el día 3'),
          ],
          profiles: const {
            'u1': UserPublicProfile(
              uid: 'u1',
              displayName: 'Ana',
              displayNameLowercase: 'ana',
            ),
            'u2': UserPublicProfile(
              uid: 'u2',
              displayName: 'Beto',
              displayNameLowercase: 'beto',
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Muy completa'), findsOneWidget);
      expect(find.text('Me costó el día 3'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Beto'), findsOneWidget);
    });

    testWidgets('ratings WITHOUT a comment do not appear in the list',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          makeTemplate(ratingAvg: 4, ratingsCount: 2),
          ratings: [
            makeRating(userId: 'u1', rating: 5),
            makeRating(userId: 'u2', rating: 4, comment: '   '),
          ],
          profiles: const {
            'u1': UserPublicProfile(
              uid: 'u1',
              displayName: 'Ana',
              displayNameLowercase: 'ana',
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Todavía no hay comentarios.'), findsOneWidget);
      expect(find.text('Ana'), findsNothing);
    });

    testWidgets('a deleted author falls back to the deleted-user label',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          makeTemplate(ratingAvg: 4, ratingsCount: 1),
          ratings: [makeRating(userId: 'gone', comment: 'Buenísima')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Buenísima'), findsOneWidget);
      expect(find.text('Usuario eliminado'), findsOneWidget);
    });

    testWidgets('a failing ratings stream shows its own error, not a crash',
        (tester) async {
      await tester.pumpWidget(
        _wrap(makeTemplate(ratingAvg: 4, ratingsCount: 2), ratingsError: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar los comentarios.'), findsOneWidget);
      // The aggregate comes from the routine doc, so it survives.
      expect(find.byKey(const Key('template_rating_average')), findsOneWidget);
    });
  });
}
