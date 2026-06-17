import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';

void main() {
  group('MuscleGroup taxonomy', () {
    test('exposes the curated 12 groups in display order', () {
      expect(MuscleGroup.displayOrder.length, 12);
      expect(
        MuscleGroup.displayOrder.map((g) => g.label).toList(),
        [
          'Pecho',
          'Espalda',
          'Hombros',
          'Bíceps',
          'Tríceps',
          'Cuádriceps',
          'Isquiotibiales',
          'Glúteos',
          'Pantorrilla',
          'Abdominales',
          'Cardio',
          'Cuerpo completo',
        ],
      );
    });

    test('canonical keys are unique and match the stock catalogue', () {
      final keys = MuscleGroup.values.map((g) => g.key).toList();
      expect(keys.toSet().length, keys.length);
      // The stock seed already uses these English keys — no migration needed.
      expect(MuscleGroup.pecho.key, 'chest');
      expect(MuscleGroup.pantorrilla.key, 'calves');
      expect(MuscleGroup.abdominales.key, 'core');
    });
  });

  group('MuscleGroup.fromKey', () {
    test('resolves canonical keys', () {
      expect(MuscleGroup.fromKey('chest'), MuscleGroup.pecho);
      expect(MuscleGroup.fromKey('hamstrings'), MuscleGroup.isquiotibiales);
      expect(MuscleGroup.fromKey('full_body'), MuscleGroup.cuerpoCompleto);
    });

    test('resolves English aliases', () {
      expect(MuscleGroup.fromKey('abs'), MuscleGroup.abdominales);
      expect(MuscleGroup.fromKey('fullbody'), MuscleGroup.cuerpoCompleto);
    });

    test('canonicalises legacy Spanish labels so old custom data is not lost',
        () {
      // These are the values the old editor persisted — they used to map to
      // nothing and stayed invisible in filters/insights.
      expect(MuscleGroup.fromKey('Pecho'), MuscleGroup.pecho);
      expect(MuscleGroup.fromKey('Espalda alta'), MuscleGroup.espalda);
      expect(MuscleGroup.fromKey('Dorsales'), MuscleGroup.espalda);
      expect(MuscleGroup.fromKey('Gemelos'), MuscleGroup.pantorrilla);
      expect(MuscleGroup.fromKey('Antebrazos'), MuscleGroup.biceps);
      expect(MuscleGroup.fromKey('Aductores'), MuscleGroup.cuadriceps);
      expect(
          MuscleGroup.fromKey('Cuerpo completo'), MuscleGroup.cuerpoCompleto);
    });

    test('is case- and whitespace-insensitive', () {
      expect(MuscleGroup.fromKey('  CHEST '), MuscleGroup.pecho);
      expect(MuscleGroup.fromKey('glúteos'), MuscleGroup.gluteos);
    });

    test('returns null for empty, null, and unknown/Otro values', () {
      expect(MuscleGroup.fromKey(null), isNull);
      expect(MuscleGroup.fromKey(''), isNull);
      expect(MuscleGroup.fromKey('   '), isNull);
      expect(MuscleGroup.fromKey('Otro'), isNull);
      expect(MuscleGroup.fromKey('zzz'), isNull);
    });
  });
}
