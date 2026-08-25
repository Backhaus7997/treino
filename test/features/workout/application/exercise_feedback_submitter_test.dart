import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/application/exercise_feedback_submitter.dart';
import 'package:treino/features/workout/data/exercise_feedback_repository.dart';
import 'package:treino/features/workout/data/session_feedback_photo_upload_service.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';

class _MockUploader extends Mock implements SessionFeedbackPhotoUploadService {}

/// Repositorio que explota en `add`, para el camino de rollback.
class _ExplodingRepository extends ExerciseFeedbackRepository {
  _ExplodingRepository(FirebaseFirestore firestore)
      : super(firestore: firestore);

  @override
  Future<ExerciseFeedback> add({
    required String uid,
    required String sessionId,
    required ExerciseFeedback feedback,
  }) async {
    throw StateError('firestore caido');
  }
}

void main() {
  late FakeFirebaseFirestore firestore;
  late ExerciseFeedbackRepository repo;
  late _MockUploader uploader;
  late ExerciseFeedbackSubmitter submitter;

  const uid = 'athlete-sub';
  const sessionId = 'session-sub';
  const localPath = '/tmp/foto.jpg';
  const photoPath = 'sessionFeedback/$uid/$sessionId/generated.jpg';
  const photoUrl =
      'https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = ExerciseFeedbackRepository(firestore: firestore);
    uploader = _MockUploader();
    submitter = ExerciseFeedbackSubmitter(
      repository: repo,
      photoUploader: uploader,
    );

    when(() => uploader.extensionFor(any())).thenReturn('jpg');
    when(() => uploader.buildPath(
          uid: any(named: 'uid'),
          sessionId: any(named: 'sessionId'),
          feedbackId: any(named: 'feedbackId'),
          ext: any(named: 'ext'),
        )).thenReturn(photoPath);
    when(() => uploader.upload(
          any(),
          sessionId: any(named: 'sessionId'),
          feedbackId: any(named: 'feedbackId'),
        )).thenAnswer((_) async => photoUrl);
    when(() => uploader.deleteByPath(any())).thenAnswer((_) async => true);
  });

  Future<ExerciseFeedback> submit({
    String? text = 'Me tira el hombro',
    String? localPhotoPath,
    ExerciseFeedbackKind kind = ExerciseFeedbackKind.discomfort,
    int? setNumber = 3,
    ExerciseFeedbackSubmitter? withSubmitter,
  }) {
    return (withSubmitter ?? submitter).submit(
      uid: uid,
      sessionId: sessionId,
      exerciseId: 'bench-press',
      exerciseName: 'Press de banca',
      kind: kind,
      setNumber: setNumber,
      text: text,
      localPhotoPath: localPhotoPath,
      now: DateTime.utc(2026, 8, 24, 18, 30),
    );
  }

  test('sin texto ni foto no gasta un upload — falla antes', () async {
    await expectLater(submit(text: '  '), throwsArgumentError);
    verifyNever(() => uploader.upload(any(),
        sessionId: any(named: 'sessionId'),
        feedbackId: any(named: 'feedbackId')));
  });

  test('sólo texto: no toca Storage y persiste el reporte', () async {
    final saved = await submit();

    verifyNever(() => uploader.upload(any(),
        sessionId: any(named: 'sessionId'),
        feedbackId: any(named: 'feedbackId')));
    expect(saved.photoUrl, isNull);
    expect(saved.photoPath, isNull);
    expect(saved.kind, equals(ExerciseFeedbackKind.discomfort));
    expect(saved.setNumber, equals(3));

    final list = await repo.list(uid: uid, sessionId: sessionId);
    expect(list.single.text, equals('Me tira el hombro'));
  });

  test('el texto se guarda trimmeado', () async {
    final saved = await submit(text: '   me duele   ');
    expect(saved.text, equals('me duele'));
  });

  test('con foto: sube PRIMERO y guarda url + path', () async {
    final saved = await submit(text: null, localPhotoPath: localPath);

    // El id se aloca antes del upload para que el objeto referencie al
    // documento real desde el primer byte.
    final captured = verify(() => uploader.upload(
          localPath,
          sessionId: sessionId,
          feedbackId: captureAny(named: 'feedbackId'),
        )).captured.single as String;
    expect(captured, isNotEmpty);
    expect(saved.id, equals(captured));

    expect(saved.photoUrl, equals(photoUrl));
    expect(saved.photoPath, equals(photoPath));
  });

  test('si el write falla DESPUÉS del upload, borra la foto huérfana',
      () async {
    // Sin este rollback quedaría dato de salud en el bucket que nadie
    // referencia, con su URL de descarga viva.
    final exploding = ExerciseFeedbackSubmitter(
      repository: _ExplodingRepository(firestore),
      photoUploader: uploader,
    );

    await expectLater(
      submit(localPhotoPath: localPath, withSubmitter: exploding),
      throwsA(isA<StateError>()),
    );

    verify(() => uploader.deleteByPath(photoPath)).called(1);
  });

  test('si el write falla SIN foto, no intenta borrar nada', () async {
    final exploding = ExerciseFeedbackSubmitter(
      repository: _ExplodingRepository(firestore),
      photoUploader: uploader,
    );

    await expectLater(
      submit(withSubmitter: exploding),
      throwsA(isA<StateError>()),
    );

    verifyNever(() => uploader.deleteByPath(any()));
  });
}
