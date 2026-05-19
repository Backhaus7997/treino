import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // userPublicProfileProvider
  // ──────────────────────────────────────────────────────────────────────────
  group('userPublicProfileProvider', () {
    test('SCENARIO-254 (via provider): returns null when doc missing', () async {
      final firestore = FakeFirebaseFirestore();

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(userPublicProfileProvider('u99').future);
      expect(result, isNull);
    });

    test('SCENARIO-255 (via provider): returns profile when doc exists',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('userPublicProfiles').doc('u1').set({
        'uid': 'u1',
        'displayName': 'Ana',
        'displayNameLowercase': 'ana',
        'avatarUrl': null,
        'gymId': 'g1',
      });

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(userPublicProfileProvider('u1').future);
      expect(result, isNotNull);
      expect(result, isA<UserPublicProfile>());
      expect(result!.uid, equals('u1'));
      expect(result.displayName, equals('Ana'));
      expect(result.gymId, equals('g1'));
    });

    test('returns null when unauthenticated', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('userPublicProfiles').doc('u1').set({
        'uid': 'u1',
        'displayName': 'Ana',
        'displayNameLowercase': 'ana',
        'avatarUrl': null,
        'gymId': null,
      });

      final container = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((_) => Stream.value(null)),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(userPublicProfileProvider('u1').future);
      expect(result, isNull);
    });
  });
}
