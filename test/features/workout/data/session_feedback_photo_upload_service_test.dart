import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/data/session_feedback_photo_upload_service.dart';

void main() {
  // `.testable()` skips Firebase init so the pure helpers run without platform
  // channels — same pattern as PostPhotoUploadService's tests.
  final service = SessionFeedbackPhotoUploadService.testable();

  group('buildPath', () {
    test('is sessionFeedback/{uid}/{sessionId}/{feedbackId}.{ext}', () {
      expect(
        service.buildPath(
          uid: 'u1',
          sessionId: 's1',
          feedbackId: 'fb1',
          ext: 'jpg',
        ),
        'sessionFeedback/u1/s1/fb1.jpg',
      );
    });

    test('puts the uid first so the delete cascade can wipe by prefix', () {
      // Regression guard: chatMedia/{chatId}/{uid}/… forced the cascade to walk
      // every chat. This path must never repeat that mistake.
      final path = service.buildPath(
        uid: 'u1',
        sessionId: 's1',
        feedbackId: 'fb1',
        ext: 'jpg',
      );
      expect(path.startsWith('sessionFeedback/u1/'), isTrue);
    });
  });

  group('contentTypeForExt', () {
    test('maps supported image extensions', () {
      expect(service.contentTypeForExt('jpg'), 'image/jpeg');
      expect(service.contentTypeForExt('jpeg'), 'image/jpeg');
      expect(service.contentTypeForExt('png'), 'image/png');
      expect(service.contentTypeForExt('heic'), 'image/heic');
      expect(service.contentTypeForExt('webp'), 'image/webp');
    });

    test('unknown extension falls to octet-stream, which upload rejects', () {
      expect(service.contentTypeForExt('pdf'), 'application/octet-stream');
      expect(service.contentTypeForExt('mp4'), 'application/octet-stream');
    });
  });

  group('extensionFor', () {
    test('returns the lowercased extension without the dot', () {
      expect(service.extensionFor('/tmp/photo.JPG'), 'jpg');
      expect(service.extensionFor('/tmp/a/b/c.png'), 'png');
    });

    test('falls back to jpg when there is no extension', () {
      // image_picker emits JPEG in that case.
      expect(service.extensionFor('/tmp/photo'), 'jpg');
      expect(service.extensionFor('/tmp/photo.'), 'jpg');
    });
  });

  group('guardSize', () {
    test('accepts a file under 15 MB', () {
      expect(() => service.guardSize(sizeBytes: 14 * 1024 * 1024),
          returnsNormally);
    });

    test('rejects a file over 15 MB', () {
      // Mirrors the server-side bound in storage.rules, so the athlete gets an
      // actionable error instead of an opaque permission-denied.
      expect(
        () => service.guardSize(sizeBytes: 16 * 1024 * 1024),
        throwsArgumentError,
      );
    });

    test('accepts exactly 15 MB minus a byte', () {
      expect(
        () => service.guardSize(sizeBytes: 15 * 1024 * 1024 - 1),
        returnsNormally,
      );
    });
  });

  group('SessionFeedbackPhoto', () {
    test('pairs the download URL with the object path', () {
      // Both are persisted: the URL to render, the path to delete. Keeping them
      // together at the type level is what stops one without the other.
      const photo = SessionFeedbackPhoto(
        downloadUrl: 'https://example.test/p.jpg',
        path: 'sessionFeedback/u1/s1/fb1.jpg',
      );
      expect(photo.downloadUrl, isNotEmpty);
      expect(photo.path, isNotEmpty);
    });
  });
}
