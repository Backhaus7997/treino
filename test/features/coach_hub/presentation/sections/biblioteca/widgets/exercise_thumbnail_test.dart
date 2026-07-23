// Widget tests for ExerciseThumbnail — resolves a network demo image via
// exerciseImageUrl(exercise.name), falling back to the honest placeholder
// icon when there's no confident match (or the network load errors).
//
// No mocking of the network layer: siguiendo el precedente ya establecido
// en `chat_web_v2_media_test.dart` (Image.network + errorBuilder), estos
// tests NO usan `pumpAndSettle()` — solo verifican que el widget correcto
// (Image vs ícono fallback) esté presente tras el primer frame, sin esperar
// a que la carga de red efectivamente resuelva.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/widgets/exercise_thumbnail.dart';
import 'package:treino/features/workout/domain/exercise.dart';

const _withMatch = Exercise(
  id: 'bicep-curl',
  name: 'Curl de bíceps', // real catalog name, media_confidence: high
  muscleGroup: 'biceps',
  category: 'isolation',
);

const _withoutMatch = Exercise(
  id: 'no-media-exercise',
  name: 'Ejercicio Sin Imagen De Catálogo',
  muscleGroup: 'biceps',
  category: 'isolation',
);

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SizedBox(width: 200, height: 150, child: child),
      ),
    );

void main() {
  group('ExerciseThumbnail —', () {
    testWidgets(
        'sin match confiable → ícono fallback (jamás una imagen equivocada)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const ExerciseThumbnail(exercise: _withoutMatch)),
      );
      await tester.pump();

      expect(find.byIcon(TreinoIcon.dumbbell), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
          find.byKey(const Key('exercise_thumbnail_fallback')), findsOneWidget);
    });

    testWidgets('con match confiable → renderiza Image.network',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const ExerciseThumbnail(exercise: _withMatch)),
      );
      await tester.pump();

      expect(
          find.byKey(const Key('exercise_thumbnail_network')), findsOneWidget);
      final img = tester.widget<Image>(find.byType(Image));
      expect(img.image, isA<NetworkImage>());
      expect((img.image as NetworkImage).url, contains('Dumbbell_Bicep_Curl'));
    });

    testWidgets('con match confiable el Image usa fit: cover', (tester) async {
      await tester.pumpWidget(
        _wrap(const ExerciseThumbnail(exercise: _withMatch)),
      );
      await tester.pump();

      final img = tester.widget<Image>(find.byType(Image));
      expect(img.fit, BoxFit.cover);
    });

    testWidgets('smoke dark+light sin crash, con y sin match', (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        for (final exercise in [_withMatch, _withoutMatch]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SizedBox(
                  width: 200,
                  height: 150,
                  child: ExerciseThumbnail(exercise: exercise),
                ),
              ),
            ),
          );
          await tester.pump();
        }
      }
      expect(tester.takeException(), isNull);
    });
  });
}
