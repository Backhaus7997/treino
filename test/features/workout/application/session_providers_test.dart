import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';

ProviderContainer makeContainer({required SessionRepository repo}) =>
    ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
      ],
    );

void main() {
  group('session providers', () {
    test(
        'SCENARIO-256: sessionRepositoryProvider resolves with FakeFirebaseFirestore override',
        () {
      final firestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
        ],
      );
      addTearDown(container.dispose);

      // Should not throw — just reads the provider.
      final repo = container.read(sessionRepositoryProvider);
      expect(repo, isA<SessionRepository>());
    });

    test(
        'SCENARIO-257: sessionsByUidProvider returns empty list for unknown uid',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result =
          await container.read(sessionsByUidProvider('uid_nobody').future);
      expect(result, isEmpty);
    });

    test(
        'SCENARIO-258: sessionsByUidProvider returns empty list when uid is empty',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(sessionsByUidProvider('').future);
      expect(result, isEmpty);
    });

    test('SCENARIO-259: activeSessionProvider returns null when uid is empty',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result = await container.read(activeSessionProvider('').future);
      expect(result, isNull);
    });

    test(
        'SCENARIO-260: activeSessionProvider returns null when no active session exists',
        () async {
      final firestore = FakeFirebaseFirestore();
      final container = makeContainer(
        repo: SessionRepository(firestore: firestore),
      );
      addTearDown(container.dispose);

      final result =
          await container.read(activeSessionProvider('uid_001').future);
      expect(result, isNull);
    });
  });
}
