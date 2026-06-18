import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/domain/media_type.dart';
import 'package:treino/features/chat/domain/message.dart';

void main() {
  final baseCreatedAt = Timestamp.fromDate(DateTime.utc(2026, 6, 18, 10, 0));

  // ─── REQ-CHATMEDIA-001 ─────────────────────────────────────────────────────

  group('Message — media-only round-trip (REQ-CHATMEDIA-001)', () {
    test('media-only message serializes and deserializes correctly', () {
      final rawMap = <String, dynamic>{
        'id': 'msg-media-001',
        'senderId': 'uid-a',
        'text': '',
        'mediaUrl':
            'https://storage.googleapis.com/bucket/chatMedia/c1/u1/abc.jpg',
        'mediaType': 'image',
        'createdAt': baseCreatedAt,
      };

      final msg = Message.fromJson(rawMap);

      expect(msg.id, 'msg-media-001');
      expect(msg.senderId, 'uid-a');
      expect(msg.text, '');
      expect(msg.mediaUrl,
          'https://storage.googleapis.com/bucket/chatMedia/c1/u1/abc.jpg');
      expect(msg.mediaType, MediaType.image);

      // Round-trip: toJson → fromJson must yield equal object.
      final decoded = Message.fromJson(msg.toJson());
      expect(decoded, equals(msg));
    });

    test('caption + media message preserves both fields', () {
      final rawMap = <String, dynamic>{
        'id': 'msg-media-002',
        'senderId': 'uid-b',
        'text': 'Great form!',
        'mediaUrl':
            'https://storage.googleapis.com/bucket/chatMedia/c1/u1/vid.mp4',
        'mediaType': 'video',
        'createdAt': baseCreatedAt,
      };

      final msg = Message.fromJson(rawMap);

      expect(msg.text, 'Great form!');
      expect(msg.mediaUrl, isNotNull);
      expect(msg.mediaType, MediaType.video);

      final decoded = Message.fromJson(msg.toJson());
      expect(decoded, equals(msg));
    });

    test('text-only message remains backward compatible (REQ-CHATMEDIA-015)',
        () {
      final rawMap = <String, dynamic>{
        'id': 'msg-text-001',
        'senderId': 'uid-c',
        'text': 'Hola!',
        'createdAt': baseCreatedAt,
      };

      final msg = Message.fromJson(rawMap);

      expect(msg.text, 'Hola!');
      expect(msg.mediaUrl, isNull);
      expect(msg.mediaType, isNull);
    });

    test('text field defaults to empty string when absent', () {
      final rawMap = <String, dynamic>{
        'id': 'msg-media-003',
        'senderId': 'uid-d',
        'mediaUrl': 'https://example.com/photo.jpg',
        'mediaType': 'image',
        'createdAt': baseCreatedAt,
      };

      final msg = Message.fromJson(rawMap);

      expect(msg.text, '');
      expect(msg.mediaType, MediaType.image);
    });

    test('video mediaType round-trip', () {
      final msg = Message(
        id: 'msg-vid',
        senderId: 'uid-a',
        text: '',
        mediaUrl: 'https://example.com/video.mp4',
        mediaType: MediaType.video,
        createdAt: DateTime.utc(2026, 6, 18),
      );

      final decoded = Message.fromJson(msg.toJson());
      expect(decoded.mediaType, MediaType.video);
      expect(decoded.mediaUrl, 'https://example.com/video.mp4');
    });
  });
}
