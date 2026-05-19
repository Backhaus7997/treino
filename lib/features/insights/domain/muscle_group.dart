/// Las 6 categorías display que muestra la pantalla de Insights.
/// Los `muscleGroup` granulares del catálogo (chest, back, quads, glutes,
/// hamstrings, calves, biceps, triceps, shoulders, core) se mapean a estos
/// 6 grupos visibles vía la extension de abajo.
enum MuscleGroupDisplay {
  pecho,
  espalda,
  piernas,
  brazos,
  hombros,
  core;

  /// Etiqueta UPPER-CASE para renderizar en la lista (PECHO, ESPALDA, …).
  String get displayLabel => switch (this) {
        MuscleGroupDisplay.pecho => 'PECHO',
        MuscleGroupDisplay.espalda => 'ESPALDA',
        MuscleGroupDisplay.piernas => 'PIERNAS',
        MuscleGroupDisplay.brazos => 'BRAZOS',
        MuscleGroupDisplay.hombros => 'HOMBROS',
        MuscleGroupDisplay.core => 'CORE',
      };

  /// Orden de display canónico (matchea el mockup insights.png).
  static const List<MuscleGroupDisplay> displayOrder = [
    MuscleGroupDisplay.pecho,
    MuscleGroupDisplay.espalda,
    MuscleGroupDisplay.piernas,
    MuscleGroupDisplay.brazos,
    MuscleGroupDisplay.hombros,
    MuscleGroupDisplay.core,
  ];
}

/// Mapping del `muscleGroup` granular del catálogo a la categoría display.
extension MuscleGroupMapping on String {
  /// Devuelve la `MuscleGroupDisplay` correspondiente, o null si el string
  /// no matchea ningún grupo conocido (defensivo — un ejercicio con
  /// muscleGroup desconocido simplemente no suma a ningún total).
  MuscleGroupDisplay? toDisplayGroup() => switch (toLowerCase()) {
        'chest' => MuscleGroupDisplay.pecho,
        'back' => MuscleGroupDisplay.espalda,
        'shoulders' => MuscleGroupDisplay.hombros,
        'quads' ||
        'hamstrings' ||
        'glutes' ||
        'calves' =>
          MuscleGroupDisplay.piernas,
        'biceps' || 'triceps' => MuscleGroupDisplay.brazos,
        'core' || 'abs' => MuscleGroupDisplay.core,
        _ => null,
      };
}
