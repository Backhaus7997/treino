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
  _Index._(this.byName, this.exercises)
      : byId = {for (final ex in exercises) ex.id: ex};
  final Map<String, MatcherExercise> byName;
  final Map<String, MatcherExercise> byId;
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

/// Tokens que cuentan para el score: sin stopwords ni palabras de < 3
/// letras, y con el equipo en su forma canónica ("pesa rusa" y "kettlebell"
/// valen lo mismo, y "pesa" + "rusa" cuentan una sola vez).
Set<String> _meaningfulTokens(String normalized) => normalized
    .split(' ')
    .where((token) => token.length >= 3 && !_stopwords.contains(token))
    .map((token) => _equipmentByToken[token] ?? token)
    .toSet();

Set<String> _classifiedTokens(
  String normalized,
  Map<String, String> classification,
) =>
    normalized
        .split(' ')
        .map((token) => classification[token])
        .whereType<String>()
        .toSet();

/// Compatibilidad entre lo que escribió el entrenador y UNA etiqueta del
/// catálogo (nombre o alias). Se evalúa por etiqueta, no sobre la unión de
/// nombre + alias: si no, el alias "Sentadilla goblet" le prestaría su
/// calificador al ejercicio "Sentadilla con barra".
bool _isCompatibleLabel(String query, String normalizedLabel) {
  final queryEquipment = _classifiedTokens(query, _equipmentByToken);
  // Si el Excel declara equipo, la etiqueta debe declarar exactamente ese
  // equipo: ni omitirlo ni sumar uno distinto.
  if (queryEquipment.isNotEmpty &&
      !_sameSet(
        queryEquipment,
        _classifiedTokens(normalizedLabel, _equipmentByToken),
      )) {
    return false;
  }
  // Variantes: el mismo conjunto de ambos lados (presente de un solo lado
  // => no hay sugerencia).
  return _sameSet(
    _classifiedTokens(query, _variantByToken),
    _classifiedTokens(normalizedLabel, _variantByToken),
  );
}

/// Veto determinístico, público: [rawName] (lo que escribió el PF) y [label]
/// (nombre o alias del catálogo) son compatibles si declaran el mismo equipo y
/// las mismas variantes. Normaliza los dos lados. No mide parecido: sólo dice
/// si la etiqueta NO puede ser ese ejercicio.
bool isCompatibleLabel(String rawName, String label) =>
    _isCompatibleLabel(normalize(rawName), normalize(label));

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

MatcherExercise? _bestFuzzySuggestion(String query, _Index index) {
  final queryTokens = _meaningfulTokens(query);
  if (queryTokens.isEmpty) return null;

  final scores = <String, int>{};
  for (final exercise in index.exercises) {
    var best = 0;
    for (final label in <String>[exercise.name, ...exercise.aliases]) {
      final normalizedLabel = normalize(label);
      if (!_isCompatibleLabel(query, normalizedLabel)) continue;
      final score =
          queryTokens.intersection(_meaningfulTokens(normalizedLabel)).length;
      if (score > best) best = score;
    }
    if (best > 0) scores[exercise.id] = best;
  }

  if (scores.isEmpty) return null;
  final bestScore = scores.values.reduce((a, b) => a > b ? a : b);
  if (bestScore < (queryTokens.length / 2).ceil()) return null;
  final bestIds = scores.entries
      .where((entry) => entry.value == bestScore)
      .map((entry) => entry.key)
      .toList();
  // Empate => ninguna sugerencia: nunca se elige al azar.
  if (bestIds.length != 1) return null;
  return index.exercises
      .firstWhere((exercise) => exercise.id == bestIds.single);
}

/// Veredicto del matcher para UN nombre: coincidencia exacta/alias
/// ([exercise]), sugerencia confirmable ([suggestion]) o ninguna de las dos.
class ExerciseNameMatch {
  const ExerciseNameMatch({this.exercise, this.suggestion});
  final MatcherExercise? exercise;
  final MatcherExercise? suggestion;
}

/// Matcher de nombres sueltos sobre un catálogo ya indexado. Es la misma
/// política de [matchExercises] (#1455: exacto o alias se asigna solo,
/// aproximado sólo sugiere, nunca se adivina una variante), pero por nombre,
/// para que cada componente de una superserie pase por separado.
class ExerciseNameMatcher {
  ExerciseNameMatcher(List<MatcherExercise> exercises)
      : _index = _Index.build(exercises);

  final _Index _index;

  ExerciseNameMatch match(String rawName) {
    final key = normalize(rawName);
    final exercise = _index.byName[key];
    if (exercise != null) return ExerciseNameMatch(exercise: exercise);
    return ExerciseNameMatch(suggestion: _bestFuzzySuggestion(key, _index));
  }

  /// Valida un candidato externo (p. ej. el que propone el LLM del import de
  /// PDF) para [rawName]: devuelve el ejercicio si [id] existe en el catálogo
  /// y alguna de sus etiquetas pasa el veto de [isCompatibleLabel]; si no,
  /// null. El resultado es SÓLO una sugerencia por confirmar (#1455): nunca
  /// se autoasigna.
  MatcherExercise? suggestFromCandidate(String id, String rawName) {
    final exercise = _index.byId[id];
    if (exercise == null) return null;
    final query = normalize(rawName);
    final compatible = <String>[exercise.name, ...exercise.aliases]
        .any((label) => _isCompatibleLabel(query, normalize(label)));
    return compatible ? exercise : null;
  }
}
