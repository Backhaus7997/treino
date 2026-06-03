/// UI copy for the Coach Discovery feature (es-AR).
///
/// All visible strings for trainer discovery, list, and profile screens
/// live here. No inline literals in widget code per project convention.
abstract final class CoachStrings {
  // ── TrainersListScreen ────────────────────────────────────────────────────
  static const appBarTitle = 'Entrenadores';
  static const loadingLabel = 'Cargando entrenadores…';
  static const errorLabel = 'No pudimos cargar los entrenadores.';
  static const retryLabel = 'Reintentar';
  static const emptyLabel = 'No encontramos entrenadores en tu zona.';
  static const mapToggleLabel = 'Mapa';
  static const mapProximamente = 'Próximamente';

  // ── TrainerListTile ───────────────────────────────────────────────────────
  static const distanceUnknown = '—';
  static const monthlyRateUnit = '/mes';

  // ── TrainerSpecialtyChips ─────────────────────────────────────────────────
  static const specialtyAll = 'Todos';

  // ── TrainerProfileHero ────────────────────────────────────────────────────
  // (display name shown as-is; no extra copy needed)

  // ── TrainerStatsRow ───────────────────────────────────────────────────────
  static const statsReviewsLabel = 'RESEÑAS';
  static const statsExperienceLabel = 'AÑOS EXP';
  static const statsStudentsLabel = 'ALUMNOS';
  static const statsPlaceholder = '—';

  // ── TrainerPublicProfileScreen ────────────────────────────────────────────
  static const profileLoadingLabel = 'Cargando perfil…';
  static const profileErrorLabel = 'No pudimos cargar este perfil.';
  static const profileNotFoundLabel = 'Entrenador no encontrado.';
  static const profileBioEmpty = 'Sin descripción.';
  static const profileRateLabel = 'Tarifa mensual';

  // ── TrainerContactCtaStub ─────────────────────────────────────────────────
  static const ctaLabel = 'PEDIR VÍNCULO';
  static const ctaProximamente = 'Próximamente — Etapa 3';

  // ── LocationPermissionRationaleSheet ─────────────────────────────────────
  static const locationSheetTitle = 'Permitir ubicación';
  static const locationSheetBody =
      'TREINO usa tu ubicación para mostrarte entrenadores cerca tuyo. '
      'Tu ubicación no es visible para otros usuarios.';
  static const locationSheetAccept = 'ACEPTAR';
  static const locationSheetDeny = 'Ahora no';

  // ── Coach Plans Mobile (Fase 5 · Etapa 4) ────────────────────────────────
  static const miPlanTitle = 'MI PLAN';
  static const miPlanEmpty = 'No tenés rutina asignada todavía.';
  static const miPlanError = 'Error al cargar tu plan.';
  static const miPlanFinalizado = 'Plan finalizado';
  static const miPlanCurrent = 'Actual';
  static const assignedByPrefix = 'Asignado por ';
  static const assignedByLoading = 'Asignado por …';
  static const assignedByError = 'Asignado por un PF';
  static const createPlanCta = 'CREAR PLAN';
  static const createPlanSuccess = 'Plan creado y asignado.';
  static const createPlanError = 'No pudimos crear el plan. Intentá de nuevo.';
  static const athleteDetailNoPlans = 'Todavía no le asignaste planes.';
  static const editorTitle = 'Crear plan';
  static const editorNameLabel = 'NOMBRE';
  static const editorSplitLabel = 'SPLIT (e.g. PPL)';
  static const editorAddDay = 'Agregar día';
  static const editorAddSlot = 'Agregar ejercicio';
  static const editorAddSuperset = '+ Superserie';
  static const editorSubmit = 'ASIGNAR PLAN';
  static const exercisePicker = 'Buscar ejercicio';
}
