import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/application/email_gate_providers.dart';
import 'package:treino/features/coach_hub/application/coach_hub_router_refresh.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';

Stream<UserProfile?> _silentProfile(Ref ref) =>
    Completer<UserProfile?>().future.asStream();
Stream<bool> _silentGate(Ref ref) => Completer<bool>().future.asStream();
Stream<User?> _silentAuth(Ref ref) => Completer<User?>().future.asStream();

void main() {
  group('coachHubRouterRefreshProvider (REQ-CHW-ONB-004 / SCENARIO-019)', () {
    test('un cambio del pendiente de escrituras notifica al listenable',
        () async {
      final pending = StreamController<bool>.broadcast();
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith(_silentAuth),
          userProfileProvider.overrideWith(_silentProfile),
          emailGateEnabledProvider.overrideWith(_silentGate),
          userProfileHasPendingWritesProvider
              .overrideWith((_) => pending.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(pending.close);

      final refresh = container.read(coachHubRouterRefreshProvider);
      var calls = 0;
      refresh.addListener(() => calls++);

      pending.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      pending.add(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, 2);
    });

    test('un cambio del perfil sigue notificando por el notifier compartido',
        () async {
      final profile = StreamController<UserProfile?>.broadcast();
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith(_silentAuth),
          userProfileProvider.overrideWith((_) => profile.stream),
          emailGateEnabledProvider.overrideWith(_silentGate),
          userProfileHasPendingWritesProvider
              .overrideWith((_) => const Stream<bool>.empty()),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(profile.close);

      final refresh = container.read(coachHubRouterRefreshProvider);
      var calls = 0;
      refresh.addListener(() => calls++);

      profile.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, 1);
    });

    test('el notifier de mobile NO escucha el pendiente (queda intacto)',
        () async {
      final pending = StreamController<bool>.broadcast();
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith(_silentAuth),
          userProfileProvider.overrideWith(_silentProfile),
          emailGateEnabledProvider.overrideWith(_silentGate),
          userProfileHasPendingWritesProvider
              .overrideWith((_) => pending.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(pending.close);

      final mobile = container.read(routerRefreshNotifierProvider);
      var calls = 0;
      mobile.addListener(() => calls++);
      // Mantener vivo el provider de pendiente.
      container.listen(userProfileHasPendingWritesProvider, (_, __) {});

      pending.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, 0);
    });
  });
}
