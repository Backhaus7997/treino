/// UI copy constants for the check-in feature (es-AR).
///
/// All user-facing strings are centralised here so the dialog widget
/// stays free of inline literals and strings are easily reviewable.
abstract final class CheckInStrings {
  static const header = '¿ESTÁS EN EL GYM HOY?';
  static const neutralSubtext = 'Confirma tu entrenamiento de hoy';
  static const noButton = 'NO';
  static const siButton = 'SÍ, ENTRÉ';

  /// Subtext shown when the user has a gym configured in their profile.
  static String gymSubtext(String gymName) =>
      '$gymName · ¡Detectamos que podés estar entrenando!';
}
