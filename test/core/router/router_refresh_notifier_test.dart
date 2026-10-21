import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
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

/// Y el pendiente de escrituras: es el cuarto provider que escucha el notifier y
/// se reconstruye con auth (loading → data), así que sin silenciarlo suma
/// notificaciones de más al conteo exacto de los tests de auth.
Stream<bool> _silentPending(Ref ref) => Completer<bool>().future.asStream();

/// `AuthNotifier` fijo. El real se reconstruye con cada emisión de auth
/// (loading → data), y su salida de loading es un refresh más: los tests que
/// cuentan exacto las emisiones del stream lo silencian.
class _SilentAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() => Completer<User?>().future;
}

/// `AuthNotifier` que el test mueve a mano, para ver qué transiciones avisan.
class _ManualAuthNotifier extends AuthNotifier {
  @override
  Future<User?> build() async => null;

  void poner(AsyncValue<User?> valor) => state = valor;
}

void main() {
  group('RouterRefreshNotifier (via routerRefreshNotifierProvider)', () {
    test('notifyListeners fires once per auth stream emission', () async {
      final controller = StreamController<User?>.broadcast();
      final mockUser = MockUser();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((_) => controller.stream),
          authNotifierProvider.overrideWith(_SilentAuthNotifier.new),
          userProfileProvider.overrideWith(_silentProfile),
          emailGateEnabledProvider.overrideWith(_silentGate),
          userProfileHasPendingWritesProvider.overrideWith(_silentPending),
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
          userProfileHasPendingWritesProvider.overrideWith(_silentPending),
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
        'notifyListeners fires when the pending-writes signal changes '
        '(server ack: true -> false, sin emisión nueva del perfil) (#1335)',
        () async {
      final pending = StreamController<bool>.broadcast();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider
              .overrideWith((_) => Stream<User?>.value(MockUser())),
          userProfileProvider.overrideWith(_silentProfile),
          emailGateEnabledProvider.overrideWith(_silentGate),
          userProfileHasPendingWritesProvider
              .overrideWith((_) => pending.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(pending.close);

      final notifier = container.read(routerRefreshNotifierProvider);

      int callCount = 0;
      notifier.addListener(() => callCount++);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final baseline = callCount;

      pending.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, baseline + 1);

      // El ack del servidor solo cambia metadata: el perfil NO re-emite, y esta
      // es la única señal que le avisa al router que puede soltar /birth-date.
      pending.add(false);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, baseline + 2);
    });

    // Los dos redirects leen `authNotifierProvider` y se abstienen mientras
    // carga. El refresh de una emisión de auth lo encuentra reconstruyéndose, así
    // que la salida de loading tiene que volver a disparar el redirect: sin eso,
    // «Cerrar sesión» en «Confirmá tu mail» del Coach Hub dejaba la pantalla
    // ahí, sin usuario.
    test('notifyListeners fires when authNotifierProvider leaves loading',
        () async {
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider
              .overrideWith((_) => Stream<User?>.value(null)),
          authNotifierProvider.overrideWith(_ManualAuthNotifier.new),
          userProfileProvider.overrideWith(_silentProfile),
          emailGateEnabledProvider.overrideWith(_silentGate),
          userProfileHasPendingWritesProvider.overrideWith(_silentPending),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(routerRefreshNotifierProvider);
      await container.read(authNotifierProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      int callCount = 0;
      notifier.addListener(() => callCount++);
      final auth =
          container.read(authNotifierProvider.notifier) as _ManualAuthNotifier;

      // Entrar en loading no avisa: el redirect no haría nada con eso.
      auth.poner(const AsyncLoading());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, 0);

      auth.poner(const AsyncData(null));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, 1);

      // De data a data no es una salida de loading: eso ya lo avisa el stream.
      auth.poner(AsyncData(MockUser()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, 1);
    });

    test(
        'after container dispose, additional emissions do NOT call notifyListeners',
        () async {
      final controller = StreamController<User?>.broadcast();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((_) => controller.stream),
          authNotifierProvider.overrideWith(_SilentAuthNotifier.new),
          userProfileProvider.overrideWith(_silentProfile),
          emailGateEnabledProvider.overrideWith(_silentGate),
          userProfileHasPendingWritesProvider.overrideWith(_silentPending),
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
