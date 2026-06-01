import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_video_player.dart';

void main() {
  group('parseYoutubeVideoId', () {
    test('null and empty inputs return null', () {
      expect(parseYoutubeVideoId(null), isNull);
      expect(parseYoutubeVideoId(''), isNull);
      expect(parseYoutubeVideoId('   '), isNull);
    });

    test('bare 11-char id is accepted as-is', () {
      expect(parseYoutubeVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });

    test('youtube.com/watch?v=ID parses', () {
      expect(
        parseYoutubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      // m.youtube subdomain
      expect(
        parseYoutubeVideoId('https://m.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      // Extra query params don't break parsing
      expect(
        parseYoutubeVideoId(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=120s'),
        'dQw4w9WgXcQ',
      );
    });

    test('youtu.be short links parse', () {
      expect(
        parseYoutubeVideoId('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('youtube shorts and embed URLs parse', () {
      expect(
        parseYoutubeVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        parseYoutubeVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });

    test('returns null for non-YouTube hosts', () {
      expect(
        parseYoutubeVideoId('https://vimeo.com/dQw4w9WgXcQ'),
        isNull,
      );
      expect(
        parseYoutubeVideoId('https://example.com/watch?v=dQw4w9WgXcQ'),
        isNull,
      );
    });

    test('returns null for malformed/too-short id', () {
      expect(
        parseYoutubeVideoId('https://youtu.be/short'),
        isNull,
      );
      expect(
        parseYoutubeVideoId('https://www.youtube.com/watch?v=tooshort'),
        isNull,
      );
    });

    test('returns null for non-parseable strings', () {
      expect(parseYoutubeVideoId('not a url'), isNull);
      expect(parseYoutubeVideoId('123'), isNull);
    });
  });
}
