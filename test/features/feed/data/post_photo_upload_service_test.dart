// Tests de los helpers puros de PostPhotoUploadService (share-composer PR1).
// El ctor .testable() saltea Firebase, así que esto corre sin platform
// channels — mismo patrón que chat_media_upload_service_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/data/post_photo_upload_service.dart';

void main() {
  final service = PostPhotoUploadService.testable();

  group('contentTypeForExt', () {
    test('mapea extensiones de imagen soportadas', () {
      expect(service.contentTypeForExt('jpg'), 'image/jpeg');
      expect(service.contentTypeForExt('jpeg'), 'image/jpeg');
      expect(service.contentTypeForExt('png'), 'image/png');
      expect(service.contentTypeForExt('heic'), 'image/heic');
      expect(service.contentTypeForExt('webp'), 'image/webp');
    });

    test('extensiones no-imagen caen a octet-stream (upload las rechaza)', () {
      expect(service.contentTypeForExt('mp4'), 'application/octet-stream');
      expect(service.contentTypeForExt('pdf'), 'application/octet-stream');
      expect(service.contentTypeForExt(''), 'application/octet-stream');
    });
  });

  group('extensionFor', () {
    test('extrae la extensión lowercased sin punto', () {
      expect(service.extensionFor('/tmp/foto.JPG'), 'jpg');
      expect(service.extensionFor('a/b/c.heic'), 'heic');
    });

    test('sin extensión cae a jpg', () {
      expect(service.extensionFor('/tmp/foto'), 'jpg');
      expect(service.extensionFor('/tmp/foto.'), 'jpg');
    });
  });

  group('guardSize', () {
    test('acepta hasta 15 MB', () {
      service.guardSize(sizeBytes: 15 * 1024 * 1024);
    });

    test('rechaza más de 15 MB', () {
      expect(
        () => service.guardSize(sizeBytes: 15 * 1024 * 1024 + 1),
        throwsArgumentError,
      );
    });
  });

  group('buildPath', () {
    test('espeja el match postPhotos/{uid}/{postId}.{ext} de storage.rules',
        () {
      expect(
        service.buildPath(uid: 'u1', postId: 'p1', ext: 'jpg'),
        'postPhotos/u1/p1.jpg',
      );
    });
  });

  group('extractStoragePath', () {
    test('extrae el object path de una download URL de Firebase', () {
      const url =
          'https://firebasestorage.googleapis.com/v0/b/treino-dev.appspot.com/'
          'o/postPhotos%2Fu1%2Fp1.jpg?alt=media&token=abc';
      expect(service.extractStoragePath(url), 'postPhotos/u1/p1.jpg');
    });

    test('devuelve null para URLs ajenas a Firebase Storage', () {
      expect(service.extractStoragePath('https://example.com/x.jpg'), isNull);
      expect(service.extractStoragePath('no-es-una-url'), isNull);
    });
  });
}
