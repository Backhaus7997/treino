// Coach-isolation wiring test for the read-only exercise detail route.
//
// The safety property under test: on
// /coach/athlete/:athleteId/plan/:routineId/exercise/:exerciseId the screen's
// personal stats belong to the ATHLETE in the path — the signed-in PF must
// NEVER see their own numbers in an athlete's context. This pins the real
// buildRouter() wiring (ExerciseDetailScreen.athleteId ← path param) so a
// future refactor can't silently drop it.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/presentation/exercise_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _profile() => UserProfile(
      uid: 'coach-uid',
      email: 'coach@example.com',
      displayName: 'coach',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

void main() {
  testWidgets(
      'coach exercise route: ExerciseDetailScreen.athleteId comes from the '
      'path and the progression/history providers query THAT athlete, not '
      'the signed-in uid', (tester) async {
    ExerciseProgressionKey? receivedProgressionKey;
    ExerciseHistoryKey? receivedHistoryKey;

    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(_MockUser())),
        ),
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_profile()),
        ),
        authStateChangesProvider.overrideWith((_) => Stream.value(null)),
        exercisesProvider.overrideWith(
          (_) async => const [
            Exercise(
              id: 'bench-press',
              name: 'Bench Press',
              muscleGroup: 'chest',
              category: 'compound',
            ),
          ],
        ),
        exerciseProgressionProvider.overrideWith((ref, key) async {
          receivedProgressionKey = key;
          return ExerciseProgression.empty(
            exerciseId: key.exerciseId,
            exerciseName: '',
          );
        }),
        exerciseSessionHistoryProvider.overrideWith((ref, key) async {
          receivedHistoryKey = key;
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    await container.read(userProfileProvider.future);

    final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0),
      read: container.read,
    );
    router.go(
      '/coach/athlete/athlete-1/plan/routine-1/exercise/bench-press',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final screen = tester.widget<ExerciseDetailScreen>(
      find.byType(ExerciseDetailScreen),
    );
    expect(screen.athleteId, 'athlete-1',
        reason: 'the route must forward the path athleteId to the screen');
    expect(receivedProgressionKey?.athleteUid, 'athlete-1',
        reason: 'stats must be queried for the inspected athlete');

    // The HISTORIAL section sits below the fold and SliverList builds
    // lazily — scroll it into view so its provider watch actually fires.
    await tester.scrollUntilVisible(
      find.text('Aún no entrenaste este ejercicio'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(receivedHistoryKey?.athleteUid, 'athlete-1',
        reason: 'history must be queried for the inspected athlete');
  });
}
