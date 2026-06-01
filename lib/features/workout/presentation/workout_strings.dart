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

  // --- Historial section (lista) ---
  static const historialHeading = 'HISTORIAL';
  static const historialEmptyMessage = 'Todavía no entrenaste.';
  static const historialEmptyCta = 'Empezar entrenamiento';
  static const historialErrorMessage = 'No pudimos cargar tu historial.';
  static const historialErrorRetry = 'Reintentar';
  static const historialCardKgSuffix = ' kg';
  static const historialCardMinSuffix = ' min';

  // --- Historial section (expand toggle) ---
  /// Default cap for the collapsed historial. Cards beyond this are hidden
  /// until the user taps "Ver más".
  static const historialCollapsedLimit = 5;
  static const historialShowLess = 'Ver menos';
  static String historialShowMore(int hidden) => 'Ver más ($hidden)';

  // --- Historial detail screen (SessionDetailScreen) ---
  // Note: StatTile renders label.toUpperCase() — constants are pre-uppercase
  // so find.text() matches what's rendered on screen.
  static const detailStatDuration = 'DURACIÓN';
  static const detailStatSets = 'SETS';
  static const detailStatVolume = 'VOLUMEN';
  static const detailStatPrsToday = 'PRS HOY';
  static const detailPrBadge = 'PR';

  // ── MIS RUTINAS — self-creating editor (REQ-USR-011, Design §es-AR strings) ─
  static const selfEditorTitle = 'Nueva rutina';
  static const selfEditorSubmitLabel = 'CREAR RUTINA';
  static const selfEditorSuccess = 'Rutina creada';
  static const selfEditorError = 'No pudimos crear la rutina. Reintentá.';
  static const selfEditorPermissionDenied =
      'No tenés permisos para hacer esto. Recargá la app.';
  static const editStubToast =
      'Pronto vas a poder editar el contenido. Por ahora podés archivar y crear de nuevo.';
  static const selfEditorCapReached =
      'Llegaste al máximo de 10 rutinas activas.';
}
