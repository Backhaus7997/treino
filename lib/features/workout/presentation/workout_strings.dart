/// Centralized Spanish (es-AR) copy for workout screens.
/// Mirrors [AuthStrings] in structure — abstract final class with static consts.
/// ARB localization deferred to Etapa 6+.
abstract final class WorkoutStrings {
  // --- Post-Workout Summary header ---
  static const summaryHeaderCompleted = 'BUEN ENTRENO';
  static const summaryHeaderAbandoned = 'SESIÓN INTERRUMPIDA';

  // --- Stat grid labels ---
  static const statDuration = 'DURACIÓN';
  static const statVolume = 'VOLUMEN';
  static const statSets = 'SETS';
  static const statPrsToday = 'PRs HOY';
  static const statPrsTodayStub = '—';

  // --- PRs section ---
  static const prsSectionTitle = 'PRS DE LA SESIÓN';
  static const prsPlaceholder = 'Próximamente';

  // --- Buttons ---
  static const buttonDone = 'LISTO';
  static const buttonShare = 'COMPARTIR';
  static const buttonRetry = 'Reintentar';
  static const buttonBackToWorkout = 'Volver a Entrenar';

  // --- States ---
  static const notFoundTitle = 'Sesión no encontrada';
  static const errorTitle = 'No pudimos cargar tu sesión';

  // --- SnackBars ---
  static const snackShareSuccess = '¡Post compartido!';
  static const snackShareError =
      'No pudimos compartir tu post. Intentá de nuevo.';

  // --- Post autocomplete text ---
  static const postAutoCompleteText = '¡Terminé mi entreno! 💪';
}
