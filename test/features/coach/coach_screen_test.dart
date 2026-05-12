import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/athlete_coach_view.dart';
import 'package:treino/features/coach/coach_screen.dart';
import 'package:treino/features/coach/trainer_coach_view.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

UserProfile _athleteProfile() => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: 'pf-mauro',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

ProviderContainer _container({UserProfile? profile}) => ProviderContainer(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(profile),
        ),
      ],
    );

ProviderContainer _loadingContainer() => ProviderContainer(
      overrides: [
        userProfileProvider.overrideWith(
          (ref) => const Stream<UserProfile?>.empty(),
        ),
      ],
    );

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: CoachScreen()),
      ),
    );

void main() {
  group('CoachScreen dispatch', () {
    testWidgets(
        'athlete profile → AthleteCoachView rendered, TrainerCoachView absent',
        (tester) async {
      final c = _container(profile: _athleteProfile());
      addTearDown(c.dispose);

      await tester.pumpWidget(_wrap(c));
      await tester.pumpAndSettle();

      expect(find.byType(AthleteCoachView), findsOneWidget);
      expect(find.byType(TrainerCoachView), findsNothing);
    });

    testWidgets(
        'trainer profile → TrainerCoachView rendered, AthleteCoachView absent',
        (tester) async {
      final c = _container(profile: _trainerProfile());
      addTearDown(c.dispose);

      await tester.pumpWidget(_wrap(c));
      await tester.pumpAndSettle();

      expect(find.byType(TrainerCoachView), findsOneWidget);
      expect(find.byType(AthleteCoachView), findsNothing);
    });

    testWidgets(
        'AsyncLoading (empty stream) → neither view rendered, no exception',
        (tester) async {
      final c = _loadingContainer();
      addTearDown(c.dispose);

      await tester.pumpWidget(_wrap(c));
      // Do NOT pumpAndSettle — the stream never completes, so we just pump once
      await tester.pump();

      expect(find.byType(AthleteCoachView), findsNothing);
      expect(find.byType(TrainerCoachView), findsNothing);
    });

    testWidgets('null profile → neither view rendered, no exception',
        (tester) async {
      final c = _container(profile: null);
      addTearDown(c.dispose);

      await tester.pumpWidget(_wrap(c));
      await tester.pumpAndSettle();

      expect(find.byType(AthleteCoachView), findsNothing);
      expect(find.byType(TrainerCoachView), findsNothing);
    });
  });
}
