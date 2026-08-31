import '../../domain/set_limits.dart';

/// Lo que se entiende de una línea como `banca 4x10 60`.
///
/// El parser es TOLERANTE y nunca el único camino: el picker completo sigue
/// estando. Si no reconoce nada, lo que sobra es la búsqueda y el ejercicio
/// entra con la prescripción por defecto — nunca falla, nunca bloquea.
class QuickEntry {
  const QuickEntry({
    required this.query,
    required this.sets,
    this.reps,
    this.weightKg,
  });

  /// Lo que queda fuera del patrón: la búsqueda contra el catálogo.
  final String query;

  /// Cuántas series. [kDefaultSets] cuando la línea no dice.
  final int sets;

  /// Repeticiones por serie, o null — el ejercicio entra con los sets vacíos y
  /// se completa después, como uno agregado por el picker.
  final int? reps;

  /// Peso en kilos, o null. Vacío es "sin peso" y es un estado legítimo: peso
  /// corporal se prescribe así.
  final double? weightKg;

  /// Series cuando la línea no las dice. Tres es lo que trae un ejercicio
  /// agregado por el picker.
  static const int kDefaultSets = 3;

  /// True cuando la línea trae alguna prescripción, no sólo un nombre.
  bool get tienePrescripcion => reps != null || weightKg != null;

  @override
  String toString() =>
      'QuickEntry(query: $query, sets: $sets, reps: $reps, kg: $weightKg)';

  @override
  bool operator ==(Object other) =>
      other is QuickEntry &&
      other.query == query &&
      other.sets == sets &&
      other.reps == reps &&
      other.weightKg == weightKg;

  @override
  int get hashCode => Object.hash(query, sets, reps, weightKg);
}

/// `4x10`, `4 X 10`, `4×10`, y un peso opcional detrás: `4x10 60` o `4x10 60,5`.
///
/// La `×` tipográfica entra porque el teclado de iOS la ofrece en el mismo
/// lugar que la `x`, y una línea escrita con ella no puede fallar en silencio.
final RegExp _kPatron =
    RegExp(r'(\d+)\s*[xX×]\s*(\d+)(?:\s+(\d+(?:[.,]\d+)?))?');

/// Tope de series que el parser acepta de una línea.
///
/// LOCAL a propósito: el dominio no tiene una constante para esto —
/// `set_limits.dart` acota repeticiones y peso, no cuántas series lleva un
/// ejercicio— y agregarle una sería cambiar el dominio, que el límite duro de
/// la épica excluye. Acá sólo evita que un `999x10` arme novecientas filas de
/// un tipeo. El usuario puede seguir sumando sets a mano después.
const int _kMaxSets = 20;

/// Lee una línea de entrada rápida.
///
/// Nunca tira: una línea que no matchea devuelve la línea entera como búsqueda
/// y la prescripción por defecto. Los valores se recortan a los topes del
/// dominio ([kMaxReps], [kMaxWeightKg]) en vez de rechazarse — el mismo
/// criterio que `BoundedNumberFormatter` aplica al tipear en una celda.
QuickEntry parseQuickEntry(String input) {
  final texto = input.trim();
  if (texto.isEmpty) {
    return const QuickEntry(query: '', sets: QuickEntry.kDefaultSets);
  }

  final match = _kPatron.firstMatch(texto);
  if (match == null) {
    return QuickEntry(query: texto, sets: QuickEntry.kDefaultSets);
  }

  // Lo que rodea al patrón es el nombre. Se une con un espacio porque el
  // número puede estar en el medio: "4x10 press banca" y "press 4x10 banca"
  // tienen que dar la misma búsqueda.
  final query = (texto.substring(0, match.start) + texto.substring(match.end))
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  final sets =
      _enteroAcotado(match.group(1), 1, _kMaxSets) ?? QuickEntry.kDefaultSets;
  final reps = _enteroAcotado(match.group(2), 1, kMaxReps);
  final kg = _pesoAcotado(match.group(3));

  return QuickEntry(query: query, sets: sets, reps: reps, weightKg: kg);
}

int? _enteroAcotado(String? raw, int min, int max) {
  if (raw == null) return null;
  final n = int.tryParse(raw);
  if (n == null) return null;
  return n.clamp(min, max);
}

double? _pesoAcotado(String? raw) {
  if (raw == null) return null;
  // Coma o punto: el teclado numérico de iOS ofrece coma en es-AR y el de
  // Android punto. Los dos tienen que llegar al mismo double, igual que en
  // `parseEditorWeight`.
  final n = double.tryParse(raw.replaceAll(',', '.'));
  if (n == null || n <= 0) return null;
  return clampWeightKg(n);
}
