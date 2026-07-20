// QA-WKT-002 / QA-WKT-003 — domain caps for a single set.
//
// Guards the two paths that feed a SetLog against physically-impossible values:
//   1. `isSetValid` (routine editor validation) rejects reps/weight over the cap.
//   2. `BoundedNumberFormatter` (numeric input in both editor and player) can't
//      hold a value that diverges from what will be logged, nor exceed the cap.
// A set over the ceiling corrupts totalVolumeKg and the server-side ranking
// recompute; there was no regression net for this before.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_limits.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/features/workout/presentation/widgets/bounded_number_formatter.dart';

void main() {
  group('clamp helpers', () {
    test('clampReps caps at kMaxReps and floors at 0', () {
      expect(clampReps(1000000), kMaxReps);
      expect(clampReps(-5), 0);
      expect(clampReps(12), 12);
    });
    test('clampWeightKg caps at kMaxWeightKg and floors at 0', () {
      expect(clampWeightKg(99999), kMaxWeightKg);
      expect(clampWeightKg(-3), 0);
      expect(clampWeightKg(80.5), 80.5);
    });
  });

  group('BoundedNumberFormatter — weight (decimal)', () {
    const f = BoundedNumberFormatter(max: kMaxWeightKg, decimal: true);
    String apply(String oldT, String newT) => f
        .formatEditUpdate(
          TextEditingValue(text: oldT),
          TextEditingValue(text: newT),
        )
        .text;

    test('accepts a value within range', () => expect(apply('45', '450'), '450'));
    test('reverts a keystroke that pushes over the cap (750 > 500)',
        () => expect(apply('75', '750'), '75'));
    test('accepts exactly the cap', () => expect(apply('50', '500'), '500'));
    test('rejects a second decimal separator (1.2.3)',
        () => expect(apply('1.2', '1.2.'), '1.2'));
    test('allows a trailing separator mid-typing (1.)',
        () => expect(apply('1', '1.'), '1.'));
    test('accepts comma as separator',
        () => expect(apply('17', '17,5'), '17,5'));
  });

  group('BoundedNumberFormatter — reps (integer)', () {
    const f = BoundedNumberFormatter(max: 999, decimal: false);
    String apply(String oldT, String newT) => f
        .formatEditUpdate(
          TextEditingValue(text: oldT),
          TextEditingValue(text: newT),
        )
        .text;

    test('accepts within range', () => expect(apply('12', '120'), '120'));
    test('reverts over cap (1000 > 999)',
        () => expect(apply('100', '1000'), '100'));
    test('rejects a decimal point', () => expect(apply('1', '1.'), '1'));
  });

  group('isSetValid — upper bounds', () {
    test('rejects a working set with weight over the cap', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.single,
          weightKg: kMaxWeightKg + 1,
          reps: 10,
        ),
        isFalse,
      );
    });
    test('rejects a failure set with weight over the cap (volume still counts)',
        () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.single,
          type: SetType.failure,
          weightKg: kMaxWeightKg + 1,
        ),
        isFalse,
      );
    });
    test('rejects reps over the cap', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.single,
          reps: kMaxReps + 1,
        ),
        isFalse,
      );
    });
    test('rejects a range whose max exceeds the cap', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.range,
          repsMin: 8,
          repsMax: kMaxReps + 1,
        ),
        isFalse,
      );
    });
    test('accepts a normal set within limits', () {
      expect(
        RoutineEditorTestBridge.isSetValidBridge(
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.single,
          weightKg: 80,
          reps: 10,
        ),
        isTrue,
      );
    });
  });
}
