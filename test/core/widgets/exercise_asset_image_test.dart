// Tests for the shared exercise illustration cascade (#542).
//
// The candidate ORDER is the contract: picker thumbnail and detail hero must
// resolve the same asset for the same exercise, so the order is pinned here
// as pure unit tests (no bundle, no fixtures).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/widgets/exercise_asset_image.dart';

void main() {
  group('exerciseAssetCandidates', () {
    test('full cascade order for a 3-segment id — pins doc example', () {
      expect(
        exerciseAssetCandidates(
          exerciseId: 'barbell-back-squat',
          muscleGroup: 'quads',
        ),
        [
          'assets/exercises/barbell-back-squat.png',
          'assets/exercises/barbell-back.png', // strip suffix
          'assets/exercises/back-squat.png', // strip prefix
          'assets/muscles/barbell-back-squat.png',
          'assets/muscles/barbell-back.png',
          'assets/muscles/back-squat.png',
          'assets/muscles/quads.png', // muscle bucket
        ],
      );
    });

    test('single-segment id probes only the strict slug + muscle bucket', () {
      expect(
        exerciseAssetCandidates(exerciseId: 'plank', muscleGroup: 'core'),
        [
          'assets/exercises/plank.png',
          'assets/muscles/plank.png',
          'assets/muscles/core.png',
        ],
      );
    });

    test('single-hyphen id gets NO strip-prefix variant (first == last)', () {
      // Stripping 'bench-' to probe `press.png` would be a nonsense match;
      // the prefix strip only fires on 3+-segment ids.
      expect(
        exerciseAssetCandidates(
          exerciseId: 'bench-press',
          muscleGroup: 'chest',
        ),
        [
          'assets/exercises/bench-press.png',
          'assets/exercises/bench.png',
          'assets/muscles/bench-press.png',
          'assets/muscles/bench.png',
          'assets/muscles/chest.png',
        ],
      );
    });

    test('empty muscleGroup drops the muscle bucket', () {
      expect(
        exerciseAssetCandidates(exerciseId: 'plank', muscleGroup: ''),
        [
          'assets/exercises/plank.png',
          'assets/muscles/plank.png',
        ],
      );
    });

    test('empty id still yields the muscle bucket', () {
      expect(
        exerciseAssetCandidates(exerciseId: '', muscleGroup: 'back'),
        ['assets/muscles/back.png'],
      );
    });

    test('Drive-catalogue id resolves via the muscle bucket — the #542 case',
        () {
      // Real catalogue ids (e.g. `pullup-pesocorporal`) match no bundled PNG;
      // the muscle bucket at the end is what guarantees an illustration.
      final candidates = exerciseAssetCandidates(
        exerciseId: 'pullup-pesocorporal',
        muscleGroup: 'back',
      );
      expect(candidates.last, 'assets/muscles/back.png');
    });
  });

  group('ExerciseAssetImage', () {
    testWidgets('no candidates at all → paints fallback immediately',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseAssetImage(
            exerciseId: '',
            muscleGroup: '',
            fallback: Container(key: const Key('fb')),
          ),
        ),
      );

      expect(find.byKey(const Key('fb')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('every candidate misses → walks the chain to the fallback',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseAssetImage(
            exerciseId: 'no-such-exercise',
            muscleGroup: 'no-such-muscle',
            fallback: Container(key: const Key('fb')),
          ),
        ),
      );
      // Each missing asset fails its load asynchronously before the
      // errorBuilder swaps in the next candidate — drain the whole chain.
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      expect(find.byKey(const Key('fb')), findsOneWidget);
    });

    testWidgets('bundled muscle asset resolves for a Drive-catalogue id',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseAssetImage(
            exerciseId: 'pullup-pesocorporal',
            muscleGroup: 'back',
            fallback: Container(key: const Key('fb')),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      // The walk must stop at `assets/muscles/back.png` (bundled), never
      // reaching the fallback. Failed candidates stay in the tree as the
      // errorBuilder parents of the winner, so scan all mounted Images.
      expect(find.byKey(const Key('fb')), findsNothing);
      final assetNames = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => (i.image as AssetImage).assetName);
      expect(assetNames, contains('assets/muscles/back.png'));
    });
  });
}
