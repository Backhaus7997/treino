import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/data/follow_repository.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FollowRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FollowRepository(firestore: firestore);
  });

  Future<void> seed(
    String follower,
    String followee, {
    FollowStatus status = FollowStatus.accepted,
  }) =>
      firestore
          .collection('follows')
          .doc(Follow.edgeId(follower, followee))
          .set(
            Follow(
              id: Follow.edgeId(follower, followee),
              followerUid: follower,
              followeeUid: followee,
              status: status,
              members: [follower, followee],
              createdAt: DateTime.utc(2026, 8, 4),
            ).toJson(),
          );

  // ── follow ────────────────────────────────────────────────────────────────
  group('FollowRepository.follow', () {
    // REQ-FOLLOW-001 / REQ-FOLLOW-004 / SCENARIO-800 / SCENARIO-804
    test('cuenta PÚBLICA → escribe follows/u1_u2 como accepted', () async {
      final edge = await repo.follow('u1', 'u2', targetIsPublic: true);

      expect(edge.id, 'u1_u2');
      expect(edge.followerUid, 'u1');
      expect(edge.followeeUid, 'u2');
      expect(edge.status, FollowStatus.accepted);
      expect(edge.members, ['u1', 'u2']);

      final snap = await firestore.collection('follows').doc('u1_u2').get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['status'], 'accepted');
    });

    // REQ-FOLLOW-005 / SCENARIO-805
    test('cuenta PRIVADA → escribe pending, no accepted', () async {
      final edge = await repo.follow('u1', 'u2', targetIsPublic: false);

      expect(edge.status, FollowStatus.pending);
      final snap = await firestore.collection('follows').doc('u1_u2').get();
      expect(snap.data()!['status'], 'pending');
    });

    test('escribe UNA sola arista, no la inversa', () async {
      // La asimetría es el punto entero del cambio: seguir a alguien no puede
      // hacer que esa persona te siga de vuelta.
      await repo.follow('u1', 'u2', targetIsPublic: true);

      expect(
        (await firestore.collection('follows').doc('u2_u1').get()).exists,
        isFalse,
      );
      expect((await firestore.collection('follows').get()).docs.length, 1);
    });

    test('es idempotente: seguir dos veces no pisa la arista existente',
        () async {
      // Importa para no degradar un accepted a pending si el perfil cambió de
      // público a privado en el medio.
      await repo.follow('u1', 'u2', targetIsPublic: true);
      final segunda = await repo.follow('u1', 'u2', targetIsPublic: false);

      expect(segunda.status, FollowStatus.accepted);
      expect((await firestore.collection('follows').get()).docs.length, 1);
    });
  });

  // ── acceptRequest ─────────────────────────────────────────────────────────
  group('FollowRepository.acceptRequest', () {
    // REQ-FOLLOW-005 / SCENARIO-805
    test('el followee acepta: pending → accepted', () async {
      await seed('u1', 'u2', status: FollowStatus.pending);

      await repo.acceptRequest('u1_u2', 'u2');

      final snap = await firestore.collection('follows').doc('u1_u2').get();
      expect(snap.data()!['status'], 'accepted');
    });

    test('el FOLLOWER no puede auto-aceptarse', () async {
      // Equivalente a SCENARIO-132 del modelo viejo. Las rules lo bloquean del
      // lado del servidor; el repo falla temprano para no mandar un write que
      // va a rebotar igual.
      await seed('u1', 'u2', status: FollowStatus.pending);

      expect(
        () => repo.acceptRequest('u1_u2', 'u1'),
        throwsA(isA<StateError>()),
      );

      final snap = await firestore.collection('follows').doc('u1_u2').get();
      expect(snap.data()!['status'], 'pending');
    });

    test('un tercero ajeno a la arista no puede aceptar', () async {
      await seed('u1', 'u2', status: FollowStatus.pending);

      expect(
        () => repo.acceptRequest('u1_u2', 'intruso'),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ── deleteEdge ────────────────────────────────────────────────────────────
  group('FollowRepository.deleteEdge', () {
    // REQ-FOLLOW-006 / REQ-FOLLOW-007 / SCENARIO-806 / SCENARIO-808
    test('borra el documento', () async {
      await seed('u1', 'u2');

      await repo.deleteEdge('u1_u2');

      expect(
        (await firestore.collection('follows').doc('u1_u2').get()).exists,
        isFalse,
      );
    });

    test('borrar una dirección NO toca la inversa', () async {
      // Con follow mutuo (el estado en que quedan las relaciones migradas),
      // dejar de seguir tiene que cortar una sola dirección.
      await seed('u1', 'u2');
      await seed('u2', 'u1');

      await repo.deleteEdge('u1_u2');

      expect(
        (await firestore.collection('follows').doc('u2_u1').get()).exists,
        isTrue,
      );
    });
  });

  // ── followingOf / watchFollowingOf ────────────────────────────────────────
  group('FollowRepository.followingOf', () {
    // REQ-FOLLOW-011
    test('devuelve los followees accepted, no los pending', () async {
      await seed('u1', 'a');
      await seed('u1', 'b');
      await seed('u1', 'c', status: FollowStatus.pending);

      expect((await repo.followingOf('u1'))..sort(), ['a', 'b']);
    });

    test('NO devuelve a quienes lo siguen a él', () async {
      // El bug que motivó todo el cambio: en el modelo viejo esto devolvía a
      // los dos lados porque la relación era un solo documento simétrico.
      await seed('u1', 'sigo-a-este');
      await seed('me-sigue-este', 'u1');

      expect(await repo.followingOf('u1'), ['sigo-a-este']);
    });

    test('watchFollowingOf emite la misma lista', () async {
      await seed('u1', 'a');

      expect(await repo.watchFollowingOf('u1').first, ['a']);
    });
  });

  // ── pendingReceivedFor ────────────────────────────────────────────────────
  group('FollowRepository.pendingReceivedFor', () {
    // REQ-FOLLOW-005
    test('devuelve solo las pending donde el uid es el DESTINATARIO', () async {
      await seed('otro', 'u1', status: FollowStatus.pending); // recibida ✓
      await seed('u1', 'tercero', status: FollowStatus.pending); // enviada ✗
      await seed('cuarto', 'u1'); // ya accepted ✗

      final recibidas = await repo.pendingReceivedFor('u1');

      expect(recibidas.map((e) => e.id), ['otro_u1']);
    });

    test('el filtro es server-side, sin post-filtrado en memoria', () async {
      // Si el filtro se hiciera en el cliente, la query traería las solicitudes
      // ENVIADAS por el usuario además de las recibidas — y con las rules
      // nuevas ni siquiera podría leerlas todas. Se verifica pidiendo una
      // colección donde una lectura sin filtro traería documentos de más.
      await seed('a', 'u1', status: FollowStatus.pending);
      await seed('b', 'u1', status: FollowStatus.pending);
      await seed('u1', 'c', status: FollowStatus.pending);

      expect((await repo.pendingReceivedFor('u1')).length, 2);
      expect(await repo.watchPendingReceivedFor('u1').first, hasLength(2));
    });
  });

  // ── getEdge / watchEdge ───────────────────────────────────────────────────
  group('FollowRepository.getEdge', () {
    // REQ-FOLLOW-003 / SCENARIO-802
    test('resuelve por doc id', () async {
      await seed('u1', 'u2');

      final edge = await repo.getEdge('u1_u2');

      expect(edge, isNotNull);
      expect(edge!.followerUid, 'u1');
      expect(edge.followeeUid, 'u2');
    });

    test('devuelve null si la arista no existe', () async {
      expect(await repo.getEdge('no_existe'), isNull);
    });

    test('las dos direcciones se resuelven por separado', () async {
      // Los cuatro estados posibles entre dos usuarios se leen combinando
      // estas dos consultas, y por eso tienen que ser independientes.
      await seed('u1', 'u2');

      expect(await repo.getEdge('u1_u2'), isNotNull);
      expect(await repo.getEdge('u2_u1'), isNull);
    });

    test('watchEdge emite null cuando la arista se borra', () async {
      await seed('u1', 'u2');

      expect(await repo.watchEdge('u1_u2').first, isNotNull);
      await repo.deleteEdge('u1_u2');
      expect(await repo.watchEdge('u1_u2').first, isNull);
    });
  });

  // ── allOf ─────────────────────────────────────────────────────────────────
  group('FollowRepository.allOf', () {
    test('trae las aristas en las dos direcciones, con un array-contains',
        () async {
      // Es el insumo del cascade de borrado de cuenta y de la exclusión en
      // sugerencias: ahí hace falta "todo lo que toca a este usuario",
      // independientemente de la dirección y del status.
      await seed('u1', 'a');
      await seed('b', 'u1');
      await seed('c', 'u1', status: FollowStatus.pending);
      await seed('x', 'y'); // ajena

      final todas = await repo.allOf('u1');

      expect(
        todas.map((e) => e.id).toList()..sort(),
        ['b_u1', 'c_u1', 'u1_a'],
      );
    });
  });
}
