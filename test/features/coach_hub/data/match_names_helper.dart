import 'package:treino/features/coach_hub/data/exercise_matcher.dart';

/// Adaptador de test: pasa una lista de nombres por `ExerciseNameMatcher` y
/// devuelve el veredicto con la forma que usaban los tests del matcher
/// (items por día + no resueltos). Así los casos de #1455 siguen midiendo la
/// política del matcher sin depender del import viejo.
class MatchedItem {
  MatchedItem({
    required this.rowName,
    required this.exerciseId,
    required this.exerciseName,
    required this.muscleGroup,
    required this.suggestedExerciseId,
    required this.suggestedExerciseName,
  });

  final String rowName;
  final String? exerciseId;
  final String exerciseName;
  final String? muscleGroup;
  final String? suggestedExerciseId;
  final String? suggestedExerciseName;
}

class MatchedDay {
  MatchedDay(this.items);
  final List<MatchedItem> items;
}

class MatchedUnresolved {
  MatchedUnresolved(this.rowName);
  final String rowName;
}

class MatchedNames {
  MatchedNames(this.days, this.unmatched);
  final List<MatchedDay> days;
  final List<MatchedUnresolved> unmatched;
}

List<String> namesOf(List<String> names) => names;

MatchedNames matchExercises(
  List<String> names,
  List<MatcherExercise> catalog,
) {
  final matcher = ExerciseNameMatcher(catalog);
  final items = <MatchedItem>[];
  final unmatched = <MatchedUnresolved>[];
  for (final name in names) {
    final v = matcher.match(name);
    final ex = v.exercise;
    if (ex == null) unmatched.add(MatchedUnresolved(name));
    items.add(MatchedItem(
      rowName: name,
      exerciseId: ex?.id,
      exerciseName: ex?.name ?? name,
      muscleGroup: ex?.muscleGroup,
      suggestedExerciseId: ex == null ? v.suggestion?.id : null,
      suggestedExerciseName: ex == null ? v.suggestion?.name : null,
    ));
  }
  return MatchedNames([MatchedDay(items)], unmatched);
}
