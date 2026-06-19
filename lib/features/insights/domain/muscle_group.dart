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

  /// Masks PNG bajo `assets/body/` para tintar la vista FRONTAL del cuerpo
  /// cuando este grupo tiene sets entrenados. Cada mask se stackea sobre
  /// `bodyfront.png` via `ColorFiltered` + accent.
  ///
  /// Lista vacía → este grupo no aparece en la vista frontal (e.g. glúteos
  /// solo en la espalda, tríceps sin mask todavía).
  ///
  /// Decisión 2 (2026-06-19): grupos con múltiples masks (e.g. abdominales
  /// = abs + obliques, espalda = back + lats + lowerback) se pintan todas
  /// juntas cuando hay sets — refleja la realidad anatómica del grupo.
  ///
  /// Decisión 1A (2026-06-19): tríceps sin mask por ahora (no existe
  /// `mask_back_triceps.png` en assets). TODO(assets): agregar la mask.
  List<String> get frontMaskAssets => switch (this) {
        MuscleGroupDisplay.pecho => const ['assets/body/mask_front_chest.png'],
        MuscleGroupDisplay.espalda => const [],
        MuscleGroupDisplay.hombros => const [
            'assets/body/mask_front_shoulders.png'
          ],
        MuscleGroupDisplay.biceps => const [
            'assets/body/mask_front_biceps.png'
          ],
        MuscleGroupDisplay.triceps => const [], // 1A: sin mask
        MuscleGroupDisplay.cuadriceps => const [
            'assets/body/mask_front_quads.png'
          ],
        MuscleGroupDisplay.isquiotibiales => const [],
        MuscleGroupDisplay.gluteos => const [],
        MuscleGroupDisplay.pantorrilla => const [
            'assets/body/mask_front_calves.png'
          ],
        MuscleGroupDisplay.abdominales => const [
            'assets/body/mask_front_abs.png',
            'assets/body/mask_front_obliques.png',
          ],
      };

  /// Masks PNG bajo `assets/body/` para tintar la vista TRASERA del cuerpo.
  /// Misma mecánica que [frontMaskAssets].
  List<String> get backMaskAssets => switch (this) {
        MuscleGroupDisplay.pecho => const [],
        MuscleGroupDisplay.espalda => const [
            'assets/body/mask_back_back.png',
            'assets/body/mask_back_lats.png',
            'assets/body/mask_back_lowerback.png',
          ],
        MuscleGroupDisplay.hombros => const [
            'assets/body/mask_back_shoulders.png'
          ],
        MuscleGroupDisplay.biceps => const [],
        MuscleGroupDisplay.triceps => const [], // 1A: sin mask
        MuscleGroupDisplay.cuadriceps => const [],
        MuscleGroupDisplay.isquiotibiales => const [
            'assets/body/mask_back_hamstrings.png'
          ],
        MuscleGroupDisplay.gluteos => const [
            'assets/body/mask_back_glutes.png'
          ],
        MuscleGroupDisplay.pantorrilla => const [
            'assets/body/mask_back_calves.png'
          ],
        MuscleGroupDisplay.abdominales => const [],
      };
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
