import '../../domain/set_limits.dart';

/// Lo que se entiende de una línea como `banca 4x10 60` o
/// `sentadilla 4x10, 8, 6, 4  55, 45, 35, 25`.
///
/// El parser es TOLERANTE y nunca el único camino: el picker completo sigue
/// estando. Si no reconoce nada, lo que sobra es la búsqueda y el ejercicio
/// entra con la prescripción por defecto — nunca falla, nunca bloquea.
class QuickEntry {
  const QuickEntry({
    required this.query,
    required this.sets,
    this.reps = const [],
    this.weights = const [],
  });

  /// Lo que queda fuera del patrón: la búsqueda contra el catálogo.
  final String query;

  /// Cuántas series entran.
  final int sets;

  /// Repeticiones POR SET. Vacía cuando la línea no las dice.
  ///
  /// `4x10` da `[10]` y `4x10, 8, 6, 4` da `[10, 8, 6, 4]` — una pirámide
  /// descendente, que es como se escribe una en papel.
  final List<int> reps;

  /// Peso POR SET, en kilos. Vacía cuando la línea no lo dice — y vacío es un
  /// estado legítimo: peso corporal se prescribe así.
  ///
  /// `4x10 55, 45, 35, 25` es una descarga.
  final List<double> weights;

  /// Series cuando la línea no las dice. Tres es lo que trae un ejercicio
  /// agregado por el picker.
  static const int kDefaultSets = 3;

  /// True cuando la línea trae alguna prescripción, no sólo un nombre.
  bool get tienePrescripcion => reps.isNotEmpty || weights.isNotEmpty;

  /// Las repeticiones del set [i], o null si la línea no las dice.
  ///
  /// Una lista más corta que la cantidad de sets REPITE su último valor:
  /// `4x10` son cuatro sets de diez, no uno de diez y tres vacíos. Es la
  /// lectura que hace cualquiera al escribirlo.
  int? repsDeSet(int i) => _enPosicion(reps, i);

  /// El peso del set [i], o null. Misma regla de repetición que [repsDeSet].
  double? pesoDeSet(int i) => _enPosicion(weights, i);

  static T? _enPosicion<T>(List<T> valores, int i) {
    if (valores.isEmpty) return null;
    return i < valores.length ? valores[i] : valores.last;
  }

  @override
  String toString() =>
      'QuickEntry(query: $query, sets: $sets, reps: $reps, kg: $weights)';

  @override
  bool operator ==(Object other) =>
      other is QuickEntry &&
      other.query == query &&
      other.sets == sets &&
      _mismaLista(other.reps, reps) &&
      _mismaLista(other.weights, weights);

  static bool _mismaLista<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        query,
        sets,
        Object.hashAll(reps),
        Object.hashAll(weights),
      );
}

/// `4x10`, `4 X 10`, `4×10`: cuántas series por cuántas repeticiones.
///
/// La `×` tipográfica entra porque el teclado de iOS la ofrece en el mismo
/// lugar que la `x`, y una línea escrita con ella no puede fallar en silencio.
final RegExp _kNumeroPorNumero = RegExp(r'(\d+)\s*[xX×]\s*(\d+)');

/// El siguiente valor de una lista: `,45`, `, 45`.
///
/// **La coma SIEMPRE separa; el decimal es el punto.** La primera versión pedía
/// un espacio detrás de la coma para poder distinguirla del decimal de es-AR
/// —`60,5` contra `60, 45`—, y esa regla se rompió en device apenas se probó:
/// escribir `55,45,35,25` de un tirón es lo natural en un teléfono, y el
/// parser lo leía como un único peso de 55,45.
///
/// El intercambio está elegido: una descarga por set se escribe seguido, un
/// peso fraccionario casi nunca. Quien necesite 62 y medio escribe `62.5`, y
/// la celda de la tabla sigue aceptando coma cuando se edita a mano.
final RegExp _kResto = RegExp(r'^\s*,\s*(\d+(?:\.\d+)?)');

/// Un número suelto. Decimal con punto — ver [_kResto].
final RegExp _kNumero = RegExp(r'^\s+(\d+(?:\.\d+)?)');

/// Tope de series que el parser acepta de una línea.
///
/// LOCAL a propósito: el dominio no tiene una constante para esto —
/// `set_limits.dart` acota repeticiones y peso, no cuántas series lleva un
/// ejercicio— y agregarle una sería cambiar el dominio, que el límite duro de
/// la épica excluye. Acá sólo evita que un `999x10` arme novecientas filas de
/// un tipeo.
const int kMaxSetsEntradaRapida = 20;

/// Lee una línea de entrada rápida.
///
/// **La gramática en una frase: la COMA encadena la misma lista, el ESPACIO
/// abre la siguiente.**
///
/// ```
/// banca 4x10                     4 sets · 10 reps
/// banca 4x10 60                  4 sets · 10 reps · 60 kg
/// banca 4x10,8,6,4               4 sets · 10/8/6/4 reps        (pirámide)
/// banca 4x10 55,45,35,25         4 sets · 10 reps · descarga
/// banca 4x10,8,6,4 55,45         4 sets · 10/8/6/4 · 55/45/45/45
/// banca 4x10 62.5                el decimal va con PUNTO
/// ```
///
/// Los espacios después de las comas son opcionales: `55,45` y `55, 45` se
/// leen igual.
///
/// Nunca tira: una línea que no matchea devuelve la línea entera como búsqueda
/// y la prescripción por defecto. Los valores se recortan a los topes del
/// dominio en vez de rechazarse — el mismo criterio que
/// `BoundedNumberFormatter` aplica al tipear en una celda.
QuickEntry parseQuickEntry(String input) {
  final texto = input.trim();
  if (texto.isEmpty) {
    return const QuickEntry(query: '', sets: QuickEntry.kDefaultSets);
  }

  final match = _kNumeroPorNumero.firstMatch(texto);
  if (match == null) {
    return QuickEntry(query: texto, sets: QuickEntry.kDefaultSets);
  }

  final declarados = int.tryParse(match.group(1)!) ?? QuickEntry.kDefaultSets;
  final primeraRep = int.tryParse(match.group(2)!);

  // Todo lo que sigue al `NxM` se lee como listas; lo que sobra al final, más
  // lo que había antes, es el nombre.
  var cursor = match.end;
  final reps = <int>[if (primeraRep != null) primeraRep];

  // Las comas inmediatas siguen la lista de REPETICIONES.
  while (true) {
    final m = _kResto.firstMatch(texto.substring(cursor));
    if (m == null) break;
    final n = int.tryParse(m.group(1)!.split('.').first);
    if (n == null) break;
    reps.add(n);
    cursor += m.end;
  }

  // Un número separado por ESPACIO abre la lista de PESOS, que a su vez puede
  // encadenar con comas.
  final weights = <double>[];
  final primerPeso = _kNumero.firstMatch(texto.substring(cursor));
  if (primerPeso != null) {
    final p = _peso(primerPeso.group(1));
    if (p != null) {
      weights.add(p);
      cursor += primerPeso.end;
      while (true) {
        final m = _kResto.firstMatch(texto.substring(cursor));
        if (m == null) break;
        final q = _peso(m.group(1));
        if (q == null) break;
        weights.add(q);
        cursor += m.end;
      }
    }
  }

  // Lo que rodea a todo el patrón es el nombre. Se une con un espacio porque
  // los números pueden estar en el medio: "4x10 press banca" y
  // "press 4x10 banca" tienen que dar la misma búsqueda.
  final query = (texto.substring(0, match.start) + texto.substring(cursor))
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  // Cuántos sets: lo declarado, pero nunca menos que la lista más larga. Quien
  // escribe `3x10, 8, 6, 4` está pidiendo cuatro series aunque haya tecleado
  // un 3 — la lista es más específica que el número.
  final sets = [
    declarados,
    reps.length,
    weights.length,
  ].reduce((a, b) => a > b ? a : b).clamp(1, kMaxSetsEntradaRapida);

  return QuickEntry(
    query: query,
    sets: sets,
    reps: [for (final r in reps) r.clamp(1, kMaxReps)],
    weights: weights,
  );
}

double? _peso(String? raw) {
  if (raw == null) return null;
  // El `replaceAll` queda por si algún día el patrón vuelve a capturar comas:
  // hoy no lo hace, porque la coma pasó a separar la lista. Ver [_kResto].
  final n = double.tryParse(raw.replaceAll(',', '.'));
  if (n == null || n <= 0) return null;
  return clampWeightKg(n);
}
