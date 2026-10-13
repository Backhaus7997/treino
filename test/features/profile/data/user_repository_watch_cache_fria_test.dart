// Regresión del cuelgue por "documento inexistente + caché".
//
// `UserRepository.watch` descarta la snapshot `!exists && isFromCache` porque
// con la caché fría eso es "todavía no sé", no "no existe". Pero el SDK de
// Firestore, cuando el servidor confirma ese MISMO "no existe", sólo cambia la
// metadata (`isFromCache` true → false). Sin `includeMetadataChanges: true`
// esa confirmación no se emite, y el stream queda en loading para siempre.
//
// `fake_cloud_firestore` no modela `isFromCache`, así que se mockea la cadena
// `collection → doc → snapshots`. `CollectionReference`, `DocumentReference` y
// `DocumentSnapshot` están `@sealed`; mockearlos es la única forma de
// controlar la metadata (mismo criterio que
// `trainer_link_repository_cache_fria_test.dart`).
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, Object?>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, Object?>> {}

class _MockSnapshotMetadata extends Mock implements SnapshotMetadata {}

void main() {
  const uid = 'u1';

  late _MockDocumentReference doc;
  late StreamController<DocumentSnapshot<Map<String, Object?>>> conMetadata;
  late StreamController<DocumentSnapshot<Map<String, Object?>>> sinMetadata;
  late UserRepository repo;

  setUp(() {
    final firestore = _MockFirebaseFirestore();
    final users = _MockCollectionReference();
    doc = _MockDocumentReference();
    conMetadata = StreamController<DocumentSnapshot<Map<String, Object?>>>();
    sinMetadata = StreamController<DocumentSnapshot<Map<String, Object?>>>();

    when(() => firestore.collection('users')).thenReturn(users);
    when(() => users.doc(uid)).thenReturn(doc);
    when(() => doc.snapshots(includeMetadataChanges: true))
        .thenAnswer((_) => conMetadata.stream);
    when(() => doc.snapshots()).thenAnswer((_) => sinMetadata.stream);

    repo = UserRepository(firestore: firestore);
  });

  tearDown(() async {
    await conMetadata.close();
    await sinMetadata.close();
  });

  DocumentSnapshot<Map<String, Object?>> inexistente({
    required bool isFromCache,
  }) {
    final metadata = _MockSnapshotMetadata();
    when(() => metadata.isFromCache).thenReturn(isFromCache);
    final snap = _MockDocumentSnapshot();
    when(() => snap.exists).thenReturn(false);
    when(() => snap.data()).thenReturn(null);
    when(() => snap.metadata).thenReturn(metadata);
    return snap;
  }

  test(
      'doc inexistente: caché y luego confirmación SOLO de metadata emite '
      'null (no se cuelga)', () async {
    final emissions = <UserProfile?>[];
    final sub = repo.watch(uid).listen(emissions.add);

    final cache = inexistente(isFromCache: true);
    final servidor = inexistente(isFromCache: false);
    // Sin la opción el SDK sólo entrega la snapshot de caché; con ella,
    // además la confirmación del servidor.
    sinMetadata.add(cache);
    conMetadata
      ..add(cache)
      ..add(servidor);
    await Future<void>.delayed(Duration.zero);

    expect(emissions, [null],
        reason: 'el servidor confirmó que el perfil no existe: el router '
            'tiene que poder mandarlo a /profile-setup');

    await sub.cancel();
  });

  test('watchCorreosPromocionales: mismo cuelgue, mismo arreglo', () async {
    final emissions = <bool>[];
    final sub = repo.watchCorreosPromocionales(uid).listen(emissions.add);

    final cache = inexistente(isFromCache: true);
    final servidor = inexistente(isFromCache: false);
    sinMetadata.add(cache);
    conMetadata
      ..add(cache)
      ..add(servidor);
    await Future<void>.delayed(Duration.zero);

    // Ausente = true (igual que el servidor), y deduplicado: la caché y el
    // servidor dicen lo mismo.
    expect(emissions, [true]);

    await sub.cancel();
  });
}
