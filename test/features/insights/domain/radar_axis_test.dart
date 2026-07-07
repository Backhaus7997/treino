import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/insights/domain/radar_axis.dart';

void main() {
  group('RadarAxis.fromDisplayGroup', () {
    // [AD4] Every one of the 10 MuscleGroupDisplay values MUST fold cleanly
    // to exactly one of the 6 radar axes — ZERO orphans. This is the
    // must-pass regression: if a future MuscleGroupDisplay value is added
    // without updating fromDisplayGroup's switch, the exhaustive switch in
    // the implementation breaks the build (compile-time safety net), and
    // this test proves the CURRENT 10 values all resolve today (run-time
    // safety net).
    test('every MuscleGroupDisplay value maps to a RadarAxis (zero orphans)',
        () {
      for (final group in MuscleGroupDisplay.values) {
        final axis = RadarAxis.fromDisplayGroup(group);
        expect(
          axis,
          isNotNull,
          reason: '$group must map to a RadarAxis — found none',
        );
      }
    });

    test('Back axis = espalda only', () {
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.espalda),
          RadarAxis.back);
    });

    test('Chest axis = pecho only', () {
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.pecho),
          RadarAxis.chest);
    });

    test('Core axis = abdominales only', () {
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.abdominales),
          RadarAxis.core);
    });

    test('Shoulders axis = hombros only', () {
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.hombros),
          RadarAxis.shoulders);
    });

    test('Arms axis = biceps + triceps', () {
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.biceps),
          RadarAxis.arms);
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.triceps),
          RadarAxis.arms);
    });

    test('Legs axis = quads + hams + glutes + calves', () {
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.cuadriceps),
          RadarAxis.legs);
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.isquiotibiales),
          RadarAxis.legs);
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.gluteos),
          RadarAxis.legs);
      expect(RadarAxis.fromDisplayGroup(MuscleGroupDisplay.pantorrilla),
          RadarAxis.legs);
    });
  });

  group('RadarAxis.displayOrder', () {
    test('has exactly 6 axes, one per canonical group', () {
      expect(RadarAxis.displayOrder.length, 6);
      expect(RadarAxis.displayOrder.toSet(), RadarAxis.values.toSet());
    });
  });

  group('RadarAxis.displayLabel', () {
    test('every axis has a non-empty label', () {
      for (final axis in RadarAxis.values) {
        expect(axis.displayLabel, isNotEmpty);
      }
    });
  });
}
