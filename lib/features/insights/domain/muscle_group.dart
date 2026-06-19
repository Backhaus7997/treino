/// Las 10 categorías display que muestra la pantalla de Insights.
///
/// Mismas categorías granulares que el exercise picker
/// (`lib/features/workout/domain/muscle_group.dart`) MENOS `cardio` (los sets
/// de cardio no son comparables con sets de fuerza, decisión 1B 2026-06-19)
/// y `cuerpoCompleto` (un set "cuerpo completo" no es atribuible a un grupo
/// puntual — los ejercicios full-body se cuentan a través de su slot real en
/// la rutina, no acá).
///
/// Los `muscleGroup` granulares persistidos en el catálogo + custom exercises
/// (`chest`, `back`, `quads`, `glutes`, `hamstrings`, `calves`, `biceps`,
/// `triceps`, `shoulders`, `core`/`abs`) se mapean a estos 10 valores vía la
/// extension de abajo.
///
/// Strings legacy de la taxonomía anterior (`brazos`, `piernas`, etc.) NO se
/// remapean — devuelven `null` y el provider los skipea silenciosamente
/// (cutoff 2B 2026-06-19: la app no tiene usuarios reales todavía, así que
/// se acepta perder ese historial en lugar de inventar repartos arbitrarios).
enum MuscleGroupDisplay {
  pecho,
  espalda,
  hombros,
  biceps,
  triceps,
  cuadriceps,
  isquiotibiales,
  gluteos,
  pantorrilla,
  abdominales;

  /// Etiqueta UPPER-CASE para renderizar en la lista (PECHO, ESPALDA, …).
  String get displayLabel => switch (this) {
        MuscleGroupDisplay.pecho => 'PECHO',
        MuscleGroupDisplay.espalda => 'ESPALDA',
        MuscleGroupDisplay.hombros => 'HOMBROS',
        MuscleGroupDisplay.biceps => 'BÍCEPS',
        MuscleGroupDisplay.triceps => 'TRÍCEPS',
        MuscleGroupDisplay.cuadriceps => 'CUÁDRICEPS',
        MuscleGroupDisplay.isquiotibiales => 'ISQUIOTIBIALES',
        MuscleGroupDisplay.gluteos => 'GLÚTEOS',
        MuscleGroupDisplay.pantorrilla => 'PANTORRILLA',
        MuscleGroupDisplay.abdominales => 'ABDOMINALES',
      };

  /// Orden de display canónico — matchea el orden del exercise picker:
  /// tren superior (empuje → jalón → hombros → bíceps → tríceps) → tren
  /// inferior (cuádriceps → isquios → glúteos → pantorrilla) → core.
  static const List<MuscleGroupDisplay> displayOrder = [
    MuscleGroupDisplay.pecho,
    MuscleGroupDisplay.espalda,
    MuscleGroupDisplay.hombros,
    MuscleGroupDisplay.biceps,
    MuscleGroupDisplay.triceps,
    MuscleGroupDisplay.cuadriceps,
    MuscleGroupDisplay.isquiotibiales,
    MuscleGroupDisplay.gluteos,
    MuscleGroupDisplay.pantorrilla,
    MuscleGroupDisplay.abdominales,
  ];
}

/// Mapping del `muscleGroup` granular del catálogo a la categoría display.
extension MuscleGroupMapping on String {
  /// Devuelve la `MuscleGroupDisplay` correspondiente, o null si el string
  /// no matchea ningún grupo conocido.
  ///
  /// Devuelve null para:
  ///   * Strings desconocidos (defensivo)
  ///   * `cardio` y `full_body` — se excluyen de Insights por diseño
  ///   * Strings legacy de la taxonomía vieja (`brazos`, `piernas`, etc.) —
  ///     cutoff 2B (no se remapean, las sesiones viejas dejan de aparecer
  ///     en los rollups sin inventar agrupaciones arbitrarias)
  MuscleGroupDisplay? toDisplayGroup() => switch (toLowerCase()) {
        'chest' => MuscleGroupDisplay.pecho,
        'back' => MuscleGroupDisplay.espalda,
        'shoulders' => MuscleGroupDisplay.hombros,
        'biceps' => MuscleGroupDisplay.biceps,
        'triceps' => MuscleGroupDisplay.triceps,
        'quads' => MuscleGroupDisplay.cuadriceps,
        'hamstrings' => MuscleGroupDisplay.isquiotibiales,
        'glutes' => MuscleGroupDisplay.gluteos,
        'calves' => MuscleGroupDisplay.pantorrilla,
        'core' || 'abs' => MuscleGroupDisplay.abdominales,
        _ => null,
      };
}
