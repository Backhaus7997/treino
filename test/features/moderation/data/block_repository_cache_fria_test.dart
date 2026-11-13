// Regresión de «Usuarios bloqueados» sin red (#1831): con la caché fría una query
// no falla, contesta con un `QuerySnapshot` VACÍO con `isFromCache == true`, y la
// pantalla lo dibujaba como «No bloqueaste a nadie». Mismo agujero que el feed
// (#1744, `post_repository_cache_fria_test.dart`).
//
// `fake_cloud_firestore` no modela `isFromCache`, así que se mockea con mocktail
// la cadena real de la query y se ejercita `BlockRepository` de verdad. Los
// documentos son reales (sembrados en una `FakeFirebaseFirestore` auxiliar):
// `QueryDocumentSnapshot` es `@sealed`.

// `CollectionReference` y `Query` están `@sealed` en `cloud_firestore`.
// Mockearlas es la ÚNICA forma de controlar `metadata.isFromCache`.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/moderation/data/block_repository.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockQuery extends Mock implements Query<Map<String, Object?>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, Object?>> {}

class _MockSnapshotMetadata extends Mock implements SnapshotMetadata {}

typedef _Docs = List<QueryDocumentSnapshot<Map<String, Object?>>>;

/// Documentos `blocks/` REALES para [blocked] (los uids que 'aaa' bloqueó).
Future<_Docs> _realDocs(List<String> blocked) async {
  final aux = FakeFirebaseFirestore();
  for (final uid in blocked) {
    await aux.collection('blocks').doc('aaa_$uid').set({
      'id': 'aaa_$uid',
      'blockerUid': 'aaa',
      'blockedUid': uid,
      'members': ['aaa', uid],
      'createdAt': Timestamp.now(),
    });
  }
  return (await aux.collection('blocks').get()).docs;
}

QuerySnapshot<Map<String, Object?>> _snap({
  required _Docs docs,
  required bool isFromCache,
}) {
  final metadata = _MockSnapshotMetadata();
  when(() => metadata.isFromCache).thenReturn(isFromCache);
  final snap = _MockQuerySnapshot();
  when(() => snap.docs).thenReturn(docs);
  when(() => snap.metadata).thenReturn(metadata);
  return snap;
}

void main() {
  late _MockQuery query;
  late BlockRepository repo;

  /// La query `blocks where blockerUid == 'aaa'` contesta [get] por `get()` y
  /// [live] por `snapshots()`.
  void cablear({
    required QuerySnapshot<Map<String, Object?>> get,
    Stream<QuerySnapshot<Map<String, Object?>>>? live,
  }) {
    when(() => query.get()).thenAnswer((_) async => get);
    when(() => query.snapshots()).thenAnswer((_) => live ?? Stream.value(get));
  }

  setUp(() {
    final firestore = _MockFirebaseFirestore();
    final blocks = _MockCollectionReference();
    query = _MockQuery();
    when(() => firestore.collection('blocks')).thenReturn(blocks);
    when(() => blocks.where('blockerUid', isEqualTo: 'aaa')).thenReturn(query);
    repo = BlockRepository(firestore: firestore);
  });

  Matcher throwsUnavailable() => throwsA(
        isA<FirebaseException>().having((e) => e.code, 'code', 'unavailable'),
      );

  group('watchBlockedUidsConfirmed — la lista que se MUESTRA', () {
    test('vacío DESDE CACHÉ → unavailable, no un «no bloqueaste a nadie»',
        () async {
      cablear(get: _snap(docs: const [], isFromCache: true));

      await expectLater(
        repo.watchBlockedUidsConfirmed('aaa').first,
        throwsUnavailable(),
      );
    });

    test('vacío CONFIRMADO por el servidor → [] (un vacío real)', () async {
      cablear(get: _snap(docs: const [], isFromCache: false));

      expect(await repo.watchBlockedUidsConfirmed('aaa').first, isEmpty);
    });

    test('con bloqueados en la caché → los muestra (viejos pero reales)',
        () async {
      cablear(
        get: _snap(docs: await _realDocs(['bbb', 'ccc']), isFromCache: true),
      );

      expect(
        await repo.watchBlockedUidsConfirmed('aaa').first,
        unorderedEquals(['bbb', 'ccc']),
      );
    });

    test(
        'la guarda corre UNA vez: desbloquear al último sin red es un vacío '
        'real, no un error', () async {
      // Carga inicial con un bloqueado (confirmada); después el usuario lo
      // desbloquea sin red y el listener entrega la snapshot vacía de la caché.
      cablear(
        get: _snap(docs: await _realDocs(['bbb']), isFromCache: false),
        live: Stream.fromIterable([
          _snap(docs: await _realDocs(['bbb']), isFromCache: false),
          _snap(docs: const [], isFromCache: true),
        ]),
      );

      final emisiones = await repo.watchBlockedUidsConfirmed('aaa').toList();

      expect(emisiones.first, ['bbb']);
      expect(emisiones.last, isEmpty);
    });
  });

  group('watchBlockedUids — el del feed, el chat y myBlockedUids', () {
    // Es la contracara de lo de arriba y se fija a propósito: ante la caché fría
    // éstos asumen «sin bloqueos». Si el vacío de caché tirara acá, el feed
    // (`blockedUidsProvider.future`) perdería los posts cacheados sin red para
    // todo usuario sin bloqueos.
    test('vacío DESDE CACHÉ → [] (no tira)', () async {
      cablear(get: _snap(docs: const [], isFromCache: true));

      expect(await repo.watchBlockedUids('aaa').first, isEmpty);
    });
  });
}
