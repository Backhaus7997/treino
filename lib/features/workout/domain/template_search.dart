import '../../profile/domain/experience_level.dart';
import 'routine.dart';
import 'routine_goal.dart';

/// Búsqueda por texto sobre el catálogo de EXPLORAR (#1412).
///
/// Dominio puro, sin Flutter ni Riverpod: la presentación sólo la cablea. El
/// catálogo ya está cargado en memoria (50 docs), así que filtrar es una
/// cuenta local — cero queries nuevas a Firestore, cero índices.
///
/// ## Qué mira una plantilla
///
/// En este orden de peso (el orden de arriba es el de relevancia editorial;
/// hoy NO se usa para reordenar, ver más abajo):
///
///  1. nombre de la plantilla, `split` y nombre de cada día,
///  2. grupo muscular de los slots (`slots[].muscleGroup`), traducido por
///     [_muscleSynonyms] — "pecho" encuentra un PPL cuyo nombre no lo dice,
///  3. nombre de cada ejercicio,
///  4. objetivo y nivel, con su vocabulario en español.
///
/// ## Qué NO hace
///
/// No ordena. El orden por afinidad del mini-onboarding (#635) se conserva
/// entre los resultados: esto es un FILTRO, y filtrar una lista ya ordenada
/// preserva su orden. Por eso el peso de arriba no se traduce en puntaje.
///
/// ## Reglas de matching
///
///  * Se normaliza todo: minúsculas y sin acentos ("glúteos" = "gluteos").
///  * Plural tolerante: cada palabra se reduce a su singular aproximado
///    ("piernas"→"pierna", "flexiones"→"flexion") de los DOS lados.
///  * Cada palabra de la consulta tiene que aparecer (AND), en cualquier
///    orden, como PREFIJO de alguna palabra de la plantilla — así "sentad"
///    ya encuentra "sentadilla" mientras el atleta todavía tipea.
///  * Las palabras de relleno ("de", "y", "tren"…) se ignoran.
abstract final class TemplateSearch {
  /// Minúsculas y sin diacríticos. `ñ` pasa a `n` (como en `foldSearch` de
  /// la biblioteca de ejercicios): quien escribe "anos" y "años" busca igual.
  static String normalize(String input) {
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const to = 'aaaaaeeeeiiiiooooouuuunc';
    final buf = StringBuffer();
    for (final code in input.toLowerCase().runes) {
      final ch = String.fromCharCode(code);
      final idx = from.indexOf(ch);
      buf.write(idx >= 0 ? to[idx] : ch);
    }
    return buf.toString();
  }

  /// Singular aproximado de una palabra YA normalizada.
  ///
  /// No es lematización: es lo justo para que "piernas"/"pierna",
  /// "glúteos"/"gluteo" y "flexiones"/"flexion" coincidan. Se aplica a la
  /// consulta y al texto de la plantilla, así que los casos raros
  /// ("lunges"→"lung") siguen coincidiendo entre sí.
  static String stem(String word) {
    if (word.length <= 3) return word;
    if (word.endsWith('es') && word.length > 4) {
      // consonante + "es": flexiones→flexion, dolores→dolor. Con vocal antes
      // ("clases", "pesas") alcanza con sacar la "s".
      final before = word[word.length - 3];
      if (!'aeiou'.contains(before)) return word.substring(0, word.length - 2);
    }
    if (word.endsWith('s')) return word.substring(0, word.length - 1);
    return word;
  }

  static final _nonWord = RegExp(r'[^a-z0-9]+');

  /// Palabras normalizadas y reducidas de [text], sin vacías.
  static List<String> _words(String text) => [
        for (final w in normalize(text).split(_nonWord))
          if (w.isNotEmpty) stem(w),
      ];

  /// Relleno que no discrimina nada: "pecho y espalda", "tren inferior".
  static const _stopwords = {
    'de',
    'del',
    'la',
    'el',
    'los',
    'las',
    'y',
    'e',
    'con',
    'para',
    'en',
    'un',
    'una',
    'tren',
  };

  /// Las palabras que cuentan de una consulta.
  static List<String> queryTokens(String query) => [
        for (final w in _words(query))
          if (!_stopwords.contains(w)) w,
      ];

  /// `true` si [query] no tiene nada que filtrar (vacía o sólo relleno).
  static bool isBlank(String query) => queryTokens(query).isEmpty;

  /// Español → claves canónicas de `MuscleGroup.key` (lo que guarda
  /// `slots[].muscleGroup`; el catálogo sembrado usa además `fullbody`).
  ///
  /// Las claves ya están en forma "stem" (singular, sin acentos), porque se
  /// comparan contra la consulta reducida.
  static const Map<String, Set<String>> _muscleSynonyms = {
    // Empuje / tracción
    'pecho': {'chest'},
    'pectoral': {'chest'},
    'espalda': {'back'},
    'dorsal': {'back'},
    'dorso': {'back'},
    'lat': {'back'},
    'trapecio': {'back'},
    'hombro': {'shoulders'},
    'deltoide': {'shoulders'},
    // Brazos
    'brazo': {'biceps', 'triceps'},
    'bicep': {'biceps'},
    'tricep': {'triceps'},
    // Piernas
    'pierna': {'quads', 'hamstrings', 'glutes', 'calves'},
    'cuadricep': {'quads'},
    'cuadri': {'quads'},
    'isquio': {'hamstrings'},
    'isquiotibial': {'hamstrings'},
    'femoral': {'hamstrings'},
    'gluteo': {'glutes'},
    'pantorrilla': {'calves'},
    'gemelo': {'calves'},
    'soleo': {'calves'},
    // Centro
    'abdomen': {'core'},
    'abdominal': {'core'},
    'abs': {'core'},
    'core': {'core'},
    // Resto
    'cardio': {'cardio'},
    'torso': {'chest', 'back', 'shoulders', 'biceps', 'triceps'},
    'superior': {'chest', 'back', 'shoulders', 'biceps', 'triceps'},
    'inferior': {'quads', 'hamstrings', 'glutes', 'calves'},
    'completo': {'full_body', 'fullbody'},
    'cuerpo': {'full_body', 'fullbody'},
  };

  /// Objetivo → vocabulario en español con el que alguien lo buscaría.
  static const Map<RoutineGoal, String> _goalWords = {
    RoutineGoal.health: 'salud',
    RoutineGoal.injuryPrevention: 'prevencion lesion lesiones',
    RoutineGoal.aesthetics: 'estetica fisico',
    RoutineGoal.sport: 'deporte deportivo rendimiento',
    RoutineGoal.wellbeing: 'bienestar',
  };

  static const Map<ExperienceLevel, String> _levelWords = {
    ExperienceLevel.beginner: 'principiante inicial',
    ExperienceLevel.intermediate: 'intermedio',
    ExperienceLevel.advanced: 'avanzado',
  };

  /// Prefijo en cualquiera de los dos sentidos: "sentad" ⊂ "sentadilla", y
  /// "lunge" ~ "lunges" (el segundo sólo con palabras largas, para que
  /// "pres" no capture "presion" ni "es" capture todo).
  static bool _wordMatches(String haystackWord, String token) =>
      haystackWord.startsWith(token) ||
      (haystackWord.length >= 4 && token.startsWith(haystackWord));

  /// Claves de músculo que [token] nombra, o vacío.
  ///
  /// Con 3+ letras también acepta prefijo de la palabra clave ("pec"→pecho,
  /// "glut"→glúteos) para que el resultado aparezca mientras se tipea.
  static Set<String> _musclesNamedBy(String token) {
    final exact = _muscleSynonyms[token];
    if (exact != null) return exact;
    if (token.length < 3) return const {};
    final out = <String>{};
    for (final e in _muscleSynonyms.entries) {
      if (e.key.startsWith(token)) out.addAll(e.value);
    }
    return out;
  }

  /// ¿[routine] responde a [query]?
  ///
  /// Una consulta en blanco responde a todo.
  static bool matches(Routine routine, String query) {
    final tokens = queryTokens(query);
    if (tokens.isEmpty) return true;
    final index = _Index.of(routine);
    return tokens.every(index.satisfies);
  }

  /// Filtra [items] conservando su orden. [routineOf] saca la rutina de cada
  /// elemento, así sirve igual para `List<Routine>` que para los
  /// `TemplateEntry` de la grilla.
  static List<T> filter<T>(
    List<T> items,
    String query,
    Routine Function(T item) routineOf,
  ) {
    final tokens = queryTokens(query);
    if (tokens.isEmpty) return items;
    return [
      for (final item in items)
        if (tokens.every(_Index.of(routineOf(item)).satisfies)) item,
    ];
  }
}

/// Lo buscable de una plantilla, ya normalizado.
class _Index {
  _Index._(this._words, this._muscles);

  final Set<String> _words;
  final Set<String> _muscles;

  factory _Index.of(Routine r) {
    final words = <String>{
      ...TemplateSearch._words(r.name),
      if (r.split != null) ...TemplateSearch._words(r.split!),
    };
    final muscles = <String>{};
    for (final day in r.days) {
      words.addAll(TemplateSearch._words(day.name));
      for (final slot in day.slots) {
        words.addAll(TemplateSearch._words(slot.exerciseName));
        muscles.add(slot.muscleGroup.trim().toLowerCase());
      }
    }
    for (final g in r.goals) {
      final w = TemplateSearch._goalWords[g];
      if (w != null) words.addAll(TemplateSearch._words(w));
    }
    final level = TemplateSearch._levelWords[r.level];
    if (level != null) words.addAll(TemplateSearch._words(level));
    return _Index._(words, muscles);
  }

  /// Un token se satisface por texto (nombre, día, ejercicio, objetivo,
  /// nivel) o por un músculo que algún slot trabaja.
  bool satisfies(String token) {
    for (final w in _words) {
      if (TemplateSearch._wordMatches(w, token)) return true;
    }
    final named = TemplateSearch._musclesNamedBy(token);
    if (named.isEmpty) return false;
    return named.any(_muscles.contains);
  }
}
