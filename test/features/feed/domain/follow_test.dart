import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';

Follow _edge({
  String follower = 'u1',
  String followee = 'u2',
  FollowStatus status = FollowStatus.accepted,
}) =>
    Follow(
      id: Follow.edgeId(follower, followee),
      followerUid: follower,
      followeeUid: followee,
      status: status,
      members: [follower, followee],
      createdAt: DateTime.utc(2026, 8, 4),
    );

void main() {
  // REQ-FOLLOW-001 / SCENARIO-800.
  group('Follow.edgeId', () {
    test('es {follower}_{followee}, NO ordenado', () {
      // Esta es LA diferencia con `Friendship.sortedDocId`, que ordenaba para
      // que el par tuviera un id único. Acá la dirección ES el dato: si el id
      // se ordenara, las dos direcciones colisionarían en el mismo documento y
      // volveríamos a no poder representar "A sigue a B pero B no a A".
      expect(Follow.edgeId('u1', 'u2'), 'u1_u2');
      expect(Follow.edgeId('u2', 'u1'), 'u2_u1');
    });

    test('las dos direcciones de un par dan ids DISTINTOS', () {
      expect(Follow.edgeId('a', 'b'), isNot(Follow.edgeId('b', 'a')));
    });

    test('no depende del orden lexicográfico de los uids', () {
      // Con `sortedDocId` estos dos daban lo mismo. Acá no.
      expect(Follow.edgeId('zzz', 'aaa'), 'zzz_aaa');
      expect(Follow.edgeId('aaa', 'zzz'), 'aaa_zzz');
    });
  });

  group('Follow — forma del documento', () {
    test('members es [follower, followee], en ese orden', () {
      // El orden importa: `members` existe para poder resolver "todas las
      // aristas de este usuario" con un solo `array-contains`, pero la
      // dirección se lee de followerUid/followeeUid, no de la posición.
      final e = _edge(follower: 'u1', followee: 'u2');
      expect(e.members, ['u1', 'u2']);
    });

    test('el id coincide con edgeId(followerUid, followeeUid)', () {
      final e = _edge(follower: 'abc', followee: 'xyz');
      expect(e.id, Follow.edgeId(e.followerUid, e.followeeUid));
    });

    test('round-trip JSON preserva dirección y status', () {
      for (final status in FollowStatus.values) {
        final original = _edge(status: status);
        final vuelta = Follow.fromJson(original.toJson());

        expect(vuelta, original);
        expect(vuelta.followerUid, 'u1');
        expect(vuelta.followeeUid, 'u2');
        expect(vuelta.status, status);
      }
    });

    test('el JSON serializa el status con su literal de wire', () {
      final json = _edge(status: FollowStatus.pending).toJson();
      expect(json['status'], 'pending');
    });

    test('dos aristas opuestas del mismo par son documentos distintos', () {
      final ida = _edge(follower: 'a', followee: 'b');
      final vuelta = _edge(follower: 'b', followee: 'a');

      expect(ida.id, isNot(vuelta.id));
      expect(ida, isNot(vuelta));
      // Pero las dos resuelven por `array-contains` para cualquiera de los dos.
      expect(ida.members, containsAll(['a', 'b']));
      expect(vuelta.members, containsAll(['a', 'b']));
    });
  });
}
