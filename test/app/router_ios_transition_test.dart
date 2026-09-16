// Repro for the device-reported BLACK SCREEN on pushed shell routes after
// 5e2c506 switched them from `pageBuilder + _noAnim` to `builder` (MaterialPage
// → CupertinoPageRoute on iOS).
//
// KEY: widget tests run with TargetPlatform.android by default, so the
// Cupertino transition path was NEVER exercised — this file forces iOS.

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
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/presentation/exercise_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Fecha de nacimiento de un adulto.
///
/// Todo test que monte el router REAL con un usuario logueado la necesita:
/// `authRedirect` tiene un gate de edad mínima que manda a `/birth-date`
/// cuando `bornAt` falta o no llega al piso, así que un perfil "completo" sin
/// este campo nunca llega a la pantalla que el test quiere medir.
final _adultBornAt = DateTime.utc(1990, 5, 20);

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

UserProfile _athleteProfile() => UserProfile(
      uid: 'athlete-uid',
      email: 'athlete@example.com',
      displayName: 'sporty',
      bornAt: _adultBornAt,
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

void main() {
  // Platform is forced via ThemeData.platform (see pumpWidget) — a global
  // debugDefaultTargetPlatformOverride trips debugAssertAllFoundationVarsUnset.

  testWidgets(
      'iOS Cupertino push: /workout/exercise/:id renders visible content '
      '(black-screen regression repro)', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(_MockUser())),
        ),
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
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
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    await container.read(userProfileProvider.future);

    final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0),
      read: container.read,
    );
    router.go('/workout');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.dark().copyWith(platform: TargetPlatform.iOS),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to the sub-route: adding the child page to the stack plays
    // the real entrance transition (CupertinoPageRoute on iOS).
    router.go('/workout/exercise/bench-press');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'the push transition must not throw');
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/workout/exercise/bench-press',
      reason: 'the push must actually navigate',
    );
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    expect(find.text('BENCH PRESS'), findsWidgets,
        reason: 'screen content must be visible after the push');
  });

  testWidgets(
      'iOS: pushing /workout/exercise/:id FROM a top-level editor route '
      'renders content (device black-screen repro)', (tester) async {
    // The device repro: open the exercise detail from the picker sheet inside
    // the routine editor — a TOP-LEVEL route outside the ShellRoute. Pushing a
    // shell sub-route from there mounts the shell (_noAnim) while the child
    // page runs a Cupertino transition with no /workout page beneath it.
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(
          () => _StubAuthNotifier(AsyncData(_MockUser())),
        ),
        userProfileProvider.overrideWith(
          (ref) => Stream<UserProfile?>.value(_athleteProfile()),
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
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    await container.read(userProfileProvider.future);

    final router = buildRouter(
      refreshListenable: ValueNotifier<int>(0),
      read: container.read,
    );
    // Start on the TOP-LEVEL editor route (outside the shell), like the video.
    router.go('/workout/my-routine-editor');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.dark().copyWith(platform: TargetPlatform.iOS),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    router.push('/workout/exercise/bench-press');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'pushing from a top-level route must not throw');
    expect(find.byType(ExerciseDetailScreen), findsOneWidget,
        reason: 'the detail screen must mount when pushed from the editor');
    expect(find.text('BENCH PRESS'), findsWidgets,
        reason: 'detail content must be visible — not a black screen');
  });
}
