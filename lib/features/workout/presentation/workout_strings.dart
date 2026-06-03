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

  // ── MIS RUTINAS — section UI strings (REQ-USR-002..003, Design §es-AR strings) ─
  static const misRutinasSectionTitle = 'MIS RUTINAS';
  static const misRutinasCta = '+ CREAR RUTINA';
  static const misRutinasCtaDisabledTooltip =
      'Llegaste al máximo de 10 rutinas activas. Archivá una para crear otra.';
  static const misRutinasEmptyState =
      'Todavía no creaste ninguna rutina. Tocá CREAR RUTINA para armar la primera.';
  static const misRutinasError = 'No pudimos cargar tus rutinas.';
  static const misRutinasErrorRetry = 'Reintentar';
  static const misRutinasOverflowEdit = 'EDITAR';
  static const misRutinasOverflowArchive = 'ARCHIVAR';
  static const misRutinasConfirmTitle = 'Archivar rutina';
  static const misRutinasConfirmBody =
      'La rutina dejará de aparecer en MIS RUTINAS. Tu historial se conserva.';
  static const misRutinasConfirmCancel = 'CANCELAR';
  static const misRutinasConfirmConfirm = 'ARCHIVAR';
  static const misRutinasArchiveSuccess = 'Rutina archivada';
  static const misRutinasArchiveError =
      'No pudimos archivar la rutina. Reintentá.';

  // ── REQ-RER-014: nullable split fallback (ADR-RER-04) ──────────────────────
  /// Displayed when [Routine.split] is null. Display sites call `.toUpperCase()`
  /// as needed — this constant is stored in sentence case.
  static const String splitFallback = 'Sin split';

  // ── REQ-RER-005/006: exercise picker filter strings (T-RER-017) ─────────────
  static const String pickerMuscleFilter = 'Músculos';
  static const String pickerEquipmentFilter = 'Equipamiento';
  static const String pickerMuscleSheetTitle = 'Grupo muscular';
  static const String pickerEquipmentSheetTitle = 'Tipo de equipo';
  static const String pickerMuscleAll = 'Todos los músculos';
  static const String pickerEquipmentAll = 'Todo el equipamiento';
  static const String pickerEmptyFiltered = 'Ningún ejercicio coincide';
  static const String pickerEmptyFilteredHint =
      'Probá quitando un filtro o ajustando la búsqueda.';

  /// Builds the sticky CTA label for the multi-select picker.
  /// e.g. "Agregar 1 ejercicio" / "Agregar 3 ejercicios".
  static String pickerAddButton(int count) =>
      'Agregar $count ejercicio${count == 1 ? '' : 's'}';

  // ── PR3 athlete form simplification (T-RER-030) ──────────────────────────
  /// Athlete-mode name hint, replaces the trainer hint 'Ej: Fuerza PPL'.
  static const String selfEditorNameHint = 'Mi rutina';

  // ── Filter sheet (multi-select) CTAs — PR2 refinement ────────────────────
  /// Clears the current filter selection without dismissing the sheet.
  static const String pickerSheetClear = 'Limpiar';

  /// Label of the sticky Apply button when zero filters are selected
  /// (semantically equivalent to "match all").
  static const String pickerSheetApplyAll = 'APLICAR (TODOS)';

  /// Label of the sticky Apply button with N filters selected.
  /// e.g. "APLICAR (3)".
  static String pickerSheetApply(int count) => 'APLICAR ($count)';
}
