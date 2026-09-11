// Regresión del bug de caché fría (fix en commit f7dbb4ef).
//
// `TrainerLinkRepository.listForAthlete` hacía `query.get()`. Resuelto desde
// la caché local FRÍA, un `.get()` devuelve una lista VACÍA y no un error —
// quien pregunta no tiene forma de distinguir "no tenés vínculo" de "todavía
// no sé". `watchForAthlete` (el método nuevo, con `.snapshots()`) arregla esto
// descartando la primera snapshot vacía-de-caché y esperando la que confirma
// el servidor. Ver trainer_link_repository.dart:200-236.
//
// `fake_cloud_firestore` NO modela `metadata.isFromCache` (sus snapshots
// siempre se comportan como si vinieran del servidor), así que no puede
// reproducir el bug. Este archivo mockea con mocktail la cadena real
// `CollectionReference → Query.where → Query.orderBy → Query.snapshots()`
// para poder emitir `QuerySnapshot` falsos con el `isFromCache` que haga
// falta, y ejercita `watchForAthlete` de verdad — no una reimplementación.
//
// Los `QueryDocumentSnapshot` de los docs NO se mockean directamente:
// `Query`, `DocumentSnapshot` y `QueryDocumentSnapshot` están `@sealed` en
// `cloud_firestore` (mockearlos dispara el warning `subtype_of_sealed_class`
// del analyzer). En su lugar, los documentos se generan REALES con una
// `FakeFirebaseFirestore` auxiliar (mismo patrón que ya usa el resto de la
// suite) y esos `docs` reales se inyectan en el `QuerySnapshot` mockeado.
// Sólo `CollectionReference`/`Query` — que la tarea pide mockear explícita y
// puntualmente para poder controlar `snapshots()` — quedan con ese warning;
// es inevitable si se quiere ejercitar el código real sin pegarle a un
// backend.

// `CollectionReference` y `Query` están `@sealed` en `cloud_firestore`.
// Mockearlas es la ÚNICA forma de controlar `metadata.isFromCache`, que es
// justo lo que este archivo prueba: `fake_cloud_firestore` no lo modela.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockQuery extends Mock implements Query<Map<String, Object?>> {}

class _MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, Object?>> {}

class _MockSnapshotMetadata extends Mock implements SnapshotMetadata {}

void main() {
  const athleteId = 'athlete-1';

  late _MockFirebaseFirestore firestore;
  late _MockCollectionReference collection;
  late _MockQuery afterWhere;
  late _MockQuery afterOrderBy;
  late StreamController<QuerySnapshot<Map<String, Object?>>> snapshots;
  late TrainerLinkRepository repo;

  setUp(() {
    firestore = _MockFirebaseFirestore();
    collection = _MockCollectionReference();
    afterWhere = _MockQuery();
    afterOrderBy = _MockQuery();
    snapshots = StreamController<QuerySnapshot<Map<String, Object?>>>();

    when(() => firestore.collection('trainer_links')).thenReturn(collection);
    when(
      () => collection.where('athleteId', isEqualTo: athleteId),
    ).thenReturn(afterWhere);
    when(
      () => afterWhere.orderBy('requestedAt', descending: true),
    ).thenReturn(afterOrderBy);
    when(() => afterOrderBy.snapshots()).thenAnswer((_) => snapshots.stream);

    repo = TrainerLinkRepository(firestore: firestore);
  });

  tearDown(() => snapshots.close());

  // Arma un QuerySnapshot mockeado con el isFromCache que se necesite.
  QuerySnapshot<Map<String, Object?>> fakeSnapshot({
    required List<QueryDocumentSnapshot<Map<String, Object?>>> docs,
    required bool isFromCache,
  }) {
    final metadata = _MockSnapshotMetadata();
    when(() => metadata.isFromCache).thenReturn(isFromCache);
    final snap = _MockQuerySnapshot();
    when(() => snap.docs).thenReturn(docs);
    when(() => snap.metadata).thenReturn(metadata);
    return snap;
  }

  TrainerLink link({
    required String id,
    TrainerLinkStatus status = TrainerLinkStatus.active,
  }) =>
      TrainerLink(
        id: id,
        trainerId: 'trainer-1',
        athleteId: athleteId,
        status: status,
        requestedAt: DateTime.utc(2026, 1, 1),
      );

  // Genera QueryDocumentSnapshot REALES (no mockeados — ver nota de arriba)
  // sembrando `links` en una FakeFirebaseFirestore auxiliar, sin tocar la
  // FirebaseFirestore mockeada que usa `repo`.
  Future<List<QueryDocumentSnapshot<Map<String, Object?>>>> realDocsFor(
    List<TrainerLink> links,
  ) async {
    final aux = FakeFirebaseFirestore();
    for (final l in links) {
      await aux.collection('trainer_links').doc(l.id).set(l.toJson());
    }
    final snap = await aux
        .collection('trainer_links')
        .where('athleteId', isEqualTo: athleteId)
        .orderBy('requestedAt', descending: true)
        .get();
    return snap.docs;
  }

  test('una snapshot VACÍA que viene de caché NO se emite', () async {
    final emissions = <List<TrainerLink>>[];
    final sub = repo.watchForAthlete(athleteId).listen(emissions.add);

    snapshots.add(fakeSnapshot(docs: const [], isFromCache: true));
    await Future<void>.delayed(Duration.zero);

    expect(
      emissions,
      isEmpty,
      reason: 'una snapshot vacía de la caché fría es "todavía no sé", no '
          '"no hay vínculos" — no debe emitirse',
    );

    await sub.cancel();
  });

  test('cuando contesta el servidor, emite el vínculo', () async {
    // ESTE es el test que reproduce el bug del usuario: la primera respuesta
    // (caché fría, vacía) no puede ser la última palabra — tiene que llegar
    // la del servidor con el vínculo real.
    final theLink = link(id: 'link-1');
    final realDocs = await realDocsFor([theLink]);

    final emissions = <List<TrainerLink>>[];
    final sub = repo.watchForAthlete(athleteId).listen(emissions.add);

    snapshots.add(fakeSnapshot(docs: const [], isFromCache: true));
    await Future<void>.delayed(Duration.zero);
    expect(emissions, isEmpty); // todavía nada — la de caché se descartó

    snapshots.add(fakeSnapshot(docs: realDocs, isFromCache: false));
    await Future<void>.delayed(Duration.zero);

    expect(emissions, hasLength(1),
        reason: 'la snapshot vacía de caché no debía haberse emitido antes');
    expect(emissions.single, hasLength(1));
    expect(emissions.single.single.id, theLink.id);
    expect(emissions.single.single.status, TrainerLinkStatus.active);

    await sub.cancel();
  });

  test('una snapshot CON documentos sí se emite aunque venga de caché',
      () async {
    final theLink = link(id: 'link-1');
    final realDocs = await realDocsFor([theLink]);

    final emissions = <List<TrainerLink>>[];
    final sub = repo.watchForAthlete(athleteId).listen(emissions.add);

    snapshots.add(fakeSnapshot(docs: realDocs, isFromCache: true));
    await Future<void>.delayed(Duration.zero);

    expect(emissions, hasLength(1),
        reason: 'el dato ya está en la caché — no hay razón para esperar '
            'al servidor');
    expect(emissions.single.single.id, theLink.id);

    await sub.cancel();
  });

  test('una snapshot vacía del SERVIDOR sí se emite', () async {
    final emissions = <List<TrainerLink>>[];
    final sub = repo.watchForAthlete(athleteId).listen(emissions.add);

    snapshots.add(fakeSnapshot(docs: const [], isFromCache: false));
    await Future<void>.delayed(Duration.zero);

    expect(emissions, hasLength(1),
        reason: 'un alumno sin vínculo tiene que poder ver el gate — el '
            'servidor ya contestó que no hay nada');
    expect(emissions.single, isEmpty);

    await sub.cancel();
  });

  test('el filtro por statuses sigue funcionando', () async {
    final active = link(id: 'active-1');
    final pending = link(id: 'pending-1', status: TrainerLinkStatus.pending);
    final terminated =
        link(id: 'terminated-1', status: TrainerLinkStatus.terminated);
    final realDocs = await realDocsFor([active, pending, terminated]);

    final emissions = <List<TrainerLink>>[];
    final sub = repo.watchForAthlete(athleteId,
        statuses: {TrainerLinkStatus.active}).listen(emissions.add);

    snapshots.add(fakeSnapshot(docs: realDocs, isFromCache: false));
    await Future<void>.delayed(Duration.zero);

    expect(emissions, hasLength(1));
    expect(emissions.single, hasLength(1));
    expect(emissions.single.single.id, active.id);

    await sub.cancel();
  });
}
