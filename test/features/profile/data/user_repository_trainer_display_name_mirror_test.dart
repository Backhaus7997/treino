import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// #1336 — Coach Hub, Ajustes → Cuenta escribe `displayName` solo (sin campos
/// de PF). El espejo a `trainerPublicProfiles` tiene que seguir al ROL, no a
/// la presencia de un campo de PF en el partial.
void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

  Future<void> seed(String uid, UserRole role) async {
    final now = DateTime.utc(2026, 1, 1);
    await firestore.collection('users').doc(uid).set(UserProfile(
          uid: uid,
          email: 'seed@test.com',
          displayName: 'Viejo Nombre',
          role: role,
          createdAt: now,
          updatedAt: now,
        ).toJson());
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserRepository(firestore: firestore);
  });

  test('PF: un partial con SOLO displayName actualiza la tarjeta pública',
      () async {
    await seed('pf-1', UserRole.trainer);
    await firestore.collection('trainerPublicProfiles').doc('pf-1').set({
      'uid': 'pf-1',
      'displayName': 'Viejo Nombre',
      'displayNameLowercase': 'viejo nombre',
    });

    await repo.update('pf-1', {'displayName': 'Nuevo Apellido'});

    final snap =
        await firestore.collection('trainerPublicProfiles').doc('pf-1').get();
    expect(snap.data()!['displayName'], 'Nuevo Apellido');
    expect(snap.data()!['displayNameLowercase'], 'nuevo apellido');
    expect(snap.data()!['uid'], 'pf-1');
  });

  test('PF sin tarjeta previa: NO la crea (la crea el paso pf del onboarding)',
      () async {
    await seed('pf-2', UserRole.trainer);

    await repo.update('pf-2', {'displayName': 'Ana Gómez'});

    final snap =
        await firestore.collection('trainerPublicProfiles').doc('pf-2').get();
    expect(snap.exists, isFalse);
    final user = await firestore.collection('users').doc('pf-2').get();
    expect(user.data()!['displayName'], 'Ana Gómez');
  });

  for (final nombre in <String?>[null, '', '   ']) {
    test(
        'PF: displayName ${nombre == null ? 'null' : "'$nombre'"} no se '
        'espeja a la tarjeta', () async {
      await seed('pf-4', UserRole.trainer);
      await firestore.collection('trainerPublicProfiles').doc('pf-4').set({
        'uid': 'pf-4',
        'displayName': 'Viejo Nombre',
        'displayNameLowercase': 'viejo nombre',
      });

      await repo.update('pf-4', {'displayName': nombre});

      final snap =
          await firestore.collection('trainerPublicProfiles').doc('pf-4').get();
      expect(snap.data()!['displayName'], 'Viejo Nombre');
      expect(snap.data()!['displayNameLowercase'], 'viejo nombre');
    });
  }

  test('alumno: displayName solo NO toca trainerPublicProfiles (#58)',
      () async {
    await seed('al-1', UserRole.athlete);

    await repo.update('al-1', {'displayName': 'Franco'});

    final snap =
        await firestore.collection('trainerPublicProfiles').doc('al-1').get();
    expect(snap.exists, isFalse);
  });

  test('PF: un partial sin displayName no toca la tarjeta', () async {
    await seed('pf-3', UserRole.trainer);

    await repo.update('pf-3', {'phone': '123'});

    final snap =
        await firestore.collection('trainerPublicProfiles').doc('pf-3').get();
    expect(snap.exists, isFalse);
  });

  test('usuario sin doc en users: no espeja y no tira', () async {
    await repo.update('fantasma', {'displayName': 'X'});

    final snap = await firestore
        .collection('trainerPublicProfiles')
        .doc('fantasma')
        .get();
    expect(snap.exists, isFalse);
  });
}
