import '../domain/parsed_plan.dart';
import 'excel_parser.dart';

/// Catálogo mínimo del lado matcher — sólo lo que necesita para mapear.
class MatcherExercise {
  MatcherExercise({
    required this.id,
    required this.name,
    this.muscleGroup,
    this.aliases = const <String>[],
  });

  final String id;
  final String name;
  final String? muscleGroup;

  /// Synonyms in Spanish or trainer jargon — every alias gets indexed
  /// alongside `name`, so "Sentadilla con barra" matches the same exercise
  /// as "Back Squat".
  final List<String> aliases;
}

class MatchResult {
  MatchResult({required this.days, required this.unmatched});
  final List<ParsedPlanDay> days;
  final List<ParsedPlanUnmatched> unmatched;
}

// NORMALIZE-PARITY: see ADR-CXP-006 — TS port lives in functions/src/add-alias.ts
String normalize(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp('[áàäâã]'), 'a')
      .replaceAll(RegExp('[éèëê]'), 'e')
      .replaceAll(RegExp('[íìïî]'), 'i')
      .replaceAll(RegExp('[óòöôõ]'), 'o')
      .replaceAll(RegExp('[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _Index {
  _Index._(this.byName, this.exercises);
  final Map<String, MatcherExercise> byName;
  final List<MatcherExercise> exercises;

  factory _Index.build(List<MatcherExercise> exercises) {
    final byName = <String, MatcherExercise>{};

    void indexLabel(String label, MatcherExercise ex) {
      final normalized = normalize(label);
      if (normalized.isEmpty) return;
      byName.putIfAbsent(normalized, () => ex);
    }

    for (final ex in exercises) {
      indexLabel(ex.name, ex);
      for (final alias in ex.aliases) {
        indexLabel(alias, ex);
      }
    }
    return _Index._(byName, exercises);
  }
}

const _stopwords = <String>{
  'con',
  'de',
  'del',
  'en',
  'la',
  'el',
  'los',
  'las',
  'a',
  'al',
  'y',
  'para',
  'por',
};

/// Términos de equipamiento canónicos. Los sinónimos comparten valor para que,
/// por ejemplo, "pesa rusa" y "kettlebell" se consideren el mismo equipo.
/// Esta es la única lista que gobierna compatibilidad de equipamiento.
const _equipmentByToken = <String, String>{
  'barra': 'barra',
  'barbell': 'barra',
  'mancuerna': 'mancuerna',
  'mancuernas': 'mancuerna',
  'dumbbell': 'mancuerna',
  'dumbbells': 'mancuerna',
  'banda': 'banda',
  'bandas': 'banda',
  'elastico': 'banda',
  'elastica': 'banda',
  'elasticos': 'banda',
  'elasticas': 'banda',
  'pesa': 'pesa-rusa',
  'rusa': 'pesa-rusa',
  'kettlebell': 'pesa-rusa',
  'polea': 'polea',
  'poleas': 'polea',
  'cable': 'polea',
  'cables': 'polea',
  'maquina': 'maquina',
  'maquinas': 'maquina',
  'smith': 'smith',
  'multipower': 'smith',
  'disco': 'disco',
  'discos': 'disco',
  'trx': 'trx',
  'bosu': 'bosu',
  'fitball': 'fitball',
  'pelota': 'fitball',
  'landmine': 'landmine',
};

/// Variantes biomecánicas que no se pueden inferir por coincidencia parcial.
/// La comparación es conservadora: query y candidato deben declarar el mismo
/// conjunto; si el calificador aparece de un solo lado, no hay sugerencia.
const _variantByToken = <String, String>{
  'bulgara': 'bulgara',
  'bulgaro': 'bulgara',
  'rumano': 'rumano',
  'rumana': 'rumano',
  'inclinado': 'inclinado',
  'inclinada': 'inclinado',
  'declinado': 'declinado',
  'declinada': 'declinado',
  'goblet': 'goblet',
  'frontal': 'frontal',
  'sumo': 'sumo',
  'convencional': 'convencional',
  'unilateral': 'unilateral',
  'plano': 'plano',
  'plana': 'plano',
  'zercher': 'zercher',
  'hack': 'hack',
};

Set<String> _meaningfulTokens(String normalized) => normalized
    .split(' ')
    .where((token) => token.length >= 3 && !_stopwords.contains(token))
    .toSet();

Set<String> _classifiedTokens(
  Iterable<String> labels,
  Map<String, String> classification,
) =>
    labels
        .expand((label) => normalize(label).split(' '))
        .map((token) => classification[token])
        .whereType<String>()
        .toSet();

bool _isCompatible(String query, MatcherExercise candidate) {
  final labels = <String>[candidate.name, ...candidate.aliases];
  final queryEquipment = _classifiedTokens([query], _equipmentByToken);
  final candidateEquipment = _classifiedTokens(labels, _equipmentByToken);

  // Si el Excel declara equipo, el catálogo debe declarar exactamente ese
  // equipo: ni omitirlo ni sumar uno distinto.
  if (queryEquipment.isNotEmpty &&
      !_sameSet(queryEquipment, candidateEquipment)) {
    return false;
  }

  final queryVariants = _classifiedTokens([query], _variantByToken);
  final candidateVariants = _classifiedTokens(labels, _variantByToken);
  return _sameSet(queryVariants, candidateVariants);
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

MatcherExercise? _bestFuzzySuggestion(String query, _Index index) {
  final queryTokens = _meaningfulTokens(query);
  if (queryTokens.isEmpty) return null;

  final scores = <String, int>{};
  for (final exercise in index.exercises) {
    if (!_isCompatible(query, exercise)) continue;
    final labels = <String>[exercise.name, ...exercise.aliases];
    final score = labels
        .map((label) => queryTokens
            .intersection(_meaningfulTokens(normalize(label)))
            .length)
        .fold<int>(0, (best, value) => value > best ? value : best);
    if (score > 0) scores[exercise.id] = score;
  }

  if (scores.isEmpty) return null;
  final bestScore = scores.values.reduce((a, b) => a > b ? a : b);
  if (bestScore < (queryTokens.length / 2).ceil()) return null;
  final bestIds = scores.entries
      .where((entry) => entry.value == bestScore)
      .map((entry) => entry.key)
      .toList();
  if (bestIds.length != 1) return null;
  return index.exercises
      .firstWhere((exercise) => exercise.id == bestIds.single);
}

MatchResult matchExercises(
  List<RawParsedDay> rawDays,
  List<MatcherExercise> exercises,
) {
  final index = _Index.build(exercises);
  final unmatched = <ParsedPlanUnmatched>[];
  final days = <ParsedPlanDay>[];

  for (final day in rawDays) {
    final items = <ParsedPlanItem>[];
    for (final item in day.items) {
      final key = normalize(item.rowName);
      final exercise = index.byName[key];
      final suggestion =
          exercise == null ? _bestFuzzySuggestion(key, index) : null;

      if (exercise == null) {
        unmatched.add(ParsedPlanUnmatched(
          dayNumber: day.dayNumber,
          rowName: item.rowName,
        ));
        items.add(ParsedPlanItem(
          rowName: item.rowName,
          sets: item.sets,
          repsMin: item.repsMin,
          repsMax: item.repsMax,
          weightKg: item.weightKg,
          restSec: item.restSec,
          notes: item.notes,
          exerciseId: null,
          exerciseName: item.rowName,
          muscleGroup: null,
          suggestedExerciseId: suggestion?.id,
          suggestedExerciseName: suggestion?.name,
          suggestedMuscleGroup: suggestion?.muscleGroup,
        ));
      } else {
        items.add(ParsedPlanItem(
          rowName: item.rowName,
          sets: item.sets,
          repsMin: item.repsMin,
          repsMax: item.repsMax,
          weightKg: item.weightKg,
          restSec: item.restSec,
          notes: item.notes,
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          muscleGroup: exercise.muscleGroup,
        ));
      }
    }
    days.add(ParsedPlanDay(dayNumber: day.dayNumber, items: items));
  }

  return MatchResult(days: days, unmatched: unmatched);
}
