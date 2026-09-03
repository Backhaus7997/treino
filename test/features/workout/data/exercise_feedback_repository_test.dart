import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/exercise_feedback_repository.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ExerciseFeedbackRepository repo;

  const uid = 'athlete-fb-001';
  const sessionId = 'session-fb-001';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ExerciseFeedbackRepository(firestore: firestore);
  });

  ExerciseFeedback build({
    required String id,
    ExerciseFeedbackKind kind = ExerciseFeedbackKind.comment,
    String? text = 'Algo para el PF',
    String? photoUrl,
    String? photoPath,
    int? setNumber = 3,
    String exerciseId = 'bench-press',
    DateTime? createdAt,
  }) {
    return ExerciseFeedback(
      id: id,
      exerciseId: exerciseId,
      exerciseName: 'Press de banca',
      setNumber: setNumber,
      kind: kind,
      text: text,
      photoUrl: photoUrl,
      photoPath: photoPath,
      createdAt: createdAt ?? DateTime.utc(2026, 8, 24, 18, 30, 0),
    );
  }

  Future<Map<String, Object?>?> rawDoc(String id) async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('exerciseFeedback')
        .doc(id)
        .get();
    return snap.data();
  }

  // ─── add ──────────────────────────────────────────────────────────────────

  test('add escribe bajo users/{uid}/sessions/{sid}/exerciseFeedback/{id}',
      () async {
    await repo.add(uid: uid, sessionId: sessionId, feedback: build(id: 'fb-1'));

    // El path exacto importa: es el que pinean firestore.rules y el paso de
    // cascade. Si se moviera, las reglas dejarían de cubrirlo en silencio.
    final data = await rawDoc('fb-1');
    expect(data, isNotNull);
    expect(data!['exerciseId'], equals('bench-press'));
    expect(data['kind'], equals('comment'));
    expect(data['setNumber'], equals(3));
  });

  test('add rechaza un reporte sin texto ni foto, antes de tocar Firestore',
      () async {
    // Espejo client-side de la regla de negocio del servidor: sin esto el
    // usuario ve un permission-denied opaco en vez de un mensaje útil.
    expect(
      () => repo.add(
        uid: uid,
        sessionId: sessionId,
        feedback: build(id: 'fb-vacio', text: null),
      ),
      throwsArgumentError,
    );

    expect(await rawDoc('fb-vacio'), isNull);
  });

  test('add acepta el reporte que sólo trae foto', () async {
    await repo.add(
      uid: uid,
      sessionId: sessionId,
      feedback: build(
        id: 'fb-foto',
        text: null,
        photoUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media',
        photoPath: 'sessionFeedback/$uid/$sessionId/fb-foto.jpg',
      ),
    );

    final data = await rawDoc('fb-foto');
    expect(data!['photoPath'],
        equals('sessionFeedback/$uid/$sessionId/fb-foto.jpg'));
  });

  test('newFeedbackId devuelve ids distintos y no vacíos', () {
    // Se aloca ANTES de subir la foto para que el objeto de Storage apunte al
    // documento real desde el primer byte.
    final a = repo.newFeedbackId(uid, sessionId);
    final b = repo.newFeedbackId(uid, sessionId);
    expect(a, isNotEmpty);
    expect(a, isNot(equals(b)));
  });

  // ─── list ─────────────────────────────────────────────────────────────────

  test('list devuelve los reportes del más viejo al más nuevo', () async {
    await repo.add(
      uid: uid,
      sessionId: sessionId,
      feedback: build(id: 'fb-b', createdAt: DateTime.utc(2026, 8, 24, 18, 40)),
    );
    await repo.add(
      uid: uid,
      sessionId: sessionId,
      feedback: build(id: 'fb-a', createdAt: DateTime.utc(2026, 8, 24, 18, 30)),
    );

    final list = await repo.list(uid: uid, sessionId: sessionId);
    expect(list.map((f) => f.id).toList(), equals(['fb-a', 'fb-b']));
  });

  test('list devuelve [] sin tocar Firestore si falta una clave', () async {
    expect(await repo.list(uid: '', sessionId: sessionId), isEmpty);
    expect(await repo.list(uid: uid, sessionId: ''), isEmpty);
  });

  test('list toma el id del PATH, no del cuerpo', () async {
    // Si alguna vez no coincidieran, un delete por el id del cuerpo apuntaría
    // a un documento que no existe.
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('exerciseFeedback')
        .doc('id-del-path')
        .set({
      ...build(id: 'id-mentiroso-del-cuerpo').toJson(),
      'id': 'id-mentiroso-del-cuerpo',
    });

    final list = await repo.list(uid: uid, sessionId: sessionId);
    expect(list.single.id, equals('id-del-path'));
  });

  test('un reporte no parseable no se lleva puestos a los demás', () async {
    // Del lado del PF esto significaría que una molestia reportada no se ve
    // porque OTRA está mal formada.
    await repo.add(uid: uid, sessionId: sessionId, feedback: build(id: 'ok'));
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('exerciseFeedback')
        .doc('roto')
        .set({'createdAt': DateTime.utc(2026, 8, 24, 19), 'kind': 'comment'});

    final list = await repo.list(uid: uid, sessionId: sessionId);
    expect(list.map((f) => f.id).toList(), equals(['ok']));
  });

  // ─── delete ───────────────────────────────────────────────────────────────

  test('delete borra el documento', () async {
    await repo.add(uid: uid, sessionId: sessionId, feedback: build(id: 'fb-1'));
    await repo.delete(uid: uid, sessionId: sessionId, feedbackId: 'fb-1');

    expect(await rawDoc('fb-1'), isNull);
  });

  // ─── watch ────────────────────────────────────────────────────────────────

  test('watch emite la lista viva de la sesión', () async {
    final stream = repo.watch(uid: uid, sessionId: sessionId);
    final first = stream.firstWhere((l) => l.isNotEmpty);

    await repo.add(uid: uid, sessionId: sessionId, feedback: build(id: 'fb-1'));

    expect((await first).single.id, equals('fb-1'));
  });

  test('watch devuelve un stream vacío si falta una clave', () async {
    expect(await repo.watch(uid: '', sessionId: sessionId).first, isEmpty);
  });
}
