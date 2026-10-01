import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/application/email_gate_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';

class MockUser extends Mock implements User {}

/// Stream que nunca emite ni completa. Sirve para mantener
/// `userProfileProvider` en AsyncLoading permanente cuando el test sólo
/// quiere verificar el branch de `authStateChangesProvider` sin emisiones
/// colaterales del segundo subscription que agregamos en Etapa 6.
Stream<UserProfile?> _silentProfile(Ref ref) =>
    Completer<UserProfile?>().future.asStream();

/// Lo mismo para el interruptor `app_config/email_gate`. En estos tests no toca
/// Firestore (el user de prueba no tiene uid, así que el provider emite `false`
/// sin abrir nada), pero cuando auth emite se reconstruye y pasa por
/// AsyncData(false) → AsyncLoading → AsyncData(false): esas transiciones son
/// notificaciones de más que rompen el conteo exacto del primer test (daba 3 en
/// vez de 2).
Stream<bool> _silentGate(Ref ref) => Completer<bool>().future.asStream();

void main() {
  group('RouterRefreshNotifier (via routerRefreshNotifierProvider)', () {
    test('notifyListeners fires once per auth stream emission', () async {
      final controller = StreamController<User?>.broadcast();
      final mockUser = MockUser();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((_) => controller.stream),
          userProfileProvider.overrideWith(_silentProfile),
          emailGateEnabledProvider.overrideWith(_silentGate),
        ],
      );
      addTearDown(container.dispose);

      // Read the notifier through the provider so it uses the real Ref.
      final notifier = container.read(routerRefreshNotifierProvider);

      int callCount = 0;
      notifier.addListener(() => callCount++);

      controller.add(mockUser);
      controller.add(null);

      // Let the stream callbacks propagate
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(callCount, 2);
      await controller.close();
    });

    test('notifyListeners fires when userProfileProvider emits', () async {
      final profileController = StreamController<UserProfile?>.broadcast();

      final container = ProviderContainer(
        overrides: [
          // Auth queda quieta: emitimos el user fijo al subscribirse.
          authStateChangesProvider
              .overrideWith((_) => Stream<User?>.value(MockUser())),
          userProfileProvider.overrideWith((_) => profileController.stream),
          emailGateEnabledProvider.overrideWith(_silentGate),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(routerRefreshNotifierProvider);

      int callCount = 0;
      notifier.addListener(() => callCount++);

      // Esperar a que el auth.value se emita primero (no debe contarse en
      // los listeners porque fireImmediately:false).
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final baseline = callCount;

      // Ahora emitimos un cambio en el profile.
      profileController.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(callCount, greaterThan(baseline));
      await profileController.close();
    });

    test('notifyListeners fires when the email gate switch changes', () async {
      final gateController = StreamController<bool>.broadcast();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider
              .overrideWith((_) => Stream<User?>.value(MockUser())),
          userProfileProvider.overrideWith(_silentProfile),
          emailGateEnabledProvider.overrideWith((_) => gateController.stream),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(routerRefreshNotifierProvider);

      int callCount = 0;
      notifier.addListener(() => callCount++);

      // Deja pasar el arranque (auth emite su user fijo) y toma la línea de base.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final baseline = callCount;

      // El equipo prende el interruptor desde la consola: el redirect tiene que
      // re-evaluarse sin esperar a un cambio de auth o de profile.
      gateController.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, baseline + 1);

      gateController.add(false);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, baseline + 2);

      await gateController.close();
    });

    test(
        'after container dispose, additional emissions do NOT call notifyListeners',
        () async {
      final controller = StreamController<User?>.broadcast();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((_) => controller.stream),
          userProfileProvider.overrideWith(_silentProfile),
          emailGateEnabledProvider.overrideWith(_silentGate),
        ],
      );

      // Read notifier to instantiate it
      final notifier = container.read(routerRefreshNotifierProvider);

      int callCount = 0;
      notifier.addListener(() => callCount++);

      // First emission — should fire
      controller.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, 1);

      // Dispose the container — triggers ref.onDispose → notifier.dispose()
      // which closes the ProviderSubscriptions.
      container.dispose();

      // Second emission after dispose — should NOT fire
      controller.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, 1);

      await controller.close();
    });
  });
}
