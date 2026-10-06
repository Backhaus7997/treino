import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/moderation/moderation_guard.dart';
import 'package:treino/core/utils/geohash.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach_hub/application/hub_onboarding_controller.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider, userProfileProvider, userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// Repo cuyo `update` y `getFromServer` se pueden hacer fallar, para medir lo
/// que hace el controller cuando el servidor contesta mal. Cuenta los updates:
/// «no escribe» se prueba contra el contador y contra el doc, no contra uno.
class _RepoFalible extends UserRepository {
  _RepoFalible({required super.firestore});

  Object? errorEnUpdate;
  Object? errorEnGetFromServer;
  int updates = 0;

  @override
  Future<void> update(
    String uid,
    Map<String, Object?> partial, {
    bool grantLocationConsent = false,
  }) {
    final e = errorEnUpdate;
    if (e != null) throw e;
    updates++;
    return super
        .update(uid, partial, grantLocationConsent: grantLocationConsent);
  }

  @override
  Future<UserProfile?> getFromServer(String uid) {
    final e = errorEnGetFromServer;
    if (e != null) throw e;
    return super.getFromServer(uid);
  }
}

final _adulto = DateTime.utc(1990, 5, 20);
final _t0 = Timestamp.fromDate(DateTime.utc(2026, 1, 1, 12));

void main() {
  late FakeFirebaseFirestore firestore;
  late _RepoFalible repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = _RepoFalible(firestore: firestore);
  });

  Future<void> sembrar({Map<String, Object?> extra = const {}}) async {
    final now = DateTime.utc(2026, 1, 1);
    await firestore.collection('users').doc('u1').set({
      'uid': 'u1',
      'email': 'pf@test.com',
      'displayName': null,
      'role': 'trainer',
      'createdAt': now,
      'updatedAt': now,
      ...extra,
    });
  }

  Future<ProviderContainer> contenedor() async {
    final c = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(firestore),
      userRepositoryProvider.overrideWithValue(repo),
      userProfileProvider.overrideWith((ref) => repo.watch('u1')),
    ]);
    addTearDown(c.dispose);
    await c.read(userProfileProvider.future);
    return c;
  }

  Future<Map<String, Object?>> users() async =>
      (await firestore.collection('users').doc('u1').get()).data()!;

  Future<Map<String, Object?>?> publico(String col) async =>
      (await firestore.collection(col).doc('u1').get()).data();

  HubOnboardingController ctl(ProviderContainer c) =>
      c.read(hubOnboardingControllerProvider.notifier);

  group('guardarEdad', () {
    test('SCENARIO-027: escribe solo bornAt', () async {
      await sembrar();
      final c = await contenedor();
      final antes = await users();

      await ctl(c).guardarEdad(_adulto);

      final d = await users();
      expect(d['bornAt'], isNotNull);
      expect(c.read(hubOnboardingControllerProvider).hasError, isFalse);
      final cambiadas = {
        for (final k in d.keys)
          if (!antes.containsKey(k) || antes[k] != d[k]) k,
      };
      expect(cambiadas, {'bornAt', 'updatedAt'});
    });

    test('SCENARIO-026: menor de 13 no escribe y deja error', () async {
      await sembrar();
      final c = await contenedor();
      final hoy = DateTime.now().toUtc();

      await ctl(c).guardarEdad(DateTime.utc(hoy.year - 12, hoy.month, 1));

      expect(repo.updates, 0);
      expect((await users()).containsKey('bornAt'), isFalse);
      expect(c.read(hubOnboardingControllerProvider).hasError, isTrue);
    });

    test('SCENARIO-028: permission-denied es error visible y no cuelga',
        () async {
      await sembrar();
      final c = await contenedor();
      repo.errorEnUpdate = FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied');

      await ctl(c).guardarEdad(_adulto);

      final s = c.read(hubOnboardingControllerProvider);
      expect(s.isLoading, isFalse);
      expect(s.hasError, isTrue);
    });
  });

  group('guardarIdentidad', () {
    test(
        'SCENARIO-024/025/030/048: una escritura con nombres, displayName, '
        'terminos y espejo; sin username ni role', () async {
      await sembrar();
      final c = await contenedor();

      await ctl(c).guardarIdentidad(
          nombre: ' Ana ', apellido: 'Pérez ', aceptoTerminos: true);

      expect(repo.updates, 1);
      final d = await users();
      expect(d['firstName'], 'Ana');
      expect(d['lastName'], 'Pérez');
      expect(d['displayName'], 'Ana Pérez');
      expect(d['termsAcceptedAt'], isNotNull);
      expect(d['acceptedTermsVersion'], kTermsVersion);
      expect(d['acceptedPrivacyVersion'], kPrivacyVersion);
      expect(d.containsKey('username'), isFalse);
      expect(d['role'], 'trainer');
      expect(
          (await publico('userPublicProfiles'))!['displayName'], 'Ana Pérez');
    });

    test('SCENARIO-031: no pisa evidencia existente y sí escribe el nombre',
        () async {
      await sembrar(extra: {
        'termsAcceptedAt': _t0,
        'acceptedTermsVersion': 0,
        'acceptedPrivacyVersion': 0,
      });
      final c = await contenedor();

      await ctl(c).guardarIdentidad(
          nombre: 'Ana', apellido: 'Pérez', aceptoTerminos: false);

      final d = await users();
      expect(d['termsAcceptedAt'], _t0);
      expect(d['acceptedTermsVersion'], 0);
      expect(d['acceptedPrivacyVersion'], 0);
      expect(d['displayName'], 'Ana Pérez');
    });

    test(
        'SCENARIO-031b: el observado dice que falta pero el servidor ya '
        'tiene evidencia: no pisa', () async {
      // El perfil observado (stream) no tiene la evidencia; el "servidor" sí.
      await sembrar();
      await firestore.collection('users').doc('u1').update({
        'termsAcceptedAt': _t0,
        'acceptedTermsVersion': 0,
        'acceptedPrivacyVersion': 0,
      });
      final obs = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(firestore),
        userRepositoryProvider.overrideWithValue(repo),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(
            // perfil viejo en caché, sin evidencia
            UserProfile(
              uid: 'u1',
              email: 'pf@test.com',
              displayName: null,
              role: UserRole.trainer,
              createdAt: DateTime.utc(2026, 1, 1),
              updatedAt: DateTime.utc(2026, 1, 1),
            ),
          ),
        ),
      ]);
      addTearDown(obs.dispose);
      await obs.read(userProfileProvider.future);

      await ctl(obs).guardarIdentidad(
          nombre: 'Ana', apellido: 'Pérez', aceptoTerminos: true);

      expect((await users())['termsAcceptedAt'], _t0);
      expect((await users())['acceptedTermsVersion'], 0);
    });

    test('SCENARIO-032: getFromServer falla: no estampa y muestra el error',
        () async {
      await sembrar();
      final c = await contenedor();
      repo.errorEnGetFromServer = StateError('offline');

      await ctl(c).guardarIdentidad(
          nombre: 'Ana', apellido: 'Pérez', aceptoTerminos: true);

      expect(repo.updates, 0);
      final d = await users();
      expect(d.containsKey('termsAcceptedAt'), isFalse);
      expect(d.containsKey('firstName'), isFalse);
      expect(c.read(hubOnboardingControllerProvider).hasError, isTrue);
    });

    test('requerido y sin marcar: no escribe', () async {
      await sembrar();
      final c = await contenedor();

      await ctl(c).guardarIdentidad(
          nombre: 'Ana', apellido: 'Pérez', aceptoTerminos: false);

      expect(repo.updates, 0);
      expect(c.read(hubOnboardingControllerProvider).hasError, isTrue);
    });

    test('nombre o apellido en blanco: no escribe', () async {
      await sembrar();
      final c = await contenedor();

      await ctl(c).guardarIdentidad(
          nombre: '  ', apellido: 'Pérez', aceptoTerminos: true);
      await ctl(c)
          .guardarIdentidad(nombre: 'Ana', apellido: ' ', aceptoTerminos: true);

      expect(repo.updates, 0);
    });

    test('SCENARIO-061: moderación rechaza: error, sin términos, sin nombre',
        () async {
      await sembrar();
      final c = await contenedor();

      await ctl(c).guardarIdentidad(
          nombre: 'sos un', apellido: 'hijo de puta', aceptoTerminos: true);

      final s = c.read(hubOnboardingControllerProvider);
      expect(s.error, isA<ModerationBlockedException>());
      final d = await users();
      expect(d.containsKey('termsAcceptedAt'), isFalse);
      expect(d['displayName'], isNull);
    });
  });

  group('guardarPerfilPf', () {
    PerfilPfDraft draft({
      String bio = 'Entreno fuerza e hipertrofia hace diez años.',
      bool online = true,
      List<TrainerLocation> locs = const [],
    }) =>
        PerfilPfDraft(
          bio: bio,
          specialty: TrainerSpecialty.powerlifting,
          monthlyRate: 20000,
          offersOnline: online,
          locations: locs,
        );

    final lugar = TrainerLocation(
      id: 'custom-1',
      type: TrainerLocationType.custom,
      customLabel: 'Av. Siempreviva 742',
      lat: -34.603722,
      lng: -58.381592,
      geohash: geohash5(-34.603722, -58.381592),
    );

    test('SCENARIO-063: displayName llega a trainerPublicProfiles', () async {
      await sembrar(extra: {'displayName': 'Ana Pérez'});
      final c = await contenedor();

      await ctl(c)
          .guardarPerfilPf(draft(), otorgaConsentimientoUbicacion: false);

      final p = await publico('trainerPublicProfiles');
      expect(p!['displayName'], 'Ana Pérez');
      expect(p['trainerBio'], isNotNull);
    });

    test('rechaza «sin modalidad» sin escribir', () async {
      await sembrar(extra: {'displayName': 'Ana Pérez'});
      final c = await contenedor();

      await ctl(c).guardarPerfilPf(draft(online: false),
          otorgaConsentimientoUbicacion: false);

      expect(repo.updates, 0);
      expect(c.read(hubOnboardingControllerProvider).hasError, isTrue);
    });

    test('rechaza bio corta sin escribir', () async {
      await sembrar(extra: {'displayName': 'Ana Pérez'});
      final c = await contenedor();

      await ctl(c).guardarPerfilPf(draft(bio: 'corta'),
          otorgaConsentimientoUbicacion: false);

      expect(repo.updates, 0);
    });

    test(
        'SCENARIO-038/039/041: ubicación custom exacta + consentimiento en '
        'el MISMO batch', () async {
      await sembrar(extra: {'displayName': 'Ana Pérez'});
      final c = await contenedor();

      await ctl(c).guardarPerfilPf(draft(online: false, locs: [lugar]),
          otorgaConsentimientoUbicacion: true);

      expect(repo.updates, 1);
      final d = await users();
      final locs = d['trainerLocations'] as List;
      expect(locs, hasLength(1));
      final l = locs.single as Map;
      expect(l['type'], 'custom');
      expect(l['lat'], -34.603722);
      expect(l['lng'], -58.381592);
      expect(l['geohash'], geohash5(-34.603722, -58.381592));
      expect(l['gymId'], isNull);
      expect(d['trainerGeohashes'], [geohash5(-34.603722, -58.381592)]);
      expect(d['trainerLocationConsentAt'], isNotNull);
      expect(d['trainerLocationConsentPromptedAt'], isNotNull);
      final p = await publico('trainerPublicProfiles');
      expect((p!['trainerLocations'] as List), hasLength(1));
      expect(p['trainerGeohashes'], [geohash5(-34.603722, -58.381592)]);
    });

    test(
        'trainerLocationsCoordsFetchedAt es el MÁS VIEJO de los lugares con '
        'placeId; null si no hay ninguno (y no va al perfil público)',
        () async {
      await sembrar(extra: {'displayName': 'Ana Pérez'});
      final c = await contenedor();
      final viejo = DateTime.utc(2026, 9, 1);
      final nuevo = DateTime.utc(2026, 10, 1);
      TrainerLocation de(String id, double lat, String? placeId, DateTime? t) =>
          TrainerLocation(
            id: id,
            type: TrainerLocationType.custom,
            customLabel: id,
            lat: lat,
            lng: -58.4,
            geohash: geohash5(lat, -58.4),
            placeId: placeId,
            coordsFetchedAt: t,
          );

      await ctl(c).guardarPerfilPf(
        draft(online: false, locs: [
          de('a', -34.1, 'P1', nuevo),
          de('b', -34.2, 'P2', viejo),
          // GPS del móvil: sin placeId, no se refresca ni cuenta.
          de('c', -34.3, null, DateTime.utc(2020, 1, 1)),
        ]),
        otorgaConsentimientoUbicacion: true,
      );

      final d = await users();
      expect(
          (d['trainerLocationsCoordsFetchedAt'] as Timestamp).toDate().toUtc(),
          viejo);
      final p = await publico('trainerPublicProfiles');
      expect(p!.containsKey('trainerLocationsCoordsFetchedAt'), isFalse);

      await ctl(c).guardarPerfilPf(
        draft(online: true, locs: [de('c', -34.3, null, null)]),
        otorgaConsentimientoUbicacion: false,
      );
      expect((await users())['trainerLocationsCoordsFetchedAt'], isNull);
    });

    test('SCENARIO-042: consentimiento previo no se pisa', () async {
      await sembrar(extra: {
        'displayName': 'Ana Pérez',
        'trainerLocationConsentAt': _t0,
        'trainerLocationConsentPromptedAt': _t0,
      });
      final c = await contenedor();

      await ctl(c).guardarPerfilPf(draft(online: false, locs: [lugar]),
          otorgaConsentimientoUbicacion: false);

      final d = await users();
      expect(d['trainerLocationConsentAt'], _t0);
      expect(d['trainerLocationConsentPromptedAt'], _t0);
      expect((d['trainerLocations'] as List), hasLength(1));
    });

    test('SCENARIO-048: no escribe role', () async {
      await sembrar(extra: {'displayName': 'Ana Pérez'});
      final c = await contenedor();

      await ctl(c)
          .guardarPerfilPf(draft(), otorgaConsentimientoUbicacion: false);

      expect((await users())['role'], 'trainer');
    });
  });
}
