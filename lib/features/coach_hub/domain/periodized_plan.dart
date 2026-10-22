import '../../workout/domain/set_spec.dart';

/// Borrador del import de un plan periodizado: del Excel (spec:
/// docs/plan-import-excel-periodizado.md) o del JSON que extrae el import de
/// PDF. Es el resultado de LEER el plan, antes de matchear contra el catálogo
/// y de armar la `Routine`.
///
/// Son clases planas y no freezed a propósito: no se serializan ni se
/// persisten, sólo viajan del parser al mapper y a la vista previa.

/// Gravedad de un diagnóstico. Los errores bloquean la subida; los avisos no.
enum ImportDiagnosticSeverity { error, warning }

/// Qué pasó, en forma que la vista previa puede ramificar sin parsear texto.
enum ImportDiagnosticCode {
  // ── Errores ───────────────────────────────────────────────────────────────
  unreadableFile,
  notTemplate,
  oldFormat,
  noDayHeader,
  weekColumnsNotContiguous,
  weekColumnsDuplicated,
  tooManyWeeks,
  tooManyDays,
  duplicatedDay,
  invalidDayNumber,
  exerciseOutsideBlock,
  emptyExerciseComponent,
  unreadableCell,
  atomCountMismatch,
  invalidRest,
  invalidNumber,
  noExercises,
  // ── Avisos ────────────────────────────────────────────────────────────────
  numberingGap,
  missingReps,
  emptyWeek,
  qualifierSavedAsNote,
  mixedSetKinds,
}

/// Un hallazgo del parser, con la ubicación para que el PF lo encuentre: la
/// celda en el Excel ([sheet], [row], [column]) o la página en el PDF
/// ([page]). Lo que no tiene celda ni página lleva la ubicación en el
/// [message].
class ImportDiagnostic {
  const ImportDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.sheet,
    this.row,
    this.column,
    this.page,
    this.rawValue,
  });

  final ImportDiagnosticSeverity severity;
  final ImportDiagnosticCode code;
  final String message;

  /// Hoja del Excel. Null en los hallazgos del archivo entero y en el PDF.
  final String? sheet;

  /// Fila de Excel, base 1. Null en el PDF.
  final int? row;

  /// Letra de columna de Excel (`A`, `B`, … `AA`). Null en el PDF.
  final String? column;

  /// Página del PDF, base 1, si el extractor la informó. Null en el Excel.
  final int? page;

  /// Lo que había en la celda, tal cual (sin normalizar).
  final String? rawValue;

  bool get isError => severity == ImportDiagnosticSeverity.error;

  /// `Programa!D5`, o null si el hallazgo no apunta a una celda.
  String? get cellRef =>
      (row == null || column == null) ? null : '${sheet ?? ''}!$column$row';

  /// Dónde buscarlo: la celda del Excel, `página N` del PDF, o null.
  String? get location => cellRef ?? (page == null ? null : 'página $page');

  @override
  String toString() =>
      'ImportDiagnostic(${severity.name}/${code.name}, ${location ?? '-'}, '
      '"$rawValue": $message)';
}

/// Identifica un componente de un renglón: día, [PeriodizedRow.position] del
/// renglón (fila de Excel u ordinal del PDF) e índice dentro del renglón (0 =
/// primer ejercicio de la superserie). Es una record, así que tiene igualdad
/// estructural y sirve de clave de Map.
typedef ExerciseKey = ({int dayNumber, int row, int component});

/// UN ejercicio de un renglón, con su prescripción semana por semana.
class PeriodizedExercise {
  const PeriodizedExercise({
    required this.component,
    required this.rawName,
    required this.weeks,
    this.note,
    this.emptyWeeks = const <int>{},
  });

  /// Posición dentro del renglón (0 si no es superserie).
  final int component;

  /// Nombre tal cual lo escribió el PF, ya separado por `+`.
  final String rawName;

  /// `weeks[w]` = series de la columna SEMANA w+1. Cada semana tiene al menos
  /// una serie (la celda vacía es 1 serie sin reps).
  final List<List<SetSpec>> weeks;

  /// Calificadores (`c/pierna`…) sin repetir, para la nota del slot.
  final String? note;

  /// Semanas (0-based) cuya celda estaba vacía: salen en rojo en la vista
  /// previa ("falta cargar reps").
  final Set<int> emptyWeeks;
}

/// Un renglón del plan: uno o varios ejercicios (superserie).
class PeriodizedRow {
  const PeriodizedRow({
    required this.position,
    required this.number,
    required this.restSeconds,
    required this.exercises,
  });

  /// Identifica el renglón dentro del día, base 1: la fila de Excel en el
  /// Excel; el ordinal del renglón en el día en el PDF (que no tiene filas).
  final int position;

  /// Valor de la columna `N°`. Null = sin número = calentamiento.
  final int? number;

  /// Descanso de la fila (60 si la celda venía vacía).
  final int restSeconds;

  final List<PeriodizedExercise> exercises;

  bool get isWarmup => number == null;
  bool get isSuperset => exercises.length > 1;
}

class PeriodizedDay {
  const PeriodizedDay({
    required this.dayNumber,
    this.headerRow,
    required this.rows,
  });

  final int dayNumber;

  /// Fila de Excel (base 1) del encabezado `DÍA N`. Null en el PDF.
  final int? headerRow;

  final List<PeriodizedRow> rows;
}

/// El plan leído: semanas y bloques de día. Sin nada del catálogo.
class PeriodizedPlan {
  const PeriodizedPlan({required this.numWeeks, required this.days});

  final int numWeeks;
  final List<PeriodizedDay> days;
}

/// Salida del parser: el borrador y TODOS los diagnósticos.
class PeriodizedParseResult {
  const PeriodizedParseResult({required this.plan, required this.diagnostics});

  /// Null cuando ni siquiera se pudo determinar el esquema (no es la
  /// plantilla, no hay encabezado). Con errores de celda viene igual, sin los
  /// renglones que fallaron; igual NO se debe importar si [errors] no está
  /// vacío.
  final PeriodizedPlan? plan;
  final List<ImportDiagnostic> diagnostics;

  List<ImportDiagnostic> get errors =>
      diagnostics.where((d) => d.isError).toList(growable: false);
  List<ImportDiagnostic> get warnings =>
      diagnostics.where((d) => !d.isError).toList(growable: false);

  /// Se puede seguir al matcher/mapper: hay plan y ningún error.
  bool get canImport => plan != null && errors.isEmpty;
}
