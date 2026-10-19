// «Mis ejercicios» vive dentro del shell (con la barra inferior) y el editor de
// un ejercicio sigue inmersivo (#1502).
//
// «Mis ejercicios» (`/profile/my-exercises`) estaba registrada FUERA del shell
// como ruta inmersiva y por eso no tenía barra inferior, a diferencia del resto
// de las subpantallas de Perfil. Estos tests cruzan la frontera a propósito: se
// monta el `buildRouter()` real y se mira la barra real. Un test sobre
// `MyExercisesScreen` sola daría verde aunque la ruta siguiera afuera del shell.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart'
    show customExerciseVideoCapsProvider, customExerciseVideoCountProvider;
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/presentation/custom_exercise_editor_screen.dart';
import 'package:treino/features/workout/presentation/my_exercises_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../helpers/onboarding_test_helpers.dart';

const _uid = 'uid-test';

class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() => Completer<User?>().future;
}

UserProfile _profile() => UserProfile(
      uid: _uid,
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      // Sin esto el tour de onboarding (#627) se monta full-screen y tapa la
      // barra. Ver test/helpers/onboarding_test_helpers.dart.
      onboardingSeen: allSurfacesSeen(),
    );

Future<void> _pump(WidgetTester tester, String location) async {
  final container = ProviderContainer(overrides: [
    authStateChangesProvider.overrideWith((_) => const Stream<User?>.empty()),
    authNotifierProvider.overrideWith(_LoadingAuthNotifier.new),
    userProfileProvider.overrideWith((_) => Stream.value(_profile())),
    currentUidProvider.overrideWithValue(_uid),
    customExercisesForTrainerStreamProvider(_uid)
        .overrideWith((_) => Stream.value(const <Never>[])),
    customExerciseQuotaProvider
        .overrideWithValue(const AsyncValue.data((limit: 60, count: 0))),
    customExerciseVideoCountProvider.overrideWith((_) => Stream.value(0)),
    customExerciseVideoCapsProvider
        .overrideWithValue((maxCount: 50, maxBytes: 100 * 1024 * 1024)),
  ]);
  addTearDown(container.dispose);
  final router = buildRouter(
    refreshListenable: ValueNotifier<int>(0),
    read: container.read,
  );
  router.go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
  // `pump()` fijo y no `pumpAndSettle()`: el editor puede dejar un Timer vivo
  // (ExerciseVideoPlayer) y colgar el settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('/profile/my-exercises muestra la lista CON la barra inferior',
      (tester) async {
    await _pump(tester, '/profile/my-exercises');

    expect(find.byType(MyExercisesScreen), findsOneWidget);
    expect(find.text('MIS EJERCICIOS'), findsOneWidget);
    expect(find.byType(TreinoBottomBar), findsOneWidget);
  });

  testWidgets('el editor (/profile/my-exercises/new) sigue sin barra inferior',
      (tester) async {
    await _pump(tester, '/profile/my-exercises/new');

    expect(find.byType(CustomExerciseEditorScreen), findsOneWidget);
    expect(find.byType(TreinoBottomBar), findsNothing);
  });

  testWidgets('el editor de un ejercicio existente resuelve por :exId',
      (tester) async {
    await _pump(tester, '/profile/my-exercises/ex-1');

    expect(find.byType(CustomExerciseEditorScreen), findsOneWidget);
    expect(
      tester
          .widget<CustomExerciseEditorScreen>(
              find.byType(CustomExerciseEditorScreen))
          .exerciseId,
      'ex-1',
    );
    expect(find.byType(TreinoBottomBar), findsNothing);
  });
}
