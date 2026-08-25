import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_feedback_photo_upload_service.dart';

void main() {
  late SessionFeedbackPhotoUploadService svc;

  setUp(() {
    // .testable() saltea la init de Firebase — los helpers de abajo son puros.
    svc = SessionFeedbackPhotoUploadService.testable();
  });

  group('buildPath', () {
    test('es el espejo EXACTO del match de storage.rules', () {
      // `match /sessionFeedback/{userId}/{sessionId}/{fileName}` pide TRES
      // wildcards. Un path con más o menos niveles cae en el catch-all y se
      // deniega — este test es el que avisa si alguien cambia el layout.
      expect(
        svc.buildPath(
          uid: 'uid-1',
          sessionId: 'session-1',
          feedbackId: 'fb-1',
          ext: 'jpg',
        ),
        equals('sessionFeedback/uid-1/session-1/fb-1.jpg'),
      );
    });

    test('tiene exactamente cuatro segmentos', () {
      final path = svc.buildPath(
        uid: 'uid-1',
        sessionId: 'session-1',
        feedbackId: 'fb-1',
        ext: 'heic',
      );
      expect(path.split('/'), hasLength(4));
      expect(path.split('/').first, equals('sessionFeedback'));
    });
  });

  group('contentTypeForExt', () {
    test('mapea las extensiones de imagen soportadas', () {
      expect(svc.contentTypeForExt('jpg'), equals('image/jpeg'));
      expect(svc.contentTypeForExt('jpeg'), equals('image/jpeg'));
      expect(svc.contentTypeForExt('png'), equals('image/png'));
      expect(svc.contentTypeForExt('heic'), equals('image/heic'));
      expect(svc.contentTypeForExt('webp'), equals('image/webp'));
    });

    test('lo desconocido cae a octet-stream, que upload rechaza', () {
      // storage.rules exige `image/.*`; el fallback garantiza que un archivo
      // raro se frene acá y no con un permission-denied opaco.
      expect(svc.contentTypeForExt('mp4'), equals('application/octet-stream'));
      expect(svc.contentTypeForExt('pdf'), equals('application/octet-stream'));
    });
  });

  group('extensionFor', () {
    test('devuelve la extensión lowercased sin el punto', () {
      expect(svc.extensionFor('/tmp/foto.JPG'), equals('jpg'));
      expect(svc.extensionFor('/tmp/a/b/foto.HEIC'), equals('heic'));
    });

    test('cae a jpg cuando no hay extensión', () {
      expect(svc.extensionFor('/tmp/foto'), equals('jpg'));
      expect(svc.extensionFor('/tmp/foto.'), equals('jpg'));
    });
  });

  group('guardSize', () {
    test('acepta justo por debajo del cap de 15 MB', () {
      expect(() => svc.guardSize(sizeBytes: 15 * 1024 * 1024), returnsNormally);
    });

    test('rechaza por encima del cap', () {
      expect(
        () => svc.guardSize(sizeBytes: 15 * 1024 * 1024 + 1),
        throwsArgumentError,
      );
    });
  });
}
