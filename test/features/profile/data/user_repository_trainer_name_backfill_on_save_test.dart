import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// Directorio "Encontrá tu coach": la tarjeta del PF se creaba SIN nombre
/// cuando "Editar perfil de PF" guardaba bio/tarifa/lugares (sin
/// `displayName`) después de un alta que sí lo había mandado, pero sin campos
/// de PF. El nombre tiene que salir de `users/{uid}`.
void main() {
  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

  Future<void> seed(String uid, UserRole role, {String? name}) async {
    final now = DateTime.utc(2026, 1, 1);
    await firestore.collection('users').doc(uid).set(UserProfile(
          uid: uid,
          email: 'seed@test.com',
          displayName: name,
          role: role,
          createdAt: now,
          updatedAt: now,
        ).toJson());
  }

  Future<Map<String, dynamic>?> card(String uid) async =>
      (await firestore.collection('trainerPublicProfiles').doc(uid).get())
          .data();

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserRepository(firestore: firestore);
  });

  test('PF guarda campos de PF sin nombre: la tarjeta toma el de users/',
      () async {
    await seed('pf-1', UserRole.trainer, name: 'Pepe');

    await repo.update('pf-1', {'trainerBio': 'Hola, soy Pepe'});

    final data = await card('pf-1');
    expect(data!['displayName'], 'Pepe');
    expect(data['displayNameLowercase'], 'pepe');
    expect(data['trainerBio'], 'Hola, soy Pepe');
  });

  test('el nombre de users/ se recorta y se baja a minúsculas', () async {
    await seed('pf-2', UserRole.trainer, name: '  Ana GÓMEZ ');

    await repo.update('pf-2', {'trainerBio': 'bio'});

    final data = await card('pf-2');
    expect(data!['displayName'], 'Ana GÓMEZ');
    expect(data['displayNameLowercase'], 'ana gómez');
  });

  test('un displayName explícito en el partial gana sobre el de users/',
      () async {
    await seed('pf-3', UserRole.trainer, name: 'Pepe');

    await repo.update('pf-3', {'displayName': 'Pepe Nuevo', 'trainerBio': 'b'});

    final data = await card('pf-3');
    expect(data!['displayName'], 'Pepe Nuevo');
    expect(data['displayNameLowercase'], 'pepe nuevo');
  });

  test('sin nombre en users/ no se escribe un nombre vacío', () async {
    await seed('pf-4', UserRole.trainer);

    await repo.update('pf-4', {'trainerBio': 'bio'});

    final data = await card('pf-4');
    expect(data!.containsKey('displayName'), isFalse);
    expect(data.containsKey('displayNameLowercase'), isFalse);
  });

  test('un alumno que guarda no crea ni toca la tarjeta de PF', () async {
    await seed('al-1', UserRole.athlete, name: 'Lucía');

    await repo.update('al-1', {'heightCm': 170});
    await repo.update('al-1', {'displayName': 'Lucía R'});

    expect(await card('al-1'), isNull);
  });
}
