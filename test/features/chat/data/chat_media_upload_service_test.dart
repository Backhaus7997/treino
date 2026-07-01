import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/data/chat_media_upload_service.dart';
import 'package:treino/features/chat/domain/media_type.dart';

/// Tests for the pure/testable helpers exposed by [ChatMediaUploadService].
///
/// The upload() and deleteByDownloadUrl() methods require live Firebase SDKs;
/// they are covered by integration/smoke tests, not unit tests.
/// REQ-CHATMEDIA-007.
void main() {
  late ChatMediaUploadService service;

  setUp(() {
    service = ChatMediaUploadServiceMobile.testable();
  });

  // ─── Extension → content-type mapping ───────────────────────────────────

  group('contentTypeForExt — image formats', () {
    test('jpg → image/jpeg', () {
      expect(service.contentTypeForExt('jpg'), 'image/jpeg');
    });

    test('jpeg → image/jpeg', () {
      expect(service.contentTypeForExt('jpeg'), 'image/jpeg');
    });

    test('png → image/png', () {
      expect(service.contentTypeForExt('png'), 'image/png');
    });

    test('heic → image/heic', () {
      expect(service.contentTypeForExt('heic'), 'image/heic');
    });

    test('webp → image/webp', () {
      expect(service.contentTypeForExt('webp'), 'image/webp');
    });
  });

  group('contentTypeForExt — video formats', () {
    test('mp4 → video/mp4', () {
      expect(service.contentTypeForExt('mp4'), 'video/mp4');
    });

    test('mov → video/quicktime', () {
      expect(service.contentTypeForExt('mov'), 'video/quicktime');
    });

    test('m4v → video/x-m4v', () {
      expect(service.contentTypeForExt('m4v'), 'video/x-m4v');
    });
  });

  group('contentTypeForExt — unknown extension', () {
    test('unknown ext falls back to application/octet-stream', () {
      expect(service.contentTypeForExt('xyz'), 'application/octet-stream');
    });

    test('empty string falls back to application/octet-stream', () {
      expect(service.contentTypeForExt(''), 'application/octet-stream');
    });
  });

  // ─── Extension extraction ────────────────────────────────────────────────

  group('extensionFor', () {
    test('extracts lowercase extension from path', () {
      expect(service.extensionFor('/tmp/photo.jpg'), 'jpg');
    });

    test('lowercases extension', () {
      expect(service.extensionFor('/tmp/PHOTO.JPG'), 'jpg');
    });

    test('returns empty string when no extension dot', () {
      expect(service.extensionFor('/tmp/photofile'), '');
    });

    test('handles path with multiple dots — last segment wins', () {
      expect(service.extensionFor('/tmp/my.photo.backup.jpg'), 'jpg');
    });
  });

  // ─── Size guard ──────────────────────────────────────────────────────────

  group('guardSize — image limits (15 MB)', () {
    test('image exactly at 15 MB does not throw', () {
      const fifteenMb = 15 * 1024 * 1024;
      expect(
        () =>
            service.guardSize(sizeBytes: fifteenMb, mediaType: MediaType.image),
        returnsNormally,
      );
    });

    test('image over 15 MB throws ArgumentError before upload', () {
      const fifteenMbPlus = 15 * 1024 * 1024 + 1;
      expect(
        () => service.guardSize(
            sizeBytes: fifteenMbPlus, mediaType: MediaType.image),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('guardSize — video limits (100 MB)', () {
    test('video exactly at 100 MB does not throw', () {
      const hundredMb = 100 * 1024 * 1024;
      expect(
        () =>
            service.guardSize(sizeBytes: hundredMb, mediaType: MediaType.video),
        returnsNormally,
      );
    });

    test('video over 100 MB throws ArgumentError before upload', () {
      const hundredMbPlus = 100 * 1024 * 1024 + 1;
      expect(
        () => service.guardSize(
            sizeBytes: hundredMbPlus, mediaType: MediaType.video),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ─── Path shape ──────────────────────────────────────────────────────────

  group('buildPath — chatMedia/{chatId}/{uid}/{ts}.{ext}', () {
    test('builds correct path', () {
      final path = service.buildPath(
        chatId: 'chat-abc',
        uid: 'user-xyz',
        ext: 'jpg',
        timestamp: 'ts123',
      );
      expect(path, 'chatMedia/chat-abc/user-xyz/ts123.jpg');
    });

    test('works for video extension', () {
      final path = service.buildPath(
        chatId: 'chat-1',
        uid: 'uid-1',
        ext: 'mp4',
        timestamp: 'abc',
      );
      expect(path, 'chatMedia/chat-1/uid-1/abc.mp4');
    });
  });
}
