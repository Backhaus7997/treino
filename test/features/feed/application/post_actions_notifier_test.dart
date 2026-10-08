/// PR #1217 (P1 de Codex): `docs/legal/retencion-y-borrado.md` decía que
/// borrar una publicación desde su menú borraba "la publicación" — pero
/// `PostRepository.delete` sólo borraba el doc de Firestore. La foto en
/// `postPhotos/{uid}/{postId}.{ext}` sobrevivía con URL de descarga viva y
/// accesible a cualquier usuario autenticado (storage.rules) — mismo failure
/// mode que documenta `functions/src/cascade/storage.ts` para el borrado de
/// cuenta. Este archivo cubre el fix: `PostActionsNotifier.deletePost` ahora
/// borra la foto ANTES del doc, y propaga cualquier falla real de Storage en
/// vez de dejar un borrado parcial silencioso.
library;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/application/post_actions_notifier.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_photo_upload_service.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';

Post _makePost({
  String id = 'p1',
  String authorUid = 'u1',
  String? photoUrl,
}) {
  return Post(
    id: id,
    authorUid: authorUid,
    authorDisplayName: 'Test User',
    authorAvatarUrl: null,
    authorGymId: null,
    text: 'Test post',
    routineTag: null,
    privacy: PostPrivacy.public,
    createdAt: DateTime.utc(2026, 1, 1),
    photoUrl: photoUrl,
  );
}

/// Doble controlable de [PostPhotoUploadService] — mismo patrón que
/// `_FakeChatMediaUploadService` en `chat_media_send_controller_test.dart`.
/// El test decide si `deleteByDownloadUrl` tiene éxito (`true`), devuelve
/// `false` (objeto ya ausente — benigno, mismo contrato que la impl real) o
/// relanza (falla real de Storage).
class _FakePostPhotoUploadService extends PostPhotoUploadService {
  _FakePostPhotoUploadService({this.deleteResult = true, this.deleteError})
      : super.testable();

  final bool deleteResult;
  final Object? deleteError;
  final deletedUrls = <String>[];

  @override
  Future<bool> deleteByDownloadUrl(String url) async {
    deletedUrls.add(url);
    final e = deleteError;
    if (e != null) throw e;
    return deleteResult;
  }
}

void main() {
  late FakeFirebaseFirestore firestore;
  late PostRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = PostRepository(firestore: firestore);
  });

  ProviderContainer makeContainer(PostPhotoUploadService photo) {
    final container = ProviderContainer(overrides: [
      postRepositoryProvider.overrideWithValue(repo),
      postPhotoUploadServiceProvider.overrideWithValue(photo),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('PostActionsNotifier.deletePost — borrado en cascada de la foto', () {
    test('post CON foto: borra el objeto de Storage y el doc de Firestore',
        () async {
      const url = 'https://firebasestorage.googleapis.com/v0/b/x/o/'
          'postPhotos%2Fu1%2Fp1.jpg?alt=media&token=abc';
      final photo = _FakePostPhotoUploadService();
      final container = makeContainer(photo);
      final post = _makePost(id: 'p1', photoUrl: url);
      await repo.create(post);

      await container.read(postActionsProvider).deletePost(post);

      expect(photo.deletedUrls, [url]);
      final snap = await firestore.collection('posts').doc('p1').get();
      expect(snap.exists, isFalse);
    });

    test('post SIN foto: no toca Storage y borra el doc igual', () async {
      final photo = _FakePostPhotoUploadService();
      final container = makeContainer(photo);
      final post = _makePost(id: 'p2'); // photoUrl null

      await repo.create(post);
      await container.read(postActionsProvider).deletePost(post);

      expect(photo.deletedUrls, isEmpty,
          reason: 'sin foto no hay nada que borrar en Storage');
      final snap = await firestore.collection('posts').doc('p2').get();
      expect(snap.exists, isFalse);
    });

    test(
        'la foto ya no existe (object-not-found → false): NO es un fallo, '
        'el post se borra igual', () async {
      const url = 'https://firebasestorage.googleapis.com/v0/b/x/o/'
          'postPhotos%2Fu1%2Fp3.jpg?alt=media';
      final photo = _FakePostPhotoUploadService(deleteResult: false);
      final container = makeContainer(photo);
      final post = _makePost(id: 'p3', photoUrl: url);
      await repo.create(post);

      await container.read(postActionsProvider).deletePost(post);

      expect(photo.deletedUrls, [url]);
      final snap = await firestore.collection('posts').doc('p3').get();
      expect(snap.exists, isFalse,
          reason: 'un post viejo sin foto real no puede quedar imborrable');
    });

    test(
        'Storage falla de verdad (permission-denied): NO se borra el post '
        'y el error se propaga', () async {
      const url = 'https://firebasestorage.googleapis.com/v0/b/x/o/'
          'postPhotos%2Fu1%2Fp4.jpg?alt=media';
      final photo = _FakePostPhotoUploadService(
        deleteError: FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
        ),
      );
      final container = makeContainer(photo);
      final post = _makePost(id: 'p4', photoUrl: url);
      await repo.create(post);

      await expectLater(
        container.read(postActionsProvider).deletePost(post),
        throwsA(isA<FirebaseException>()),
      );

      final snap = await firestore.collection('posts').doc('p4').get();
      expect(snap.exists, isTrue,
          reason: 'un borrado parcial silencioso es el bug — si no pudimos '
              'confirmar que la foto se fue, el post tiene que seguir '
              'existiendo para que el autor pueda reintentar');
    });
  });
}
