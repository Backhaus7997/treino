// La barra de pestañas pregunta antes de abandonar una pantalla con cambios
// sin guardar. Se monta el `buildRouter()` real y se toca la barra real: un
// test sobre `GuardiaDeSalida` sola daría verde aunque el shell nunca la
// consultara.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/guardia_de_salida.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/notifications/application/notification_router.dart'
    show locationActualDe;
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart'
    show customExerciseVideoCapsProvider, customExerciseVideoCountProvider;
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

import '../helpers/onboarding_test_helpers.dart';

const _uid = 'uid-test';

class _LoadingAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() => Completer<User?>().future;
}

/// Monta la app en `/profile/my-exercises` (dentro del shell, con barra) y
/// devuelve la guardia y el router.
Future<(GuardiaDeSalida, GoRouter)> _pump(WidgetTester tester) async {
  final container = ProviderContainer(overrides: [
    authStateChangesProvider.overrideWith((_) => const Stream<User?>.empty()),
    authNotifierProvider.overrideWith(_LoadingAuthNotifier.new),
    userProfileProvider.overrideWith(
      (_) => Stream.value(UserProfile(
        uid: _uid,
        email: 'test@test.com',
        displayName: 'Test User',
        role: UserRole.athlete,
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
        onboardingSeen: allSurfacesSeen(),
      )),
    ),
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
  router.go('/profile/my-exercises');
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return (container.read(guardiaDeSalidaProvider), router);
}

Future<void> _tocarFeed(WidgetTester tester) async {
  await tester.tap(find.text('FEED'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('GuardiaDeSalida', () {
    test('sin nadie anotado, deja salir', () async {
      expect(await GuardiaDeSalida().puedeSalir(), isTrue);
    });

    test('liberar sólo borra a la pantalla que sigue anotada', () async {
      final guardia = GuardiaDeSalida();
      Future<bool> vieja() async => false;
      Future<bool> nueva() async => false;
      guardia.registrar(vieja);
      guardia.registrar(nueva);

      guardia.liberar(vieja);
      expect(await guardia.puedeSalir(), isFalse,
          reason: 'la vieja no puede borrar a la que la reemplazó');

      guardia.liberar(nueva);
      expect(await guardia.puedeSalir(), isTrue);
    });
  });

  testWidgets('la barra NO cambia de pestaña si la pantalla no deja salir',
      (tester) async {
    final (guardia, router) = await _pump(tester);
    guardia.registrar(() async => false);

    await _tocarFeed(tester);

    expect(locationActualDe(router), '/profile/my-exercises');
  });

  testWidgets('la barra cambia de pestaña si la pantalla deja salir',
      (tester) async {
    final (guardia, router) = await _pump(tester);
    guardia.registrar(() async => true);

    await _tocarFeed(tester);

    expect(locationActualDe(router), '/feed');
  });
}
