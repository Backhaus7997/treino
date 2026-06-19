import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/insights/presentation/widgets/body_silhouette_placeholder.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

/// Counts mask `Image.asset` instances in the widget tree by asset path
/// substring. The widget renders one base body PNG + N mask PNGs stacked
/// with `ColorFiltered + Opacity`, so finding masks via path substring is
/// the simplest assertion (and survives an internal Stack rewrite).
int _countMasksContaining(WidgetTester tester, String pathFragment) {
  return tester.widgetList<Image>(find.byType(Image)).where((img) {
    final provider = img.image;
    if (provider is! AssetImage) return false;
    return provider.assetName.contains(pathFragment);
  }).length;
}

void main() {
  group('BodySilhouettePlaceholder — base render', () {
    testWidgets('renders bodyfront PNG when showBack=false', (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(width: 160, height: 240),
      ));
      expect(_countMasksContaining(tester, 'assets/body/bodyfront.png'), 1);
      expect(_countMasksContaining(tester, 'assets/body/bodyback.png'), 0);
    });

    testWidgets('renders bodyfront + bodyback when showBack=true',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 400,
          height: 280,
          showBack: true,
        ),
      ));
      expect(_countMasksContaining(tester, 'assets/body/bodyfront.png'), 1);
      expect(_countMasksContaining(tester, 'assets/body/bodyback.png'), 1);
    });

    testWidgets('no setsByGroup → no mask PNGs stacked on the body',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 400,
          height: 280,
          showBack: true,
        ),
      ));
      // Only the 2 base PNGs (front+back), zero masks.
      expect(_countMasksContaining(tester, 'mask_'), 0);
    });
  });

  group('BodySilhouettePlaceholder — mask stacking by trained group', () {
    testWidgets('pecho with sets → mask_front_chest stacks on front view only',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 400,
          height: 280,
          showBack: true,
          setsByGroup: {MuscleGroupDisplay.pecho: 5},
          targetByGroup: {MuscleGroupDisplay.pecho: 10},
        ),
      ));
      expect(_countMasksContaining(tester, 'mask_front_chest'), 1);
      expect(_countMasksContaining(tester, 'mask_back_'), 0);
    });

    testWidgets(
        'espalda with sets → 3 back masks stacked (decision 2: back + lats + lowerback)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 400,
          height: 280,
          showBack: true,
          setsByGroup: {MuscleGroupDisplay.espalda: 8},
          targetByGroup: {MuscleGroupDisplay.espalda: 10},
        ),
      ));
      expect(_countMasksContaining(tester, 'mask_back_back'), 1);
      expect(_countMasksContaining(tester, 'mask_back_lats'), 1);
      expect(_countMasksContaining(tester, 'mask_back_lowerback'), 1);
      // No front masks for back-only muscles.
      expect(_countMasksContaining(tester, 'mask_front_'), 0);
    });

    testWidgets(
        'hombros with sets → mask_front_shoulders AND mask_back_shoulders (front+back)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 400,
          height: 280,
          showBack: true,
          setsByGroup: {MuscleGroupDisplay.hombros: 3},
          targetByGroup: {MuscleGroupDisplay.hombros: 9},
        ),
      ));
      expect(_countMasksContaining(tester, 'mask_front_shoulders'), 1);
      expect(_countMasksContaining(tester, 'mask_back_shoulders'), 1);
    });

    testWidgets(
        'abdominales with sets → abs + obliques stacked together (decision 2)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 160,
          height: 240,
          setsByGroup: {MuscleGroupDisplay.abdominales: 4},
          targetByGroup: {MuscleGroupDisplay.abdominales: 6},
        ),
      ));
      expect(_countMasksContaining(tester, 'mask_front_abs'), 1);
      expect(_countMasksContaining(tester, 'mask_front_obliques'), 1);
    });

    testWidgets(
        'triceps with sets → NO mask stacked (decision 1A: no asset yet)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 400,
          height: 280,
          showBack: true,
          setsByGroup: {MuscleGroupDisplay.triceps: 6},
          targetByGroup: {MuscleGroupDisplay.triceps: 6},
        ),
      ));
      // No tríceps mask exists → silhouette is the only PNG per view.
      expect(_countMasksContaining(tester, 'mask_'), 0);
    });

    testWidgets('group with 0 sets → mask is NOT stacked', (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 160,
          height: 240,
          setsByGroup: {MuscleGroupDisplay.pecho: 0},
          targetByGroup: {MuscleGroupDisplay.pecho: 10},
        ),
      ));
      expect(_countMasksContaining(tester, 'mask_front_chest'), 0);
    });

    testWidgets(
        'multiple groups trained → each contributes its own masks independently',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 400,
          height: 280,
          showBack: true,
          setsByGroup: {
            MuscleGroupDisplay.pecho: 4,
            MuscleGroupDisplay.gluteos: 2,
            MuscleGroupDisplay.cuadriceps: 6,
          },
          targetByGroup: {
            MuscleGroupDisplay.pecho: 10,
            MuscleGroupDisplay.gluteos: 6,
            MuscleGroupDisplay.cuadriceps: 8,
          },
        ),
      ));
      expect(_countMasksContaining(tester, 'mask_front_chest'), 1);
      expect(_countMasksContaining(tester, 'mask_front_quads'), 1);
      expect(_countMasksContaining(tester, 'mask_back_glutes'), 1);
    });
  });

  group('BodySilhouettePlaceholder — intensity opacity (decision 3C)', () {
    /// Reads the Opacity wrapper around a mask that contains [pathFragment]
    /// in its asset name.
    double? opacityForMask(WidgetTester tester, String pathFragment) {
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
      for (final op in opacities) {
        final imgs = find.descendant(
          of: find.byWidget(op),
          matching: find.byType(Image),
        );
        for (final img in tester.widgetList<Image>(imgs)) {
          final provider = img.image;
          if (provider is AssetImage &&
              provider.assetName.contains(pathFragment)) {
            return op.opacity;
          }
        }
      }
      return null;
    }

    testWidgets('done == target → opacity 1.0 (full intensity)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 160,
          height: 240,
          setsByGroup: {MuscleGroupDisplay.pecho: 10},
          targetByGroup: {MuscleGroupDisplay.pecho: 10},
        ),
      ));
      expect(opacityForMask(tester, 'mask_front_chest'), 1.0);
    });

    testWidgets('done == 50% target → opacity 0.5', (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 160,
          height: 240,
          setsByGroup: {MuscleGroupDisplay.pecho: 5},
          targetByGroup: {MuscleGroupDisplay.pecho: 10},
        ),
      ));
      expect(opacityForMask(tester, 'mask_front_chest'), 0.5);
    });

    testWidgets('done > target → opacity clamped to 1.0 (no overflow)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 160,
          height: 240,
          setsByGroup: {MuscleGroupDisplay.pecho: 25},
          targetByGroup: {MuscleGroupDisplay.pecho: 10},
        ),
      ));
      expect(opacityForMask(tester, 'mask_front_chest'), 1.0);
    });

    testWidgets(
        'sets > 0 but NO target in routine → opacity 0.6 (orphan fallback)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const BodySilhouettePlaceholder(
          width: 160,
          height: 240,
          setsByGroup: {MuscleGroupDisplay.pecho: 3},
          // targetByGroup is empty — athlete trained something off-plan.
        ),
      ));
      expect(opacityForMask(tester, 'mask_front_chest'), 0.6);
    });
  });
}
