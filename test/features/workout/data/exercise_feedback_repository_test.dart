import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/exercise_feedback_repository.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/exercise_feedback_kind.dart';

const _uid = 'athlete-1';
const _sessionId = 'session-1';

ExerciseFeedback _feedback({
  String id = '',
  String exerciseId = 'ex-bench',
  String exerciseName = 'Press banca',
  int slotIndex = 0,
  int? setNumber,
  ExerciseFeedbackKind kind = ExerciseFeedbackKind.comment,
  String? text = 'Molestia en el hombro',
  DateTime? createdAt,
}) {
  return ExerciseFeedback(
    id: id,
    exerciseId: exerciseId,
    exerciseName: exerciseName,
    slotIndex: slotIndex,
    setNumber: setNumber,
    kind: kind,
    text: text,
    createdAt: createdAt ?? DateTime.utc(2026, 8, 11, 15, 30),
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late ExerciseFeedbackRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ExerciseFeedbackRepository(firestore: firestore);
  });

  group('create', () {
    test('writes under users/{uid}/sessions/{sessionId}/exerciseFeedback', () {
      // The path is what makes the existing session_shares grant apply, so it
      // is asserted explicitly rather than inferred from a read-back.
      return repo
          .create(uid: _uid, sessionId: _sessionId, feedback: _feedback())
          .then((created) async {
        final snap = await firestore
            .collection('users')
            .doc(_uid)
            .collection('sessions')
            .doc(_sessionId)
            .collection('exerciseFeedback')
            .doc(created.id)
            .get();
        expect(snap.exists, isTrue);
        expect(snap.data()!['exerciseId'], 'ex-bench');
      });
    });

    test('returns the entry with the generated doc id', () async {
      final created = await repo.create(
        uid: _uid,
        sessionId: _sessionId,
        feedback: _feedback(),
      );
      expect(created.id, isNotEmpty);
    });

    test('rejects an entry with neither text nor photo', () {
      // No empty reports — the rules deny it too, but failing here keeps the
      // round-trip out of the picture.
      expect(
        () => repo.create(
          uid: _uid,
          sessionId: _sessionId,
          feedback: _feedback(text: null),
        ),
        throwsArgumentError,
      );
    });

    test('rejects whitespace-only text', () async {
      await expectLater(
        repo.create(
          uid: _uid,
          sessionId: _sessionId,
          feedback: _feedback(text: '   '),
        ),
        throwsArgumentError,
      );
    });

    test('persists slotIndex and setNumber', () async {
      final created = await repo.create(
        uid: _uid,
        sessionId: _sessionId,
        feedback: _feedback(slotIndex: 3, setNumber: 2),
      );
      final list = await repo.list(uid: _uid, sessionId: _sessionId);
      expect(list.single.id, created.id);
      expect(list.single.slotIndex, 3);
      expect(list.single.setNumber, 2);
    });
  });

  group('list', () {
    test('returns entries oldest first', () async {
      await repo.create(
        uid: _uid,
        sessionId: _sessionId,
        feedback: _feedback(
          text: 'segundo',
          createdAt: DateTime.utc(2026, 8, 11, 16),
        ),
      );
      await repo.create(
        uid: _uid,
        sessionId: _sessionId,
        feedback: _feedback(
          text: 'primero',
          createdAt: DateTime.utc(2026, 8, 11, 15),
        ),
      );

      final list = await repo.list(uid: _uid, sessionId: _sessionId);
      expect(list.map((f) => f.text), ['primero', 'segundo']);
    });

    test('empty session → empty list', () async {
      final list = await repo.list(uid: _uid, sessionId: 'nope');
      expect(list, isEmpty);
    });

    test('does not leak another session\'s feedback', () async {
      await repo.create(
        uid: _uid,
        sessionId: 'other-session',
        feedback: _feedback(),
      );
      final list = await repo.list(uid: _uid, sessionId: _sessionId);
      expect(list, isEmpty);
    });

    test('skips a malformed doc instead of throwing', () async {
      // The trainer surfaces read other users' docs; one bad entry must not
      // blank out the whole session view.
      await firestore
          .collection('users')
          .doc(_uid)
          .collection('sessions')
          .doc(_sessionId)
          .collection('exerciseFeedback')
          .add({'garbage': true});
      await repo.create(
        uid: _uid,
        sessionId: _sessionId,
        feedback: _feedback(),
      );

      final list = await repo.list(uid: _uid, sessionId: _sessionId);
      expect(list, hasLength(1));
    });
  });

  group('delete', () {
    test('removes the entry', () async {
      final created = await repo.create(
        uid: _uid,
        sessionId: _sessionId,
        feedback: _feedback(),
      );
      await repo.delete(
        uid: _uid,
        sessionId: _sessionId,
        feedbackId: created.id,
      );
      expect(await repo.list(uid: _uid, sessionId: _sessionId), isEmpty);
    });
  });

  group('watch', () {
    test('emits the current entries', () async {
      await repo.create(
        uid: _uid,
        sessionId: _sessionId,
        feedback: _feedback(text: 'hola'),
      );
      final first = await repo.watch(uid: _uid, sessionId: _sessionId).first;
      expect(first.single.text, 'hola');
    });
  });
}
