import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';

class MockUser extends Mock implements User {}

void main() {
  group('RouterRefreshNotifier (via routerRefreshNotifierProvider)', () {
    test('notifyListeners fires once per stream emission', () async {
      final controller = StreamController<User?>.broadcast();
      final mockUser = MockUser();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((_) => controller.stream),
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

    test(
        'after container dispose, additional emissions do NOT call notifyListeners',
        () async {
      final controller = StreamController<User?>.broadcast();

      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((_) => controller.stream),
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
      // which closes the ProviderSubscription.
      container.dispose();

      // Second emission after dispose — should NOT fire
      controller.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(callCount, 1);

      await controller.close();
    });
  });
}
