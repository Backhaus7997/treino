// Tests for the pure helpers inherited by ChatMediaUploadServiceWeb.
//
// upload() and deleteByDownloadUrl() require live Firebase SDKs + a real
// browser XFile (blob URL) — those paths are covered by smoke, not unit
// tests. Here we assert the web impl inherits the same pure helpers as
// mobile so a future refactor cannot silently make them diverge.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/data/chat_media_upload_service.dart';
import 'package:treino/features/chat/data/chat_media_upload_service_web.dart';
import 'package:treino/features/chat/domain/media_type.dart';

void main() {
  late ChatMediaUploadService service;

  setUp(() {
    service = ChatMediaUploadServiceWeb.testable();
  });

  test('is a ChatMediaUploadService', () {
    expect(service, isA<ChatMediaUploadService>());
  });

  group('contentTypeForExt — inherited from base', () {
    test('jpg → image/jpeg', () {
      expect(service.contentTypeForExt('jpg'), 'image/jpeg');
    });
    test('png → image/png', () {
      expect(service.contentTypeForExt('png'), 'image/png');
    });
    test('unknown → application/octet-stream', () {
      expect(service.contentTypeForExt('xyz'), 'application/octet-stream');
    });
  });

  group('guardSize — inherited from base', () {
    test('image below 15MB does not throw', () {
      expect(
        () => service.guardSize(
          sizeBytes: 10 * 1024 * 1024,
          mediaType: MediaType.image,
        ),
        returnsNormally,
      );
    });

    test('image above 15MB throws ArgumentError', () {
      expect(
        () => service.guardSize(
          sizeBytes: 20 * 1024 * 1024,
          mediaType: MediaType.image,
        ),
        throwsArgumentError,
      );
    });

    test('video below 100MB does not throw', () {
      expect(
        () => service.guardSize(
          sizeBytes: 50 * 1024 * 1024,
          mediaType: MediaType.video,
        ),
        returnsNormally,
      );
    });
  });

  group('buildPath — inherited from base', () {
    test('builds canonical chatMedia/{chatId}/{uid}/{ts}.{ext} path', () {
      final path = service.buildPath(
        chatId: 'chat-abc',
        uid: 'user-xyz',
        ext: 'jpg',
        timestamp: 'ts123',
      );
      expect(path, 'chatMedia/chat-abc/user-xyz/ts123.jpg');
    });
  });

  group('extensionFor — inherited from base', () {
    test('lowercases the extension', () {
      expect(service.extensionFor('/tmp/photo.JPG'), 'jpg');
    });
    test('handles blob URLs (web picker returns those)', () {
      // In web the picker returns a path like `blob:...uuid...` without
      // extension. Should return empty string (defensive), not throw.
      expect(service.extensionFor('blob:http://localhost/abc-uuid'), '');
    });
  });

  group('extractStoragePath — inherited from base', () {
    test('parses a Firebase Storage v0 download URL', () {
      const url = 'https://firebasestorage.googleapis.com/v0/b/treino-dev'
          '.appspot.com/o/chatMedia%2Fchat-1%2Fuser-1%2Fts.jpg?alt=media';
      expect(
        service.extractStoragePath(url),
        'chatMedia/chat-1/user-1/ts.jpg',
      );
    });

    test('returns null for non-Firebase URLs', () {
      expect(
        service.extractStoragePath('https://example.com/file.jpg'),
        isNull,
      );
    });
  });
}
