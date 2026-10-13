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
/// Nombre de la plantilla, `split` y nombre de cada día; nombre de cada
/// ejercicio; grupo muscular de los slots (`slots[].muscleGroup`, traducido
/// por [_muscleSynonyms] — "pecho" encuentra un PPL cuyo nombre no lo dice);
/// y objetivo y nivel con su vocabulario en español.
///
/// ## Relevancia (ordena, no sólo filtra)
///
/// El catálogo es parejo: casi toda plantilla tiene algún slot de pecho, así
/// que filtrar sin ordenar devolvía 46 de 50 en cualquier orden. Por eso los
/// resultados se rankean. Tiers por palabra, de mayor a menor:
///
///  1. nombre / split / nombre de día (1000),
///  2. nombre de ejercicio (500),
///  3. sólo músculo: 100 + 300 × (slots del grupo / slots totales),
///  4. objetivo o nivel (50, débil).
///
/// Corte de ruido: si una palabra matchea SÓLO por músculo y el grupo ocupa
/// menos del 10% de los slots, no matchea ([minMuscleShare]). Un match por
/// nombre pasa siempre, sin importar el porcentaje.
///
/// Con varias palabras todas deben matchear y el puntaje es la suma.
/// El desempate es la posición de entrada, o sea el orden por afinidad.
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

  /// Puntaje por tier de una palabra. Los tiers están separados para que un
  /// tier más alto siempre gane al de abajo (el muscular llega a 400 como
  /// máximo, el de ejercicio arranca en 500).
  static const double _tierName = 1000;
  static const double _tierExercise = 500;
  static const double _tierMuscleBase = 100;
  static const double _tierMuscleSpan = 300; // base + span*share, share<=1
  static const double _tierWeak = 50;

  /// Piso de participación: si una palabra sólo matchea por músculo y ese
  /// grupo ocupa menos de esta fracción de los slots, NO matchea. Evita que
  /// "pecho" traiga una plantilla de glúteos con 1 ejercicio de pecho en 27.
  static const double minMuscleShare = 0.10;

  /// Relevancia de [routine] para [query], o `null` si no matchea.
  ///
  /// Cada palabra tiene que matchear (AND) y el puntaje de la plantilla es la
  /// SUMA de los puntajes por palabra: una plantilla que matchea todas las
  /// palabras en el nombre le gana a una que matchea una en el nombre y otra
  /// sólo por músculo. Consulta en blanco: `0`.
  static double? score(Routine routine, String query) {
    final tokens = queryTokens(query);
    if (tokens.isEmpty) return 0;
    return _Index.of(routine).scoreAll(tokens);
  }

  /// ¿[routine] responde a [query]? (blanco responde a todo).
  static bool matches(Routine routine, String query) =>
      score(routine, query) != null;

  /// Filtra Y ORDENA por relevancia (mayor primero). El empate se resuelve
  /// por la posición original en [items], o sea que el orden por afinidad
  /// del mini-onboarding actúa de desempate. Sin consulta devuelve [items]
  /// sin tocar. [routineOf] saca la rutina de cada elemento.
  static List<T> filter<T>(
    List<T> items,
    String query,
    Routine Function(T item) routineOf,
  ) {
    final tokens = queryTokens(query);
    if (tokens.isEmpty) return items;
    final scored = <({T item, double score, int position})>[];
    for (var i = 0; i < items.length; i++) {
      final s = _Index.of(routineOf(items[i])).scoreAll(tokens);
      if (s != null) scored.add((item: items[i], score: s, position: i));
    }
    // List.sort no es estable en Dart: el desempate va explícito.
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.position.compareTo(b.position);
    });
    return [for (final e in scored) e.item];
  }
}

/// Lo buscable de una plantilla, ya normalizado.
class _Index {
  _Index._(
    this._nameWords,
    this._exerciseWords,
    this._weakWords,
    this._muscleCounts,
    this._totalSlots,
  );

  /// Nombre, split y nombres de día.
  final Set<String> _nameWords;
  final Set<String> _exerciseWords;

  /// Objetivo y nivel.
  final Set<String> _weakWords;

  /// Slots por clave de músculo y total de slots (todos los días).
  final Map<String, int> _muscleCounts;
  final int _totalSlots;

  factory _Index.of(Routine r) {
    final nameWords = <String>{
      ...TemplateSearch._words(r.name),
      if (r.split != null) ...TemplateSearch._words(r.split!),
    };
    final exerciseWords = <String>{};
    final counts = <String, int>{};
    var total = 0;
    for (final day in r.days) {
      nameWords.addAll(TemplateSearch._words(day.name));
      for (final slot in day.slots) {
        exerciseWords.addAll(TemplateSearch._words(slot.exerciseName));
        final key = slot.muscleGroup.trim().toLowerCase();
        counts[key] = (counts[key] ?? 0) + 1;
        total++;
      }
    }
    final weak = <String>{};
    for (final g in r.goals) {
      final w = TemplateSearch._goalWords[g];
      if (w != null) weak.addAll(TemplateSearch._words(w));
    }
    final level = TemplateSearch._levelWords[r.level];
    if (level != null) weak.addAll(TemplateSearch._words(level));
    return _Index._(nameWords, exerciseWords, weak, counts, total);
  }

  static bool _any(Set<String> words, String token) =>
      words.any((w) => TemplateSearch._wordMatches(w, token));

  /// Participación (0..1) de los grupos que [token] nombra, o `null` si no
  /// nombra ninguno. Los slots de la plantilla son el denominador.
  double? _muscleShare(String token) {
    final named = TemplateSearch._musclesNamedBy(token);
    if (named.isEmpty) return null;
    if (_totalSlots == 0) return 0;
    var hits = 0;
    for (final key in named) {
      hits += _muscleCounts[key] ?? 0;
    }
    return hits / _totalSlots;
  }

  /// Puntaje de una palabra, o `null` si no matchea. Gana el mejor tier.
  ///
  /// Cuando la palabra además nombra un músculo, los tiers de nombre y de
  /// ejercicio suman un bonus de hasta 99 puntos por participación, sólo para
  /// ordenar DENTRO del tier (nunca lo cruza): entre dos plantillas con
  /// "pecho" en el nombre, sube la que más pecho entrena.
  double? _scoreToken(String token) {
    final share = _muscleShare(token);
    final bonus = 99 * (share ?? 0);
    if (_any(_nameWords, token)) return TemplateSearch._tierName + bonus;
    // Una palabra de músculo dentro de un nombre de ejercicio no es evidencia
    // de que la plantilla lo entrene ("Jalón al pecho" es de espalda), así
    // que también pasa por el corte de participación.
    final weakMuscle = share != null && share < TemplateSearch.minMuscleShare;
    if (!weakMuscle && _any(_exerciseWords, token)) {
      return TemplateSearch._tierExercise + bonus;
    }
    double? best;
    if (share != null && share >= TemplateSearch.minMuscleShare) {
      best = TemplateSearch._tierMuscleBase +
          TemplateSearch._tierMuscleSpan * share;
    }
    if (_any(_weakWords, token)) {
      best = best == null
          ? TemplateSearch._tierWeak
          : (best > TemplateSearch._tierWeak ? best : TemplateSearch._tierWeak);
    }
    return best;
  }

  double? scoreAll(List<String> tokens) {
    var sum = 0.0;
    for (final t in tokens) {
      final s = _scoreToken(t);
      if (s == null) return null;
      sum += s;
    }
    return sum;
  }
}
