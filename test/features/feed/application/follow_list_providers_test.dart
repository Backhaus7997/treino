import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/follow_list_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        authStateChangesProvider
            .overrideWith((ref) => Stream.value(_MockUser(uid: 'viewer'))),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> seedProfile(String uid, {String? displayName}) {
    final name = displayName ?? uid.toUpperCase();
    return firestore.collection('userPublicProfiles').doc(uid).set(
          UserPublicProfile(
            uid: uid,
            displayName: name,
            displayNameLowercase: name.toLowerCase(),
          ).toJson(),
        );
  }

  /// Siembra UNA arista dirigida. El doc id NO se ordena: si se ordenara, las
  /// dos direcciones de un par colisionarían en el mismo documento.
  Future<void> seedEdge(
    String follower,
    String followee, {
    String status = 'accepted',
  }) =>
      firestore.collection('follows').doc('${follower}_$followee').set({
        'id': '${follower}_$followee',
        'followerUid': follower,
        'followeeUid': followee,
        'status': status,
        'members': [follower, followee],
        'createdAt': DateTime.utc(2026, 8, 4).toIso8601String(),
      });

  group('followListKey', () {
    test('arma una key String, nunca un record ni una List', () {
      expect(followListKey(FollowListKind.followers, 'u1'), 'followers:u1');
      expect(followListKey(FollowListKind.following, 'u1'), 'following:u1');
    });

    test('el round-trip devuelve lo mismo que entró', () {
      for (final kind in FollowListKind.values) {
        final key = followListKey(kind, 'u1');
        expect(parseFollowListKey(key), (kind: kind, uid: 'u1'));
      }
    });
  });

  group('followListProvider', () {
    test('SEGUIDORES: resuelve los perfiles de quienes siguen al target',
        () async {
      await seedProfile('a');
      await seedProfile('b');
      await seedEdge('a', 'u1');
      await seedEdge('b', 'u1');

      final container = buildContainer();
      final profiles = await container.read(
        followListProvider(followListKey(FollowListKind.followers, 'u1'))
            .future,
      );

      expect(profiles.map((p) => p.uid).toList()..sort(), ['a', 'b']);
    });

    test('SEGUIDOS: resuelve los perfiles de a quiénes sigue el target',
        () async {
      await seedProfile('a');
      await seedProfile('b');
      await seedEdge('u1', 'a');
      await seedEdge('b', 'u1');

      final container = buildContainer();
      final profiles = await container.read(
        followListProvider(followListKey(FollowListKind.following, 'u1'))
            .future,
      );

      expect(profiles.map((p) => p.uid).toList(), ['a']);
    });

    // Las dos listas son conjuntos distintos. Si esto se rompiera estaríamos
    // de vuelta en el modelo simétrico viejo.
    test('las dos direcciones no se mezclan', () async {
      await seedProfile('me-sigue');
      await seedProfile('lo-sigo');
      await seedEdge('me-sigue', 'u1');
      await seedEdge('u1', 'lo-sigo');

      final container = buildContainer();
      final followers = await container.read(
        followListProvider(followListKey(FollowListKind.followers, 'u1'))
            .future,
      );
      final following = await container.read(
        followListProvider(followListKey(FollowListKind.following, 'u1'))
            .future,
      );

      expect(followers.map((p) => p.uid), ['me-sigue']);
      expect(following.map((p) => p.uid), ['lo-sigo']);
    });

    test('ignora las aristas pending', () async {
      await seedProfile('aceptado');
      await seedProfile('pendiente');
      await seedEdge('aceptado', 'u1');
      await seedEdge('pendiente', 'u1', status: 'pending');

      final container = buildContainer();
      final profiles = await container.read(
        followListProvider(followListKey(FollowListKind.followers, 'u1'))
            .future,
      );

      expect(profiles.map((p) => p.uid), ['aceptado']);
    });

    test('sin relaciones devuelve vacío', () async {
      final container = buildContainer();

      final profiles = await container.read(
        followListProvider(followListKey(FollowListKind.followers, 'u1'))
            .future,
      );

      expect(profiles, isEmpty);
    });

    // Una arista puede sobrevivir al perfil (cuenta borrada a medias). La fila
    // se omite en vez de romper la lista entera.
    test('omite las aristas cuyo perfil ya no existe', () async {
      await seedProfile('vive');
      await seedEdge('vive', 'u1');
      await seedEdge('fantasma', 'u1');

      final container = buildContainer();
      final profiles = await container.read(
        followListProvider(followListKey(FollowListKind.followers, 'u1'))
            .future,
      );

      expect(profiles.map((p) => p.uid), ['vive']);
    });

    // El batch de perfiles devuelve un Map (sin orden). El provider tiene que
    // reordenarlo según la query, no según lo que salga del Map.
    test('respeta el orden que devuelve la query de follows', () async {
      final container = buildContainer();
      for (final uid in ['c', 'a', 'b']) {
        await seedProfile(uid);
        await seedEdge(uid, 'u1');
      }

      final uids = await container.read(
        followListUidsProvider(followListKey(FollowListKind.followers, 'u1'))
            .future,
      );
      final profiles = await container.read(
        followListProvider(followListKey(FollowListKind.followers, 'u1'))
            .future,
      );

      expect(profiles.map((p) => p.uid).toList(), uids);
    });
  });
}
