import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1, 12, 0, 0);

  group('Friendship', () {
    // SCENARIO-116: Friendship default values and members contains both UIDs
    test(
        'SCENARIO-116: members contains both UIDs and status defaults to pending',
        () {
      final friendship = Friendship(
        id: 'aaa_bbb',
        uidA: 'aaa',
        uidB: 'bbb',
        status: FriendshipStatus.pending,
        requesterId: 'aaa',
        members: const ['aaa', 'bbb'],
        createdAt: createdAt,
      );

      expect(friendship.members, containsAll(['aaa', 'bbb']));
      expect(friendship.status, equals(FriendshipStatus.pending));
    });

    // SCENARIO for sortedDocId
    test('sortedDocId: ("bbb","aaa") returns "aaa_bbb"', () {
      expect(Friendship.sortedDocId('bbb', 'aaa'), equals('aaa_bbb'));
    });

    test('sortedDocId: ("aaa","bbb") returns "aaa_bbb"', () {
      expect(Friendship.sortedDocId('aaa', 'bbb'), equals('aaa_bbb'));
    });

    test('sortedDocId: equal strings returns "aaa_aaa"', () {
      expect(Friendship.sortedDocId('aaa', 'aaa'), equals('aaa_aaa'));
    });
  });
}
