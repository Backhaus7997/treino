import '../../workout/domain/muscle_group.dart';

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
/// Los labels legacy en español que el editor viejo persistió (`Pecho`,
/// `Espalda alta`, `Gemelos`, …) SÍ se canonicalizan vía `MuscleGroup.fromKey`
/// (#384) — igual que el resto de la app. Solo devuelven `null` (y el provider
/// los skipea) los strings que ni `fromKey` resuelve (taxonomía ultra-vieja
/// `brazos`/`piernas`, catch-all `Otro`) más `cardio`/`full_body` (excluidos
/// de Insights por diseño).
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
  /// solo se pintan en la vista trasera).
  ///
  /// Decisión 2 (2026-06-19): grupos con múltiples masks (e.g. abdominales
  /// = abs + obliques, espalda = back + lats + lowerback) se pintan todas
  /// juntas cuando hay sets — refleja la realidad anatómica del grupo.
  ///
  List<String> get frontMaskAssets => switch (this) {
        MuscleGroupDisplay.pecho => const ['assets/body/mask_front_chest.png'],
        MuscleGroupDisplay.espalda => const [],
        MuscleGroupDisplay.hombros => const [
            'assets/body/mask_front_shoulders.png'
          ],
        MuscleGroupDisplay.biceps => const [
            'assets/body/mask_front_biceps.png'
          ],
        MuscleGroupDisplay.triceps => const [],
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
        MuscleGroupDisplay.triceps => const [
            'assets/body/mask_back_triceps.png'
          ],
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

/// Mapping del `muscleGroup` almacenado a la categoría display de Insights.
extension MuscleGroupMapping on String {
  /// Devuelve la `MuscleGroupDisplay` correspondiente, o null si el string no
  /// resuelve a un grupo de fuerza mostrable.
  ///
  /// #384: canonicaliza vía [MuscleGroup.fromKey] — la MISMA resolución que usa
  /// el resto de la app — así que las claves canónicas (`chest`…), los aliases
  /// (`abs`) y los labels legacy en español que el editor viejo persistió
  /// (`Pecho`, `Espalda alta`, `Gemelos`, …) mapean todos igual. Antes este
  /// switch aceptaba solo las claves inglesas y descartaba en silencio el legacy
  /// español (que sí resuelve en el picker) → sus sets desaparecían del radar.
  ///
  /// Devuelve null para:
  ///   * `cardio` y `full_body` — excluidos de Insights por diseño (no son
  ///     atribuibles a un eje puntual del radar).
  ///   * Strings que ni [MuscleGroup.fromKey] resuelve (desconocidos, el
  ///     catch-all legacy `Otro`, o la taxonomía ultra-vieja `brazos`/`piernas`).
  MuscleGroupDisplay? toDisplayGroup() => switch (MuscleGroup.fromKey(this)) {
        MuscleGroup.pecho => MuscleGroupDisplay.pecho,
        MuscleGroup.espalda => MuscleGroupDisplay.espalda,
        MuscleGroup.hombros => MuscleGroupDisplay.hombros,
        MuscleGroup.biceps => MuscleGroupDisplay.biceps,
        MuscleGroup.triceps => MuscleGroupDisplay.triceps,
        MuscleGroup.cuadriceps => MuscleGroupDisplay.cuadriceps,
        MuscleGroup.isquiotibiales => MuscleGroupDisplay.isquiotibiales,
        MuscleGroup.gluteos => MuscleGroupDisplay.gluteos,
        MuscleGroup.pantorrilla => MuscleGroupDisplay.pantorrilla,
        MuscleGroup.abdominales => MuscleGroupDisplay.abdominales,
        MuscleGroup.cardio || MuscleGroup.cuerpoCompleto || null => null,
      };
}
