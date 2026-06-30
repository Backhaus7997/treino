import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/chat/domain/media_type.dart';

void main() {
  group('MediaType JSON round-trip (REQ-CHATMEDIA-002)', () {
    test('MediaType.image serializes to "image"', () {
      expect(MediaType.image.toJson(), 'image');
    });

    test('MediaType.video serializes to "video"', () {
      expect(MediaType.video.toJson(), 'video');
    });

    test('"image" deserializes to MediaType.image', () {
      expect(MediaTypeX.fromJson('image'), MediaType.image);
    });

    test('"video" deserializes to MediaType.video', () {
      expect(MediaTypeX.fromJson('video'), MediaType.video);
    });

    test('unknown value throws ArgumentError', () {
      expect(
        () => MediaTypeX.fromJson('audio'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
