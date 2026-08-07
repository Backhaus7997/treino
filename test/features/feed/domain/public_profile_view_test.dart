import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';

Follow _edge(String follower, String followee, FollowStatus status) => Follow(
      id: Follow.edgeId(follower, followee),
      followerUid: follower,
      followeeUid: followee,
      status: status,
      members: [follower, followee],
      createdAt: DateTime.utc(2026, 1, 1),
    );

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
          outgoingFollow: null,
          incomingFollow: null,
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
          outgoingFollow: null,
          incomingFollow: null,
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
          outgoingFollow: null,
          incomingFollow: null,
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
          outgoingFollow: null,
          incomingFollow: null,
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

    test('SCENARIO-193: holds all fields when fully populated', () {
      final outgoing = _edge('viewer', 'target', FollowStatus.accepted);
      final incoming = _edge('target', 'viewer', FollowStatus.accepted);

      final view = PublicProfileView(
        authorDisplayName: 'Tincho',
        authorAvatarUrl: 'https://x/y.jpg',
        authorGymId: 'la-fuerza',
        outgoingFollow: outgoing,
        incomingFollow: incoming,
        isSelf: false,
      );

      expect(view.authorDisplayName, equals('Tincho'));
      expect(view.authorAvatarUrl, equals('https://x/y.jpg'));
      expect(view.authorGymId, equals('la-fuerza'));
      expect(view.outgoingFollow, equals(outgoing));
      expect(view.incomingFollow, equals(incoming));
      expect(view.isSelf, isFalse);
    });

    // SCENARIO-822 — LAS DOS DIRECCIONES SON INDEPENDIENTES.
    //
    // Es la razón de ser del cambio de modelo. Con `Friendship? friendship`
    // había UN solo campo, así que "yo lo sigo" y "él me sigue" no se podían
    // representar por separado: el view-model no tenía dónde poner la
    // diferencia. Estos dos casos son literalmente inexpresables en el modelo
    // viejo.
    test('SCENARIO-822: lo sigo pero no me sigue', () {
      final view = PublicProfileView(
        authorDisplayName: 'Tincho',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: _edge('viewer', 'target', FollowStatus.accepted),
        incomingFollow: null,
        isSelf: false,
      );

      expect(view.outgoingFollow?.status, equals(FollowStatus.accepted));
      expect(view.incomingFollow, isNull);
    });

    test('SCENARIO-822: me sigue pero no lo sigo', () {
      final view = PublicProfileView(
        authorDisplayName: 'Tincho',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: null,
        incomingFollow: _edge('target', 'viewer', FollowStatus.accepted),
        isSelf: false,
      );

      expect(view.outgoingFollow, isNull);
      expect(view.incomingFollow?.status, equals(FollowStatus.accepted));
    });

    test(
        'SCENARIO-822: dos vistas que difieren SOLO en la dirección no son iguales',
        () {
      // Ancla de que las dos aristas no colapsaron en un solo campo por
      // descuido: si `incomingFollow` no formara parte de la igualdad, estas
      // dos vistas —que describen situaciones opuestas— serían indistinguibles.
      final soloSaliente = PublicProfileView(
        authorDisplayName: 'X',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: _edge('viewer', 'target', FollowStatus.accepted),
        incomingFollow: null,
        isSelf: false,
      );
      final soloEntrante = PublicProfileView(
        authorDisplayName: 'X',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: null,
        incomingFollow: _edge('target', 'viewer', FollowStatus.accepted),
        isSelf: false,
      );

      expect(soloSaliente, isNot(equals(soloEntrante)));
    });

    test(
        'SCENARIO-194: handles nullable fields (no avatar, no gym, sin aristas)',
        () {
      const view = PublicProfileView(
        authorDisplayName: 'Anónimo',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: null,
        incomingFollow: null,
        isSelf: false,
      );

      expect(view.authorDisplayName, equals('Anónimo'));
      expect(view.authorAvatarUrl, isNull);
      expect(view.authorGymId, isNull);
      expect(view.outgoingFollow, isNull);
      expect(view.incomingFollow, isNull);
      expect(view.isSelf, isFalse);
    });

    test('SCENARIO-195: isSelf=true for self-visit', () {
      const view = PublicProfileView(
        authorDisplayName: 'Yo',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: null,
        incomingFollow: null,
        isSelf: true,
      );

      expect(view.isSelf, isTrue);
    });

    test('SCENARIO-196: equality via freezed (same values → equal)', () {
      const a = PublicProfileView(
        authorDisplayName: 'X',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: null,
        incomingFollow: null,
        isSelf: false,
      );
      const b = PublicProfileView(
        authorDisplayName: 'X',
        authorAvatarUrl: null,
        authorGymId: null,
        outgoingFollow: null,
        incomingFollow: null,
        isSelf: false,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
