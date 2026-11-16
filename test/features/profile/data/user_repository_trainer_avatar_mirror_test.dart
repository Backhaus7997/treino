import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// #1694 — cambiar la foto (Coach Hub: Ajustes → Cuenta; mobile: «Datos
/// personales») escribe `avatarUrl` SIN campos de PF. El espejo a
/// `trainerPublicProfiles` tiene que seguir al ROL, igual que el del nombre
/// (#1336): si no, Discovery sigue mostrando la foto vieja.
void main() {
  const urlVieja = 'https://cdn.example.com/avatars/pf-1-vieja.jpg';
  const urlNueva = 'https://cdn.example.com/avatars/pf-1-nueva.jpg';

  late FakeFirebaseFirestore firestore;
  late UserRepository repo;

  Future<void> seed(
    String uid,
    UserRole role, {
    String? avatarUrl = urlVieja,
  }) async {
    final now = DateTime.utc(2026, 1, 1);
    await firestore.collection('users').doc(uid).set(UserProfile(
          uid: uid,
          email: 'seed@test.com',
          displayName: 'Viejo Nombre',
          avatarUrl: avatarUrl,
          role: role,
          createdAt: now,
          updatedAt: now,
        ).toJson());
  }

  Future<void> seedTarjeta(String uid) =>
      firestore.collection('trainerPublicProfiles').doc(uid).set({
        'uid': uid,
        'displayName': 'Viejo Nombre',
        'displayNameLowercase': 'viejo nombre',
        'avatarUrl': urlVieja,
        'trainerBio': 'Bio original',
        'averageRating': 4.5,
        'reviewCount': 7,
      });

  Future<Map<String, Object?>?> tarjeta(String uid) async =>
      (await firestore.collection('trainerPublicProfiles').doc(uid).get())
          .data();

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserRepository(firestore: firestore);
  });

  test('PF: un partial con SOLO avatarUrl actualiza la tarjeta pública',
      () async {
    await seed('pf-1', UserRole.trainer);
    await seedTarjeta('pf-1');

    await repo.update('pf-1', {'avatarUrl': urlNueva});

    final card = await tarjeta('pf-1');
    expect(card!['avatarUrl'], urlNueva);
    expect(card['uid'], 'pf-1');
  });

  test('PF: espejar la foto no pisa el resto de la tarjeta', () async {
    await seed('pf-1', UserRole.trainer);
    await seedTarjeta('pf-1');

    await repo.update('pf-1', {'avatarUrl': urlNueva});

    final card = await tarjeta('pf-1');
    expect(card!['displayName'], 'Viejo Nombre');
    expect(card['displayNameLowercase'], 'viejo nombre');
    expect(card['trainerBio'], 'Bio original');
    // Agregados que sólo escribe una Cloud Function: el cliente no los toca.
    expect(card['averageRating'], 4.5);
    expect(card['reviewCount'], 7);
  });

  test('PF: la foto nueva también llega a users/ y a userPublicProfiles/',
      () async {
    await seed('pf-1', UserRole.trainer);
    await seedTarjeta('pf-1');

    await repo.update('pf-1', {'avatarUrl': urlNueva});

    final user = await firestore.collection('users').doc('pf-1').get();
    final pub =
        await firestore.collection('userPublicProfiles').doc('pf-1').get();
    expect(user.data()!['avatarUrl'], urlNueva);
    expect(pub.data()!['avatarUrl'], urlNueva);
  });

  test('PF: «Quitar foto» (avatarUrl null) también limpia la tarjeta',
      () async {
    await seed('pf-1', UserRole.trainer);
    await seedTarjeta('pf-1');

    await repo.update('pf-1', {'avatarUrl': null});

    final card = await tarjeta('pf-1');
    expect(card!.containsKey('avatarUrl'), isTrue);
    expect(card['avatarUrl'], isNull);
    expect(card['displayName'], 'Viejo Nombre');
  });

  test('PF: nombre y foto en el mismo partial se espejan juntos', () async {
    await seed('pf-1', UserRole.trainer);
    await seedTarjeta('pf-1');

    await repo.update('pf-1', {
      'displayName': 'Nuevo Apellido',
      'avatarUrl': urlNueva,
    });

    final card = await tarjeta('pf-1');
    expect(card!['avatarUrl'], urlNueva);
    expect(card['displayName'], 'Nuevo Apellido');
    expect(card['displayNameLowercase'], 'nuevo apellido');
  });

  test('PF: un nombre en blanco no frena el espejo de la foto', () async {
    await seed('pf-1', UserRole.trainer);
    await seedTarjeta('pf-1');

    await repo.update('pf-1', {'displayName': '   ', 'avatarUrl': urlNueva});

    final card = await tarjeta('pf-1');
    expect(card!['avatarUrl'], urlNueva);
    // El nombre en blanco no se espeja: anularía `displayNameLowercase`.
    expect(card['displayName'], 'Viejo Nombre');
    expect(card['displayNameLowercase'], 'viejo nombre');
  });

  test('PF sin tarjeta previa: NO la crea (la crea el paso pf del onboarding)',
      () async {
    await seed('pf-2', UserRole.trainer);

    await repo.update('pf-2', {'avatarUrl': urlNueva});

    expect(await tarjeta('pf-2'), isNull);
    final user = await firestore.collection('users').doc('pf-2').get();
    expect(user.data()!['avatarUrl'], urlNueva);
  });

  test('alumno: avatarUrl solo NO toca trainerPublicProfiles (#58)', () async {
    await seed('al-1', UserRole.athlete);

    await repo.update('al-1', {'avatarUrl': urlNueva});

    expect(await tarjeta('al-1'), isNull);
    final user = await firestore.collection('users').doc('al-1').get();
    expect(user.data()!['avatarUrl'], urlNueva);
  });

  test('PF: un partial sin nombre ni foto no toca la tarjeta', () async {
    await seed('pf-1', UserRole.trainer);
    await seedTarjeta('pf-1');

    await repo.update('pf-1', {'phone': '123'});

    final card = await tarjeta('pf-1');
    expect(card!['avatarUrl'], urlVieja);
  });

  // #1717 — la tarjeta NACE con la foto que la cuenta ya tenía. El alta del
  // mobile (o un alumno promovido a PF) deja `users/{uid}.avatarUrl` cargado
  // antes de que exista `trainerPublicProfiles/{uid}`; la tarjeta la crea el
  // primer guardado de PF, que no manda la foto.
  group('#1717 — la tarjeta nace con la foto de la cuenta', () {
    test('PF sin tarjeta: el primer guardado de PF la crea con la foto',
        () async {
      await seed('pf-1', UserRole.trainer);

      await repo.update('pf-1', {'trainerBio': 'Hola'});

      final card = await tarjeta('pf-1');
      expect(card!['avatarUrl'], urlVieja);
      expect(card['trainerBio'], 'Hola');
    });

    test(
        'el guardado del paso `pf` del Hub (manda displayName, no la foto) '
        'también la completa', () async {
      await seed('pf-1', UserRole.trainer);

      await repo.update('pf-1', {
        'displayName': 'Viejo Nombre',
        'trainerBio': 'Hola',
        'trainerOffersOnline': true,
      });

      final card = await tarjeta('pf-1');
      expect(card!['avatarUrl'], urlVieja);
      expect(card['displayName'], 'Viejo Nombre');
    });

    test('un avatarUrl explícito en el partial gana sobre el de la cuenta',
        () async {
      await seed('pf-1', UserRole.trainer);

      await repo.update('pf-1', {'trainerBio': 'Hola', 'avatarUrl': urlNueva});

      final card = await tarjeta('pf-1');
      expect(card!['avatarUrl'], urlNueva);
    });

    test('una tarjeta existente sin foto se cura en el siguiente guardado',
        () async {
      await seed('pf-1', UserRole.trainer);
      await firestore.collection('trainerPublicProfiles').doc('pf-1').set({
        'uid': 'pf-1',
        'displayName': 'Viejo Nombre',
        'displayNameLowercase': 'viejo nombre',
      });

      await repo.update('pf-1', {'trainerBio': 'Nueva bio'});

      final card = await tarjeta('pf-1');
      expect(card!['avatarUrl'], urlVieja);
      expect(card['trainerBio'], 'Nueva bio');
    });

    test('cuenta sin foto: no se escribe avatarUrl en la tarjeta', () async {
      await seed('pf-1', UserRole.trainer, avatarUrl: null);

      await repo.update('pf-1', {'trainerBio': 'Hola'});

      final card = await tarjeta('pf-1');
      expect(card!.containsKey('avatarUrl'), isFalse);
    });

    test('cuenta con la foto en blanco: no se escribe avatarUrl', () async {
      await seed('pf-1', UserRole.trainer, avatarUrl: '   ');

      await repo.update('pf-1', {'trainerBio': 'Hola'});

      final card = await tarjeta('pf-1');
      expect(card!.containsKey('avatarUrl'), isFalse);
    });

    test('un alumno que guarda no crea la tarjeta ni se lleva la foto',
        () async {
      await seed('al-1', UserRole.athlete);

      await repo.update('al-1', {'heightCm': 170});

      expect(await tarjeta('al-1'), isNull);
    });
  });

  test('usuario sin doc en users: no espeja y no tira', () async {
    await repo.update('fantasma', {'avatarUrl': urlNueva});

    expect(await tarjeta('fantasma'), isNull);
  });
}
