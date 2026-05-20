import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/friendship.dart';
import 'package:treino/features/feed/domain/friendship_status.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';

void main() {
  group('PublicProfileView', () {
    // ── SCENARIO-326: New counter fields on PublicProfileView ───────────────
    group('SCENARIO-326 — counter fields', () {
      test(
          'SCENARIO-326a: construction without counter fields → all 4 null (backward compat)',
          () {
        const view = PublicProfileView(
          authorDisplayName: 'Tincho',
          authorAvatarUrl: null,
          authorGymId: null,
          friendship: null,
          isSelf: false,
        );
        expect(view.workoutsCount, isNull);
        expect(view.racha, isNull);
        expect(view.followersCount, isNull);
        expect(view.followingCount, isNull);
      });

      test(
          'SCENARIO-326b: construction with all counter fields → values preserved',
          () {
        const view = PublicProfileView(
          authorDisplayName: 'Tincho',
          authorAvatarUrl: null,
          authorGymId: null,
          friendship: null,
          isSelf: false,
          workoutsCount: 89,
          racha: 23,
          followersCount: 412,
          followingCount: 284,
        );
        expect(view.workoutsCount, equals(89));
        expect(view.racha, equals(23));
        expect(view.followersCount, equals(412));
        expect(view.followingCount, equals(284));
      });

      test('SCENARIO-326c: equality via freezed — same counter values → equal',
          () {
        const a = PublicProfileView(
          authorDisplayName: 'X',
          authorAvatarUrl: null,
          authorGymId: null,
          friendship: null,
          isSelf: false,
          workoutsCount: 10,
          racha: 5,
          followersCount: 20,
          followingCount: 15,
        );
        const b = PublicProfileView(
          authorDisplayName: 'X',
          authorAvatarUrl: null,
          authorGymId: null,
          friendship: null,
          isSelf: false,
          workoutsCount: 10,
          racha: 5,
          followersCount: 20,
          followingCount: 15,
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });
    });

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
