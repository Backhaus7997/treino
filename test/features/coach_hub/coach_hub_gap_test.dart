import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';

import 'data/match_names_helper.dart';

// ---------------------------------------------------------------------------
// Gap tests for the coach_hub matcher layer: fuzzy-match scoring threshold.
// (Los casos del parser simple y del repositorio viejo se retiraron junto con
// ese formato; el import periodizado tiene sus propias suites en data/.)
// ---------------------------------------------------------------------------

List<String> _dayWith(List<String> names) => namesOf(names);

void main() {
  // -------------------------------------------------------------------------
  // coach_hub-11 (P1) — fuzzy matching ignores stopwords and never auto-maps.
  // -------------------------------------------------------------------------
  test('coach_hub-11: skips tokens shorter than 3 chars in fuzzy matching', () {
    final catalog = [
      MatcherExercise(
          id: 'remo-con-barra', name: 'Remo con barra', muscleGroup: 'Espalda'),
    ];

    final result = matchExercises(_dayWith(['el de barra']), catalog);

    expect(result.unmatched, hasLength(1));
    expect(result.days.first.items.first.exerciseId, isNull);
    expect(
      result.days.first.items.first.suggestedExerciseId,
      'remo-con-barra',
    );
  });

  // -------------------------------------------------------------------------
  // coach_hub-12 (P0) — fuzzy score must be >= ceil(tokens/2) to accept.
  // Query 'Press banca inclinado' (3 long tokens) shares ZERO tokens with the
  // only catalog entry 'Sentadilla con barra' → best score 0 < ceil(3/2)=2 →
  // item goes to unmatched. Guards against over-matching on coincidence.
  // -------------------------------------------------------------------------
  test('coach_hub-12: requires fuzzy score >= ceil(tokens/2) to accept a match',
      () {
    final catalog = [
      MatcherExercise(
          id: 'sentadilla-con-barra',
          name: 'Sentadilla con barra',
          muscleGroup: 'Piernas'),
    ];

    final result = matchExercises(_dayWith(['Press banca inclinado']), catalog);

    expect(result.unmatched, hasLength(1));
    expect(result.unmatched.first.rowName, 'Press banca inclinado');
    final item = result.days.first.items.first;
    expect(item.exerciseId, isNull);
    expect(item.exerciseName, 'Press banca inclinado',
        reason: 'unmatched item keeps the raw rowName as exerciseName');
  });
}
