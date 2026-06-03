import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/notifications/data/fcm_token_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FcmTokenRepository repo;

  Future<void> seedDoc(String uid, {List<String>? tokens}) async {
    final data = <String, Object?>{'uid': uid};
    if (tokens != null) {
      data['fcmTokens'] = tokens;
    }
    await firestore.collection('users').doc(uid).set(data);
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FcmTokenRepository(firestore: firestore);
  });

  group('FcmTokenRepository', () {
    // SCENARIO-619: saveToken on new doc with no fcmTokens field
    test(
      'SCENARIO-619: saveToken on fresh doc creates fcmTokens array',
      () async {
        const uid = 'user-619';
        await seedDoc(uid);

        await repo.saveToken(uid, 'tok-1');

        final snap = await firestore.collection('users').doc(uid).get();
        final tokens = List<String>.from(
          (snap.data()?['fcmTokens'] as List?) ?? [],
        );
        expect(tokens, equals(['tok-1']));
      },
    );

    // SCENARIO-620: duplicate saveToken is idempotent (arrayUnion semantics)
    test(
      'SCENARIO-620: saveToken with duplicate token keeps array at 1 element',
      () async {
        const uid = 'user-620';
        await seedDoc(uid, tokens: ['tok-1']);

        await repo.saveToken(uid, 'tok-1');

        final snap = await firestore.collection('users').doc(uid).get();
        final tokens = List<String>.from(
          (snap.data()?['fcmTokens'] as List?) ?? [],
        );
        expect(tokens, equals(['tok-1']));
      },
    );

    // SCENARIO-621: second device token added without overwriting first
    test(
      'SCENARIO-621: saveToken second device token appends without overwrite',
      () async {
        const uid = 'user-621';
        await seedDoc(uid, tokens: ['tok-phone']);

        await repo.saveToken(uid, 'tok-tablet');

        final snap = await firestore.collection('users').doc(uid).get();
        final tokens = List<String>.from(
          (snap.data()?['fcmTokens'] as List?) ?? [],
        );
        expect(tokens, containsAll(['tok-phone', 'tok-tablet']));
        expect(tokens.length, equals(2));
      },
    );

    // SCENARIO-622: removeToken removes the correct token
    test(
      'SCENARIO-622: removeToken removes specified token from array',
      () async {
        const uid = 'user-622';
        await seedDoc(uid, tokens: ['tok-1', 'tok-2']);

        await repo.removeToken(uid, 'tok-1');

        final snap = await firestore.collection('users').doc(uid).get();
        final tokens = List<String>.from(
          (snap.data()?['fcmTokens'] as List?) ?? [],
        );
        expect(tokens, equals(['tok-2']));
      },
    );

    // SCENARIO-623: removing absent token is a no-op
    test(
      'SCENARIO-623: removeToken of absent token is a no-op, no error',
      () async {
        const uid = 'user-623';
        await seedDoc(uid, tokens: ['tok-2']);

        expect(
          () => repo.removeToken(uid, 'tok-999'),
          returnsNormally,
        );
        await repo.removeToken(uid, 'tok-999');

        final snap = await firestore.collection('users').doc(uid).get();
        final tokens = List<String>.from(
          (snap.data()?['fcmTokens'] as List?) ?? [],
        );
        expect(tokens, equals(['tok-2']));
      },
    );

    // arrayUnion semantics verified via SCENARIO-621
    test(
      'SCENARIO-621 (arrayUnion): saveToken uses arrayUnion semantics — '
      'concurrent tokens coexist',
      () async {
        const uid = 'user-621b';
        await seedDoc(uid);

        await repo.saveToken(uid, 'tok-a');
        await repo.saveToken(uid, 'tok-b');

        final snap = await firestore.collection('users').doc(uid).get();
        final tokens = List<String>.from(
          (snap.data()?['fcmTokens'] as List?) ?? [],
        );
        expect(tokens, containsAll(['tok-a', 'tok-b']));
      },
    );

    // arrayRemove semantics verified via SCENARIO-622, 623
    test(
      'SCENARIO-622 (arrayRemove): removeToken uses arrayRemove semantics — '
      'only specified token removed',
      () async {
        const uid = 'user-622b';
        await seedDoc(uid, tokens: ['tok-keep', 'tok-remove']);

        await repo.removeToken(uid, 'tok-remove');

        final snap = await firestore.collection('users').doc(uid).get();
        final tokens = List<String>.from(
          (snap.data()?['fcmTokens'] as List?) ?? [],
        );
        expect(tokens, equals(['tok-keep']));
        expect(tokens, isNot(contains('tok-remove')));
      },
    );
  });
}
