import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/firebase/emuladores.dart';
import 'package:treino/core/widgets/firebase_storage_video_player.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_video_player.dart';

const _deLaNube = 'https://firebasestorage.googleapis.com/v0/b/treino-dev'
    '.firebasestorage.app/o/customExerciseVideos%2Fuid%2Fclip.mp4'
    '?alt=media&token=t';

/// Lo que devuelve `getDownloadURL()` contra el emulador (medido en el
/// simulador de iOS) y lo que estampan los scripts de Storage (#1444).
const _delEmulador = 'http://localhost:9199/v0/b/treino-dev'
    '.firebasestorage.app/o/customExerciseVideos%2Fuid%2Fclip.mp4'
    '?alt=media&token=t';

void _modoEmulador() {
  debugUsaEmuladoresOverride = true;
  addTearDown(() => debugUsaEmuladoresOverride = null);
}

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('isFirebaseStorageVideo / extractFirebaseStoragePath', () {
    test('la URL de la nube vale con y sin USE_EMULATOR', () {
      expect(isFirebaseStorageVideo(_deLaNube), isTrue);
      expect(extractFirebaseStoragePath(_deLaNube),
          'customExerciseVideos/uid/clip.mp4');
      _modoEmulador();
      expect(isFirebaseStorageVideo(_deLaNube), isTrue);
      expect(extractFirebaseStoragePath(_deLaNube),
          'customExerciseVideos/uid/clip.mp4');
    });

    test('sin USE_EMULATOR, la del emulador NO es de Storage', () {
      expect(isFirebaseStorageVideo(_delEmulador), isFalse);
      expect(extractFirebaseStoragePath(_delEmulador), isNull);
    });

    test('con USE_EMULATOR, la del emulador reproduce y se puede borrar', () {
      _modoEmulador();
      expect(isFirebaseStorageVideo(_delEmulador), isTrue);
      // Sin el path, deleteByDownloadUrl no borra el objeto del emulador.
      expect(extractFirebaseStoragePath(_delEmulador),
          'customExerciseVideos/uid/clip.mp4');
    });

    test('con USE_EMULATOR, un host cualquiera sigue afuera', () {
      _modoEmulador();
      const ajeno = 'http://attacker.test:9199/v0/b/x/o/clip.mp4';
      expect(isFirebaseStorageVideo(ajeno), isFalse);
      expect(extractFirebaseStoragePath(ajeno), isNull);
    });
  });

  group('ExerciseVideoPlayer con la URL del emulador', () {
    testWidgets('sin USE_EMULATOR: «No pudimos leer el video.», sin player',
        (tester) async {
      await tester
          .pumpWidget(_wrap(const ExerciseVideoPlayer(videoUrl: _delEmulador)));
      await tester.pump();

      expect(find.text('No pudimos leer el video.'), findsOneWidget);
      expect(find.byType(FirebaseStorageVideoPlayer), findsNothing);
    });

    testWidgets(
        'con USE_EMULATOR, una URL con un escape inválido no rompe el build',
        (tester) async {
      _modoEmulador();
      await tester.pumpWidget(_wrap(
          const ExerciseVideoPlayer(videoUrl: 'https://example.com/%FF')));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('No pudimos leer el video.'), findsOneWidget);
    });

    testWidgets('con USE_EMULATOR: monta el player nativo', (tester) async {
      _modoEmulador();
      await tester
          .pumpWidget(_wrap(const ExerciseVideoPlayer(videoUrl: _delEmulador)));
      await tester.pump();

      expect(find.byType(FirebaseStorageVideoPlayer), findsOneWidget);
      expect(find.text('No pudimos leer el video.'), findsNothing);
    });
  });

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
