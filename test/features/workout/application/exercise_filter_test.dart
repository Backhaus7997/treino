// Tests for the extracted filter predicate — T-BIBW-001
// REQ-BIBW-08, SCENARIO-BIBW-08a, SCENARIO-BIBW-08b
// SCENARIO-BIBW-05b (diacritic), SCENARIO-BIBW-06b (ADR-RER-05)

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/exercise_filter.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _bench = Exercise(
  id: 'bench-press',
  name: 'Press de Banca',
  muscleGroup: 'chest',
  category: 'compound',
  equipment: EquipmentType.barra,
);

const _lunge = Exercise(
  id: 'lunge-press',
  name: 'Estocada a Press',
  muscleGroup: 'quads',
  secondaryMuscleGroup: 'shoulders',
  category: 'compound',
  equipment: EquipmentType.mancuerna,
);

const _curl = Exercise(
  id: 'biceps-curl',
  name: 'Curl de Bíceps',
  muscleGroup: 'biceps',
  category: 'isolation',
  // equipment intentionally null
);

const _remo = Exercise(
  id: 'remo-mancuerna',
  name: 'Remo con Mancuerna',
  muscleGroup: 'back',
  category: 'compound',
  equipment: EquipmentType.mancuerna,
  aliases: ['remo unilateral'],
);

// ── foldSearch ────────────────────────────────────────────────────────────────

void main() {
  group('foldSearch', () {
    test('lowercases ASCII', () {
      expect(foldSearch('BICEPS'), equals('biceps'));
    });

    test('strips Spanish accents — á é í ó ú ñ', () {
      expect(foldSearch('Bíceps'), equals('biceps'));
      expect(foldSearch('Elevación'), equals('elevacion'));
      expect(foldSearch('Mancuerna'), equals('mancuerna'));
      expect(foldSearch('España'), equals('espana'));
    });

    test('strips accent on ü ê ë etc.', () {
      expect(foldSearch('güe'), equals('gue'));
    });

    test('empty input returns empty string', () {
      expect(foldSearch(''), equals(''));
    });
  });

  // ── exerciseMatchesFilters — empty filters ────────────────────────────────

  group('exerciseMatchesFilters — all filters empty', () {
    test('returns true for any exercise when all filters empty', () {
      expect(
        exerciseMatchesFilters(
          _bench,
          query: '',
          muscles: const {},
          equipment: const {},
        ),
        isTrue,
      );
    });

    test('returns true for exercise with null equipment when filters empty',
        () {
      expect(
        exerciseMatchesFilters(
          _curl,
          query: '',
          muscles: const {},
          equipment: const {},
        ),
        isTrue,
      );
    });
  });

  // ── exerciseMatchesFilters — query ────────────────────────────────────────

  group('exerciseMatchesFilters — query matching', () {
    test('name match (case-insensitive)', () {
      expect(
        exerciseMatchesFilters(
          _bench,
          query: 'press',
          muscles: const {},
          equipment: const {},
        ),
        isTrue,
      );
    });

    test('name match (diacritic-tolerant) — SCENARIO-BIBW-05b', () {
      // "mancuerna" (no accent) should match "Remo con Mancuerna"
      expect(
        exerciseMatchesFilters(
          _remo,
          query: 'mancuerna',
          muscles: const {},
          equipment: const {},
        ),
        isTrue,
      );
    });

    test('alias match', () {
      expect(
        exerciseMatchesFilters(
          _remo,
          query: 'unilateral',
          muscles: const {},
          equipment: const {},
        ),
        isTrue,
      );
    });

    test('query mismatch returns false', () {
      expect(
        exerciseMatchesFilters(
          _bench,
          query: 'sentadilla',
          muscles: const {},
          equipment: const {},
        ),
        isFalse,
      );
    });

    test('whitespace-only query is treated as empty (pass through)', () {
      expect(
        exerciseMatchesFilters(
          _bench,
          query: '   ',
          muscles: const {},
          equipment: const {},
        ),
        isTrue,
      );
    });
  });

  // ── exerciseMatchesFilters — muscle filter ────────────────────────────────

  group('exerciseMatchesFilters — muscle filter', () {
    test('matches by primary muscle', () {
      expect(
        exerciseMatchesFilters(
          _bench,
          query: '',
          muscles: {MuscleGroup.pecho},
          equipment: const {},
        ),
        isTrue,
      );
    });

    test(
        'matches by SECONDARY muscle (primary-OR-secondary rule) — SCENARIO-BIBW-06b like',
        () {
      // lunge has primary=quads, secondary=shoulders
      expect(
        exerciseMatchesFilters(
          _lunge,
          query: '',
          muscles: {MuscleGroup.hombros},
          equipment: const {},
        ),
        isTrue,
      );
    });

    test('does NOT match when neither primary nor secondary in filter', () {
      expect(
        exerciseMatchesFilters(
          _bench,
          query: '',
          muscles: {MuscleGroup.biceps},
          equipment: const {},
        ),
        isFalse,
      );
    });

    test('OR within muscle dimension — multiple muscles', () {
      // Both bench (chest) and curl (biceps) should pass when filter has both
      expect(
        exerciseMatchesFilters(
          _bench,
          query: '',
          muscles: {MuscleGroup.pecho, MuscleGroup.biceps},
          equipment: const {},
        ),
        isTrue,
      );
      expect(
        exerciseMatchesFilters(
          _curl,
          query: '',
          muscles: {MuscleGroup.pecho, MuscleGroup.biceps},
          equipment: const {},
        ),
        isTrue,
      );
    });
  });

  // ── exerciseMatchesFilters — equipment filter / ADR-RER-05 ───────────────

  group('exerciseMatchesFilters — equipment filter (ADR-RER-05)', () {
    test(
        'null equipment is INCLUDED when equipment filter is empty — SCENARIO-BIBW-08b inverse',
        () {
      expect(
        exerciseMatchesFilters(
          _curl, // equipment null
          query: '',
          muscles: const {},
          equipment: const {},
        ),
        isTrue,
      );
    });

    test(
        'null equipment is EXCLUDED when equipment filter is non-empty — ADR-RER-05 / SCENARIO-BIBW-08b',
        () {
      expect(
        exerciseMatchesFilters(
          _curl, // equipment null
          query: '',
          muscles: const {},
          equipment: {EquipmentType.mancuerna},
        ),
        isFalse,
      );
    });

    test('matching equipment passes filter', () {
      expect(
        exerciseMatchesFilters(
          _remo, // equipment mancuerna
          query: '',
          muscles: const {},
          equipment: {EquipmentType.mancuerna},
        ),
        isTrue,
      );
    });

    test('non-matching equipment returns false', () {
      expect(
        exerciseMatchesFilters(
          _bench, // equipment barra
          query: '',
          muscles: const {},
          equipment: {EquipmentType.mancuerna},
        ),
        isFalse,
      );
    });

    test('OR within equipment dimension', () {
      expect(
        exerciseMatchesFilters(
          _bench, // equipment barra
          query: '',
          muscles: const {},
          equipment: {EquipmentType.mancuerna, EquipmentType.barra},
        ),
        isTrue,
      );
    });
  });

  // ── exerciseMatchesFilters — ADR-RER-05 combo (the live guard) ────────────

  group('exerciseMatchesFilters — ADR-RER-05 combo (was skip in picker test)',
      () {
    // This group is the ONLY live coverage of the combo: equipment filter ON
    // + null-equipment exercise + muscle filter + query all combined.
    // exercise_picker_filter_combo_test.dart is entirely skip:-ped.

    test('query + muscle + equipment — all must match (AND across dimensions)',
        () {
      // remo: name=Remo con Mancuerna, muscle=back, equipment=mancuerna
      expect(
        exerciseMatchesFilters(
          _remo,
          query: 'remo',
          muscles: {MuscleGroup.espalda},
          equipment: {EquipmentType.mancuerna},
        ),
        isTrue,
      );
    });

    test('query matches but muscle does not — fails', () {
      expect(
        exerciseMatchesFilters(
          _remo,
          query: 'remo',
          muscles: {MuscleGroup.pecho}, // chest — remo is back
          equipment: {EquipmentType.mancuerna},
        ),
        isFalse,
      );
    });

    test('muscle matches but equipment null (ADR-RER-05 excluded)', () {
      // curl: muscle=biceps, equipment=null
      // With equipment filter active, null-equipment exercises are excluded
      // regardless of muscle match.
      expect(
        exerciseMatchesFilters(
          _curl,
          query: '',
          muscles: {MuscleGroup.biceps},
          equipment: {EquipmentType.mancuerna},
        ),
        isFalse,
      );
    });

    test('null equipment included when equipment filter is CLEARED', () {
      // Same exercise — once filter is cleared (empty set), null-equipment passes
      expect(
        exerciseMatchesFilters(
          _curl,
          query: '',
          muscles: {MuscleGroup.biceps},
          equipment: const {},
        ),
        isTrue,
      );
    });
  });

  // ── customToExercise ──────────────────────────────────────────────────────

  group('customToExercise', () {
    test('stamps category as "custom"', () {
      final custom = _makeCustom();
      final result = customToExercise(custom);
      expect(result.category, equals('custom'));
    });

    test('preserves id, name, muscleGroup', () {
      final custom = _makeCustom();
      final result = customToExercise(custom);
      expect(result.id, equals('custom-1'));
      expect(result.name, equals('Press Personalizado'));
      expect(result.muscleGroup, equals('chest'));
    });

    test('preserves equipment and restSeconds', () {
      final custom = _makeCustom();
      final result = customToExercise(custom);
      expect(result.equipment, equals(EquipmentType.mancuerna));
      expect(result.defaultRestSeconds, equals(90));
    });

    test('techniqueInstructions is null (lossy adapter)', () {
      final custom = _makeCustom();
      final result = customToExercise(custom);
      expect(result.techniqueInstructions, isNull);
    });
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

CustomExercise _makeCustom() {
  return CustomExercise(
    id: 'custom-1',
    ownerId: 'trainer-uid',
    name: 'Press Personalizado',
    muscleGroup: 'chest',
    equipment: EquipmentType.mancuerna,
    defaultRestSeconds: 90,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}
