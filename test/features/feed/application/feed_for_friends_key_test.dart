import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';

Post _makePost(String id) => Post(
      id: id,
      authorUid: 'u1',
      authorDisplayName: 'Tincho',
      authorAvatarUrl: null,
      authorGymId: null,
      text: 'Hola',
      routineTag: null,
      privacy: PostPrivacy.friends,
      createdAt: DateTime.utc(2026, 5, 14, 10, 0, 0),
    );

void main() {
  group('friendUidsKey', () {
    // The bug: feedForFriendsProvider was keyed on List<String>, which has
    // identity equality. A fresh list on every Firestore emission thrashed the
    // family cache. friendUidsKey must produce a stable, order-independent key.

    test('produces identical keys for distinct list instances with same UIDs',
        () {
      final keyA = friendUidsKey(['u2', 'u3']);
      final keyB = friendUidsKey(['u2', 'u3']); // distinct instance
      expect(keyA, equals(keyB));
    });

    test('is order-independent (sorts before joining)', () {
      expect(friendUidsKey(['u3', 'u2']), equals(friendUidsKey(['u2', 'u3'])));
    });

    test('empty list yields empty key', () {
      expect(friendUidsKey(const <String>[]), isEmpty);
    });

    test('does not mutate the input list', () {
      final input = ['u3', 'u1', 'u2'];
      friendUidsKey(input);
      expect(input, equals(['u3', 'u1', 'u2']));
    });
  });

  group('feedForFriendsProvider', () {
    // Same key -> single provider entry -> repository query runs once and the
    // result is reused, instead of re-firing on every list re-emission.
    test('reuses the cached entry for equal keys (no redundant build)',
        () async {
      var buildCount = 0;
      final posts = [_makePost('p1')];

      final container = ProviderContainer(
        overrides: [
          feedForFriendsProvider.overrideWith((ref, key) {
            buildCount++;
            return Future.value(posts);
          }),
        ],
      );
      addTearDown(container.dispose);

      final keyFromFirstEmission = friendUidsKey(['u2', 'u3']);
      final keyFromSecondEmission = friendUidsKey(['u3', 'u2']);

      final first =
          await container.read(feedForFriendsProvider(keyFromFirstEmission).future);
      final second =
          await container.read(feedForFriendsProvider(keyFromSecondEmission).future);

      expect(first, equals(posts));
      expect(second, equals(posts));
      expect(buildCount, equals(1),
          reason: 'equal keys must hit the same cached family entry');
    });
  });
}
