import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';

void main() {
  group('PublicProfileView', () {
    test('SCENARIO-193: holds all 5 fields when fully populated', () {
      final friendship = Friendship(
        id: 'a_b',
        uidA: 'a',
        uidB: 'b',
        status: FriendshipStatus.accepted,
        requesterId: 'a',
        members: const ['a', 'b'],
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final view = PublicProfileView(
        authorDisplayName: 'Tincho',
        authorAvatarUrl: 'https://x/y.jpg',
        authorGymId: 'la-fuerza',
        friendship: friendship,
        isSelf: false,
      );

      expect(view.authorDisplayName, equals('Tincho'));
      expect(view.authorAvatarUrl, equals('https://x/y.jpg'));
      expect(view.authorGymId, equals('la-fuerza'));
      expect(view.friendship, equals(friendship));
      expect(view.isSelf, isFalse);
    });

    test(
        'SCENARIO-194: handles nullable fields (no avatar, no gym, no friendship)',
        () {
      const view = PublicProfileView(
        authorDisplayName: 'Anónimo',
        authorAvatarUrl: null,
        authorGymId: null,
        friendship: null,
        isSelf: false,
      );

      expect(view.authorDisplayName, equals('Anónimo'));
      expect(view.authorAvatarUrl, isNull);
      expect(view.authorGymId, isNull);
      expect(view.friendship, isNull);
      expect(view.isSelf, isFalse);
    });

    test('SCENARIO-195: isSelf=true for self-visit', () {
      const view = PublicProfileView(
        authorDisplayName: 'Yo',
        authorAvatarUrl: null,
        authorGymId: null,
        friendship: null,
        isSelf: true,
      );

      expect(view.isSelf, isTrue);
    });

    test('SCENARIO-196: equality via freezed (same values → equal)', () {
      const a = PublicProfileView(
        authorDisplayName: 'X',
        authorAvatarUrl: null,
        authorGymId: null,
        friendship: null,
        isSelf: false,
      );
      const b = PublicProfileView(
        authorDisplayName: 'X',
        authorAvatarUrl: null,
        authorGymId: null,
        friendship: null,
        isSelf: false,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
