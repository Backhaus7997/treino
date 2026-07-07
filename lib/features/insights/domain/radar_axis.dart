import 'muscle_group.dart';

/// [AD4] The 6 axes of the muscle distribution radar chart
/// ([MuscleDistributionRadar]) — one coarser fold on top of the 10
/// [MuscleGroupDisplay] categories already used by the body heat-map.
///
/// Folding rule (verified during design — ZERO orphans across all 10
/// [MuscleGroupDisplay] values):
/// - [back]      ← espalda
/// - [chest]     ← pecho
/// - [core]      ← abdominales
/// - [shoulders] ← hombros
/// - [arms]      ← biceps + triceps
/// - [legs]      ← cuadriceps + isquiotibiales + gluteos + pantorrilla
///
/// `cardio`/`full_body` never reach [MuscleGroupDisplay] at all — they're
/// already excluded upstream via `String.toDisplayGroup()` returning `null`
/// (see muscle_group.dart) — so this fold never needs to handle them.
enum RadarAxis {
  back,
  chest,
  core,
  shoulders,
  arms,
  legs;

  /// Canonical order for rendering the radar's 6 axes.
  static const List<RadarAxis> displayOrder = [
    RadarAxis.back,
    RadarAxis.chest,
    RadarAxis.core,
    RadarAxis.shoulders,
    RadarAxis.arms,
    RadarAxis.legs,
  ];

  /// UPPER-CASE label for rendering on the radar's axis titles — matches the
  /// UI convention of [MuscleGroupDisplay.displayLabel].
  String get displayLabel => switch (this) {
        RadarAxis.back => 'ESPALDA',
        RadarAxis.chest => 'PECHO',
        RadarAxis.core => 'CORE',
        RadarAxis.shoulders => 'HOMBROS',
        RadarAxis.arms => 'BRAZOS',
        RadarAxis.legs => 'PIERNAS',
      };

  /// Folds a [MuscleGroupDisplay] into its radar axis.
  ///
  /// Exhaustive switch (no `default`/`_` branch) — if a future
  /// [MuscleGroupDisplay] value is added without updating this fold, the
  /// BUILD BREAKS at compile time rather than silently orphaning the new
  /// group at runtime. This is the deliberate compile-time safety net
  /// requested by design risk-2; [radar_axis_test.dart] is the run-time
  /// safety net proving all 10 CURRENT values resolve.
  static RadarAxis fromDisplayGroup(MuscleGroupDisplay group) {
    switch (group) {
      case MuscleGroupDisplay.espalda:
        return RadarAxis.back;
      case MuscleGroupDisplay.pecho:
        return RadarAxis.chest;
      case MuscleGroupDisplay.abdominales:
        return RadarAxis.core;
      case MuscleGroupDisplay.hombros:
        return RadarAxis.shoulders;
      case MuscleGroupDisplay.biceps:
      case MuscleGroupDisplay.triceps:
        return RadarAxis.arms;
      case MuscleGroupDisplay.cuadriceps:
      case MuscleGroupDisplay.isquiotibiales:
      case MuscleGroupDisplay.gluteos:
      case MuscleGroupDisplay.pantorrilla:
        return RadarAxis.legs;
    }
  }
}
