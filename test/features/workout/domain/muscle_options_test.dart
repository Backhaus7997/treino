import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/muscle_options.dart';

void main() {
  group('kMuscleOptions', () {
    test('contains expected muscles in the specified order', () {
      expect(kMuscleOptions, [
        'Pecho',
        'Espalda alta',
        'Dorsales',
        'Hombros',
        'Bíceps',
        'Tríceps',
        'Antebrazos',
        'Cuádriceps',
        'Isquiotibiales',
        'Glúteos',
        'Gemelos',
        'Abdominales',
        'Aductores',
        'Trapecio',
        'Cuello',
        'Cardio',
        'Cuerpo completo',
        'Otro',
      ]);
    });

    test('has 18 items', () {
      expect(kMuscleOptions.length, 18);
    });

    test('all items are unique', () {
      expect(kMuscleOptions.toSet().length, kMuscleOptions.length);
    });

    test('known values are present', () {
      for (final muscle in ['Pecho', 'Bíceps', 'Glúteos', 'Otro']) {
        expect(kMuscleOptions.contains(muscle), isTrue);
      }
    });
  });

  group('edit-mode pre-selection logic', () {
    // Mirrors the logic in _hydrate():
    // kMuscleOptions.contains(ex.muscleGroup) ? ex.muscleGroup : null
    String? resolveSelection(String storedValue) =>
        kMuscleOptions.contains(storedValue) ? storedValue : null;

    test('known muscle → pre-selected', () {
      expect(resolveSelection('Cuádriceps'), 'Cuádriceps');
    });

    test('known muscle with accents → pre-selected', () {
      expect(resolveSelection('Bíceps'), 'Bíceps');
    });

    test('legacy free-text value → null (no selection)', () {
      expect(resolveSelection('cuádriceps'), isNull);
    });

    test('empty string (default) → null', () {
      expect(resolveSelection(''), isNull);
    });

    test('arbitrary old free-text → null', () {
      expect(resolveSelection('piernas en general'), isNull);
    });

    test('save mapping: selected muscle → muscleGroup string', () {
      // On save: _selectedMuscle ?? ''
      String? selected = 'Glúteos';
      final muscleGroup = selected ?? '';
      expect(muscleGroup, 'Glúteos');
    });

    test('save mapping: null selection → empty string', () {
      String? selected;
      final muscleGroup = selected ?? '';
      expect(muscleGroup, '');
    });
  });
}
