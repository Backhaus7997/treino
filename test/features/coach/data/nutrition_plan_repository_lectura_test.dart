// #1581 — el repo del plan nutricional no confunde «no lo pude leer» con
// «no existe».
//
// Las dos formas en que lo confundía terminaban igual: los editores (web y
// mobile) arrancaban de los presets con GUARDAR habilitado, y un guardado
// pisaba el plan real.
//
// 1. Caché fría: la primera snapshot de un doc llega con `exists == false` e
//    `isFromCache == true` ANTES de que conteste el servidor. Es «todavía no
//    sé». Mismo arreglo que `UserRepository.watch`:
//    `snapshotsSinCacheVacia()` (`lib/core/utils/firestore_snapshots.dart`).
// 2. Doc que no parsea: `_fromDoc` atrapaba el error y devolvía `null`.
//
// `fake_cloud_firestore` no modela `isFromCache`, así que se mockea la cadena
// `collection → doc → snapshots`, igual que
// `user_repository_watch_cache_fria_test.dart`. Dos controllers —con y sin
// `includeMetadataChanges`— prueban QUÉ listener abre el repo, no sólo qué
// emite.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/data/nutrition_plan_repository.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockCollectionReference extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockDocumentReference extends Mock
    implements DocumentReference<Map<String, Object?>> {}

class _MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, Object?>> {}

class _MockSnapshotMetadata extends Mock implements SnapshotMetadata {}

const _trainerId = 't1';
const _athleteId = 'a1';
const _docId = '${_trainerId}_$_athleteId';

final _plan = NutritionPlan(
  id: _docId,
  trainerId: _trainerId,
  athleteId: _athleteId,
  title: 'Plan de fuerza',
  meals: const [Meal(id: 'meal-1', name: 'Desayuno', groups: [])],
  updatedAt: DateTime.utc(2026, 10, 16),
);

DocumentSnapshot<Map<String, Object?>> _snap({
  Map<String, Object?>? data,
  required bool isFromCache,
}) {
  final metadata = _MockSnapshotMetadata();
  when(() => metadata.isFromCache).thenReturn(isFromCache);
  final snap = _MockDocumentSnapshot();
  when(() => snap.id).thenReturn(_docId);
  when(() => snap.exists).thenReturn(data != null);
  when(() => snap.data()).thenReturn(data);
  when(() => snap.metadata).thenReturn(metadata);
  return snap;
}

void main() {
  late _MockDocumentReference doc;
  late StreamController<DocumentSnapshot<Map<String, Object?>>> conMetadata;
  late StreamController<DocumentSnapshot<Map<String, Object?>>> sinMetadata;
  late NutritionPlanRepository repo;

  setUp(() {
    final firestore = _MockFirebaseFirestore();
    final plans = _MockCollectionReference();
    doc = _MockDocumentReference();
    conMetadata = StreamController<DocumentSnapshot<Map<String, Object?>>>();
    sinMetadata = StreamController<DocumentSnapshot<Map<String, Object?>>>();

    when(() => firestore.collection('nutrition_plans')).thenReturn(plans);
    when(() => plans.doc(_docId)).thenReturn(doc);
    when(() => doc.snapshots(includeMetadataChanges: true))
        .thenAnswer((_) => conMetadata.stream);
    when(() => doc.snapshots()).thenAnswer((_) => sinMetadata.stream);

    repo = NutritionPlanRepository(firestore: firestore);
  });

  // Sin `await`: un controller con eventos en buffer y sin oyente nunca
  // completa su `close()`.
  tearDown(() {
    unawaited(conMetadata.close());
    unawaited(sinMetadata.close());
  });

  /// Manda [snaps] por los dos listeners, en orden, y junta lo que emite el
  /// repo. Con la opción el SDK además entrega los cambios de sólo metadata;
  /// sin ella, nada de eso llega — por eso [sinOpcion] puede ser más corta.
  Future<({List<NutritionPlan?> datos, List<Object> errores})> correr(
    List<DocumentSnapshot<Map<String, Object?>>> snaps, {
    List<DocumentSnapshot<Map<String, Object?>>>? sinOpcion,
  }) async {
    final datos = <NutritionPlan?>[];
    final errores = <Object>[];
    final sub = repo
        .watch(_trainerId, _athleteId)
        .listen(datos.add, onError: errores.add);
    for (final s in sinOpcion ?? snaps) {
      sinMetadata.add(s);
    }
    for (final s in snaps) {
      conMetadata.add(s);
    }
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return (datos: datos, errores: errores);
  }

  test('offline con la caché fría NO emite «no hay plan»', () async {
    final r = await correr([_snap(isFromCache: true)]);

    expect(r.datos, isEmpty,
        reason: 'la snapshot vacía de la caché es «todavía no sé»: emitir '
            'null arranca los editores de los presets con GUARDAR habilitado');
    expect(r.errores, isEmpty);
  });

  test('cuando el servidor confirma que no existe, emite null (no se cuelga)',
      () async {
    final cache = _snap(isFromCache: true);
    final servidor = _snap(isFromCache: false);
    // El servidor confirma el MISMO «no existe»: sólo cambia la metadata, y
    // sin `includeMetadataChanges` esa confirmación no llega nunca.
    final r = await correr([cache, servidor], sinOpcion: [cache]);

    expect(r.datos, [null]);
  });

  test('un plan que viene de la caché sí se emite', () async {
    final r = await correr([_snap(data: _plan.toJson(), isFromCache: true)]);

    expect(r.datos, [_plan]);
  });

  test('un cambio de sólo metadata no vuelve a emitir el mismo plan', () async {
    final r = await correr([
      _snap(data: _plan.toJson(), isFromCache: true),
      _snap(data: _plan.toJson(), isFromCache: false),
    ]);

    expect(r.datos, [_plan]);
  });

  test('un doc que no parsea emite NutritionPlanIlegible, no null', () async {
    final r = await correr([
      _snap(data: {'trainerId': _trainerId}, isFromCache: false),
    ]);

    expect(r.datos, isEmpty,
        reason: 'null es «no hay plan»: el PF guardaría encima de uno que '
            'existe y no se pudo leer');
    expect(r.errores, [isA<NutritionPlanIlegible>()]);
    expect((r.errores.single as NutritionPlanIlegible).docId, _docId);
  });

  test('get() tampoco convierte un doc ilegible en «no hay plan»', () async {
    final corrupto = _snap(data: {'meals': 'no'}, isFromCache: false);
    when(() => doc.get()).thenAnswer((_) async => corrupto);

    await expectLater(
      repo.get(_trainerId, _athleteId),
      throwsA(isA<NutritionPlanIlegible>()),
    );
  });
}
