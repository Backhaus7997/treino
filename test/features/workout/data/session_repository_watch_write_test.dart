import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/set_log.dart';

/// El camino de escritura del RELOJ (`addSetLogFromWatch`).
///
/// La decisión de dónde escribir está bajo el contrato compartido de
/// `conformance/set_log_write_target.json` y se prueba allá. Acá se prueba lo
/// que ese contrato NO puede ver: que el repositorio efectivamente escriba en
/// el documento que la regla eligió, y sobre todo que **no destruya** el que ya
/// estaba.
void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;

  const uid = 'atleta-1';
  const sessionId = 'sesion-1';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
  });

  SetLog build({
    required int setNumber,
    String exerciseId = 'peso-muerto',
    double weightKg = 100,
  }) =>
      SetLog(
        id: '',
        exerciseId: exerciseId,
        exerciseName: 'Peso muerto',
        setNumber: setNumber,
        reps: 5,
        weightKg: weightKg,
        completedAt: DateTime.utc(2026, 8, 18, 10),
      );

  Future<Map<String, Map<String, dynamic>>> setLogsById() async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .get();
    return {for (final d in snap.docs) d.id: d.data()};
  }

  Future<void> seed(String docId, Map<String, dynamic> extra) async {
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .doc(docId)
        .set({
      'id': docId,
      'exerciseId': 'peso-muerto',
      'exerciseName': 'Peso muerto',
      'reps': 5,
      'weightKg': 100.0,
      'completedAt': DateTime.utc(2026, 8, 18, 9),
      ...extra,
    });
  }

  test('con el historial vacío escribe en la ruta determinística', () async {
    final written = await repo.addSetLogFromWatch(
      uid: uid,
      sessionId: sessionId,
      setLog: build(setNumber: 1),
    );

    expect(written?.id, 'peso-muerto__1');
    // El id tiene que quedar también en el CAMPO, no sólo en el path: el
    // teléfono lo usa para editar y borrar.
    final docs = await setLogsById();
    expect(docs.keys, ['peso-muerto__1']);
    expect(docs['peso-muerto__1']!['id'], 'peso-muerto__1');
  });

  test('si el teléfono ya la escribió, no crea un segundo documento', () async {
    // Con id AUTOGENERADO, que es como escribe el teléfono. Por id no
    // matchearía nunca: la búsqueda tiene que ser por identidad lógica.
    await seed('EeFxyim8WMzP8qQvpGxj', {'setNumber': 1});

    final written = await repo.addSetLogFromWatch(
      uid: uid,
      sessionId: sessionId,
      setLog: build(setNumber: 1, weightKg: 999),
    );

    expect(written, isNull, reason: 'no hay nada que escribir');
    final docs = await setLogsById();
    expect(docs.keys, ['EeFxyim8WMzP8qQvpGxj']);
    // Y no se pisó: 999 era el valor del reloj, y el del teléfono manda porque
    // es la superficie donde el atleta puede corregir.
    expect(docs.values.single['weightKg'], 100.0);
  });

  test('NO pisa una serie que quedó en la ruta tras una renumeración',
      () async {
    // El caso caro. El teléfono borró una serie y al renumerar conservó el id
    // del documento: `peso-muerto__3` contiene la serie 2. Escribir ahí la
    // perdería, y perder un dato que el atleta cargó es peor que un duplicado.
    await seed('peso-muerto__3', {'setNumber': 2, 'weightKg': 120.0});

    final written = await repo.addSetLogFromWatch(
      uid: uid,
      sessionId: sessionId,
      setLog: build(setNumber: 3, weightKg: 140),
    );

    expect(written?.id, 'peso-muerto__3__alt');

    final docs = await setLogsById();
    expect(docs.keys.toSet(), {'peso-muerto__3', 'peso-muerto__3__alt'});
    // La serie 2 sigue intacta.
    expect(docs['peso-muerto__3']!['setNumber'], 2);
    expect(docs['peso-muerto__3']!['weightKg'], 120.0);
    expect(docs['peso-muerto__3__alt']!['setNumber'], 3);
  });

  test('marcar dos veces la misma serie no acumula documentos', () async {
    await repo.addSetLogFromWatch(
      uid: uid,
      sessionId: sessionId,
      setLog: build(setNumber: 1),
    );
    final segunda = await repo.addSetLogFromWatch(
      uid: uid,
      sessionId: sessionId,
      setLog: build(setNumber: 1),
    );

    expect(segunda, isNull);
    expect((await setLogsById()).length, 1);
  });

  test('un documento sin los campos de identidad no rompe la decisión',
      () async {
    // Un doc corrupto o a medio escribir no puede impedir que el reloj marque.
    await seed('basura', {'setNumber': null, 'exerciseId': null});

    final written = await repo.addSetLogFromWatch(
      uid: uid,
      sessionId: sessionId,
      setLog: build(setNumber: 1),
    );

    expect(written?.id, 'peso-muerto__1');
  });
}
