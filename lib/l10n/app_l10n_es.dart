// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppL10nEs extends AppL10n {
  AppL10nEs([String locale = 'es']) : super(locale);

  @override
  String get notFoundTitle => 'Página no encontrada';

  @override
  String get notFoundBody =>
      'La ruta que buscás no existe o el enlace es inválido.';

  @override
  String get notFoundCta => 'Volver al inicio';

  @override
  String get homeAthleteFirstRunTitle => 'Arrancá tu entrenamiento';

  @override
  String get homeAthleteFirstRunBody =>
      'Creá tu propia rutina, explorá planes ya armados o buscá un entrenador que te guíe.';

  @override
  String get homeAthleteFirstRunBodyWithTrainer =>
      'Ya tenés entrenador. Mientras tanto, creá tu propia rutina o explorá planes ya armados.';

  @override
  String get homeAthleteFirstRunBodyNeutral =>
      'Creá tu propia rutina o explorá planes ya armados.';

  @override
  String get homeAthleteFirstRunCreateCta => 'CREAR RUTINA';

  @override
  String get homeAthleteFirstRunExplorePlansCta => 'Explorar planes';

  @override
  String get homeAthleteFirstRunFindTrainerCta => 'Buscar entrenador';

  @override
  String get homeEstaSemanaTitle => 'ESTA SEMANA';

  @override
  String get homeEstaSemanaLoadError => 'No pudimos cargar tus insights.';

  @override
  String get homeEstaSemanaHeaderPill => 'RACHA ACTUAL';

  @override
  String get homeEstaSemanaHeaderPillEmpty => 'PRIMER PASO';

  @override
  String homeEstaSemanaWeekMonth(int week, String month) {
    return 'SEM $week · $month';
  }

  @override
  String homeEstaSemanaStreakUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'SEMANAS',
      one: 'SEMANA',
    );
    return '$_temp0';
  }

  @override
  String get homeEstaSemanaStreakSubtextTrained =>
      'No rompas la racha — entrenaste hoy.';

  @override
  String get homeEstaSemanaStreakSubtextPending =>
      'No rompas la racha — entrena hoy.';

  @override
  String get homeEstaSemanaPeriodWeek => 'SEMANA';

  @override
  String get homeEstaSemanaPeriodMonth => 'MES';

  @override
  String homeEstaSemanaPeriodUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'entrenos',
      one: 'entreno',
    );
    return '$_temp0';
  }

  @override
  String get homeEstaSemanaMusclesTitle => 'MÚSCULOS DE LA SEMANA';

  @override
  String get homeEstaSemanaMusclesLegend =>
      'Más color = más cerca de las series que pide tu rutina esta semana.';

  @override
  String get homeGreeting => '¡HOLA!';

  @override
  String homeGreetingNamed(String name) {
    return '¡HOLA, $name!';
  }

  @override
  String get homeEstaSemanaEmptyTitle => 'TU RACHA\nEMPIEZA AQUÍ';

  @override
  String get homeEstaSemanaEmptyBody =>
      'Cada entrenamiento alimenta tu racha. Haz el primero y empieza a construir tu progreso.';

  @override
  String get homeEstaSemanaEmptyCta => 'EXPLORAR RUTINAS  →';

  @override
  String get homeEstaSemanaInsightsCta => 'VER INSIGHTS  →';

  @override
  String get homeEstaSemanaHeaderPillResume => 'A RETOMAR';

  @override
  String get homeEstaSemanaResumeTitle => 'TU RACHA\nTE ESPERA';

  @override
  String get homeEstaSemanaResumeBody =>
      'Ya tienes historial construido. Esta semana aún está en cero — retoma hoy y sigue sumando progreso.';

  @override
  String get homeEstaSemanaResumeCta => 'VOLVER A ENTRENAR  →';

  @override
  String get authSplashTagline => 'ENTRENÁ. COMPARTÍ. CRECÉ.';

  @override
  String get authBrandHeadline1Light => 'DEJA DE ';

  @override
  String get authBrandHeadline1Bold => 'IMPROVISAR.';

  @override
  String get authBrandHeadline2Light => 'EMPIEZA A ';

  @override
  String get authBrandHeadline2Bold => 'PROGRESAR.';

  @override
  String get authWelcomeEyebrow => 'ENTRENAMIENTO · GYM · COACH';

  @override
  String get authWelcomeBody =>
      'Tu rutina, tus series y tus cargas en un solo lugar. Con un coach atrás si lo quieres.';

  @override
  String get authWelcomeCta => 'EMPEZAR';

  @override
  String get authWelcomeHaveAccount => '¿Ya tenés cuenta?';

  @override
  String get authWelcomeSignIn => 'INICIAR SESIÓN';

  @override
  String get authWelcomeTrainerPrompt => '¿Eres entrenador?';

  @override
  String get authWelcomeBecomeTrainer => 'Quiero ser entrenador';

  @override
  String authWelcomeBecomeTrainerFallback(String email) {
    return 'No pudimos abrir tu correo. Escríbenos a $email.';
  }

  @override
  String get authLoginTitle => 'BIENVENIDO';

  @override
  String get authLoginSubtitle => 'Entrá para seguir tu rutina';

  @override
  String get authLoginEmailHint => 'tu@email.com';

  @override
  String get authLoginForgot => 'Olvidé la contraseña';

  @override
  String get authLoginCta => 'ENTRAR';

  @override
  String get authLoginContinueWith => 'O CONTINUÁ CON';

  @override
  String get authLoginNoAccount => '¿No tenés cuenta?';

  @override
  String get authLoginRegisterLink => 'Registrate';

  @override
  String get authLoginTrainerCardTitle => '¿Sos entrenador?';

  @override
  String get authLoginTrainerCardSubtitle => 'Pedí tu alta al equipo TREINO';

  @override
  String get authRegisterAppbar => 'CREAR CUENTA';

  @override
  String get authRegisterTitle => 'SUMATE A';

  @override
  String get authRegisterSubtitle => 'Es gratis. En 30 segundos estás adentro.';

  @override
  String get authRegisterEmailLabel => 'EMAIL';

  @override
  String get authRegisterPasswordLabel => 'CONTRASEÑA';

  @override
  String get authRegisterConfirmPasswordLabel => 'CONFIRMAR CONTRASEÑA';

  @override
  String get authRegisterCta => 'CREAR CUENTA';

  @override
  String get authRegisterDividerOr => 'O';

  @override
  String get authForgotTitle => 'RECUPERAR\nACCESO';

  @override
  String get authForgotBody =>
      'Ingresá tu email y te enviamos un link para resetear la contraseña.';

  @override
  String get authForgotEmailLabel => 'EMAIL';

  @override
  String get authForgotEmailHint => 'tu@email.com';

  @override
  String get authForgotCta => 'ENVIAR LINK';

  @override
  String get authForgotSuccess =>
      'Si tu email está registrado, te enviamos un link para resetear la contraseña.';

  @override
  String get authForgotBackToLogin => 'Volver al login';

  @override
  String get authForgotSpamHint =>
      '¿No te llegó? Puede tardar un minuto. Revisá también la carpeta de spam.';

  @override
  String get authForgotResendCta => 'Reenviar el link';

  @override
  String authForgotResendIn(int seconds) {
    return 'Podés reenviar en ${seconds}s';
  }

  @override
  String get authForgotEditEmail => 'Usar otra dirección';

  @override
  String get authTrainerInquiryDialogTitle => 'Acceso de entrenador';

  @override
  String get authTrainerInquiryDialogBody =>
      'Para alta de entrenador, escribinos a treino@gettreino.com';

  @override
  String get authTrainerInquiryDialogClose => 'Cerrar';

  @override
  String get authTermsPlaceholder => 'Próximamente';

  @override
  String get authGoogleLabel => 'GOOGLE';

  @override
  String get authAppleLabel => 'APPLE';

  @override
  String get authLoginHeaderTitle => 'Iniciar sesión';

  @override
  String get authRegisterHeaderTitle => 'Crear una cuenta';

  @override
  String get authLoginOrSignInWith => 'O iniciá sesión con';

  @override
  String get authRegisterOrSignUpWith => 'O registrate con';

  @override
  String get authContinueWithGoogle => 'Continuar con Google';

  @override
  String get authContinueWithApple => 'Continuar con Apple';

  @override
  String get authRegisterHaveAccount => '¿Ya tenés cuenta?';

  @override
  String get authRegisterSignInLink => 'Iniciá sesión';

  @override
  String get authComingSoonTooltip => 'Próximamente';

  @override
  String get authValidationEmailInvalid => 'El email no es válido';

  @override
  String get authValidationPasswordRules =>
      'La contraseña debe tener al menos 8 caracteres, una letra y un número';

  @override
  String get authValidationPasswordMismatch => 'Las contraseñas no coinciden';

  @override
  String get authProfileSignOut => 'Cerrar sesión';

  @override
  String get coachAppBarTitle => 'Entrenadores';

  @override
  String get coachLoadingLabel => 'Cargando entrenadores…';

  @override
  String get coachErrorLabel => 'No pudimos cargar los entrenadores.';

  @override
  String get coachRetryLabel => 'Reintentar';

  @override
  String get coachEmptyLabel => 'No encontramos entrenadores en tu zona.';

  @override
  String get coachMapToggleLabel => 'Mapa';

  @override
  String get coachMapProximamente => 'Próximamente';

  @override
  String get coachDistanceUnknown => '—';

  @override
  String get coachMonthlyRateUnit => '/mes';

  @override
  String get coachSpecialtyAll => 'Todos';

  @override
  String get coachStatsReviewsLabel => 'RESEÑAS';

  @override
  String get coachStatsExperienceLabel => 'AÑOS EXP';

  @override
  String get coachStatsStudentsLabel => 'ALUMNOS';

  @override
  String get coachStatsPlaceholder => '—';

  @override
  String get coachProfileLoadingLabel => 'Cargando perfil…';

  @override
  String get coachProfileErrorLabel => 'No pudimos cargar este perfil.';

  @override
  String get coachProfileNotFoundLabel => 'Entrenador no encontrado.';

  @override
  String get coachProfileBioEmpty => 'Sin descripción.';

  @override
  String get coachProfileRateLabel => 'Tarifa mensual';

  @override
  String get coachCtaLabel => 'PEDIR VÍNCULO';

  @override
  String get coachInquiryCtaLabel => 'CONSULTAR';

  @override
  String get coachInquiryCtaHelp =>
      'Pregúntale precio, modalidad y horarios sin comprometerte con nadie.';

  @override
  String get coachInquiryCtaError =>
      'No pudimos abrir la consulta. Inténtalo de nuevo.';

  @override
  String get coachPreviewBannerTitle => 'VISTA PREVIA';

  @override
  String get coachPreviewBannerBody =>
      'Así ve tu perfil un alumno. Los botones están desactivados en esta vista.';

  @override
  String get coachPreviewMissingExperience =>
      'Todavía no has cargado tus años de experiencia: los alumnos ven «—». Toca para cargarlos.';

  @override
  String get coachCtaProximamente => 'Próximamente — Etapa 3';

  @override
  String get coachLocationSheetTitle => 'TU UBICACIÓN';

  @override
  String get coachLocationSheetBody =>
      'TREINO usa tu ubicación para mostrarte entrenadores cerca de ti. Tu ubicación no es visible para otros usuarios.';

  @override
  String get coachLocationSheetContinue => 'CONTINUAR';

  @override
  String get coachLocationSettingsNoticeTitle => 'UBICACIÓN DESACTIVADA';

  @override
  String get coachLocationSettingsNoticeBody =>
      'Activa la ubicación en Ajustes para ver entrenadores cerca de ti. Si prefieres, sigue sin ubicación y explora entrenadores Online.';

  @override
  String get coachLocationSettingsNoticeOpenSettings => 'ABRIR AJUSTES';

  @override
  String get coachLocationSettingsNoticeContinueWithout =>
      'Seguir sin ubicación';

  @override
  String get coachLocationServicesOffTitle =>
      'SERVICIOS DE UBICACIÓN DESACTIVADOS';

  @override
  String get coachLocationServicesOffBody =>
      'Activa los Servicios de ubicación en Ajustes para ver entrenadores cerca de ti. Si prefieres, sigue sin ubicación y explora entrenadores Online.';

  @override
  String get coachLocationSheetBodyGyms =>
      'TREINO usa tu ubicación para mostrarte gimnasios cerca de ti. Tu ubicación no es visible para otros usuarios.';

  @override
  String get coachLocationSheetBodyDetect =>
      'TREINO usa tu ubicación una sola vez para detectar el lugar donde entrenas.';

  @override
  String get coachLocationSettingsNoticeBodyGyms =>
      'Activa la ubicación en Ajustes para ver gimnasios cerca de ti. Mientras tanto puedes buscarlo por nombre.';

  @override
  String get coachLocationSettingsNoticeBodyDetect =>
      'Activa la ubicación en Ajustes para detectar tu ubicación. También puedes elegir un gimnasio de la lista.';

  @override
  String get coachLocationServicesOffBodyGyms =>
      'Activa los Servicios de ubicación en Ajustes para ver gimnasios cerca de ti. Mientras tanto puedes buscarlo por nombre.';

  @override
  String get coachLocationServicesOffBodyDetect =>
      'Activa los Servicios de ubicación en Ajustes para detectar tu ubicación. También puedes elegir un gimnasio de la lista.';

  @override
  String get profileLocationPermissionNeeded =>
      'Necesitamos permiso de ubicación.';

  @override
  String get profileLocationDetectFailed => 'No pudimos detectar tu ubicación.';

  @override
  String get coachMiPlanTitle => 'MI PLAN';

  @override
  String get coachMiPlanEmpty => 'No tenés rutina asignada todavía.';

  @override
  String get coachMiPlanError => 'Error al cargar tu plan.';

  @override
  String get coachMiPlanFinalizado => 'Plan finalizado';

  @override
  String get coachMiPlanCurrent => 'Actual';

  @override
  String get coachAssignedByPrefix => 'Asignado por ';

  @override
  String get coachAssignedByLoading => 'Asignado por …';

  @override
  String get coachAssignedByError => 'Asignado por un PF';

  @override
  String get coachCreatePlanCta => 'CREAR PLAN';

  @override
  String get coachCreatePlanSuccess => 'Plan creado y asignado.';

  @override
  String get coachCreatePlanError =>
      'No pudimos crear el plan. Intentá de nuevo.';

  @override
  String get coachAthleteDetailNoPlans => 'Todavía no le asignaste planes.';

  @override
  String get coachEditorTitle => 'Crear plan';

  @override
  String get coachEditorEditTitle => 'Editar plan';

  @override
  String get coachEditorNameLabel => 'NOMBRE';

  @override
  String get coachEditorSplitLabel => 'SPLIT (e.g. PPL)';

  @override
  String get coachEditorAddDay => 'Agregar día';

  @override
  String get coachEditorAddSlot => 'Agregar ejercicio';

  @override
  String get coachEditorAddSuperset => '+ Superserie';

  @override
  String get coachEditorSubmit => 'ASIGNAR PLAN';

  @override
  String get coachEditorUpdateLabel => 'GUARDAR CAMBIOS';

  @override
  String get coachUpdatePlanSuccess => 'Plan actualizado.';

  @override
  String get coachExercisePicker => 'Buscar ejercicio';

  @override
  String get agendaButtonLabel => 'MI AGENDA';

  @override
  String get athleteNutritionPlanButtonLabel => 'MI PLAN NUTRICIONAL';

  @override
  String get athleteFilesButtonLabel => 'MIS ARCHIVOS';

  @override
  String get athleteNutritionPlanScreenTitle => 'PLAN NUTRICIONAL';

  @override
  String get athleteNutritionChooseOneHint => 'Elegí una';

  @override
  String get athleteNutritionEmptyGroup =>
      'Tu PF todavía no cargó opciones acá.';

  @override
  String get athleteNutritionAllHint => 'Va todo';

  @override
  String get athleteNutritionPlanEmpty =>
      'Tu PF todavía no cargó tu plan nutricional.';

  @override
  String get athleteNutritionPlanLoadError =>
      'No pudimos cargar tu plan nutricional.';

  @override
  String get athleteNutritionNeedsActiveLink =>
      'Necesitás un vínculo activo con un PF para ver tu plan nutricional.';

  @override
  String get trainerNutritionSectionTitle => 'PLAN NUTRICIONAL';

  @override
  String get trainerNutritionSectionLoadCta => '+ Cargar';

  @override
  String get trainerNutritionSectionEditCta => 'Editar';

  @override
  String get trainerNutritionSectionEmpty =>
      'Todavía no le cargaste un plan nutricional.';

  @override
  String get trainerNutritionSectionUntitled => 'Plan nutricional';

  @override
  String trainerNutritionSectionSummary(int count, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comidas',
      one: '1 comida',
    );
    return '$_temp0 · actualizado el $date';
  }

  @override
  String get trainerNutritionLoadError =>
      'No pudimos cargar el plan nutricional.';

  @override
  String get trainerNutritionEditorTitle => 'PLAN NUTRICIONAL';

  @override
  String get trainerNutritionEditorPlanTitleLabel =>
      'Título del plan (opcional)';

  @override
  String get trainerNutritionEditorPlanTitleHint =>
      'Ej: Progresión 4 - Semana 9 en adelante';

  @override
  String get trainerNutritionEditorMealNameHint => 'Nombre de la comida';

  @override
  String get trainerNutritionEditorMealTimeHint => 'Hora';

  @override
  String get trainerNutritionEditorDeleteMealTooltip => 'Eliminar comida';

  @override
  String get trainerNutritionEditorAddMeal => 'AGREGAR COMIDA';

  @override
  String get trainerNutritionEditorGroupNameHint => 'Nombre del grupo';

  @override
  String get trainerNutritionEditorDeleteGroupTooltip => 'Eliminar grupo';

  @override
  String get trainerNutritionEditorAddGroup => '+ Agregar grupo';

  @override
  String get trainerNutritionEditorChooseOne => 'Elegir una';

  @override
  String get trainerNutritionEditorAll => 'Todas';

  @override
  String get trainerNutritionEditorAddOption => '+ Agregar opción';

  @override
  String get trainerNutritionEditorEmptyGroup => 'Sin opciones todavía.';

  @override
  String get trainerNutritionEditorSave => 'GUARDAR PLAN';

  @override
  String get trainerNutritionEditorSaved => 'Plan nutricional guardado.';

  @override
  String get trainerNutritionEditorSaveError =>
      'No pudimos guardar el plan. Probá de nuevo.';

  @override
  String get trainerNutritionEditorStaleReadError =>
      'No pudimos leer el plan guardado. Para no pisarlo, no se puede guardar hasta volver a leerlo.';

  @override
  String get trainerNutritionEditorEmptyPlan =>
      'El plan está vacío. Agregá al menos una comida con nombre.';

  @override
  String get trainerNutritionEditorDiscardTitle => '¿Descartar cambios?';

  @override
  String get trainerNutritionEditorDiscardBody =>
      'Si salís ahora vas a perder los cambios del plan sin guardar.';

  @override
  String get trainerNutritionEditorDiscardConfirm => 'Descartar';

  @override
  String trainerNutritionEditorDeleteTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get trainerNutritionEditorDeleteMealBody =>
      'Se borra la comida con todos sus grupos y opciones.';

  @override
  String get trainerNutritionEditorDeleteGroupBody =>
      'Se borra el grupo con todas sus opciones.';

  @override
  String get trainerNutritionOptionNewTitle => 'NUEVA OPCIÓN';

  @override
  String get trainerNutritionOptionEditTitle => 'EDITAR OPCIÓN';

  @override
  String get trainerNutritionOptionNameLabel => 'ALIMENTO';

  @override
  String get trainerNutritionOptionNameHint => 'Ej: 5 discos de arroz';

  @override
  String get trainerNutritionOptionQuantityLabel => 'CANTIDAD';

  @override
  String get trainerNutritionOptionQuantityHint => 'Ej: 230-240';

  @override
  String get trainerNutritionOptionUnitLabel => 'UNIDAD';

  @override
  String get trainerNutritionOptionUnitHint => 'Ej: grs peso cocido';

  @override
  String get trainerNutritionOptionNotesLabel => 'NOTAS';

  @override
  String get trainerNutritionOptionNotesHint => 'Marca, aclaraciones…';

  @override
  String get trainerNutritionOptionDone => 'LISTO';

  @override
  String get trainerNutritionOptionDelete => 'ELIMINAR OPCIÓN';

  @override
  String get athleteLinkRequired =>
      'No encontramos un vínculo activo con un PF.';

  @override
  String get trainerAcceptsInquiriesTitle => 'Acepto consultas';

  @override
  String get trainerAcceptsInquiriesSubtitle =>
      'Un alumno puede escribirte antes de pedirte el vínculo. Si lo apagás, no te llegan consultas nuevas — las conversaciones ya abiertas siguen.';

  @override
  String get athleteLinkUnconfirmed =>
      'No pudimos confirmar tu vínculo con tu PF.';

  @override
  String get athleteLinkRequiredRetry => 'Reintentar';

  @override
  String get athleteSessionMissing => 'Tu sesión se cerró. Volvé a entrar.';

  @override
  String get athleteFilesScreenTitle => 'MIS ARCHIVOS';

  @override
  String get athleteFilesEmpty =>
      'Tu PF todavía no compartió archivos con vos.';

  @override
  String get athleteFilesLoadError => 'No pudimos cargar tus archivos.';

  @override
  String get agendaScreenTitle => 'Agenda';

  @override
  String get agendaEmptyAvailability => 'Tu PF todavía no configuró horarios.';

  @override
  String get agendaBookingConfirmTitle => 'Confirmar reserva';

  @override
  String agendaBookingConfirmBody(String date, String time) {
    return '¿Confirmar reserva el $date a las $time?';
  }

  @override
  String get agendaBookingConfirmCta => 'Confirmar';

  @override
  String get agendaBookingCancel => 'Cancelar';

  @override
  String get agendaBookingSuccess => 'Reserva confirmada.';

  @override
  String get agendaBookingRaceError =>
      'Ese horario fue reservado justo ahora. Probá con otro.';

  @override
  String get agendaCancellationConfirmTitle => 'Cancelar reserva';

  @override
  String get agendaCancellationConfirmBody => '¿Cancelar esta reserva?';

  @override
  String get agendaCancellationConfirmCta => 'Sí, cancelar';

  @override
  String get agendaCancellationKeep => 'No, mantener';

  @override
  String get agendaCancellationSuccess => 'Reserva cancelada.';

  @override
  String get agendaCancellationTooLate =>
      'No podés cancelar con menos de 24h de anticipación.';

  @override
  String get agendaAthleteCancelCta => 'CANCELAR';

  @override
  String get agendaAthleteCancelConfirmBody =>
      '¿Cancelar esta sesión? Le avisamos a tu entrenador.';

  @override
  String get agendaBookingCancelledByAthlete =>
      'Reserva cancelada por el alumno.';

  @override
  String get agendaAthleteNotifyTrainerCta => 'AVISAR A MI ENTRENADOR';

  @override
  String get agendaAthleteNotifyHint =>
      'Faltan menos de 24 h: si no puedes ir, avísale a tu entrenador.';

  @override
  String get agendaAthleteChatError =>
      'No pudimos abrir el chat. Inténtalo de nuevo.';

  @override
  String get agendaUpcomingAppointmentsHeading => 'TUS PRÓXIMAS RESERVAS';

  @override
  String get agendaPastAppointmentsHeading => 'TURNOS PASADOS';

  @override
  String get agendaGenericError => 'Hubo un problema. Intentá de nuevo.';

  @override
  String get agendaTrainerEmptyAvailability =>
      'Todavía no configuraste tus horarios de trabajo. Agregá uno para que tus alumnos puedan reservar.';

  @override
  String get agendaConfigureHoursCta => 'CONFIGURAR HORARIOS';

  @override
  String get agendaMyWorkingHoursHeading => 'MIS HORARIOS DE TRABAJO';

  @override
  String get agendaAddRuleCta => 'AGREGAR HORARIO';

  @override
  String get agendaBlockDayCta => 'BLOQUEAR UN DÍA';

  @override
  String get agendaEditorTitle => 'Mis horarios';

  @override
  String get agendaRuleDeleteConfirm =>
      '¿Borrar este horario? Las reservas existentes se mantienen.';

  @override
  String get agendaRuleInvalidWindow =>
      'La hora de fin debe ser posterior al inicio y dejar espacio para al menos un turno.';

  @override
  String agendaRuleOverlap(String day, String start, String end) {
    return 'Ese horario se superpone con otro que ya cargaste: $day, $start – $end.';
  }

  @override
  String get agendaBookingCancelledByCoach =>
      'Reserva cancelada por el entrenador.';

  @override
  String get agendaAttendanceMarkAbsent => 'MARCAR AUSENTE';

  @override
  String get agendaAttendanceUndoAbsent => 'DESHACER AUSENTE';

  @override
  String get agendaAttendanceDefaultHint =>
      'Si no marcas nada, la sesión cuenta como hecha.';

  @override
  String get agendaAttendanceAbsentHint => 'Marcaste que el alumno faltó.';

  @override
  String get agendaAttendanceAbsentStatus => 'Ausente';

  @override
  String get agendaAttendanceError =>
      'No pudimos guardar la asistencia. Inténtalo de nuevo.';

  @override
  String get agendaBlockedDayTitle => 'Día bloqueado';

  @override
  String agendaBlockedDayBodySingle(String date) {
    return 'El $date está marcado como bloqueado en tus horarios. ¿Querés cargar la sesión igual?';
  }

  @override
  String agendaBlockedDayBodyRecurring(int count) {
    return '$count de las fechas caen en días bloqueados. ¿Continuar igual?';
  }

  @override
  String get agendaBlockedDayConfirm => 'Cargar igual';

  @override
  String get agendaConflictTitle => 'Revisa el horario';

  @override
  String agendaConflictOverlapLine(String name, String start, String end) {
    return 'Se superpone con $name ($start – $end).';
  }

  @override
  String agendaConflictOverlapMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Y $count sesiones más.',
      one: 'Y 1 sesión más.',
    );
    return '$_temp0';
  }

  @override
  String get agendaConflictSomeoneElse => 'otra sesión';

  @override
  String get agendaConflictOutsideAvailability =>
      'Queda fuera de tu disponibilidad publicada.';

  @override
  String agendaConflictSeriesOverlap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sesiones de la serie se superponen con otras ya agendadas.',
      one: '1 sesión de la serie se superpone con otra ya agendada.',
    );
    return '$_temp0';
  }

  @override
  String agendaConflictSeriesOutside(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sesiones de la serie quedan fuera de tu disponibilidad publicada.',
      one: '1 sesión de la serie queda fuera de tu disponibilidad publicada.',
    );
    return '$_temp0';
  }

  @override
  String get agendaConflictQuestion => '¿Quieres agendarla igualmente?';

  @override
  String get agendaSlotFreeLabel => 'Disponible';

  @override
  String get agendaSlotBlockedLabel => 'Bloqueado';

  @override
  String agendaSlotBookedByLabel(String athleteName) {
    return 'Reservado por $athleteName';
  }

  @override
  String get agendaCobrarCta => 'COBRAR';

  @override
  String get agendaCobradoLabel => 'Cobrado';

  @override
  String get agendaCobrarMontoLabel => 'MONTO (ARS)';

  @override
  String get agendaCobrarConceptoLabel => 'CONCEPTO';

  @override
  String get agendaCobrarVenceElLabel => 'VENCE EL (OPCIONAL)';

  @override
  String get agendaCobrarVenceElHint => 'Sin fecha de vencimiento';

  @override
  String get agendaCobrarVenceElQuitar => 'Quitar fecha de vencimiento';

  @override
  String get agendaCobrarConfirmCta => 'CONFIRMAR COBRO';

  @override
  String get agendaCobrarCompletaCampos => 'Completa todos los campos.';

  @override
  String get agendaCobrarMontoInvalido => 'Ingresa un monto válido.';

  @override
  String get agendaCobrarSuccess => 'Turno cobrado.';

  @override
  String get agendaCobrarError =>
      'No pudimos registrar el cobro. Inténtalo de nuevo.';

  @override
  String agendaCobrarConceptoDefault(String date) {
    return 'Sesión $date';
  }

  @override
  String agendaCobrarTarifaReferencia(String amount) {
    return 'Tarifa de referencia: $amount';
  }

  @override
  String get workoutSummaryHeaderCompleted => 'BUEN ENTRENO';

  @override
  String get workoutSummaryHeaderAbandoned => 'SESIÓN INTERRUMPIDA';

  @override
  String get workoutStatDuration => 'DURACIÓN';

  @override
  String get workoutStatVolume => 'VOLUMEN';

  @override
  String get workoutStatDurationMin => 'DURACIÓN MIN';

  @override
  String get workoutStatVolumeKg => 'VOLUMEN KG';

  @override
  String get workoutStatSets => 'SETS';

  @override
  String get workoutStatPrsToday => 'PRs HOY';

  @override
  String get workoutStatPrsTodayStub => '—';

  @override
  String get workoutPrsSectionTitle => 'PRS DE LA SESIÓN';

  @override
  String get workoutPrsPlaceholder => 'Próximamente';

  @override
  String get workoutButtonDone => 'LISTO';

  @override
  String get workoutButtonShare => 'COMPARTIR';

  @override
  String get workoutButtonRetry => 'Reintentar';

  @override
  String get workoutButtonBackToWorkout => 'Volver a Entrenar';

  @override
  String get workoutNotFoundTitle => 'Sesión no encontrada';

  @override
  String get workoutErrorTitle => 'No pudimos cargar tu sesión';

  @override
  String get workoutSnackShareSuccess => '¡Post compartido!';

  @override
  String get workoutSnackShareError =>
      'No pudimos compartir tu post. Intentá de nuevo.';

  @override
  String get workoutPostAutoCompleteText => '¡Terminé mi entreno! 💪';

  @override
  String get workoutWeekCompletedTitle => '¡Semana cumplida! 🔥';

  @override
  String workoutWeekCompletedStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Llevas $count semanas de racha.',
      one: '¡Tu primera semana cumplida!',
    );
    return '$_temp0';
  }

  @override
  String get workoutWeekCompletedAction => 'Ver resumen de la semana';

  @override
  String get wellbeingTrendScreenTitle => 'CÓMO ME SENTÍ';

  @override
  String get wellbeingTrendEmptyState =>
      'Todavía no registraste cómo te sientes. Cuando lo hagas, verás tu propia serie aquí.';

  @override
  String get wellbeingTrendNeedsMoreData =>
      'Con un solo registro todavía no hay tendencia que mostrar.';

  @override
  String get wellbeingTrendLoadError =>
      'No pudimos cargar tu registro. Inténtalo de nuevo.';

  @override
  String get wellbeingTrendPainHeading => 'DOLOR O MOLESTIA';

  @override
  String wellbeingTrendPainCount(int painCount, int total) {
    return '$painCount de $total registros con dolor';
  }

  @override
  String wellbeingTrendPainCountPrevious(int painCount, int total) {
    return 'Período anterior: $painCount de $total';
  }

  @override
  String get wellbeingTrendAreasHeading => 'ZONAS REGISTRADAS';

  @override
  String get wellbeingTrendPainMark => 'con dolor';

  @override
  String get insightsTileWellbeingTitle => 'Cómo me sentí';

  @override
  String get insightsTileWellbeingSubtitle =>
      'Tu registro de sensación y dolor en el tiempo';

  @override
  String get wellbeingDailyTitle => '¿CÓMO TE SIENTES HOY?';

  @override
  String get wellbeingDailyPrompt => 'Anota cómo amaneces, entrenes o no.';

  @override
  String get wellbeingCheckInTitle => '¿CÓMO TE SENTISTE?';

  @override
  String get wellbeingCheckInFromToday => 'Ya lo contaste hoy en Inicio.';

  @override
  String get wellbeingCheckInUseForSession => 'USAR PARA ESTE ENTRENO';

  @override
  String get wellbeingCheckInOptional => 'Opcional. Podés saltearlo.';

  @override
  String get wellbeingFeelingVeryBad => 'Muy mal';

  @override
  String get wellbeingFeelingBad => 'Mal';

  @override
  String get wellbeingFeelingNeutral => 'Normal';

  @override
  String get wellbeingFeelingGood => 'Bien';

  @override
  String get wellbeingFeelingGreat => 'Muy bien';

  @override
  String get wellbeingPainQuestion => '¿Tuviste dolor o molestia?';

  @override
  String get wellbeingPainYes => 'SÍ';

  @override
  String get wellbeingPainNo => 'NO';

  @override
  String get wellbeingPainAreasQuestion => '¿En qué zona?';

  @override
  String get wellbeingPainAreasHint => 'Podés marcar más de una.';

  @override
  String get wellbeingNoteLabel => 'Nota (opcional)';

  @override
  String get wellbeingNoteHint => 'Algo que quieras recordar de hoy';

  @override
  String get wellbeingMedicalDisclaimer =>
      'Si el dolor persiste, consultá a un profesional de la salud.';

  @override
  String get wellbeingSaveButton => 'GUARDAR';

  @override
  String get wellbeingSkipButton => 'AHORA NO';

  @override
  String get wellbeingSavedLabel => 'REGISTRADO';

  @override
  String get wellbeingEditButton => 'Editar';

  @override
  String get wellbeingSaveError =>
      'No pudimos guardar tu registro. Probá de nuevo.';

  @override
  String get shareWorkoutComposerTitle => 'COMPARTIR ENTRENO';

  @override
  String get shareWorkoutComposerHint => '¿Cómo estuvo tu entreno?';

  @override
  String get shareWorkoutComposerPublish => 'PUBLICAR';

  @override
  String get shareWorkoutComposerAddPhoto => 'AGREGAR FOTO';

  @override
  String get shareWorkoutComposerRemovePhoto => 'Quitar foto';

  @override
  String get shareWorkoutComposerPhotoError =>
      'No pudimos usar esa foto. Probá con otra.';

  @override
  String get shareWorkoutComposerPreviewTitle => 'TU ENTRENO';

  @override
  String get postCardWorkoutDetailShow => 'VER DETALLE';

  @override
  String get postCardWorkoutDetailHide => 'OCULTAR DETALLE';

  @override
  String postCardWorkoutDetailTruncated(int count) {
    return 'Se muestran los primeros $count ejercicios.';
  }

  @override
  String get workoutHistorialHeading => 'HISTORIAL';

  @override
  String get coachSessionHistoryInProgress => 'En curso';

  @override
  String get coachSessionHistoryIncomplete => 'Sin completar';

  @override
  String get coachSessionHistoryEmpty =>
      'Este alumno todavía no registró entrenamientos.';

  @override
  String get workoutHistorialEmptyMessage => 'Todavía no entrenaste.';

  @override
  String get workoutHistorialEmptyCta => 'Empezar entrenamiento';

  @override
  String get workoutHistorialErrorMessage => 'No pudimos cargar tu historial.';

  @override
  String get workoutHistorialErrorRetry => 'Reintentar';

  @override
  String get workoutHistorialCardKgSuffix => ' kg';

  @override
  String get workoutHistorialCardMinSuffix => ' min';

  @override
  String get workoutHistorialShowLess => 'Ver menos';

  @override
  String workoutHistorialShowMore(int n) {
    return 'Ver más ($n)';
  }

  @override
  String get workoutHistorialSeeAll => 'Ver todo';

  @override
  String get workoutHistorialFullTitle => 'HISTORIAL';

  @override
  String get workoutDetailStatDuration => 'DURACIÓN';

  @override
  String get workoutDetailStatSets => 'SETS';

  @override
  String get workoutDetailStatVolume => 'VOLUMEN';

  @override
  String get workoutDetailStatDurationMin => 'DURACIÓN MIN';

  @override
  String get workoutDetailStatVolumeKg => 'VOLUMEN KG';

  @override
  String get workoutDetailStatPrsToday => 'PRS HOY';

  @override
  String get workoutDetailPrBadge => 'PR';

  @override
  String get workoutSelfEditorTitle => 'Nueva rutina';

  @override
  String get workoutSelfEditorEditTitle => 'Editar rutina';

  @override
  String get workoutSelfEditorSubmitLabel => 'CREAR RUTINA';

  @override
  String get workoutSelfEditorUpdateLabel => 'GUARDAR CAMBIOS';

  @override
  String get workoutSelfEditorSuccess => 'Rutina creada';

  @override
  String get workoutSelfEditorUpdateSuccess => 'Rutina actualizada';

  @override
  String get workoutSelfEditorNotFound =>
      'Esta rutina ya no existe. Volvé y actualizá la lista.';

  @override
  String get workoutSelfEditorError => 'No pudimos crear la rutina. Reintentá.';

  @override
  String get workoutDiscardError =>
      'No pudimos descartar la sesión. Probá de nuevo.';

  @override
  String get workoutSelfEditorPermissionDenied =>
      'No tenés permisos para hacer esto. Recargá la app.';

  @override
  String get workoutEditStubToast =>
      'Pronto vas a poder editar el contenido. Por ahora podés archivar y crear de nuevo.';

  @override
  String get workoutSelfEditorCapReached =>
      'Llegaste al máximo de 10 rutinas activas.';

  @override
  String get workoutRoutineUseAsBase => 'Usar como base';

  @override
  String get workoutRoutineCustomizeTitle => 'Personalizar rutina';

  @override
  String get workoutRoutineCustomizeSubmitLabel => 'GUARDAR COMO MÍA';

  @override
  String workoutRoutineCopyName(String name) {
    return '$name (mi versión)';
  }

  @override
  String get workoutTabYours => 'TU ENTRENO';

  @override
  String get workoutTabExplore => 'EXPLORAR';

  @override
  String get workoutExploreEmptyAll => 'No hay rutinas todavía.';

  @override
  String get workoutExploreEmptyLevel => 'No hay rutinas para este nivel.';

  @override
  String templatesFilterEmptyDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'No hay plantillas de $days días',
      one: 'No hay plantillas de 1 día',
    );
    return '$_temp0';
  }

  @override
  String templatesFilterEmptyMinutes(String minutes) {
    return 'No hay plantillas de $minutes min o menos';
  }

  @override
  String get templatesFilterEmptyCombination =>
      'Ninguna plantilla cumple todo lo que elegiste a la vez';

  @override
  String get templatesFilterEmptyGoals =>
      'Ninguna plantilla apunta a los objetivos que elegiste';

  @override
  String get templatesFilterEmptyZones =>
      'Ninguna plantilla trabaja las zonas que elegiste';

  @override
  String get templatesFilterEmptyAction => 'Ver todas';

  @override
  String get templatesFilterBarClear => 'Borrar filtros';

  @override
  String get templatesFiltersCleared => 'Filtros borrados';

  @override
  String get templatesFiltersClearError =>
      'No pudimos borrar los filtros. Inténtalo de nuevo.';

  @override
  String get templatesFiltersUndo => 'DESHACER';

  @override
  String get workoutExploreSearchHint =>
      'Buscar por nombre, músculo o ejercicio';

  @override
  String get workoutExploreSearchClear => 'Borrar búsqueda';

  @override
  String workoutExploreSearchEmpty(String query) {
    return 'No encontramos plantillas para «$query»';
  }

  @override
  String get workoutExploreLoadError => 'Hubo un error cargando las rutinas.';

  @override
  String get workoutMisRutinasSectionTitle => 'MIS RUTINAS';

  @override
  String get workoutMisRutinasCta => 'CREAR RUTINA';

  @override
  String get workoutMisRutinasCtaDisabledTooltip =>
      'Llegaste al máximo de 10 rutinas activas. Archivá una para crear otra.';

  @override
  String get workoutMisRutinasEmptyState =>
      'Todavía no creaste ninguna rutina. Tocá CREAR RUTINA para armar la primera.';

  @override
  String get workoutMisRutinasError => 'No pudimos cargar tus rutinas.';

  @override
  String get workoutMisRutinasErrorRetry => 'Reintentar';

  @override
  String get workoutMisRutinasOverflowEdit => 'EDITAR';

  @override
  String get workoutMisRutinasOverflowArchive => 'ELIMINAR';

  @override
  String get workoutMisRutinasOverflowMarkActive => 'MARCAR COMO ACTIVA';

  @override
  String get workoutMisRutinasOverflowUnmarkActive => 'DESMARCAR COMO ACTIVA';

  @override
  String get workoutMisRutinasActiveChip => 'ACTIVA';

  @override
  String get workoutMisRutinasMarkActiveSuccess =>
      'Marcada como tu rutina activa';

  @override
  String get workoutMisRutinasUnmarkActiveSuccess =>
      'Ya no es tu rutina activa';

  @override
  String get workoutMisRutinasActiveError =>
      'No pudimos cambiar el estado. Reintentá.';

  @override
  String get workoutMisRutinasConfirmTitle => 'Eliminar rutina';

  @override
  String get workoutMisRutinasConfirmBody =>
      'La rutina dejará de aparecer en MIS RUTINAS. Tu historial se conserva.';

  @override
  String get workoutMisRutinasConfirmCancel => 'CANCELAR';

  @override
  String get workoutMisRutinasConfirmConfirm => 'ELIMINAR';

  @override
  String get workoutMisRutinasArchiveSuccess => 'Rutina eliminada';

  @override
  String get workoutMisRutinasArchiveError =>
      'No pudimos eliminar la rutina. Reintentá.';

  @override
  String get workoutRutinasCoachChip => 'DE TU COACH';

  @override
  String get workoutPlantillasTrainerChip => 'ENTRENADOR';

  @override
  String get templateRatingsTitle => 'CALIFICACIONES';

  @override
  String get templateRatingsNoneYet =>
      'Todavía nadie calificó esta rutina. ¡Sé el primero!';

  @override
  String templateRatingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count calificaciones',
      one: '1 calificación',
    );
    return '$_temp0';
  }

  @override
  String get templateRatingsMineEmpty => '¿Qué te pareció?';

  @override
  String get templateRatingsMineLabel => 'Tu calificación';

  @override
  String get templateRatingsRateCta => 'CALIFICAR';

  @override
  String get templateRatingsEditCta => 'EDITAR';

  @override
  String get templateRatingsEmpty => 'Todavía no hay comentarios.';

  @override
  String get templateRatingsError => 'No pudimos cargar los comentarios.';

  @override
  String get templateRatingSheetTitle => 'Califica esta rutina';

  @override
  String get templateRatingSheetTitleEdit => 'Edita tu calificación';

  @override
  String get templateRatingSheetCommentHint =>
      'Cuenta cómo te fue con esta rutina (opcional)';

  @override
  String get templateRatingSheetCancel => 'CANCELAR';

  @override
  String get templateRatingSheetSubmit => 'ENVIAR';

  @override
  String get templateRatingSheetSuccess => '¡Gracias por calificar!';

  @override
  String get templateRatingSheetError => 'No pudimos guardar tu calificación.';

  @override
  String get workoutSplitFallback => 'Rutina libre';

  @override
  String get workoutPickerMuscleFilter => 'Músculos';

  @override
  String get workoutPickerEquipmentFilter => 'Equipamiento';

  @override
  String get workoutPickerMuscleSheetTitle => 'Grupo muscular';

  @override
  String get workoutPickerEquipmentSheetTitle => 'Tipo de equipo';

  @override
  String get workoutPickerMuscleAll => 'Todos los músculos';

  @override
  String get workoutPickerEquipmentAll => 'Todo el equipamiento';

  @override
  String get workoutPickerEmptyFiltered => 'Ningún ejercicio coincide';

  @override
  String get workoutPickerEmptyFilteredHint =>
      'Probá quitando un filtro o ajustando la búsqueda.';

  @override
  String workoutPickerAddButton(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ejercicios',
      one: 'ejercicio',
    );
    return 'Agregar $countString $_temp0';
  }

  @override
  String get workoutSelfEditorNameHint => 'Mi rutina';

  @override
  String get workoutPickerSheetClear => 'Limpiar';

  @override
  String get workoutPickerSheetApplyAll => 'APLICAR (TODOS)';

  @override
  String workoutPickerSheetApply(int count) {
    return 'APLICAR ($count)';
  }

  @override
  String get appFcmSnackBarActionLabel => 'Ver';

  @override
  String get profileEditPersonalNameRequired => 'Ingresá un nombre';

  @override
  String get profileEditPersonalNameMaxLength => 'Máximo 50 caracteres';

  @override
  String get profileEditPersonalWeightInvalidNumber =>
      'Ingresá un número válido';

  @override
  String get profileEditPersonalWeightOutOfRange =>
      'Ingresá un peso entre 30 y 300 kg';

  @override
  String get profileEditPersonalHeightOutOfRange =>
      'Ingresá una altura entre 120 y 230 cm';

  @override
  String get eliminarCuentaSheetTitle => 'Eliminar cuenta';

  @override
  String get eliminarCuentaSheetBodyPrefix => 'Esta acción es ';

  @override
  String get eliminarCuentaSheetBodyBold => 'irreversible';

  @override
  String get eliminarCuentaSheetBodySuffix =>
      '. Vamos a eliminar tu cuenta, tu perfil, tu historial de entrenamientos, tus posts y tu foto.';

  @override
  String get eliminarCuentaSheetSubscriptionNote =>
      'Si tenés una suscripción paga, se cancela y no se te vuelve a cobrar. No se devuelve el dinero del período en curso.';

  @override
  String get eliminarCuentaSheetDeleteCta => 'ELIMINAR';

  @override
  String get eliminarCuentaSheetCancelCta => 'CANCELAR';

  @override
  String get eliminarCuentaSheetLoadingLabel => 'Eliminando tu cuenta...';

  @override
  String get eliminarCuentaSheetLoadingSubtitle =>
      'Esto puede tardar unos segundos.';

  @override
  String get eliminarCuentaSheetErrorFallback =>
      'No pudimos eliminar tu cuenta. Probá de nuevo.';

  @override
  String get eliminarCuentaSheetRetryLabel => 'Reintentar';

  @override
  String get dashboardResumenDelDiaTitle => 'RESUMEN DEL DÍA';

  @override
  String get dashboardStatPendientes => 'PENDIENTES';

  @override
  String get dashboardStatCompletadas => 'COMPLETADAS';

  @override
  String get dashboardStatCanceladas => 'CANCELADAS';

  @override
  String get dashboardProximasSesionesSectionLabel => 'PRÓXIMAS SESIONES';

  @override
  String get dashboardAgendaTrailingLabel => 'Agenda';

  @override
  String get dashboardEntrenaronHoySectionLabel => 'ENTRENARON HOY';

  @override
  String get dashboardDejarFeedbackLabel => 'Dejar feedback';

  @override
  String get dashboardActividadRecienteSectionLabel => 'ACTIVIDAD RECIENTE';

  @override
  String get dashboardWeekday1 => 'LUNES';

  @override
  String get dashboardWeekday2 => 'MARTES';

  @override
  String get dashboardWeekday3 => 'MIÉRCOLES';

  @override
  String get dashboardWeekday4 => 'JUEVES';

  @override
  String get dashboardWeekday5 => 'VIERNES';

  @override
  String get dashboardWeekday6 => 'SÁBADO';

  @override
  String get dashboardWeekday7 => 'DOMINGO';

  @override
  String get dashboardMonth1 => 'ENERO';

  @override
  String get dashboardMonth2 => 'FEBRERO';

  @override
  String get dashboardMonth3 => 'MARZO';

  @override
  String get dashboardMonth4 => 'ABRIL';

  @override
  String get dashboardMonth5 => 'MAYO';

  @override
  String get dashboardMonth6 => 'JUNIO';

  @override
  String get dashboardMonth7 => 'JULIO';

  @override
  String get dashboardMonth8 => 'AGOSTO';

  @override
  String get dashboardMonth9 => 'SEPTIEMBRE';

  @override
  String get dashboardMonth10 => 'OCTUBRE';

  @override
  String get dashboardMonth11 => 'NOVIEMBRE';

  @override
  String get dashboardMonth12 => 'DICIEMBRE';

  @override
  String get dashboardDateToday => 'Hoy';

  @override
  String get dashboardDateTomorrow => 'Mañana';

  @override
  String get dashboardRechazarLabel => 'RECHAZAR';

  @override
  String get dashboardAceptarLabel => 'ACEPTAR';

  @override
  String get dashboardPagosPorCobrarTitle => 'PAGOS POR COBRAR';

  @override
  String get dashboardCobroTrailingLabel => '+ Cobro';

  @override
  String get dashboardAsignarRutinaLabel => '+ ASIGNAR RUTINA';

  @override
  String get dashboardCobroSueltoTitle => 'COBRO SUELTO';

  @override
  String get dashboardAlumnoLabel => 'ALUMNO';

  @override
  String get dashboardMontoArsLabel => 'MONTO (ARS)';

  @override
  String get dashboardConceptoLabel => 'CONCEPTO';

  @override
  String get dashboardAgregarCobroLabel => 'AGREGAR COBRO';

  @override
  String get dashboardMontoHint => 'Ej: 5000';

  @override
  String get dashboardConceptoHint => 'Ej: Clase de verano';

  @override
  String get dashboardVenceElLabel => 'VENCE EL (OPCIONAL)';

  @override
  String get dashboardVenceElHint => 'Sin fecha de vencimiento';

  @override
  String get dashboardVenceElQuitar => 'Quitar fecha de vencimiento';

  @override
  String get dashboardSeleccionaAlumnoHint => 'Seleccioná un alumno';

  @override
  String get dashboardSinAlumnosActivos => 'No tenés alumnos activos.';

  @override
  String get dashboardMarcarCobradoTitle => '¿Marcar como cobrado?';

  @override
  String get dashboardCancelarLabel => 'Cancelar';

  @override
  String get dashboardCobradoLabel => 'Cobrado';

  @override
  String get dashboardCobroRegistrado => 'Cobro registrado.';

  @override
  String get dashboardCobroError =>
      'Error al registrar el cobro. Intentá de nuevo.';

  @override
  String get dashboardCobroSueltoAgregado => 'Cobro suelto agregado.';

  @override
  String get dashboardCompletaCampos => 'Completá todos los campos.';

  @override
  String get dashboardMontoInvalido => 'Ingresá un monto válido.';

  @override
  String get dashboardGuardarError => 'Error al guardar. Intentá de nuevo.';

  @override
  String get dashboardCadenceMensual => 'Mensual';

  @override
  String get dashboardCadenceSemanal => 'Semanal';

  @override
  String get dashboardCadencePorSesion => 'Por sesión';

  @override
  String get dashboardCadenceSuelto => 'Suelto';

  @override
  String get dashboardAlumnoFallback => 'Alumno';

  @override
  String get dashboardProximamente => 'Próximamente.';

  @override
  String get dashboardIniciaSesion =>
      'Iniciá sesión para ver tus próximos turnos.';

  @override
  String get dashboardCargando => 'Cargando…';

  @override
  String get dashboardErrorTurnos => 'No pudimos cargar tus próximos turnos.';

  @override
  String get dashboardErrorResumen => 'No pudimos cargar el resumen del día.';

  @override
  String get dashboardSinTurnosProximos =>
      'No tenés turnos próximos confirmados.';

  @override
  String get dashboardNadieEntreno => 'Nadie entrenó hoy todavía.';

  @override
  String get athleteDetailSeguimientoEmpty =>
      'Todavía no dejaste seguimiento de este alumno.';

  @override
  String get athleteDetailSeguimientoLoadError =>
      'No pudimos cargar el seguimiento.';

  @override
  String get dashboardFeedbackSheetTitle => 'Dejar feedback';

  @override
  String get dashboardFeedbackPickAthlete =>
      '¿A quién le querés dejar feedback?';

  @override
  String get dashboardFeedbackComposerHint =>
      'Escribí tu devolución del entrenamiento…';

  @override
  String get dashboardFeedbackSave => 'Guardar';

  @override
  String get dashboardFeedbackSaved => 'Feedback guardado';

  @override
  String get dashboardFeedbackSaveError =>
      'No pudimos guardar el feedback. Probá de nuevo.';

  @override
  String get dashboardErrorActividad =>
      'No pudimos cargar la actividad de hoy.';

  @override
  String get dashboardSinActividadReciente =>
      'Sin actividad en los últimos días.';

  @override
  String get dashboardSinCobros => 'Sin cobros pendientes.';

  @override
  String get dashboardErrorCobros => 'No pudimos cargar los cobros.';

  @override
  String get dashboardHolaSinNombre => 'HOLA';

  @override
  String get a11yDashboardAvatarButton => 'Editar tu perfil profesional';

  @override
  String get dashboardSolicitudesPendientesEmpty =>
      'No tenés solicitudes pendientes.';

  @override
  String dashboardSolicitudesPendientesTitle(int count) {
    return 'SOLICITUDES PENDIENTES ($count)';
  }

  @override
  String dashboardHolaConNombre(String name) {
    return 'HOLA, $name';
  }

  @override
  String get reviewSnackBarSuccess => '¡Gracias por tu reseña!';

  @override
  String get plantillasRetryLabel => 'Reintentar';

  @override
  String get profileSetupSaveError =>
      'No pudimos guardar tu perfil. Probá de nuevo.';

  @override
  String get profileSetupCancelDialogTitle =>
      '¿Cancelar la creación de tu cuenta?';

  @override
  String get profileSetupCancelDialogBody =>
      'Vamos a borrar tu cuenta. Esta acción no se puede deshacer.';

  @override
  String get profileSetupCancelAccountError =>
      'No pudimos cancelar la cuenta. Probá de nuevo.';

  @override
  String get verifyMailWrongEmailAction => 'Me equivoqué de mail';

  @override
  String get verifyMailWrongEmailDialogTitle => '¿Te equivocaste de mail?';

  @override
  String get verifyMailWrongEmailDialogBody =>
      'Vamos a borrar esta cuenta para que puedas registrarte de nuevo con el mail correcto. Vas a poder usar el mismo nombre.';

  @override
  String get verifyMailWrongEmailDialogConfirm => 'Borrar cuenta';

  @override
  String get verifyMailWrongEmailDialogBack => 'Volver';

  @override
  String get verifyMailWrongEmailError =>
      'No pudimos borrar la cuenta. Probá de nuevo.';

  @override
  String get profileSetupGymSelectError =>
      'No pudimos cargar ese gimnasio. Inténtalo de nuevo o elige «OTRO GYM / SIN GYM».';

  @override
  String get reAuthPasswordLabel => 'Contraseña';

  @override
  String get profileGymSearchHint => 'Buscar gym';

  @override
  String get profileEditTrainerTitleEdit => 'Editá tu perfil profesional';

  @override
  String get profileEditTrainerTitleOnboarding =>
      'Completá tu perfil profesional';

  @override
  String get profileEditTrainerSaveSuccess => 'Perfil actualizado.';

  @override
  String get profileEditTrainerSaveError =>
      'No pudimos guardar. Probá de nuevo.';

  @override
  String get profileEditTrainerValidationSpecialty => 'Elegí una especialidad.';

  @override
  String get profileEditTrainerValidationLocation =>
      'Agregá al menos una ubicación o activá clases virtuales.';

  @override
  String get trainerLocationConsentSheetTitle => 'PUBLICAR TU UBICACIÓN';

  @override
  String get trainerLocationConsentSheetBody =>
      'Los atletas van a poder ver dónde entrenas y a qué distancia les queda. Puedes apagar esto cuando quieras desde tu perfil profesional.';

  @override
  String get trainerLocationConsentSheetAccept => 'ACEPTAR';

  @override
  String get trainerLocationConsentSheetRevoke => 'APAGAR LA PUBLICACIÓN';

  @override
  String get profileEditTrainerConsentConfirmTitle =>
      '¿Publicar esta ubicación?';

  @override
  String get profileEditTrainerConsentConfirmBody =>
      'Al guardar, esta ubicación va a ser visible para los atletas, con su punto en el mapa y la distancia hasta ellos. Puedes apagarla cuando quieras.';

  @override
  String get profileEditTrainerConsentConfirmAccept => 'PUBLICAR';

  @override
  String get profileEditTrainerConsentConfirmCancel => 'CANCELAR';

  @override
  String get profileEditTrainerPublished => 'Visible para los atletas';

  @override
  String get profileEditTrainerNotPublished => 'No publicada';

  @override
  String get legacyPrivacyNoticeTitle =>
      'Actualizamos la Política de Privacidad';

  @override
  String get legacyPrivacyNoticeBody =>
      'Aclaramos cómo tratamos tu ubicación. No cambió nada de lo que recolectamos de ti.';

  @override
  String get legacyPrivacyNoticeAction => 'LEER LA POLÍTICA';

  @override
  String get legacyPrivacyNoticeDismiss => 'Cerrar';

  @override
  String get athleteDetailPlansSection => 'PLANES ASIGNADOS';

  @override
  String get athleteDetailProfileLoadError => 'No pudimos cargar este perfil.';

  @override
  String get athleteDetailPlanDeleteTitle => 'Eliminar plan';

  @override
  String get athleteDetailPlanDeleteCancel => 'Cancelar';

  @override
  String get athleteDetailPlanDeleteConfirm => 'Eliminar';

  @override
  String get athleteDetailPlanDeleteSuccess => 'Plan eliminado.';

  @override
  String get athleteDetailMessageCta => 'MENSAJE';

  @override
  String get newSessionSheetTitle => 'NUEVA SESIÓN';

  @override
  String get newSessionSheetAlumnoLabel => 'ALUMNO';

  @override
  String get newSessionSheetFechaLabel => 'FECHA';

  @override
  String get newSessionSheetHoraLabel => 'HORA DE INICIO';

  @override
  String get newSessionSheetDuracionLabel => 'DURACIÓN (MIN)';

  @override
  String get newSessionSheetNotaLabel => 'NOTA PREVIA (OPCIONAL)';

  @override
  String get newSessionSheetSubmitSingle => 'REGISTRAR SESIÓN';

  @override
  String get newSessionSheetSubmitRecurring => 'REGISTRAR SERIE';

  @override
  String get newSessionSheetDurationError =>
      'Ingresá una duración válida (5–480 min).';

  @override
  String get newSessionSheetNoActiveAthletes => 'No tenés alumnos activos.';

  @override
  String get athleteCoachViewTrainerFallbackName => 'tu Personal Trainer';

  @override
  String get athleteCoachViewLinkError => 'No pudimos cargar tu vínculo.';

  @override
  String get checkInHeader => '¿ESTÁS EN EL GYM HOY?';

  @override
  String get checkInNeutralSubtext => 'Confirma tu entrenamiento de hoy';

  @override
  String get checkInNoButton => 'NO';

  @override
  String get checkInSiButton => 'SÍ, ENTRÉ';

  @override
  String checkInGymSubtext(String gymName) {
    return '$gymName · ¡Detectamos que podés estar entrenando!';
  }

  @override
  String get checkInError =>
      'No pudimos registrar tu check-in. Probá de nuevo.';

  @override
  String get profileCuentaTitle => 'CUENTA';

  @override
  String get profileCuentaSolicitudesTitle => 'Solicitudes de seguidores';

  @override
  String profileCuentaSolicitudesSubtitle(int count) {
    return '$count nuevas';
  }

  @override
  String get profileCuentaDatosPersonalesTitle => 'Datos personales';

  @override
  String get profileCuentaDatosPersonalesSubtitle => 'Editá tu info';

  @override
  String get profileCuentaGimnasioTitle => 'Gimnasio';

  @override
  String get profileCuentaNoGym => 'Sin gym';

  @override
  String get profileCuentaMisRutinasTitle => 'Mis rutinas';

  @override
  String profileCuentaRutinasSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activas',
      one: '1 activa',
    );
    return '$_temp0';
  }

  @override
  String get chatListTitle => 'MENSAJES';

  @override
  String get chatListDeletedUser => 'Usuario eliminado';

  @override
  String get chatListStartConversation => 'Iniciá la conversación';

  @override
  String get chatListEmptyTitle => 'Sin mensajes todavía';

  @override
  String get chatListEmptyBody =>
      'Le podés escribir a tu PF y a quienes seguís, y a cualquier perfil público desde su perfil. Cuando sigas a alguien, lo vas a ver acá.';

  @override
  String get chatListError => 'No pudimos cargar tus mensajes.';

  @override
  String get chatListRetryLabel => 'Reintentar';

  @override
  String get chatContactsSectionTitle => 'Escribile a…';

  @override
  String get chatContactReasonCoach => 'Tu PF';

  @override
  String get chatContactReasonAthlete => 'Tu alumno';

  @override
  String get chatContactReasonFollowing => 'Lo seguís';

  @override
  String get chatContactsError =>
      'No pudimos cargar a quién le podés escribir.';

  @override
  String get chatContactOpenError =>
      'No pudimos abrir el chat. Probá de nuevo.';

  @override
  String get chatActionArchive => 'Archivar';

  @override
  String get chatActionUnarchive => 'Desarchivar';

  @override
  String get chatActionDelete => 'Eliminar chat';

  @override
  String get chatActionUndo => 'Deshacer';

  @override
  String get chatArchivedToast => 'Chat archivado';

  @override
  String get chatUnarchivedToast => 'Chat desarchivado';

  @override
  String get chatDeletedToast => 'Chat eliminado';

  @override
  String get chatActionError =>
      'No pudimos actualizar el chat. Probá de nuevo.';

  @override
  String get chatDeleteConfirmTitle => '¿Eliminar el chat?';

  @override
  String get chatDeleteConfirmBody =>
      'Se borra el historial sólo para vos: la otra persona lo sigue viendo. Si te vuelve a escribir, el chat reaparece desde ese mensaje.';

  @override
  String get chatActionViewProfile => 'Ver perfil';

  @override
  String chatHeaderProfileA11y(String name) {
    return 'Ver el perfil de $name';
  }

  @override
  String get chatMoreActionsA11y => 'Opciones del chat';

  @override
  String chatArchivedSectionTitle(int count) {
    return 'Archivados · $count';
  }

  @override
  String get chatRelativeJustNow => 'recién';

  @override
  String chatRelativeMinutes(int minutes) {
    return 'hace ${minutes}m';
  }

  @override
  String chatRelativeHours(int hours) {
    return 'hace ${hours}h';
  }

  @override
  String chatRelativeDays(int days) {
    return 'hace ${days}d';
  }

  @override
  String get chatScreenTitleFallback => 'Usuario';

  @override
  String get chatScreenLoadError => 'No pudimos cargar los mensajes.';

  @override
  String get chatScreenComposerHint => 'Escribí un mensaje…';

  @override
  String get chatScreenSendLabel => 'Enviar';

  @override
  String get chatScreenSendError =>
      'No pudimos enviar el mensaje. Probá de nuevo.';

  @override
  String get performanceLogTitle => 'Cargar evaluación';

  @override
  String get performanceLogCancel => 'Cancelar';

  @override
  String get performanceLogSaveCta => 'GUARDAR EVALUACIÓN';

  @override
  String get performanceLogNoSession =>
      'No hay sesión activa. No se puede guardar.';

  @override
  String get performanceLogSaveSuccess => 'Evaluación guardada';

  @override
  String get performanceLogSaveError =>
      'No pudimos guardar la evaluación. Probá de nuevo.';

  @override
  String get performanceLogNotesHint => 'Observaciones del entrenador…';

  @override
  String get performanceLogSectionJumps => 'SALTOS (cm)';

  @override
  String get performanceLogSectionSpeed => 'VELOCIDAD (seg)';

  @override
  String get performanceLogSectionStrength => 'FUERZA 1RM (kg)';

  @override
  String get performanceLogSectionEndurance => 'RESISTENCIA / OTROS';

  @override
  String get performanceLogSectionNotes => 'NOTAS';

  @override
  String get performanceLogFieldCmj => 'CMJ';

  @override
  String get performanceLogFieldSquatJump => 'Squat Jump';

  @override
  String get performanceLogFieldAbalakov => 'Abalakov';

  @override
  String get performanceLogFieldBroadJump => 'Salto largo';

  @override
  String get performanceLogFieldSprint10 => 'Sprint 10m';

  @override
  String get performanceLogFieldSprint20 => '20m';

  @override
  String get performanceLogFieldSprint30 => '30m';

  @override
  String get performanceLogFieldSprint40 => '40m';

  @override
  String get performanceLogFieldSquat1rm => 'Sentadilla';

  @override
  String get performanceLogFieldBenchPress => 'Press banca';

  @override
  String get performanceLogFieldDeadlift => 'Peso muerto';

  @override
  String get performanceLogFieldOverheadPress => 'Press militar';

  @override
  String get performanceLogFieldPullUp => 'Dominada lastrada';

  @override
  String get performanceLogFieldVo2max => 'VO2máx';

  @override
  String get performanceLogFieldCourseNavette => 'Course Navette (nivel)';

  @override
  String get performanceLogFieldCooper => 'Cooper';

  @override
  String get performanceLogFieldSitAndReach => 'Flexibilidad sit-and-reach';

  @override
  String get performanceChartSectionLabel => 'PROGRESO';

  @override
  String get performanceChartEmptyHint =>
      'Cargá otra evaluación para ver el progreso.';

  @override
  String performanceChartSpanDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días',
      one: 'día',
    );
    return '($count $_temp0)';
  }

  @override
  String performanceChartSpanWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'semanas',
      one: 'semana',
    );
    return '($count $_temp0)';
  }

  @override
  String get performanceChartMetricCmj => 'CMJ';

  @override
  String get performanceChartMetricSquatJump => 'Squat Jump';

  @override
  String get performanceChartMetricAbalakov => 'Abalakov';

  @override
  String get performanceChartMetricBroadJump => 'Salto largo';

  @override
  String get performanceChartMetricSprint10 => 'Sprint 10m';

  @override
  String get performanceChartMetricSprint20 => 'Sprint 20m';

  @override
  String get performanceChartMetricSprint30 => 'Sprint 30m';

  @override
  String get performanceChartMetricSprint40 => 'Sprint 40m';

  @override
  String get performanceChartMetricSquat1rm => 'Sentadilla 1RM';

  @override
  String get performanceChartMetricBench1rm => 'Banca 1RM';

  @override
  String get performanceChartMetricDeadlift1rm => 'Peso muerto 1RM';

  @override
  String get performanceChartMetricOverheadPress1rm => 'Press militar 1RM';

  @override
  String get performanceChartMetricPullUp1rm => 'Dominada 1RM';

  @override
  String get performanceChartMetricVo2max => 'VO2máx';

  @override
  String get performanceChartMetricCourseNavette => 'Course Navette';

  @override
  String get performanceChartMetricCooper => 'Cooper';

  @override
  String get performanceChartMetricSitAndReach => 'Flexibilidad';

  @override
  String routineEditorSetsMissingReps(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sets sin reps',
      one: '1 set sin reps',
    );
    return '$_temp0';
  }

  @override
  String get routineEditorEmptyDayTitle => 'DÍA VACÍO';

  @override
  String get routineEditorEmptyDayBody =>
      'Agregá el primer ejercicio y ya queda listo para entrenar.';

  @override
  String routineEditorDayTabA11y(int n, String estado) {
    return 'Día $n$estado';
  }

  @override
  String get routineEditorPlanSheetTitle => 'DATOS DEL PLAN';

  @override
  String get routineEditorPlanSheetA11y => 'Datos del plan';

  @override
  String get routineEditorSubtitleSelfPrivate => 'Tu rutina · solo la ves vos';

  @override
  String get routineEditorSubtitleSelfShared =>
      'Tu rutina · compartida en tu perfil';

  @override
  String get routineEditorSubtitleCustomizing => 'Copia tuya';

  @override
  String get routineEditorSubtitleAssigned => 'Plan asignado';

  @override
  String get routineEditorSubtitleTemplate => 'Plantilla reusable';

  @override
  String routineEditorSubtitleWeeks(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n semanas',
      one: '1 semana',
    );
    return '$_temp0';
  }

  @override
  String routineEditorDayName(int n) {
    return 'Día $n';
  }

  @override
  String get routineEditorAddExercise => 'Agregar ejercicio';

  @override
  String get routineEditorLevelLabel => 'NIVEL';

  @override
  String get routineEditorWeeksLabel => 'SEMANAS';

  @override
  String get routineEditorDaysLabel => 'DÍAS DEL PLAN';

  @override
  String get routineEditorAddWeek => 'Semana';

  @override
  String get routineEditorRemoveLastWeek => '';

  @override
  String get routineEditorDuplicateWeek => 'Duplicar semana';

  @override
  String routineEditorWeekShort(int n) {
    return 'Sem $n';
  }

  @override
  String routineEditorInvalidWeekHint(int week, int day) {
    return 'Sets incompletos en Sem $week · Día $day';
  }

  @override
  String get routineEditorDuplicateWeekTitle => '';

  @override
  String routineEditorDuplicateWeekBody(int sourceWeek, int targetWeek) {
    return '';
  }

  @override
  String get routineEditorDialogCancel => '';

  @override
  String get routineEditorDialogConfirm => '';

  @override
  String get routineEditorCopyPrescriptionTitle => '¿Copiar sets?';

  @override
  String routineEditorCopyPrescriptionBody(String sourceExercise) {
    return 'Se reemplazarán los sets de este ejercicio por los de «$sourceExercise».';
  }

  @override
  String get routineEditorSlotMenuCopyPrevious => 'Copiar sets del anterior';

  @override
  String get routineEditorSlotMenuReplace => 'Cambiar ejercicio';

  @override
  String get routineEditorSlotMenuMoveUp => 'Subir';

  @override
  String get routineEditorSlotMenuMoveDown => 'Bajar';

  @override
  String get routineEditorSlotMenuRemove => 'Eliminar';

  @override
  String routineEditorSupersetHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'EJERCICIOS',
      one: 'EJERCICIO',
    );
    return 'SUPERSERIE · $count $_temp0';
  }

  @override
  String get routineEditorSlotMenuHint =>
      'El ⋮ de cada ejercicio tiene cambiar, copiar sets y mover.';

  @override
  String get routineEditorRestLabel => 'Descanso';

  @override
  String get routineEditorAddSet => '+ Agregar set';

  @override
  String get routineEditorFillKgA11y =>
      'Replicar el peso del primer set en todos';

  @override
  String get routineEditorFillKgApplied => 'Peso replicado en todos los sets.';

  @override
  String get routineEditorFillKgEmpty =>
      'Introduce el peso del primer set para poder replicarlo.';

  @override
  String get routineEditorFillKgUndo => 'Deshacer';

  @override
  String get routineEditorFillColumnLabel => 'A TODAS';

  @override
  String get routineEditorFillColumnA11y =>
      'Replicar este valor en toda la columna';

  @override
  String get routineEditorNextCellLabel => 'SIG.';

  @override
  String get routineEditorNextCellA11y => 'Ir a la celda siguiente';

  @override
  String routineEditorAccessoryContext(
      String ejercicio, int set, String campo) {
    return '$ejercicio · set $set · $campo';
  }

  @override
  String get routineEditorFieldKg => 'kg';

  @override
  String get routineEditorFieldReps => 'reps';

  @override
  String routineEditorRepsStepIncreaseA11y(String amount) {
    return 'Sumar $amount repeticiones';
  }

  @override
  String routineEditorRepsStepDecreaseA11y(String amount) {
    return 'Restar $amount repeticiones';
  }

  @override
  String get routineEditorFillColumnEmpty =>
      'Cargá el peso de este set para poder replicarlo.';

  @override
  String routineEditorKgStepIncreaseA11y(String amount) {
    return 'Sumar $amount kilos al peso';
  }

  @override
  String routineEditorKgStepDecreaseA11y(String amount) {
    return 'Restar $amount kilos al peso';
  }

  @override
  String get routineEditorMeasureReps => 'Reps';

  @override
  String get routineEditorMeasureTime => 'Tiempo';

  @override
  String get routineEditorSetTypeNormal => '';

  @override
  String get routineEditorSetTypeWarmup => '';

  @override
  String get routineEditorSetTypeDrop => '';

  @override
  String get routineEditorSetTypeFailure => '';

  @override
  String get routineEditorNotesLabel => 'Nota para el alumno';

  @override
  String get routineEditorNotesHint => 'Técnica, tempo, RIR…';

  @override
  String get routineEditorSummaryLabel => 'RESUMEN';

  @override
  String get routineEditorSummaryHelp =>
      'Una frase que explique qué es la rutina, para alguien que nunca pisó un gimnasio.';

  @override
  String get routineEditorSummaryHint =>
      'Ej: Empujar, tirar y piernas: cada día trabaja un tipo de movimiento distinto.';

  @override
  String get routineEditorGoalsLabel => 'PARA QUÉ SIRVE';

  @override
  String get routineEditorGoalsHelp =>
      'Opcional. Ayuda a que el alumno encuentre la plantilla cuando busca por objetivo.';

  @override
  String get exerciseNoteFromCoachTag => 'DEL COACH';

  @override
  String routineEditorIncompleteSetsFeedback(String exerciseName) {
    return 'Completá los sets de \"$exerciseName\" antes de guardar.';
  }

  @override
  String get routineDetailNotFound => 'Rutina no encontrada';

  @override
  String get routineDetailNoDaysConfigured =>
      'Esta rutina no tiene días configurados.';

  @override
  String get routineDetailLoadError => 'No pudimos cargar la rutina.';

  @override
  String get routineDetailNoExercisesThisWeek => 'Sin ejercicios esta semana';

  @override
  String get routineDetailNoExercisesThisDay => 'No hay ejercicios en este día';

  @override
  String get routineDetailStatExercises => 'EJERCICIOS';

  @override
  String get routineDetailStatSets => 'SETS';

  @override
  String get routineDetailStatMinutes => 'MINUTOS';

  @override
  String get routineDetailSuperset => 'SUPERSERIE';

  @override
  String routineDetailDayLabel(int day) {
    return 'DÍA $day';
  }

  @override
  String routineDetailWeekLabel(int week) {
    return 'SEM $week';
  }

  @override
  String get routineDetailPlanComplete => 'PLAN COMPLETADO';

  @override
  String get routineDetailCompleted => 'COMPLETADO';

  @override
  String get routineDetailStart => 'EMPEZAR';

  @override
  String get routineDetailRepeat => 'REPETIR';

  @override
  String get routineEditorDeleteScopeTitle => '';

  @override
  String get routineEditorScopeOnlyThisWeek => '';

  @override
  String get routineEditorScopeAllWeeks => '';

  @override
  String get routineEditorAddScopeTitle => '';

  @override
  String get routineEditorAddScopeBody => '';

  @override
  String get routineEditorAddOnlyThisWeek => '';

  @override
  String get routineEditorAddAllWeeks => '';

  @override
  String get routineEditorWeekLabel => '';

  @override
  String get routineEditorLevelSection => '';

  @override
  String get routineEditorWeeksSection => '';

  @override
  String get routineEditorDaysSection => '';

  @override
  String get routineEditorNameHint => '';

  @override
  String get routineEditorSplitHint => '';

  @override
  String routineEditorIncompleteSetsLabel(int weekNumber) {
    return '';
  }

  @override
  String get commonBack => 'Volver';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonLoading => 'Cargando…';

  @override
  String get commonProcessing => 'Procesando…';

  @override
  String get commonWarning => 'Atención';

  @override
  String get chatSendingA11y => 'Enviando…';

  @override
  String get feedMessagesA11y => 'Mensajes';

  @override
  String get feedSearchA11y => 'Buscar';

  @override
  String get feedCreatePostA11y => 'Crear publicación';

  @override
  String get feedFriendRequestsA11y => 'Solicitudes de seguidores';

  @override
  String feedFriendRequestsWithCountA11y(int count) {
    return 'Solicitudes de seguidores, $count pendientes';
  }

  @override
  String get feedPublishingA11y => 'Publicando…';

  @override
  String get searchUsersClearA11y => 'Limpiar búsqueda';

  @override
  String get publicProfileMessageDisabledA11y =>
      'Mensaje (no disponible: esta persona tiene que seguirte)';

  @override
  String get publicProfileStatWorkouts => 'ENTRENOS';

  @override
  String a11yAvatarLabel(String name) {
    return 'Foto de perfil de $name';
  }

  @override
  String get liftRankNone => 'Sin rango';

  @override
  String get liftRankBronze => 'Bronce';

  @override
  String get liftRankSilver => 'Plata';

  @override
  String get liftRankGold => 'Oro';

  @override
  String get liftRankPlatinum => 'Platino';

  @override
  String get liftRankDiamond => 'Diamante';

  @override
  String get liftRankChampion => 'Campeón';

  @override
  String get liftRankTitan => 'Titán';

  @override
  String get liftRankOlympian => 'Olímpico';

  @override
  String liftRankStripTitle(String lift) {
    return 'TU RANGO · $lift';
  }

  @override
  String liftRankStripPosition(int rank, int total) {
    return 'Rango $rank de $total';
  }

  @override
  String get liftRankStripBelowBronze =>
      'Todavía no llegás a Bronce. Seguí sumando kilos.';

  @override
  String get liftRankStripNoLift =>
      'Registrá este levantamiento en un entrenamiento para ver tu rango.';

  @override
  String get liftRankStripNoBodyWeight =>
      'Cargá tu peso corporal para ver tu rango.';

  @override
  String get liftRankStripPending => 'Se calcula con tu próximo entrenamiento.';

  @override
  String a11yRankingRowButtonWithRank(String name, String rank) {
    return 'Ver el perfil de $name, rango $rank';
  }

  @override
  String a11yRankingRowButton(String name) {
    return 'Ver el perfil de $name';
  }

  @override
  String get a11yReactionLike => 'Me gusta';

  @override
  String get a11yReactionFire => 'Fuego';

  @override
  String get a11yReactionClap => 'Aplausos';

  @override
  String a11yReactionCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reacciones',
      one: '1 reacción',
      zero: 'sin reacciones',
    );
    return '$_temp0';
  }

  @override
  String get a11yAvatarLabelGeneric => 'Foto de perfil';

  @override
  String get a11yHomeAvatarButton => 'Ver tu perfil';

  @override
  String homePendingRequestsA11y(int count) {
    return '$count solicitudes pendientes';
  }

  @override
  String get workoutRoutineOptionsA11y => 'Opciones de rutina';

  @override
  String sessionPlayerSetCompleteA11y(int setNumber) {
    return 'Marcar serie $setNumber como completada';
  }

  @override
  String sessionPlayerTechniqueA11y(String exerciseName) {
    return 'Ver técnica de $exerciseName';
  }

  @override
  String get sessionPlayerTimerStartA11y => 'Iniciar temporizador';

  @override
  String get sessionPlayerRemoveSetA11y => 'Eliminar serie';

  @override
  String get routineEditorDeleteDayA11y => 'Eliminar día';

  @override
  String get routineEditorEditDayNameA11y => 'Editar nombre del día';

  @override
  String get routineEditorDayNameLabel => 'NOMBRE DEL DÍA';

  @override
  String get athleteDetailEditPlanA11y => 'Editar plan';

  @override
  String get athleteDetailDeletePlanA11y => 'Eliminar plan';

  @override
  String get coachMapDisabledOnlineA11y => 'Mapa, no disponible en modo Online';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDone => 'Listo';

  @override
  String get publicProfileLoadErrorA11y => 'No pudimos cargar este perfil.';

  @override
  String get authGenericErrorFallback => 'Algo salió mal. Inténtalo de nuevo.';

  @override
  String get agendaNoUpcomingSessions =>
      'Tu entrenador todavía no te agendó sesiones.';

  @override
  String get agendaSaveError => 'No pudimos guardar. Inténtalo de nuevo.';

  @override
  String get agendaSaveSuccess => 'Horario guardado.';

  @override
  String get coachHubSectionLoadError => 'No pudimos cargar esta sección.';

  @override
  String get coachHubSignOutError =>
      'No pudimos cerrar sesión. Inténtalo de nuevo.';

  @override
  String get coachHubOnboardingAgeTitle => '¿CUÁNDO NACISTE?';

  @override
  String get coachHubOnboardingAgeBody =>
      'Necesitamos tu fecha de nacimiento para activar tu cuenta de entrenador. Tienes que tener 13 años o más.';

  @override
  String get coachHubOnboardingAgeLabel => 'FECHA DE NACIMIENTO';

  @override
  String get coachHubOnboardingIdentityTitle => '¿CÓMO TE LLAMAS?';

  @override
  String get coachHubOnboardingIdentityBody =>
      'Este es el nombre con el que te verán tus alumnos.';

  @override
  String get coachHubOnboardingFirstNameLabel => 'NOMBRE';

  @override
  String get coachHubOnboardingLastNameLabel => 'APELLIDO';

  @override
  String get coachHubOnboardingFirstNameRequired => 'Ingresa tu nombre';

  @override
  String get coachHubOnboardingLastNameRequired => 'Ingresa tu apellido';

  @override
  String get coachHubOnboardingPfTitle => 'TU PERFIL PROFESIONAL';

  @override
  String get coachHubOnboardingPfBody =>
      'Esto es lo que ven los alumnos cuando te buscan. Lo puedes cambiar cuando quieras.';

  @override
  String get coachHubOnboardingPfBioLabel => 'BIO';

  @override
  String get coachHubOnboardingPfSpecialtyLabel => 'ESPECIALIDAD';

  @override
  String get coachHubOnboardingPfRateLabel => 'TARIFA MENSUAL (ARS)';

  @override
  String get coachHubOnboardingPfModalityLabel => 'MODALIDAD';

  @override
  String get coachHubOnboardingPfOnlineSwitch => 'Doy clases online';

  @override
  String get coachHubOnboardingPfModalityRequired =>
      'Activa las clases online o suma un lugar de entrenamiento.';

  @override
  String get coachHubOnboardingPfLocationsLabel => 'LUGARES DE ENTRENAMIENTO';

  @override
  String get coachHubOnboardingPfLocationSearchLabel => 'BUSCAR UN LUGAR';

  @override
  String get coachHubOnboardingPfLocationSearchHint =>
      'Dirección o nombre del lugar';

  @override
  String get coachHubOnboardingPfLocationSearchButton => 'Buscar';

  @override
  String get coachHubOnboardingPfLocationEmpty =>
      'No encontramos ese lugar. Prueba con la dirección completa.';

  @override
  String get coachHubOnboardingPfLocationDuplicate =>
      'Ese lugar ya está en tu lista.';

  @override
  String get coachHubOnboardingPfLocationNetworkError =>
      'No pudimos buscar el lugar. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get coachHubOnboardingPfLocationConfigError =>
      'La búsqueda de lugares no está disponible en este momento. Si das clases online, puedes finalizar igual.';

  @override
  String get coachHubOnboardingPfLocationRetry => 'Reintentar';

  @override
  String get coachHubOnboardingPfLocationFound =>
      'Encontramos el lugar. Ponle el nombre con el que lo verán tus alumnos.';

  @override
  String get coachHubOnboardingPfLocationLabelLabel => 'NOMBRE DEL LUGAR';

  @override
  String get coachHubOnboardingPfLocationLabelHint =>
      'Ej: Mi estudio, Parque Sarmiento';

  @override
  String get coachHubOnboardingPfLocationAddButton => 'Agregar lugar';

  @override
  String get coachHubOnboardingPfLocationRemove => 'Quitar lugar';

  @override
  String get coachHubOnboardingPfLocationGymFallback => 'Gimnasio';

  @override
  String get coachHubOnboardingPfFinish => 'Finalizar';

  @override
  String get coachHubOnboardingContinue => 'Continuar';

  @override
  String get coachHubOnboardingSaveError =>
      'No pudimos guardar tus datos. Inténtalo de nuevo.';

  @override
  String get coachHubNotAllowedTitle => 'SOLO PARA ENTRENADORES';

  @override
  String get coachHubNotAllowedBody =>
      'El Coach Hub es solo para entrenadores. Descarga la app de TREINO desde App Store o Play Store e inicia sesión allí.';

  @override
  String get coachHubNotAllowedContactPrompt =>
      '¿Quieres ser entrenador? Ponte en contacto con el equipo.';

  @override
  String get coachHubNotAllowedContactCta => 'Contactar al equipo';

  @override
  String get coachHubNotAllowedMailSubject => 'Quiero ser entrenador en TREINO';

  @override
  String get coachHubNotAllowedContactFallback =>
      'No pudimos abrir tu correo. Escríbenos a la dirección de arriba.';

  @override
  String get coachHubLoginPrompt =>
      'Ingresa con la cuenta que ya usas en la app móvil.';

  @override
  String get coachHubLoginEmailLabel => 'Email';

  @override
  String get coachHubLoginEmailRequired => 'Ingresa tu email';

  @override
  String get coachHubLoginEmailInvalid => 'Email inválido';

  @override
  String get coachHubLoginPasswordLabel => 'Contraseña';

  @override
  String get coachHubLoginPasswordRequired => 'Ingresa tu contraseña';

  @override
  String get coachHubLoginSubmit => 'INGRESAR';

  @override
  String get coachHubLoginFooter =>
      '¿No tienes cuenta? Créala desde la app móvil TREINO.';

  @override
  String get coachHubLoginGenericError =>
      'No pudimos ingresar. Inténtalo de nuevo.';

  @override
  String get coachHubActionCancel => 'Cancelar';

  @override
  String get coachHubActionConfirm => 'Confirmar';

  @override
  String get coachHubActionPause => 'Pausar';

  @override
  String get coachHubActionResume => 'Reanudar';

  @override
  String get coachHubActionTerminate => 'Terminar';

  @override
  String get coachHubActionTerminateLink => 'Terminar vínculo';

  @override
  String get coachHubActionAccept => 'Aceptar';

  @override
  String get coachHubActionReject => 'Rechazar';

  @override
  String get coachHubDashboardImportPlanCta => 'IMPORTAR PLAN DESDE EXCEL';

  @override
  String get coachHubDashboardFilterActivos => 'ACTIVOS';

  @override
  String get coachHubDashboardFilterPausados => 'PAUSADOS';

  @override
  String get coachHubDashboardFilterHistorial => 'HISTORIAL';

  @override
  String get coachHubDashboardActiveHeader => 'TUS ALUMNOS';

  @override
  String get coachHubDashboardPausedHeader => 'EN PAUSA';

  @override
  String get coachHubDashboardHistoryHeader => 'VÍNCULOS PASADOS';

  @override
  String get coachHubDashboardEmptyActive => 'Sin alumnos activos por ahora.';

  @override
  String get coachHubDashboardEmptyPaused => 'No hay alumnos pausados.';

  @override
  String get coachHubDashboardEmptyHistory =>
      'Sin vínculos terminados todavía.';

  @override
  String coachHubDashboardPendingHeader(int count) {
    return 'SOLICITUDES PENDIENTES · $count';
  }

  @override
  String get coachHubDashboardPendingContext => 'Quiere vincularse contigo';

  @override
  String coachHubDashboardLinkedSince(String date) {
    return 'Vinculado desde $date';
  }

  @override
  String coachHubDashboardPausedOn(String date) {
    return 'Pausado el $date';
  }

  @override
  String get coachHubDashboardPausedFallback => 'Pausado';

  @override
  String get coachHubDashboardPauseLinkTitle => 'Pausar vínculo';

  @override
  String get coachHubDashboardPauseLinkBody =>
      'El alumno verá el plan pero no podrá registrar sesiones nuevas hasta que reanudes el vínculo.';

  @override
  String get coachHubDashboardTerminateLinkTitle => 'Terminar vínculo';

  @override
  String get coachHubDashboardTerminateLinkBody =>
      'Esta acción no se puede deshacer. El historial se conserva.';

  @override
  String get coachHubDashboardResumeLinkTitle => 'Reanudar vínculo';

  @override
  String coachHubDashboardResumeLinkBody(String name) {
    return '¿Reanudar el vínculo con $name?';
  }

  @override
  String get coachHubDashboardResumeLinkBodyFallback => '¿Reanudar el vínculo?';

  @override
  String get coachHubDashboardPauseLinkError => 'No pudimos pausar el vínculo.';

  @override
  String get coachHubDashboardTerminateLinkError =>
      'No pudimos terminar el vínculo.';

  @override
  String get coachHubDashboardResumeLinkError =>
      'No pudimos reanudar el vínculo.';

  @override
  String get coachHubDashboardResumePrecondition =>
      'Este vínculo ya no está disponible.';

  @override
  String get coachHubDashboardResumeUnavailable =>
      'Revisá tu conexión y probá de nuevo.';

  @override
  String get coachHubDashboardAcceptSuccess => 'Vínculo aceptado.';

  @override
  String get coachHubDashboardAcceptError => 'No pudimos aceptar el vínculo.';

  @override
  String get coachHubDashboardAcceptPrecondition =>
      'Esta solicitud ya no está disponible.';

  @override
  String get coachHubDashboardAcceptUnavailable =>
      'Revisá tu conexión y probá de nuevo.';

  @override
  String get coachHubDashboardRejectSuccess => 'Solicitud rechazada.';

  @override
  String get coachHubDashboardRejectError =>
      'No pudimos rechazar la solicitud.';

  @override
  String get coachHubDashboardTerminationReasonDeclined =>
      'Rechazado por el entrenador';

  @override
  String get coachHubDashboardTerminationReasonByAthlete =>
      'Cancelado por el atleta';

  @override
  String get coachHubDashboardTerminationReasonByTrainer =>
      'Terminado por el entrenador';

  @override
  String get coachHubDashboardTerminationReasonFallback => 'Vínculo terminado';

  @override
  String get coachHubAlumnosTitle => 'ALUMNOS';

  @override
  String coachHubAlumnosSummary(int total, int active) {
    return '$total en total · $active activos';
  }

  @override
  String get coachHubAlumnosSearchHint => 'Buscar por nombre…';

  @override
  String get coachHubAlumnosFilterAll => 'Vigentes';

  @override
  String get coachHubAlumnosFilterActivos => 'Activos';

  @override
  String get coachHubAlumnosFilterConDeuda => 'Con deuda';

  @override
  String get coachHubAlumnosFilterPausados => 'Pausados';

  @override
  String get coachHubAlumnosFilterInactivos => 'Inactivos';

  @override
  String get coachHubAlumnosEmpty => 'Todavía no tienes alumnos vinculados.';

  @override
  String get coachHubAlumnosEmptyFiltered =>
      'Ningún alumno coincide con el filtro.';

  @override
  String get coachHubAlumnosLoadError => 'No se pudieron cargar los alumnos.';

  @override
  String get coachHubAlumnosProfilesLoadError =>
      'No se pudieron cargar los perfiles.';

  @override
  String get coachHubAlumnosColumnStudent => 'ALUMNO';

  @override
  String get coachHubAlumnosColumnStatus => 'ESTADO';

  @override
  String get coachHubAlumnosColumnLastWorkout => 'ÚLTIMO ENTRENO';

  @override
  String get coachHubAlumnosColumnActions => 'ACCIONES';

  @override
  String get coachHubAlumnosNameFallback => 'Atleta';

  @override
  String get coachHubAlumnosLastWorkoutToday => 'Hoy';

  @override
  String get coachHubAlumnosStatusActive => 'Activo';

  @override
  String get coachHubAlumnosStatusDebt => 'Con deuda';

  @override
  String get coachHubAlumnosStatusBlocked => 'Sin acceso';

  @override
  String get coachHubAlumnosFilterBloqueados => 'Sin acceso';

  @override
  String get coachHubAlumnosBlockedHint =>
      'Superaste el límite de tu plan. Este alumno no cuenta y no puedes trabajar con él hasta que regularices.';

  @override
  String get coachHubAlumnosStatusPaused => 'Pausado';

  @override
  String get coachHubAlumnosStatusInactive => 'Inactivo';

  @override
  String get coachHubAlumnosViewTable => 'Tabla';

  @override
  String get coachHubAlumnosViewCards => 'Cards';

  @override
  String coachHubAlumnosDebtAmount(String amount) {
    return 'Debe $amount';
  }

  @override
  String get coachHubAlumnoDetailNotasTitle => 'Notas privadas';

  @override
  String get coachHubAlumnoDetailNotasSubtitle =>
      'Anota lo que necesites sobre este alumno. Solo tú lo ves.';

  @override
  String get coachHubAlumnoDetailNotasHint =>
      'Ej: Lesión de rodilla derecha, evitar sentadilla profunda…';

  @override
  String get coachHubAlumnoDetailNotasSaveButton => 'GUARDAR';

  @override
  String coachHubAlumnoDetailNotasUpdatedAt(String timestamp) {
    return 'Última edición · $timestamp';
  }

  @override
  String get coachHubAlumnoDetailNotasSaveSuccess => 'Nota guardada.';

  @override
  String get coachHubAlumnoDetailNotasSaveError =>
      'No pudimos guardar la nota. Inténtalo de nuevo.';

  @override
  String get coachHubAlumnoDetailNotasLoadError => 'No pudimos cargar la nota.';

  @override
  String get coachHubAlumnoDetailArchivosTitle => 'Archivos del alumno';

  @override
  String get coachHubAlumnoDetailArchivosSubtitle =>
      'PDFs y fotos que subís sobre este alumno. Elegí cuáles compartís con él.';

  @override
  String get coachHubAlumnoDetailArchivosUploadButton => 'SUBIR ARCHIVO';

  @override
  String get coachHubAlumnoDetailArchivosEmpty =>
      'Todavía no subiste archivos sobre este alumno.';

  @override
  String get coachHubAlumnoDetailArchivosLoadError =>
      'No pudimos cargar los archivos.';

  @override
  String get coachHubAlumnoDetailArchivosUploadSuccess => 'Archivo subido.';

  @override
  String get coachHubAlumnoDetailArchivosUploadError =>
      'No pudimos subir el archivo. Inténtalo de nuevo.';

  @override
  String get coachHubAlumnoDetailArchivosUploadTooLarge =>
      'El archivo supera el máximo de 10 MB.';

  @override
  String get coachHubAlumnoDetailArchivosOpenTooltip => 'Abrir archivo';

  @override
  String get coachHubAlumnoDetailArchivosDeleteTooltip => 'Eliminar';

  @override
  String get coachHubAlumnoDetailArchivosDeleteTitle => '¿Eliminar archivo?';

  @override
  String coachHubAlumnoDetailArchivosDeleteBody(String fileName) {
    return '«$fileName» se va a borrar tanto del Storage como del historial. No se puede deshacer.';
  }

  @override
  String get coachHubAlumnoDetailArchivosDeleteError =>
      'No pudimos eliminar el archivo.';

  @override
  String get coachHubAlumnoDetailArchivosSharedLabel => 'COMPARTIDO';

  @override
  String get coachHubAlumnoDetailArchivosPrivateLabel => 'PRIVADO';

  @override
  String get coachHubAlumnoDetailArchivosShareTooltip =>
      'Compartir con el alumno';

  @override
  String get coachHubAlumnoDetailArchivosUnshareTooltip =>
      'Dejar de compartir con el alumno';

  @override
  String get coachHubAlumnoDetailArchivosShareError =>
      'No pudimos cambiar quién ve el archivo.';

  @override
  String get feedLoadError => 'No pudimos cargar tu feed. Inténtalo de nuevo.';

  @override
  String get createPostLoadError =>
      'No pudimos abrir el editor. Inténtalo de nuevo.';

  @override
  String get insightsLoadError =>
      'No pudimos cargar tus insights. Inténtalo de nuevo.';

  @override
  String get insightsDayStripTodayLabel => 'HOY';

  @override
  String get insightsDayEmptyHint => 'No entrenaste este día.';

  @override
  String get coachDailyHeatmapSectionTitle => 'MÚSCULOS DEL DÍA';

  @override
  String get profileLoadError =>
      'No pudimos cargar tu perfil. Inténtalo de nuevo.';

  @override
  String get sessionDetailNoSets => 'Esta sesión no tiene sets registrados.';

  @override
  String get sessionFinishedOnWatch =>
      'Finalizaste este entrenamiento desde el reloj.';

  @override
  String get sessionLogSetError =>
      'No pudimos guardar la serie. Inténtalo de nuevo.';

  @override
  String get sessionFinishError =>
      'No pudimos finalizar la sesión. Inténtalo de nuevo.';

  @override
  String get sessionFinishNeedOneSet =>
      'Haz al menos una serie para poder terminar. Si hoy no vas a entrenar, toca ABANDONAR.';

  @override
  String get sessionFinishEarlyTitle => '¿TERMINAR IGUAL?';

  @override
  String sessionFinishEarlyMissingHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Te faltan $count series:',
      one: 'Te falta 1 serie:',
    );
    return '$_temp0';
  }

  @override
  String sessionFinishEarlyMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'y $count ejercicios más',
      one: 'y 1 ejercicio más',
    );
    return '$_temp0';
  }

  @override
  String sessionFinishEarlyCounts(int percent) {
    return 'Hiciste el $percent % de la sesión: cuenta como entreno para tu racha y tus rankings.';
  }

  @override
  String sessionFinishEarlyNotCounts(int percent, int minPercent) {
    return 'Hiciste el $percent % de la sesión. Se guarda, pero no cuenta como entreno para tu racha ni tus rankings: hace falta el $minPercent %.';
  }

  @override
  String get sessionFinishEarlyConfirm => 'TERMINAR IGUAL';

  @override
  String get sessionFinishEarlyKeepGoing => 'SEGUIR ENTRENANDO';

  @override
  String get routineEditorMissingName => 'Ponle un nombre a la rutina.';

  @override
  String routineEditorMissingExercise(int dayNumber) {
    return 'Agrega al menos un ejercicio al Día $dayNumber.';
  }

  @override
  String get routineEditorMissingReps =>
      'Completa las reps de los sets antes de guardar.';

  @override
  String get routineEditorDuplicateExercise =>
      'Ese ejercicio ya está en el día. Elegí otro.';

  @override
  String get feedPostPublishedSuccess => 'Post publicado.';

  @override
  String get postCardMenuA11y => 'Opciones del post';

  @override
  String get coachHubAlumnosRowActionsA11y => 'Opciones del alumno';

  @override
  String get postCardMenuEdit => 'Editar';

  @override
  String get postCardMenuDelete => 'Eliminar';

  @override
  String get postCardDeleteConfirmTitle => '¿Eliminar este post?';

  @override
  String get postCardDeleteConfirmBody => 'Esta acción no se puede deshacer.';

  @override
  String get postCardDeleteSuccess => 'Post eliminado.';

  @override
  String get postCardDeleteError =>
      'No pudimos eliminar el post. Inténtalo de nuevo.';

  @override
  String get createPostEditTitle => 'EDITAR POST';

  @override
  String get createPostSaveChanges => 'GUARDAR';

  @override
  String get createPostSaveChangesA11y => 'Guardar cambios';

  @override
  String get createPostSavingA11y => 'Guardando…';

  @override
  String get feedPostUpdatedSuccess => 'Cambios guardados.';

  @override
  String get feedRequestSentSuccess => 'Solicitud enviada.';

  @override
  String get feedRequestAcceptedSuccess => 'Solicitud aceptada.';

  @override
  String get feedFriendActionError =>
      'No pudimos completar la acción. Inténtalo de nuevo.';

  @override
  String get profilePersonalSaveSuccess => 'Cambios guardados.';

  @override
  String get profileGymSaveSuccess => 'Gimnasio actualizado.';

  @override
  String get profileGymSaveError =>
      'No pudimos guardar el gimnasio. Inténtalo de nuevo.';

  @override
  String get gymNearbyLocationAffordance =>
      'Activa tu ubicación para ver gimnasios cercanos';

  @override
  String get gymNearbyShowMore => 'Ver más';

  @override
  String get gymSearchConfigError =>
      'La búsqueda de gimnasios no está disponible en esta versión de la app.';

  @override
  String get gymNearbyLoadError => 'No pudimos cargar los gimnasios cercanos.';

  @override
  String get feedPullToRefreshA11y => 'Desliza para actualizar';

  @override
  String get logFieldInvalidNumber => 'Ingresa un número válido';

  @override
  String get logFieldOutOfRange => 'El valor está fuera de rango';

  @override
  String get logEmptyRecordWarning =>
      'Completa al menos un dato antes de guardar';

  @override
  String get profileSetupUsernameChecking => 'Comprobando disponibilidad…';

  @override
  String get profileSetupUsernameTaken =>
      'Ese nombre de usuario ya está en uso';

  @override
  String get profileSetupUsernameAvailable => 'Nombre de usuario disponible';

  @override
  String get profileSetupUsernameCheckError =>
      'No pudimos comprobar el nombre de usuario. Inténtalo de nuevo.';

  @override
  String get routineEditorDiscardTitle => '¿Descartar cambios?';

  @override
  String get routineEditorDiscardBody =>
      'Si sales ahora perderás los cambios sin guardar.';

  @override
  String get routineEditorDiscardConfirm => 'Descartar';

  @override
  String trainerCtaExistingLinkExplanation(String trainerName) {
    return 'Solo puedes tener un PF activo. Termina tu vínculo actual con $trainerName para pedir uno nuevo.';
  }

  @override
  String get coachHubPreviewDiscardTitle => '¿Salir sin guardar el plan?';

  @override
  String get coachHubPreviewDiscardBody =>
      'Vas a perder los ejercicios que mapeaste manualmente.';

  @override
  String get coachHubPreviewDiscardConfirm => 'Salir igual';

  @override
  String get chatAttachMediaLabel => 'Adjuntar';

  @override
  String get chatPickImageLabel => 'Foto';

  @override
  String get chatPickVideoLabel => 'Video';

  @override
  String get chatMediaUploading => 'Subiendo…';

  @override
  String get chatMediaUploadFailed =>
      'No pudimos subir el archivo. Inténtalo de nuevo.';

  @override
  String chatMediaQuotaFull(String maxMb) {
    return 'Llegaste al tope de $maxMb MB en fotos y videos de chat.';
  }

  @override
  String chatMediaFileTooLarge(String fileMb, String maxMb) {
    return 'El archivo pesa $fileMb MB y el máximo es $maxMb MB.';
  }

  @override
  String chatMediaQuotaNotEnough(String fileMb, String remainingMb) {
    return 'El archivo pesa $fileMb MB y te quedan $remainingMb MB de cupo.';
  }

  @override
  String get chatMediaPreviewPhoto => '📷 Foto';

  @override
  String get chatMediaPreviewVideo => '🎥 Video';

  @override
  String get chatMediaViewFullscreen => 'Ver foto';

  @override
  String get chatMediaImageLoadError => 'No pudimos cargar la imagen.';

  @override
  String feedMessagesWithUnreadA11y(int count) {
    return 'Mensajes, $count sin leer';
  }

  @override
  String get chatUnreadA11y => 'Sin leer';

  @override
  String get coachSessionSetLogsTitle => 'SETS';

  @override
  String get coachSessionTapToExpand => 'Ver sets';

  @override
  String get coachSessionSetLogsEmpty =>
      'Esta sesión no tiene sets registrados.';

  @override
  String get coachSessionSetLogsLoadError =>
      'No pudimos cargar los sets. Intenta de nuevo.';

  @override
  String get coachAthleteNoSharePlaceholder =>
      'El alumno no ha compartido su historial todavía.';

  @override
  String get avatarCropperTitle => 'Recortar foto';

  @override
  String get avatarCropperDone => 'LISTO';

  @override
  String get avatarCropperCancel => 'CANCELAR';

  @override
  String get progressionSectionTitle => 'EVOLUCIÓN POR EJERCICIO';

  @override
  String get progressionMetricPr => 'Peso máximo';

  @override
  String get progressionMetricOneRepMax => '1RM';

  @override
  String get progressionMetricBestSetVolume => 'Mejor serie';

  @override
  String get progressionMetricVolume => 'Volumen';

  @override
  String progressionFrequency(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones en las últimas 8 semanas',
      one: '1 sesión en las últimas 8 semanas',
      zero: 'Sin sesiones en las últimas 8 semanas',
    );
    return '$_temp0';
  }

  @override
  String progressionFrequencyPeriod(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones en este período',
      one: '1 sesión en este período',
      zero: 'Sin sesiones en este período',
    );
    return '$_temp0';
  }

  @override
  String get progressionSinglePointHint =>
      'Necesitas al menos 2 sesiones para ver la evolución.';

  @override
  String get progressionEmptyExercise => 'Sin datos para este ejercicio.';

  @override
  String get progressionEmpty => 'Sin registros de series todavía.';

  @override
  String get progressionPeriodLast30Days => 'Últimos 30 días';

  @override
  String get progressionPeriodThisWeek => 'Esta semana';

  @override
  String get progressionPeriodMonth => 'Este mes';

  @override
  String get muscleDistributionSectionTitle => 'DISTRIBUCIÓN MUSCULAR';

  @override
  String get muscleDistributionCurrentLabel => 'Actual';

  @override
  String get muscleDistributionPreviousLabel => 'Anterior';

  @override
  String get muscleDistributionEmptyState => 'Sin datos para este período.';

  @override
  String get muscleDistributionWorkoutsLabel => 'Entrenos';

  @override
  String get muscleDistributionDurationLabel => 'Duración';

  @override
  String get muscleDistributionVolumeLabel => 'Volumen';

  @override
  String get muscleDistributionSetsLabel => 'Sets';

  @override
  String get personalRecordsSectionTitle => 'RÉCORDS PERSONALES';

  @override
  String get mostFrequentExercisesSectionTitle => 'EJERCICIOS MÁS FRECUENTES';

  @override
  String mostFrequentExercisesSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones',
      one: '1 sesión',
      zero: 'Sin sesiones',
    );
    return '$_temp0';
  }

  @override
  String get mostFrequentExercisesEmpty => 'No hay datos todavía.';

  @override
  String get profileRoutinesAssignedHeader => 'RUTINAS ASIGNADAS POR TU PF';

  @override
  String get profileRoutinesOwnHeader => 'MIS RUTINAS PROPIAS';

  @override
  String get profileRoutinesNoTrainerBody => 'Todavía no tenés un PF asignado.';

  @override
  String get profileRoutinesNoTrainerCta => 'BUSCAR PF';

  @override
  String get profileRoutinesNoOwnBody => 'Todavía no creaste ninguna rutina.';

  @override
  String get profileRoutinesActiveChip => 'ACTIVA';

  @override
  String get profileSectionLegal => 'Legales';

  @override
  String get legalDocumentsTitle => 'Documentos legales';

  @override
  String get legalDocumentsSubtitle => 'Términos, privacidad y más';

  @override
  String get appearanceTitle => 'Apariencia';

  @override
  String get appearanceSystem => 'Sistema';

  @override
  String get appearanceSystemDesc => 'Sigue el tema del dispositivo';

  @override
  String get appearanceLight => 'Claro';

  @override
  String get appearanceDark => 'Oscuro';

  @override
  String get profileSectionAppearance => 'Apariencia';

  @override
  String dashboardGreeting(String name) {
    return 'BUENAS, $name';
  }

  @override
  String get dashboardGreetingPrefix => 'BUENAS, ';

  @override
  String dashboardSummaryLine(int sessions, int paraRevisar, int pagos) {
    return 'Tenés $sessions sesiones hoy, $paraRevisar para revisar, $pagos pagos pendientes';
  }

  @override
  String get dashboardQuickActionNuevoAlumno => 'Nuevo alumno';

  @override
  String get dashboardQuickActionCrearRutina => 'Crear rutina';

  @override
  String dashboardQuickActionMensajes(int count) {
    return 'Mensajes ($count)';
  }

  @override
  String get dashboardQuickActionImportarPlan => 'Importar plan';

  @override
  String get dashboardAlertBannerPlaceholder =>
      'Próximamente: resumen de atención';

  @override
  String get dashboardKpiAlumnosActivos => 'Alumnos activos';

  @override
  String get dashboardKpiIngresoMes => 'Ingreso del mes';

  @override
  String get dashboardKpiAdherencia => 'Adherencia promedio';

  @override
  String dashboardKpiPorCobrar(int count) {
    return 'Por cobrar ($count vencimientos)';
  }

  @override
  String get dashboardPlaceholderSoon => 'Próximamente';

  @override
  String get dashboardAdherenceRingPlaceholder => '--';

  @override
  String get dashboardProximaSesionManana => 'mañana';

  @override
  String get dashboardProximasSesionesEmpty =>
      'No hay sesiones próximas confirmadas.';

  @override
  String get dashboardVencimientosTitle => 'VENCIMIENTOS — 7 DÍAS';

  @override
  String get dashboardVencimientosEmpty => 'Sin pagos vencidos.';

  @override
  String get dashboardVencimientosVerTodos => 'Ver todos los pagos';

  @override
  String get dashboardInactivosTitle => 'ALUMNOS INACTIVOS';

  @override
  String get dashboardInactivosEmpty => 'Sin alumnos inactivos';

  @override
  String get dashboardAlertBannerAllClear => 'Todo al día';

  @override
  String dashboardAlertBannerSummary(
      int vencidos, int solicitudes, int inactivos) {
    String _temp0 = intl.Intl.pluralLogic(
      vencidos,
      locale: localeName,
      other: '$vencidos vencidos',
      one: '1 vencido',
    );
    String _temp1 = intl.Intl.pluralLogic(
      solicitudes,
      locale: localeName,
      other: '$solicitudes solicitudes',
      one: '1 solicitud',
    );
    String _temp2 = intl.Intl.pluralLogic(
      inactivos,
      locale: localeName,
      other: '$inactivos inactivos',
      one: '1 inactivo',
    );
    return '$_temp0 · $_temp1 · $_temp2';
  }

  @override
  String dashboardAdherenceValue(int pct) {
    return '$pct%';
  }

  @override
  String get insightsMonthlyReportTile => 'Reporte mensual';

  @override
  String get monthlyReportTitle => 'REPORTE MENSUAL';

  @override
  String get monthlyReportMetricWorkouts => 'Entrenos';

  @override
  String get monthlyReportMetricDuration => 'Duración';

  @override
  String get monthlyReportMetricVolume => 'Volumen';

  @override
  String get monthlyReportMetricSets => 'Sets';

  @override
  String get monthlyReportDurationUnit => 'min';

  @override
  String get monthlyReportDurationHoursUnit => 'h';

  @override
  String get monthlyReportVolumeUnit => 'kg';

  @override
  String get monthlyReportEmptyHint => 'Sin datos en los últimos 12 meses.';

  @override
  String get monthlyReportByMonthLabel => 'POR MES';

  @override
  String get monthlyReportByDayLabel => 'POR DÍA';

  @override
  String get monthlyReportDailyEmptyHint =>
      'Sin minutos entrenados en este mes.';

  @override
  String get monthlyReportDailyTooltipDayLabel => 'Día';

  @override
  String get monthlyReportLoadError =>
      'No pudimos cargar tu reporte mensual. Probá de nuevo.';

  @override
  String get monthlyVolumeByGroupEmpty => 'No hay sets por grupo en este mes.';

  @override
  String monthlyVolumeByGroupSets(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sets',
      one: '1 set',
    );
    return '$_temp0';
  }

  @override
  String workoutDaysCalendarStreak(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Racha de $n semanas',
      one: 'Racha de 1 semana',
      zero: 'Sin racha',
    );
    return '$_temp0';
  }

  @override
  String workoutDaysCalendarStreakHint(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Completaste el objetivo de tu rutina $n semanas seguidas.',
      one: 'Completaste el objetivo de tu rutina 1 semana seguida.',
      zero:
          'Cumplí el objetivo de días de tu rutina esta semana y arrancás una racha.',
    );
    return '$_temp0';
  }

  @override
  String get insightsAdvancedStatsHeading => 'Estadísticas avanzadas';

  @override
  String get insightsTileMuscleDistributionTitle => 'Distribución muscular';

  @override
  String get insightsTileMuscleDistributionSubtitle =>
      'Comparativa actual vs. período anterior';

  @override
  String get muscleDistributionScreenTitle => 'DISTRIBUCIÓN MUSCULAR';

  @override
  String get muscleDistributionLoadError =>
      'No pudimos cargar tu distribución muscular. Inténtalo de nuevo.';

  @override
  String get frequentExercisesLoadError =>
      'No pudimos cargar tus ejercicios frecuentes. Inténtalo de nuevo.';

  @override
  String get exerciseProgressionScreenTitle => 'EVOLUCIÓN POR EJERCICIO';

  @override
  String get insightsTileExerciseProgressionTitle => 'Evolución por ejercicio';

  @override
  String get insightsTileExerciseProgressionSubtitle =>
      'Tu progreso en cada ejercicio + records';

  @override
  String get progressionSearchHint => 'Buscar ejercicio…';

  @override
  String get progressionSearchNoResults =>
      'Ningún ejercicio tuyo coincide con la búsqueda.';

  @override
  String get insightsTileMeasurementsTitle => 'Medidas';

  @override
  String get insightsTileMeasurementsSubtitle =>
      'Peso y medidas corporales en el tiempo';

  @override
  String get measurementsScreenTitle => 'MEDIDAS';

  @override
  String get measurementsSelfLogNotesHint => 'Notas (opcional)…';

  @override
  String get measurementsAddSelfLog => 'Registrar medición';

  @override
  String get measurementsProfileCardTitle => 'TUS DATOS';

  @override
  String get measurementsProfileCardHint =>
      'Los cargaste al registrarte. Edítalos desde tu perfil.';

  @override
  String get measurementsWeightLabel => 'Peso';

  @override
  String get measurementsHeightLabel => 'Altura';

  @override
  String get measurementsEmptyState =>
      'Todavía no hay mediciones cargadas. Toca + para registrar la primera y seguir tu evolución.';

  @override
  String get measurementsNeedsMoreData =>
      'Con una sola medición no hay progreso que mostrar. Falta al menos una más.';

  @override
  String get measurementsHistoryTitle => 'HISTORIAL';

  @override
  String get measurementHistoryEditTooltip => 'Editar medición';

  @override
  String get measurementHistoryDeleteTooltip => 'Eliminar medición';

  @override
  String measurementHistoryShowAll(int count) {
    return 'Ver todas ($count)';
  }

  @override
  String get measurementHistoryShowLess => 'Ver menos';

  @override
  String get measurementDeleteConfirmTitle => '¿Eliminar medición?';

  @override
  String measurementDeleteConfirmBody(String date) {
    return 'Se eliminará la medición del $date. Esta acción no se puede deshacer.';
  }

  @override
  String get measurementDeleteConfirmAction => 'Eliminar';

  @override
  String get measurementDeleteSuccess => 'Medición eliminada';

  @override
  String get measurementDeleteError =>
      'No pudimos eliminar la medición. Inténtalo de nuevo.';

  @override
  String get measurementHistorySelfLoggedTag => 'Auto-registro';

  @override
  String get measurementHistoryTrainerLoggedTag =>
      'Registrada por tu entrenador';

  @override
  String get insightsTileFrequentExercisesTitle => 'Ejercicios frecuentes';

  @override
  String get insightsTileFrequentExercisesSubtitle =>
      'Tus ejercicios más entrenados';

  @override
  String get frequentExercisesScreenTitle => 'EJERCICIOS FRECUENTES';

  @override
  String get insightsTileMonthlyReportSubtitle => 'Resumen de entrenos por mes';

  @override
  String get insightsTileVolumeByGroupTitle => 'Volumen por grupo';

  @override
  String get insightsTileVolumeByGroupSubtitle =>
      'Sets vs. objetivo por grupo muscular';

  @override
  String get volumeByGroupScreenTitle => 'VOLUMEN POR GRUPO';

  @override
  String get volumeByGroupEmptyTarget =>
      'Necesitás una rutina asignada para ver tu volumen objetivo.';

  @override
  String get measurementChartSectionLabel => 'PROGRESO';

  @override
  String measurementChartSpanDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días',
      one: 'día',
    );
    return '($count $_temp0)';
  }

  @override
  String measurementChartSpanWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'semanas',
      one: 'semana',
    );
    return '($count $_temp0)';
  }

  @override
  String get measurementChartMetricWeight => 'Peso';

  @override
  String get measurementChartMetricBodyFat => '% Graso';

  @override
  String get measurementChartMetricMuscleMass => 'Masa muscular';

  @override
  String get measurementChartMetricWaist => 'Cintura';

  @override
  String get measurementChartMetricChest => 'Pecho';

  @override
  String get measurementChartMetricHips => 'Cadera';

  @override
  String get measurementChartMetricShoulders => 'Hombros';

  @override
  String get measurementChartMetricGlutes => 'Glúteos';

  @override
  String get measurementChartMetricBiceps => 'Bíceps';

  @override
  String get measurementChartMetricBicepsFlexed => 'Bíceps flex';

  @override
  String get measurementChartMetricForearm => 'Antebrazo';

  @override
  String get measurementChartMetricUpperThigh => 'Muslo sup';

  @override
  String get measurementChartMetricMidThigh => 'Muslo medio';

  @override
  String get measurementChartMetricCalf => 'Gemelo';

  @override
  String get measurementLogTitleCreate => 'Cargar medición';

  @override
  String get measurementLogTitleEdit => 'Editar medición';

  @override
  String get measurementLogNoSession =>
      'No hay sesión activa. No se puede guardar.';

  @override
  String get measurementLogSaveSuccess => 'Medición guardada';

  @override
  String get measurementLogUpdateSuccess => 'Medición actualizada';

  @override
  String get measurementLogSaveError =>
      'No pudimos guardar la medición. Probá de nuevo.';

  @override
  String get measurementLogSaveCta => 'GUARDAR MEDICIÓN';

  @override
  String get measurementLogUpdateCta => 'GUARDAR CAMBIOS';

  @override
  String get measurementLogSectionBodyComposition => 'COMPOSICIÓN CORPORAL';

  @override
  String get measurementLogSectionNotes => 'NOTAS';

  @override
  String get measurementLogNotesHint => 'Observaciones del entrenador…';

  @override
  String get measurementLogFieldWeight => 'Peso (kg)';

  @override
  String get measurementLogFieldBodyFat => 'Grasa (%)';

  @override
  String get measurementLogFieldMuscleMass => 'Masa muscular (kg)';

  @override
  String get measurementLogCircumferencesTitle => 'CIRCUNFERENCIAS';

  @override
  String get measurementLogCircumferencesHint =>
      'Opcional. Cargá las que quieras.';

  @override
  String get measurementLogGroupTrunk => 'TRONCO';

  @override
  String get measurementLogGroupUpperBody => 'TREN SUPERIOR';

  @override
  String get measurementLogGroupLowerBody => 'TREN INFERIOR';

  @override
  String get measurementLogFieldShoulders => 'Hombros';

  @override
  String get measurementLogFieldChest => 'Pecho';

  @override
  String get measurementLogFieldWaist => 'Cintura';

  @override
  String get measurementLogFieldHips => 'Cadera';

  @override
  String get measurementLogFieldGlutes => 'Glúteos';

  @override
  String get measurementLogFieldBiceps => 'Bíceps';

  @override
  String get measurementLogFieldBicepsFlexed => 'Bíceps (flex)';

  @override
  String get measurementLogFieldForearm => 'Antebrazo';

  @override
  String get measurementLogFieldUpperThigh => 'Muslo superior';

  @override
  String get measurementLogFieldMidThigh => 'Muslo medio';

  @override
  String get measurementLogFieldCalf => 'Gemelo';

  @override
  String get measurementLogBilateralLeftHint => 'I (cm)';

  @override
  String get measurementLogBilateralRightHint => 'D (cm)';

  @override
  String get reviewSheetTitleEdit => 'Editá tu reseña';

  @override
  String reviewSheetTitleThirtyDay(String trainerName) {
    return 'Ya llevás un mes entrenando con $trainerName. ¿Cómo va?';
  }

  @override
  String reviewSheetTitleStandard(String trainerName) {
    return '¿Cómo fue tu experiencia con $trainerName?';
  }

  @override
  String get reviewSheetCommentHint => 'Contanos cómo fue (opcional)';

  @override
  String get reviewSheetCancel => 'CANCELAR';

  @override
  String get reviewSheetSubmit => 'ENVIAR';

  @override
  String get reviewSnackBarError =>
      'No pudimos guardar tu reseña. Probá de nuevo.';

  @override
  String get reviewCtaCreate => 'DEJAR UNA RESEÑA';

  @override
  String get reviewCtaEdit => 'EDITAR MI RESEÑA';

  @override
  String get reviewTrainerFallbackName => 'tu Personal Trainer';

  @override
  String get reviewsSectionTitle => 'RESEÑAS';

  @override
  String get reviewsSectionEmpty => 'Sin reseñas todavía';

  @override
  String get reviewTileDeletedUser => 'Usuario eliminado';

  @override
  String get reviewTileDateToday => 'hoy';

  @override
  String reviewTileDateDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días',
      one: 'día',
    );
    return 'hace $count $_temp0';
  }

  @override
  String reviewTileDateMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'meses',
      one: 'mes',
    );
    return 'hace $count $_temp0';
  }

  @override
  String get postPrivacySelectorTitle => 'VISIBILIDAD';

  @override
  String get postPrivacyFriends => 'SEGUIDORES';

  @override
  String get postPrivacyGym => 'MI GYM';

  @override
  String get postPrivacyPublic => 'PÚBLICO';

  @override
  String get postPrivacyNoGymHint => 'Asociate a un gym para postear acá';

  @override
  String get suggestedUsersTitle => 'SUGERENCIAS PARA VOS';

  @override
  String get suggestedUserAnonymous => 'Anónimo';

  @override
  String a11ySuggestedUserButton(String name) {
    return 'Ver el perfil de $name';
  }

  @override
  String get notificationHistoryTitle => 'NOTIFICACIONES';

  @override
  String get notificationHistoryEmpty => 'Todavía no tenés notificaciones';

  @override
  String get notificationHistoryError =>
      'No pudimos cargar tus notificaciones.';

  @override
  String notificationPendingRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count solicitudes de seguidor pendientes',
      one: '1 solicitud de seguidor pendiente',
    );
    return '$_temp0';
  }

  @override
  String get notificationBellA11y => 'Abrir notificaciones';

  @override
  String notificationBellWithCountA11y(int count) {
    return 'Abrir notificaciones, $count pendientes';
  }

  @override
  String get postDetailTitle => 'PUBLICACIÓN';

  @override
  String get postDetailUnavailable => 'Este post ya no está disponible.';

  @override
  String feedUnfollowConfirmTitle(String name) {
    return '¿Dejar de seguir a $name?';
  }

  @override
  String get feedUnfollowConfirmAction => 'DEJAR DE SEGUIR';

  @override
  String get feedUnfollowDismiss => 'CANCELAR';

  @override
  String feedCancelRequestConfirmTitle(String name) {
    return '¿Cancelar la solicitud a $name?';
  }

  @override
  String get feedCancelRequestConfirmAction => 'CANCELAR SOLICITUD';

  @override
  String get feedCancelRequestDismiss => 'VOLVER';

  @override
  String get feedFollowButtonFollowA11y => 'Seguir a esta persona';

  @override
  String get feedFollowButtonFollowingA11y =>
      'Siguiendo. Tocá para dejar de seguir';

  @override
  String get feedFollowButtonRequestedA11y =>
      'Solicitud enviada. Tocá para cancelarla';

  @override
  String get feedFollowButtonAcceptA11y => 'Aceptar la solicitud de seguidor';

  @override
  String get feedFollowStartedSuccess => 'Ahora seguís a esta persona.';

  @override
  String get feedSegmentFollowing => 'SEGUIDORES';

  @override
  String get feedEmptyFollowing => 'Aún no hay posts de quienes seguís';

  @override
  String get chatBlockedComposerNotice =>
      'Bloqueaste a esta persona. Desbloqueala para escribirle.';

  @override
  String get chatBlockedComposerHintA11y => 'No podés escribir en este chat';

  @override
  String get followListTabFollowers => 'SEGUIDORES';

  @override
  String get followListTabFollowing => 'SIGUIENDO';

  @override
  String get followListEmptyFollowers => 'Todavía no tiene seguidores';

  @override
  String get followListEmptyFollowersSelf => 'Todavía no tienes seguidores';

  @override
  String get followListEmptyFollowing => 'Todavía no sigue a nadie';

  @override
  String get followListEmptyFollowingSelf => 'Todavía no sigues a nadie';

  @override
  String get followListLoadError =>
      'No pudimos cargar la lista. Inténtalo de nuevo.';

  @override
  String get followListOpenFollowersA11y => 'Ver seguidores';

  @override
  String get followListOpenFollowingA11y => 'Ver seguidos';

  @override
  String routineCardDaysPerWeek(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days días/sem',
      one: '1 día/sem',
    );
    return '$_temp0';
  }

  @override
  String routineCardMinutes(String value) {
    return '$value min';
  }

  @override
  String get onboardingCardDismiss => 'ENTENDIDO';

  @override
  String get onboardingCardAthleteHomeTitle => 'TU RESUMEN DEL DÍA';

  @override
  String get onboardingCardAthleteHomeBody =>
      'Acá ves qué te toca entrenar hoy, cómo venís esta semana y tu racha. Si dejaste una sesión a medias, te la ofrece para retomar.';

  @override
  String get onboardingCardAthleteWorkoutTitle => 'ACÁ ARRANCA TU ENTRENO';

  @override
  String get onboardingCardAthleteWorkoutBody =>
      'Tenés tres formas de conseguir una rutina:';

  @override
  String get onboardingCardAthleteWorkoutBullet1 =>
      'El plan de tu entrenador, ya armado y asignado a vos';

  @override
  String get onboardingCardAthleteWorkoutBullet2 =>
      'Una plantilla de TREINO, lista para usar';

  @override
  String get onboardingCardAthleteWorkoutBullet3 =>
      'Tu propia rutina, armada ejercicio por ejercicio';

  @override
  String get onboardingCardAthleteFeedTitle => 'LA PARTE SOCIAL';

  @override
  String get onboardingCardAthleteFeedBody =>
      'Publicá tus entrenamientos y seguí a tus amigos. Al lado tenés Rankings:';

  @override
  String get onboardingCardAthleteFeedBullet1 =>
      'Te compara con la gente de tu gym';

  @override
  String get onboardingCardAthleteFeedBullet2 =>
      'Es opcional: si no lo activás, ni aparecés ni ves a nadie';

  @override
  String get onboardingCardAthleteCoachTitle => 'TU ENTRENADOR';

  @override
  String get onboardingCardAthleteCoachBody =>
      'Buscá y contratá un entrenador cerca tuyo. Vos controlás qué ve de vos:';

  @override
  String get onboardingCardAthleteCoachBullet1 =>
      'Tus entrenamientos los ve apenas aceptás el vínculo';

  @override
  String get onboardingCardAthleteCoachBullet2 =>
      'Tus datos personales y medidas, solo si los activás en Perfil › Privacidad';

  @override
  String get onboardingCardAthleteProfileTitle => 'TU CUENTA';

  @override
  String get onboardingCardAthleteProfileBody =>
      'Tus datos, tus medidas y tu privacidad. Acá decidís qué comparte tu perfil público y qué ve tu entrenador.';

  @override
  String get onboardingCardTrainerHomeTitle => 'TU DÍA';

  @override
  String get onboardingCardTrainerHomeBody =>
      'Tus próximas sesiones, quién entrenó hoy, la actividad reciente de tus alumnos y lo que tenés por cobrar.';

  @override
  String get onboardingCardTrainerWorkoutTitle => 'TUS PLANTILLAS';

  @override
  String get onboardingCardTrainerWorkoutBody =>
      'Tu biblioteca de plantillas propias y el atajo para asignarle un plan a un alumno. El editor completo está en Coach Hub, desde la compu.';

  @override
  String get onboardingCardTrainerFeedTitle => 'LA COMUNIDAD';

  @override
  String get onboardingCardTrainerFeedBody =>
      'El feed social de TREINO. Podés seguir lo que publican tus alumnos y publicar vos también.';

  @override
  String get onboardingCardTrainerCoachTitle => 'ALUMNOS Y AGENDA';

  @override
  String get onboardingCardTrainerCoachBody =>
      'Acá trabajás con tus alumnos. Lo primero que conviene saber:';

  @override
  String get onboardingCardTrainerCoachBullet1 =>
      'El alumno te manda la solicitud a vos desde su app, no al revés';

  @override
  String get onboardingCardTrainerCoachBullet2 =>
      'Abrí un alumno para ver su plan, sus series, su progreso y el chat';

  @override
  String get onboardingCardTrainerCoachBullet3 =>
      'En AGENDA creás turnos sueltos o series que se repiten';

  @override
  String get onboardingCardTrainerProfileTitle => 'TU PERFIL PROFESIONAL';

  @override
  String get onboardingCardTrainerProfileBody =>
      'Así te ven los alumnos que te buscan. Desde acá también:';

  @override
  String get onboardingCardTrainerProfileBullet1 =>
      'Aceptás las solicitudes entrantes de alumnos nuevos';

  @override
  String get onboardingCardTrainerProfileBullet2 =>
      'Configurás tu disponibilidad horaria';

  @override
  String get onboardingTourSkip => 'SALTAR';

  @override
  String get onboardingTourNext => 'SIGUIENTE';

  @override
  String get onboardingTourFinish => 'COMENZAR';

  @override
  String onboardingTourProgress(int current, int total) {
    return 'Paso $current de $total';
  }

  @override
  String get onboardingCustomExerciseCta => 'CREAR MI EJERCICIO';

  @override
  String get templatesOnboardingStep1Title => '¿Cuántos días podés entrenar?';

  @override
  String get templatesOnboardingStep1Body =>
      'Elegí lo que vas a sostener. Guardamos tu respuesta para personalizar lo que te recomendamos.';

  @override
  String get templatesOnboardingStep1Label => 'Días por semana';

  @override
  String get templatesOnboardingStep1Hint =>
      'Todo lo que elijas filtra el catálogo: sólo vas a ver plantillas que cumplan con todo. Si no queda ninguna, podés ver todas.';

  @override
  String get templatesOnboardingStep2Title => '¿Cuánto dura tu sesión?';

  @override
  String get templatesOnboardingStep2Body =>
      '45 minutos reales valen más que una hora ideal. Elegí el tiempo que tenés de verdad.';

  @override
  String get templatesOnboardingStep2Label => 'Minutos por sesión';

  @override
  String get templatesOnboardingStep3Title => '¿Para qué querés entrenar?';

  @override
  String get templatesOnboardingStep3Body =>
      'Nadie elige por split, elige por para qué. Es la respuesta que más nos dice sobre lo que buscás.';

  @override
  String get templatesOnboardingStep3Label =>
      'Objetivos · podés elegir más de uno';

  @override
  String get templatesOnboardingStep4Title => 'Esto no es un examen';

  @override
  String get templatesOnboardingStep4Body =>
      'Guardamos tus respuestas en tu perfil. Esta es opcional: dejala vacía si no tenés preferencia.';

  @override
  String get templatesOnboardingStep4Label => 'Zonas a priorizar · opcional';

  @override
  String get templatesOnboardingCta => 'VER MIS PLANTILLAS';

  @override
  String get templatesOnboardingMinutes30 => '30 MIN';

  @override
  String get templatesOnboardingMinutes30Hint => 'Entro y salgo';

  @override
  String get templatesOnboardingMinutes45 => '45 MIN';

  @override
  String get templatesOnboardingMinutes45Hint => 'Lo de siempre';

  @override
  String get templatesOnboardingMinutes60 => '60 MIN';

  @override
  String get templatesOnboardingMinutes60Hint => 'Hora completa';

  @override
  String get templatesOnboardingMinutes75 => '75 MIN O MÁS';

  @override
  String get templatesOnboardingMinutes75Hint => 'Fuerza';

  @override
  String get templatesGoalHealth => 'SALUD';

  @override
  String get templatesGoalInjuryPrevention => 'PREVENCIÓN';

  @override
  String get templatesGoalAesthetics => 'ESTÉTICA';

  @override
  String get templatesGoalSport => 'DEPORTE';

  @override
  String get templatesGoalWellbeing => 'BIENESTAR';

  @override
  String get templatesZoneBack => 'ESPALDA';

  @override
  String get templatesZoneChest => 'PECHO';

  @override
  String get templatesZoneShoulders => 'HOMBROS';

  @override
  String get templatesZoneGlutes => 'GLÚTEOS';

  @override
  String get templatesZoneQuads => 'CUÁDRICEPS';

  @override
  String get templatesZoneCore => 'CORE';

  @override
  String templatesOnboardingDaysOption(int days) {
    return '$days DÍAS';
  }

  @override
  String get templatesOnboardingBack => 'VOLVER';

  @override
  String get templatesFilterBarAdjust => 'AJUSTAR';

  @override
  String get templatesFilterBarSetUp => 'AJUSTAR MI BÚSQUEDA';

  @override
  String get templatesFilterBarHint =>
      'Filtrado y ordenado según lo que buscás';

  @override
  String get templatesFilterBarHintSorted => 'Ordenado según lo que buscás';

  @override
  String get exerciseFeedbackAction => 'COMENTAR / REPORTAR';

  @override
  String exerciseFeedbackActionA11y(String exerciseName) {
    return 'Comentar o reportar una molestia en $exerciseName';
  }

  @override
  String get exerciseFeedbackSheetTitle => 'CONTALE A TU PF';

  @override
  String exerciseFeedbackSheetAnchorSet(String exerciseName, int setNumber) {
    return '$exerciseName · serie $setNumber';
  }

  @override
  String get exerciseFeedbackKindComment => 'Comentario';

  @override
  String get exerciseFeedbackKindDiscomfort => 'Molestia / dolor';

  @override
  String get exerciseFeedbackDiscomfortNotice =>
      'Tu PF recibe un aviso al toque.';

  @override
  String get exerciseFeedbackTextHint =>
      '¿Qué le querés contar? Ej: en la 3ª me tiró el hombro derecho.';

  @override
  String get exerciseFeedbackPhotoCamera => 'Cámara';

  @override
  String get exerciseFeedbackPhotoGallery => 'Galería';

  @override
  String get exerciseFeedbackPhotoRemove => 'Quitar foto';

  @override
  String get exerciseFeedbackPhotoError =>
      'No pudimos abrir la foto. Probá de nuevo.';

  @override
  String get exerciseFeedbackCancel => 'CANCELAR';

  @override
  String get exerciseFeedbackSubmit => 'ENVIAR';

  @override
  String get exerciseFeedbackSuccess =>
      'Listo. Tu PF lo va a ver junto a la serie.';

  @override
  String get exerciseFeedbackError =>
      'No pudimos guardar tu reporte. Probá de nuevo.';

  @override
  String get exerciseFeedbackNoteTagComment => 'DEL ALUMNO';

  @override
  String get exerciseFeedbackNoteTagDiscomfort => 'MOLESTIA';

  @override
  String get workoutHistorialTopeAlcanzado =>
      'Puede haber entrenamientos más viejos que no entran en esta lista.';

  @override
  String get dashboardActividadTopeAlcanzado =>
      'Puede haber más actividad que no entra en esta lista.';

  @override
  String exerciseFeedbackNoteSetTag(int setNumber) {
    return 'SERIE $setNumber';
  }

  @override
  String get coachSessionFeedbackLoadError =>
      'No pudimos cargar los reportes del alumno.';

  @override
  String get sessionFeedbackLoadError => 'No pudimos cargar tus reportes.';

  @override
  String get routineEditorGoToProblem => 'IR';

  @override
  String get routineEditorGoToProblemA11y => 'Ir al primer problema';

  @override
  String routineEditorFooterSummary(int dias, int sets) {
    String _temp0 = intl.Intl.pluralLogic(
      dias,
      locale: localeName,
      other: '$dias días',
      one: '1 día',
    );
    String _temp1 = intl.Intl.pluralLogic(
      sets,
      locale: localeName,
      other: '$sets sets',
      one: '1 set',
    );
    return '$_temp0 · $_temp1 · todo listo';
  }

  @override
  String get routineEditorProblemMissingName => 'Falta el nombre del plan';

  @override
  String get routineEditorProblemMissingSplit => 'Falta el split';

  @override
  String routineEditorProblemEmptyDay(int dia) {
    return 'Día $dia: sin ejercicios';
  }

  @override
  String routineEditorProblemDuplicate(int dia) {
    return 'Día $dia: ejercicio repetido';
  }

  @override
  String routineEditorProblemIncompleteSets(int dia, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sets sin completar',
      one: '1 set sin completar',
    );
    return 'Día $dia: $_temp0';
  }

  @override
  String routineEditorProblemOtherWeek(int semana, int dia) {
    return 'Semana $semana: día $dia sin completar';
  }

  @override
  String get routineEditorQuickEntryToggle => 'RÁPIDO';

  @override
  String get routineEditorQuickEntryToggleA11y => 'Entrada rápida';

  @override
  String get routineEditorQuickEntryHint => 'banca 4x10 60';

  @override
  String routineEditorQuickEntryWillAdd(int sets, String reps, String peso) {
    String _temp0 = intl.Intl.pluralLogic(
      sets,
      locale: localeName,
      other: '$sets sets',
      one: '1 set',
    );
    return 'Se agrega como $_temp0 × $reps a $peso.';
  }

  @override
  String get routineEditorQuickEntryNoWeight => 'sin peso';

  @override
  String get routineEditorQuickEntryEmptyHint =>
      'Buscá el ejercicio y tocalo. Después escribís 4x10 y el peso.';

  @override
  String get routineEditorQuickEntryPickedHint =>
      '4x10 y el peso. Por set con comas: 4x10,8,6,4 · 55,45,35,25. Por tiempo: 3x30s o 3x1:30. Decimales con punto: 62.5';

  @override
  String get routineEditorQuickEntryAdd => 'AGREGAR';

  @override
  String get routineEditorExerciseSheetTitle => 'ACCIONES';

  @override
  String get routineEditorSlotMenuCollapse => 'Colapsar sets';

  @override
  String get routineEditorSlotMenuExpand => 'Desplegar sets';

  @override
  String get coachTemplateEditorTitle => 'Nueva plantilla';

  @override
  String get coachTemplateEditorEditTitle => 'Editar plantilla';

  @override
  String get coachTemplateEditorSubmit => 'GUARDAR PLANTILLA';

  @override
  String get routineEditorAddNothingNew =>
      'Esos ejercicios ya estaban en el día.';

  @override
  String get routineEditorSupersetNeedsTwo =>
      'Una superserie necesita dos ejercicios. Se agregó uno solo, suelto.';

  @override
  String get routineEditorSlotMenuMergeUp => 'Unir con el de arriba';

  @override
  String get routineEditorSlotMenuUngroup => 'Sacar de la superserie';

  @override
  String get routineEditorSlotMenuMergeDown => 'Unir con el de abajo';

  @override
  String get paywallFreePlanLimitTitle => 'Esto es parte del plan pago';

  @override
  String paywallFreePlanLimitDaysBody(int max) {
    return 'Con el plan gratis armás rutinas de hasta $max días. Las plantillas de principiante del catálogo las seguís completas, sin tope.';
  }

  @override
  String get paywallFreePlanLimitWeeksBody =>
      'Periodizar en varias semanas es parte del plan pago. Con el gratis tu rutina propia va de a una semana.';

  @override
  String paywallFreePlanLimitShapeDaysBody(int actual, int max) {
    return 'Esta rutina tiene $actual días y con el plan gratis guardás hasta $max. Sacá los que sobren y vas a poder guardar los cambios. Entrenarla completa no tiene tope.';
  }

  @override
  String paywallFreePlanLimitShapeWeeksBody(int actual, int max) {
    return 'Esta rutina está periodizada en $actual semanas y con el plan gratis guardás hasta $max. Podés dejarla en $max para guardar los cambios, o pasarte al plan pago. Entrenarla completa no tiene tope.';
  }

  @override
  String get paywallFreePlanLimitUpgrade => 'Ver el plan pago';

  @override
  String get paywallFreePlanLimitDismiss => 'Entendido';

  @override
  String get paywallFreePlanLimitTemplateBody =>
      'Esta plantilla es parte del plan pago. Las de nivel principiante las podés usar completas con el plan gratis.';

  @override
  String paywallFreePlanLimitCustomizeTemplateBody(int max) {
    return 'Personalizar una plantilla del catálogo es parte del plan pago. Con el gratis la seguís tal cual, sin tope de días, o armás tu propia rutina de hasta $max días.';
  }

  @override
  String get workoutPlantillasPremiumChip => 'PLAN PAGO';

  @override
  String get progressionPeriodLast3Months => '3 meses';

  @override
  String get progressionPeriodLast1Year => '1 año';

  @override
  String get workoutRoutineFollow => 'Seguir esta plantilla';

  @override
  String get workoutRoutineFollowing => 'La estas siguiendo';

  @override
  String get workoutRoutineFollowSuccess =>
      'Listo, ahora seguís esta plantilla.';

  @override
  String get workoutRoutineFollowError =>
      'No pudimos marcarla. Probá de nuevo.';

  @override
  String get paywallFreePlanLimitRoutineCountBody =>
      'Con el plan gratis guardás hasta 3 rutinas propias. Las plantillas del catálogo que seguís no ocupan lugar.';

  @override
  String get paywallFreePlanLimitChartHistoryBody =>
      'Con el plan gratis mirás hasta un mes de historial. Los períodos de 3 meses y 1 año son del plan pago.';

  @override
  String get paywallFreePlanLimitProName => 'TREINO Pro';

  @override
  String get paywallFreePlanLimitProTagline =>
      'Todo lo que ya usás, sin los topes del plan gratis.';

  @override
  String paywallFreePlanLimitProBenefitDays(int max) {
    return 'Rutinas de hasta $max días';
  }

  @override
  String paywallFreePlanLimitProBenefitWeeks(int max) {
    return 'Hasta $max semanas, con periodización';
  }

  @override
  String get paywallFreePlanLimitProBenefitTemplates =>
      'Todas las plantillas del catálogo, de principiante a avanzado';

  @override
  String get paywallFreePlanLimitProBenefitCustomize =>
      'Personalizar cualquier plantilla del catálogo';

  @override
  String paywallFreePlanLimitProBenefitRoutines(int max) {
    return 'Hasta $max rutinas propias';
  }

  @override
  String get paywallFreePlanLimitProBenefitCharts =>
      'Gráficos de 3 meses y 1 año';

  @override
  String get paywallFreePlanLimitProMatchTag => 'Lo que buscabas';

  @override
  String get paywallAlumnoTitulo => 'TREINO Pro';

  @override
  String get paywallAlumnoBajada =>
      'Programá en serio: rutinas largas, periodización y todo tu historial.';

  @override
  String get paywallAlumnoPlanMensual => 'Mensual';

  @override
  String get paywallAlumnoPlanAnual => 'Anual';

  @override
  String get paywallAlumnoAhorro => '2 meses gratis';

  @override
  String get paywallAlumnoBeneficio1 => 'Rutinas de hasta 7 días';

  @override
  String get paywallAlumnoBeneficio2 => '16 semanas con periodización';

  @override
  String get paywallAlumnoBeneficio3 => 'Gráficos de 3 meses y 1 año';

  @override
  String get paywallAlumnoBeneficio4 => 'Las plantillas premium del catálogo';

  @override
  String get paywallAlumnoImpuestos =>
      'Tu banco le suma los impuestos argentinos a este precio (IVA y percepción). No los cobra TREINO: los vas a ver en el resumen de tu tarjeta.';

  @override
  String get paywallAlumnoCta => 'Suscribirme';

  @override
  String get paywallAlumnoRestaurar => 'Restaurar compras';

  @override
  String get paywallAlumnoSinPlanes =>
      'No pudimos cargar los planes. Probá de nuevo en un rato.';

  @override
  String get paywallAlumnoReintentar => 'Reintentar';

  @override
  String get paywallAlumnoListo => '¡Listo! Ya tenés TREINO Pro.';

  @override
  String get paywallAlumnoPendiente =>
      'Tu pago quedó pendiente de confirmación. Te avisamos cuando se acredite.';

  @override
  String get paywallAlumnoErrorCompra =>
      'No pudimos completar la compra. No se te cobró nada.';

  @override
  String get paywallAlumnoSinRestaurar =>
      'No encontramos compras para restaurar en esta cuenta.';

  @override
  String get moderationMenuA11y => 'Más opciones';

  @override
  String get moderationReportAction => 'Reportar';

  @override
  String get moderationBlockAction => 'Bloquear';

  @override
  String get moderationReportSheetTitle => '¿Por qué lo reportás?';

  @override
  String get moderationReportReasonHarassment => 'Acoso';

  @override
  String get moderationReportReasonSexualContent => 'Contenido sexual';

  @override
  String get moderationReportReasonViolenceOrSelfHarm =>
      'Violencia o autolesión';

  @override
  String get moderationReportReasonDangerousHealthAdvice =>
      'Consejo de salud peligroso';

  @override
  String get moderationReportReasonImpersonation => 'Suplantación de identidad';

  @override
  String get moderationReportReasonSpam => 'Spam';

  @override
  String get moderationReportReasonThirdPartyData => 'Datos de terceros';

  @override
  String get moderationReportReasonIntellectualProperty =>
      'Propiedad intelectual';

  @override
  String get moderationReportReasonOther => 'Otro';

  @override
  String get moderationReportDetailHint => 'Contanos más (opcional)';

  @override
  String get moderationReportSubmit => 'ENVIAR REPORTE';

  @override
  String get moderationReportCancel => 'CANCELAR';

  @override
  String get moderationReportSuccess => 'Gracias, lo vamos a revisar.';

  @override
  String get moderationReportError =>
      'No pudimos enviar el reporte. Probá de nuevo.';

  @override
  String moderationBlockConfirmTitle(String name) {
    return '¿Bloquear a $name?';
  }

  @override
  String get moderationBlockConfirmBody =>
      'No va a poder escribirte, seguirte ni reaccionar a tus posts.';

  @override
  String get moderationBlockConfirmAction => 'BLOQUEAR';

  @override
  String get moderationBlockDismiss => 'CANCELAR';

  @override
  String moderationBlockSuccess(String name) {
    return 'Bloqueaste a $name.';
  }

  @override
  String get moderationBlockError => 'No pudimos bloquear. Probá de nuevo.';

  @override
  String get moderationBlockedMessage =>
      'Ese texto no se puede publicar porque incumple las Normas de Comunidad. Revísalo e inténtalo de nuevo.';

  @override
  String get privacyTitle => 'Privacidad';

  @override
  String get privacyAnalyticsTitle => 'Analítica de uso';

  @override
  String get privacyAnalyticsSubtitle =>
      'Nos ayuda a entender qué partes de la app se usan.';

  @override
  String get privacyAnalyticsExplainer =>
      'Si la desactivás, TREINO deja de registrar cómo usás la app. No afecta tus entrenamientos, tus datos ni el funcionamiento de nada. Podés volver a activarla cuando quieras. Es una preferencia de ESTE dispositivo: si también entrás al Coach Hub, ahí se configura aparte.';

  @override
  String get privacyAnalyticsCrashNote =>
      'No incluye los reportes de errores: esos los seguimos recibiendo para poder arreglar fallas, y no describen lo que hacés en la app.';

  @override
  String get privacyEntryTitle => 'Analítica, correos y recordatorios';

  @override
  String get privacyPromoEmailsTitle => 'Correos promocionales';

  @override
  String get privacyPromoEmailsSubtitle =>
      'Si lo desactivas, dejamos de enviártelos. Los avisos de tu cuenta te seguirán llegando.';

  @override
  String get privacyPromoEmailsSaveError =>
      'No pudimos guardar el cambio. Inténtalo de nuevo.';

  @override
  String get privacyTrainingRemindersTitle => 'Recordatorios de entrenamiento';

  @override
  String get privacyTrainingRemindersSubtitle =>
      'Te avisamos si tu racha está en riesgo o si llevas días sin entrenar.';

  @override
  String get privacyTrainingRemindersSaveError =>
      'No pudimos guardar el cambio. Inténtalo de nuevo.';

  @override
  String customExerciseCounter(int count, int limit) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return '$countString de $limitString ejercicios propios';
  }

  @override
  String templateCounter(int count, int limit) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return '$countString de $limitString plantillas';
  }

  @override
  String get planLimitVerPlanesMovil => 'VER PLANES';

  @override
  String get planLimitEntendido => 'Entendido';

  @override
  String get planLimitPorMes => '/mes';

  @override
  String get planLimitPlanAMedidaTitulo => 'PLAN A MEDIDA';

  @override
  String get planLimitContactanos => 'CONTACTANOS';

  @override
  String get planLimitAlumnosTituloTope => 'LLEGASTE AL LÍMITE DE TU PLAN';

  @override
  String get planLimitAlumnosTituloInactiva => 'TU SUSCRIPCIÓN ESTÁ SUSPENDIDA';

  @override
  String get planLimitAlumnosTituloBaja => 'TU SUSCRIPCIÓN ESTÁ DADA DE BAJA';

  @override
  String get planLimitAlumnosCuerpoInactivaExplicacion =>
      'Mientras tu suscripción no esté al día, tu cuenta funciona con el límite del plan Free. Ningún alumno se elimina.';

  @override
  String planLimitAlumnosCuerpoTopeMovilLimitado(String plan, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit alumnos',
      one: '1 alumno',
    );
    return 'Tu plan $plan incluye $_temp0.';
  }

  @override
  String planLimitAlumnosCuerpoTopeMovilIlimitado(String plan) {
    return 'Tu plan $plan incluye alumnos sin límite.';
  }

  @override
  String get planLimitAlumnosPlanAMedidaCuerpo =>
      'Estás en el plan más grande. Para más de 15 alumnos estamos preparando un plan a tu medida.';

  @override
  String get planLimitAlumnosPlanAMedidaSnack =>
      'Muy pronto vas a poder tener más de 15 alumnos.';

  @override
  String planLimitReactivateTituloMovil(String plan) {
    return 'TU PLAN: $plan';
  }

  @override
  String planLimitReactivateCuerpoMovil(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alumnos',
      one: '1 alumno',
    );
    return 'No está activa. Mientras tanto, tu cuenta tiene el límite del plan Free: $_temp0.';
  }

  @override
  String get planLimitVerEstadoMovil => 'VER ESTADO';

  @override
  String planLimitReactivateEstadoMovil(String estado) {
    return 'Estado: $estado';
  }

  @override
  String get planLimitEstadoActiva => 'activa';

  @override
  String get planLimitEstadoPendiente => 'pendiente de pago';

  @override
  String get planLimitEstadoGracia => 'con pago pendiente';

  @override
  String get planLimitEstadoPausada => 'pausada';

  @override
  String get planLimitEstadoCancelada => 'cancelada';

  @override
  String planLimitAlumnosBeneficioLimitado(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit alumnos',
      one: '1 alumno',
    );
    return 'Hasta $_temp0';
  }

  @override
  String get planLimitAlumnosBeneficioIlimitado => 'Alumnos sin límite';

  @override
  String get planLimitSuscripcionPausadaMovil => 'Tu suscripción está pausada.';

  @override
  String get planLimitSuscripcionBajaMovil =>
      'Tu suscripción está dada de baja.';

  @override
  String get planLimitTrainerTituloEjercicios => 'TOPE DE EJERCICIOS PROPIOS';

  @override
  String get planLimitTrainerTituloPlantillas => 'TOPE DE PLANTILLAS';

  @override
  String planLimitTrainerPasadoTopeEjercicios(
      int count, int limit, int toDelete) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Tenés $_temp0 y tu plan incluye $limit. Conservás todos; para crear uno nuevo, borrá $toDelete.';
  }

  @override
  String planLimitTrainerPasadoTopePlantillas(
      int count, int limit, int toArchive) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plantillas',
      one: '1 plantilla',
    );
    return 'Tenés $_temp0 y tu plan incluye $limit. Conservás todas; para crear una nueva, archivá $toArchive.';
  }

  @override
  String planLimitTrainerInactivaEjercicios(
      String plan, String planEfectivo, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Tu suscripción a $plan no está activa. Mientras tanto, tu plan $planEfectivo incluye $_temp0.';
  }

  @override
  String planLimitTrainerInactivaPlantillas(
      String plan, String planEfectivo, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit plantillas',
      one: '1 plantilla',
    );
    return 'Tu suscripción a $plan no está activa. Mientras tanto, tu plan $planEfectivo incluye $_temp0.';
  }

  @override
  String planLimitTrainerTopeEjerciciosConTier(String plan, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Tu plan $plan incluye $_temp0. Podés editar o borrar los que ya tenés.';
  }

  @override
  String planLimitTrainerTopeEjerciciosGenerico(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Tu plan incluye $_temp0. Podés editar o borrar los que ya tenés.';
  }

  @override
  String planLimitTrainerTopePlantillasConTier(String plan, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit plantillas',
      one: '1 plantilla',
    );
    return 'Tu plan $plan incluye $_temp0. Podés editar o archivar las que ya tenés.';
  }

  @override
  String planLimitTrainerTopePlantillasGenerico(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit plantillas',
      one: '1 plantilla',
    );
    return 'Tu plan incluye $_temp0. Podés editar o archivar las que ya tenés.';
  }

  @override
  String planLimitTrainerBeneficioEjerciciosLimitado(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Hasta $_temp0';
  }

  @override
  String get planLimitTrainerBeneficioEjerciciosIlimitado =>
      'Ejercicios propios sin límite';

  @override
  String planLimitTrainerBeneficioPlantillasLimitado(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit plantillas',
      one: '1 plantilla',
    );
    return 'Hasta $_temp0';
  }

  @override
  String get planLimitTrainerBeneficioPlantillasIlimitado =>
      'Plantillas sin límite';

  @override
  String get planLimitTrainerPlanAMedidaCuerpo =>
      'Estás en el plan más grande. Estamos preparando un plan a tu medida.';

  @override
  String eliminarCuentaSheetTrainerUnlinkNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se van a desvincular $count alumnos. Les avisamos.',
      one: 'Se va a desvincular 1 alumno. Le avisamos.',
    );
    return '$_temp0';
  }

  @override
  String get eliminarCuentaSheetErrorSubscriptionCancel =>
      'No pudimos cancelar tu suscripción, así que tu cuenta no se eliminó. Inténtalo de nuevo en unos minutos.';

  @override
  String get eliminarCuentaSheetErrorNotAllowed =>
      'No pudimos eliminar tu cuenta desde la app. Escríbenos y lo resolvemos.';

  @override
  String get eliminarCuentaWebReauthTitle => 'Confirma tu identidad';

  @override
  String get eliminarCuentaWebReauthPasswordBody =>
      'Por seguridad, introduce tu contraseña para confirmar que eres tú.';

  @override
  String get eliminarCuentaWebReauthCta => 'CONFIRMAR';

  @override
  String eliminarCuentaWebPopupHint(String provider) {
    return 'Para confirmar que eres tú, se abrirá una ventana de $provider.';
  }

  @override
  String get coachHubOnboardingPfLocationStaleHint =>
      'Este lugar ya no está disponible. Vuelve a elegir este lugar para que te encuentren.';

  @override
  String get appUpdateTitle => 'Actualiza la app';

  @override
  String get appUpdateBody =>
      'Esta versión de TREINO ya no es compatible y puede perder datos de tus rutinas. Actualízala para seguir entrenando.';

  @override
  String get appUpdateCta => 'ACTUALIZAR';

  @override
  String get appUpdateOpenError =>
      'No pudimos abrir la tienda. Busca TREINO en la App Store o en Google Play.';

  @override
  String get timePickerHelpText => 'Elige una hora';

  @override
  String logFieldRange(String min, String max, String unit) {
    return 'Entre $min y $max $unit';
  }

  @override
  String inputMaxReached(String max, String unit) {
    return 'Máximo $max $unit';
  }

  @override
  String get performanceLogTitleEdit => 'Editar evaluación';

  @override
  String get performanceLogUpdateCta => 'GUARDAR CAMBIOS';

  @override
  String get performanceLogUpdateSuccess => 'Evaluación actualizada';

  @override
  String get performanceHistoryEditTooltip => 'Editar evaluación';

  @override
  String get performanceHistoryDeleteTooltip => 'Eliminar evaluación';

  @override
  String get performanceHistoryOtherTrainerTag => 'Cargada por otro entrenador';

  @override
  String get performanceDeleteConfirmTitle => '¿Eliminar evaluación?';

  @override
  String performanceDeleteConfirmBody(String date) {
    return 'Se eliminará la evaluación del $date. Esta acción no se puede deshacer.';
  }

  @override
  String get performanceDeleteSuccess => 'Evaluación eliminada';

  @override
  String get performanceDeleteError =>
      'No pudimos eliminar la evaluación. Prueba de nuevo.';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get agendaRuleDeleteTitle => '¿Borrar este horario?';

  @override
  String get agendaRuleDeleteBody => 'Las reservas existentes se mantienen.';

  @override
  String get agendaOverrideDeleteTitle => '¿Eliminar esta excepción?';

  @override
  String get onboardingCustomExerciseNotNow => 'AHORA NO';

  @override
  String get authSignOutConfirmTitle => '¿Cerrar sesión?';

  @override
  String get authSignOutConfirmAction => 'Salir';

  @override
  String get sessionRestEndedTitle => 'Terminó el descanso';

  @override
  String get sessionRestEndedBody => 'Vuelve a la serie';

  @override
  String get sessionRestCountdownTitle => 'Descanso';

  @override
  String get sessionRestCountdownBody =>
      'Vuelve a la serie cuando llegue a cero';

  @override
  String get pdfImportUploadTitle => 'IMPORTAR PLAN';

  @override
  String get pdfImportPrivacyNotice =>
      'Usamos IA para leer tu PDF y armar el plan. No guardamos el archivo. Sube solo los datos de tu alumno que sean necesarios.';

  @override
  String get pdfImportPickFile => 'Elegir PDF';

  @override
  String get pdfImportPickAnother => 'Elegir otro archivo';

  @override
  String get pdfImportProcess => 'PROCESAR PLAN';

  @override
  String get pdfImportProcessingTitle => 'Leyendo tu plan…';

  @override
  String get pdfImportProcessingHint =>
      'Puede tardar hasta un par de minutos. No cierres esta pantalla.';

  @override
  String get pdfImportLeaveTitle => '¿Salir mientras se lee el plan?';

  @override
  String get pdfImportLeaveBody =>
      'Este intento ya cuenta en tu cupo aunque salgas.';

  @override
  String get pdfImportLeaveConfirm => 'Salir';

  @override
  String get pdfImportRetry => 'Reintentar';

  @override
  String get pdfImportErrorTooBig =>
      'El archivo pesa más de 5 MB. Elige uno más liviano.';

  @override
  String get pdfImportErrorInternal =>
      'No pudimos leer el plan. Prueba de nuevo en un rato.';

  @override
  String pdfImportReadSummary(int days, int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days días',
      one: '1 día',
    );
    String _temp1 = intl.Intl.pluralLogic(
      weeks,
      locale: localeName,
      other: '$weeks semanas',
      one: '1 semana',
    );
    return 'Leímos $_temp0 y $_temp1.';
  }

  @override
  String get pdfImportErrorNotPdf => 'El archivo no es un PDF válido.';

  @override
  String get pdfImportErrorTooManyPages =>
      'El PDF tiene más de 20 páginas. Elige uno más corto.';

  @override
  String get pdfImportErrorEncrypted =>
      'El PDF tiene contraseña. Expórtalo sin contraseña y elígelo de nuevo.';

  @override
  String get pdfImportErrorFileUnknown =>
      'No pudimos usar este archivo. Prueba con otro.';

  @override
  String pdfImportErrorQuotaWeek(String date, String time) {
    return 'Usaste todas las importaciones de esta semana. Se renueva el $date a las $time.';
  }

  @override
  String pdfImportErrorQuotaDay(String date, String time) {
    return 'Usaste todas las importaciones de hoy. Se renueva el $date a las $time.';
  }

  @override
  String get pdfImportErrorQuotaUnknown =>
      'Usaste todas las importaciones disponibles por ahora.';

  @override
  String get pdfImportErrorTimeout =>
      'La lectura tardó demasiado. Prueba de nuevo; si el PDF es largo, prueba con menos páginas.';

  @override
  String get pdfImportErrorInvalidPlan =>
      'Leímos el PDF pero no pudimos armar el plan. Este intento ya contó en tu cupo.';

  @override
  String get pdfImportErrorDisabled =>
      'Importar de PDF no está disponible para tu cuenta.';

  @override
  String get pdfImportErrorUnavailable =>
      'Importar de PDF no está disponible por un problema nuestro. No se descontó de tu cupo.';

  @override
  String get pdfImportErrorNotTrainer =>
      'Solo los entrenadores pueden importar planes.';

  @override
  String get pdfImportErrorSignedOut =>
      'Tu sesión se cerró. Vuelve a iniciar sesión.';

  @override
  String get pdfImportCta => 'IMPORTAR DE PDF';

  @override
  String pdfImportQuotaRemaining(int week, int day) {
    return 'Te quedan $week esta semana y $day hoy.';
  }
}

/// The translations for Spanish Castilian, as used in Argentina (`es_AR`).
class AppL10nEsAr extends AppL10nEs {
  AppL10nEsAr() : super('es_AR');

  @override
  String get notFoundTitle => 'Página no encontrada';

  @override
  String get notFoundBody =>
      'La ruta que buscás no existe o el enlace es inválido.';

  @override
  String get notFoundCta => 'Volver al inicio';

  @override
  String get homeAthleteFirstRunTitle => 'Arrancá tu entrenamiento';

  @override
  String get homeAthleteFirstRunBody =>
      'Creá tu propia rutina, explorá planes ya armados o buscá un entrenador que te guíe.';

  @override
  String get homeAthleteFirstRunBodyWithTrainer =>
      'Ya tenés entrenador. Mientras tanto, creá tu propia rutina o explorá planes ya armados.';

  @override
  String get homeAthleteFirstRunBodyNeutral =>
      'Creá tu propia rutina o explorá planes ya armados.';

  @override
  String get homeAthleteFirstRunCreateCta => 'CREAR RUTINA';

  @override
  String get homeAthleteFirstRunExplorePlansCta => 'Explorar planes';

  @override
  String get homeAthleteFirstRunFindTrainerCta => 'Buscar entrenador';

  @override
  String get homeEstaSemanaTitle => 'ESTA SEMANA';

  @override
  String get homeEstaSemanaLoadError => 'No pudimos cargar tus insights.';

  @override
  String get homeEstaSemanaHeaderPill => 'RACHA ACTUAL';

  @override
  String get homeEstaSemanaHeaderPillEmpty => 'PRIMER PASO';

  @override
  String homeEstaSemanaWeekMonth(int week, String month) {
    return 'SEM $week · $month';
  }

  @override
  String homeEstaSemanaStreakUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'SEMANAS',
      one: 'SEMANA',
    );
    return '$_temp0';
  }

  @override
  String get homeEstaSemanaStreakSubtextTrained =>
      'No rompas la racha — entrenaste hoy.';

  @override
  String get homeEstaSemanaStreakSubtextPending =>
      'No rompas la racha — entrená hoy.';

  @override
  String get homeEstaSemanaPeriodWeek => 'SEMANA';

  @override
  String get homeEstaSemanaPeriodMonth => 'MES';

  @override
  String homeEstaSemanaPeriodUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'entrenos',
      one: 'entreno',
    );
    return '$_temp0';
  }

  @override
  String get homeEstaSemanaMusclesTitle => 'MÚSCULOS DE LA SEMANA';

  @override
  String get homeEstaSemanaMusclesLegend =>
      'Más color = más cerca de las series que pide tu rutina esta semana.';

  @override
  String get homeGreeting => '¡HOLA!';

  @override
  String homeGreetingNamed(String name) {
    return '¡HOLA, $name!';
  }

  @override
  String get homeEstaSemanaEmptyTitle => 'TU RACHA\nEMPIEZA ACÁ';

  @override
  String get homeEstaSemanaEmptyBody =>
      'Cada entrenamiento alimenta tu racha. Hacé el primero y empezá a construir tu progreso.';

  @override
  String get homeEstaSemanaEmptyCta => 'EXPLORAR RUTINAS  →';

  @override
  String get homeEstaSemanaInsightsCta => 'VER INSIGHTS  →';

  @override
  String get homeEstaSemanaHeaderPillResume => 'A RETOMAR';

  @override
  String get homeEstaSemanaResumeTitle => 'TU RACHA\nTE ESPERA';

  @override
  String get homeEstaSemanaResumeBody =>
      'Ya tenés historial construido. Esta semana todavía está en cero — retomá hoy y seguí sumando progreso.';

  @override
  String get homeEstaSemanaResumeCta => 'VOLVER A ENTRENAR  →';

  @override
  String get authSplashTagline => 'ENTRENÁ. COMPARTÍ. CRECÉ.';

  @override
  String get authBrandHeadline1Light => 'DEJÁ DE ';

  @override
  String get authBrandHeadline1Bold => 'IMPROVISAR.';

  @override
  String get authBrandHeadline2Light => 'EMPEZÁ A ';

  @override
  String get authBrandHeadline2Bold => 'PROGRESAR.';

  @override
  String get authWelcomeEyebrow => 'ENTRENAMIENTO · GYM · COACH';

  @override
  String get authWelcomeBody =>
      'Tu rutina, tus series y tus cargas en un solo lugar. Con un coach atrás si lo querés.';

  @override
  String get authWelcomeCta => 'EMPEZAR';

  @override
  String get authWelcomeHaveAccount => '¿Ya tenés cuenta?';

  @override
  String get authWelcomeSignIn => 'INICIAR SESIÓN';

  @override
  String get authWelcomeTrainerPrompt => '¿Sos entrenador?';

  @override
  String get authWelcomeBecomeTrainer => 'Quiero ser entrenador';

  @override
  String authWelcomeBecomeTrainerFallback(String email) {
    return 'No pudimos abrir tu correo. Escribinos a $email.';
  }

  @override
  String get authLoginTitle => 'BIENVENIDO';

  @override
  String get authLoginSubtitle => 'Entrá para seguir tu rutina';

  @override
  String get authLoginEmailHint => 'tu@email.com';

  @override
  String get authLoginForgot => 'Olvidé la contraseña';

  @override
  String get authLoginCta => 'ENTRAR';

  @override
  String get authLoginContinueWith => 'O CONTINUÁ CON';

  @override
  String get authLoginNoAccount => '¿No tenés cuenta?';

  @override
  String get authLoginRegisterLink => 'Registrate';

  @override
  String get authLoginTrainerCardTitle => '¿Sos entrenador?';

  @override
  String get authLoginTrainerCardSubtitle => 'Pedí tu alta al equipo TREINO';

  @override
  String get authRegisterAppbar => 'CREAR CUENTA';

  @override
  String get authRegisterTitle => 'SUMATE A';

  @override
  String get authRegisterSubtitle => 'Es gratis. En 30 segundos estás adentro.';

  @override
  String get authRegisterEmailLabel => 'EMAIL';

  @override
  String get authRegisterPasswordLabel => 'CONTRASEÑA';

  @override
  String get authRegisterConfirmPasswordLabel => 'CONFIRMAR CONTRASEÑA';

  @override
  String get authRegisterCta => 'CREAR CUENTA';

  @override
  String get authRegisterDividerOr => 'O';

  @override
  String get authForgotTitle => 'RECUPERAR\nACCESO';

  @override
  String get authForgotBody =>
      'Ingresá tu email y te enviamos un link para resetear la contraseña.';

  @override
  String get authForgotEmailLabel => 'EMAIL';

  @override
  String get authForgotEmailHint => 'tu@email.com';

  @override
  String get authForgotCta => 'ENVIAR LINK';

  @override
  String get authForgotSuccess =>
      'Si tu email está registrado, te enviamos un link para resetear la contraseña.';

  @override
  String get authForgotBackToLogin => 'Volver al login';

  @override
  String get authForgotSpamHint =>
      '¿No te llegó? Puede tardar un minuto. Revisá también la carpeta de spam.';

  @override
  String get authForgotResendCta => 'Reenviar el link';

  @override
  String authForgotResendIn(int seconds) {
    return 'Podés reenviar en ${seconds}s';
  }

  @override
  String get authForgotEditEmail => 'Usar otra dirección';

  @override
  String get authTrainerInquiryDialogTitle => 'Acceso de entrenador';

  @override
  String get authTrainerInquiryDialogBody =>
      'Para alta de entrenador, escribinos a treino@gettreino.com';

  @override
  String get authTrainerInquiryDialogClose => 'Cerrar';

  @override
  String get authTermsPlaceholder => 'Próximamente';

  @override
  String get authGoogleLabel => 'GOOGLE';

  @override
  String get authAppleLabel => 'APPLE';

  @override
  String get authLoginHeaderTitle => 'Iniciar sesión';

  @override
  String get authRegisterHeaderTitle => 'Crear una cuenta';

  @override
  String get authLoginOrSignInWith => 'O iniciá sesión con';

  @override
  String get authRegisterOrSignUpWith => 'O registrate con';

  @override
  String get authContinueWithGoogle => 'Continuar con Google';

  @override
  String get authContinueWithApple => 'Continuar con Apple';

  @override
  String get authRegisterHaveAccount => '¿Ya tenés cuenta?';

  @override
  String get authRegisterSignInLink => 'Iniciá sesión';

  @override
  String get authComingSoonTooltip => 'Próximamente';

  @override
  String get authValidationEmailInvalid => 'El email no es válido';

  @override
  String get authValidationPasswordRules =>
      'La contraseña debe tener al menos 8 caracteres, una letra y un número';

  @override
  String get authValidationPasswordMismatch => 'Las contraseñas no coinciden';

  @override
  String get authProfileSignOut => 'Cerrar sesión';

  @override
  String get coachAppBarTitle => 'Entrenadores';

  @override
  String get coachLoadingLabel => 'Cargando entrenadores…';

  @override
  String get coachErrorLabel => 'No pudimos cargar los entrenadores.';

  @override
  String get coachRetryLabel => 'Reintentar';

  @override
  String get coachEmptyLabel => 'No encontramos entrenadores en tu zona.';

  @override
  String get coachMapToggleLabel => 'Mapa';

  @override
  String get coachMapProximamente => 'Próximamente';

  @override
  String get coachDistanceUnknown => '—';

  @override
  String get coachMonthlyRateUnit => '/mes';

  @override
  String get coachSpecialtyAll => 'Todos';

  @override
  String get coachStatsReviewsLabel => 'RESEÑAS';

  @override
  String get coachStatsExperienceLabel => 'AÑOS EXP';

  @override
  String get coachStatsStudentsLabel => 'ALUMNOS';

  @override
  String get coachStatsPlaceholder => '—';

  @override
  String get coachProfileLoadingLabel => 'Cargando perfil…';

  @override
  String get coachProfileErrorLabel => 'No pudimos cargar este perfil.';

  @override
  String get coachProfileNotFoundLabel => 'Entrenador no encontrado.';

  @override
  String get coachProfileBioEmpty => 'Sin descripción.';

  @override
  String get coachProfileRateLabel => 'Tarifa mensual';

  @override
  String get coachCtaLabel => 'PEDIR VÍNCULO';

  @override
  String get coachInquiryCtaLabel => 'CONSULTAR';

  @override
  String get coachInquiryCtaHelp =>
      'Preguntale precio, modalidad y horarios sin comprometerte con nadie.';

  @override
  String get coachInquiryCtaError =>
      'No pudimos abrir la consulta. Probá de nuevo.';

  @override
  String get coachPreviewBannerTitle => 'VISTA PREVIA';

  @override
  String get coachPreviewBannerBody =>
      'Así ve tu perfil un alumno. Los botones están desactivados en esta vista.';

  @override
  String get coachPreviewMissingExperience =>
      'Todavía no cargaste tus años de experiencia: los alumnos ven «—». Tocá para cargarlos.';

  @override
  String get coachCtaProximamente => 'Próximamente — Etapa 3';

  @override
  String get coachLocationSheetTitle => 'TU UBICACIÓN';

  @override
  String get coachLocationSheetBody =>
      'TREINO usa tu ubicación para mostrarte entrenadores cerca tuyo. Tu ubicación no es visible para otros usuarios.';

  @override
  String get coachLocationSheetContinue => 'CONTINUAR';

  @override
  String get coachLocationSettingsNoticeTitle => 'UBICACIÓN DESACTIVADA';

  @override
  String get coachLocationSettingsNoticeBody =>
      'Activá la ubicación en Ajustes para ver entrenadores cerca tuyo. Si preferís, seguí sin ubicación y explorá entrenadores Online.';

  @override
  String get coachLocationSettingsNoticeOpenSettings => 'ABRIR AJUSTES';

  @override
  String get coachLocationSettingsNoticeContinueWithout =>
      'Seguir sin ubicación';

  @override
  String get coachLocationServicesOffTitle =>
      'SERVICIOS DE UBICACIÓN DESACTIVADOS';

  @override
  String get coachLocationServicesOffBody =>
      'Activá los Servicios de ubicación en Ajustes para ver entrenadores cerca tuyo. Si preferís, seguí sin ubicación y explorá entrenadores Online.';

  @override
  String get coachLocationSheetBodyGyms =>
      'TREINO usa tu ubicación para mostrarte gimnasios cerca tuyo. Tu ubicación no es visible para otros usuarios.';

  @override
  String get coachLocationSheetBodyDetect =>
      'TREINO usa tu ubicación una sola vez para detectar el lugar donde entrenás.';

  @override
  String get coachLocationSettingsNoticeBodyGyms =>
      'Activá la ubicación en Ajustes para ver gimnasios cerca tuyo. Mientras tanto podés buscarlo por nombre.';

  @override
  String get coachLocationSettingsNoticeBodyDetect =>
      'Activá la ubicación en Ajustes para detectar tu ubicación. También podés elegir un gimnasio de la lista.';

  @override
  String get coachLocationServicesOffBodyGyms =>
      'Activá los Servicios de ubicación en Ajustes para ver gimnasios cerca tuyo. Mientras tanto podés buscarlo por nombre.';

  @override
  String get coachLocationServicesOffBodyDetect =>
      'Activá los Servicios de ubicación en Ajustes para detectar tu ubicación. También podés elegir un gimnasio de la lista.';

  @override
  String get profileLocationPermissionNeeded =>
      'Necesitamos permiso de ubicación.';

  @override
  String get profileLocationDetectFailed => 'No pudimos detectar tu ubicación.';

  @override
  String get coachMiPlanTitle => 'MI PLAN';

  @override
  String get coachMiPlanEmpty => 'No tenés rutina asignada todavía.';

  @override
  String get coachMiPlanError => 'Error al cargar tu plan.';

  @override
  String get coachMiPlanFinalizado => 'Plan finalizado';

  @override
  String get coachMiPlanCurrent => 'Actual';

  @override
  String get coachAssignedByPrefix => 'Asignado por ';

  @override
  String get coachAssignedByLoading => 'Asignado por …';

  @override
  String get coachAssignedByError => 'Asignado por un PF';

  @override
  String get coachCreatePlanCta => 'CREAR PLAN';

  @override
  String get coachCreatePlanSuccess => 'Plan creado y asignado.';

  @override
  String get coachCreatePlanError =>
      'No pudimos crear el plan. Intentá de nuevo.';

  @override
  String get coachAthleteDetailNoPlans => 'Todavía no le asignaste planes.';

  @override
  String get coachEditorTitle => 'Crear plan';

  @override
  String get coachEditorEditTitle => 'Editar plan';

  @override
  String get coachEditorNameLabel => 'NOMBRE';

  @override
  String get coachEditorSplitLabel => 'SPLIT (e.g. PPL)';

  @override
  String get coachEditorAddDay => 'Agregar día';

  @override
  String get coachEditorAddSlot => 'Agregar ejercicio';

  @override
  String get coachEditorAddSuperset => '+ Superserie';

  @override
  String get coachEditorSubmit => 'ASIGNAR PLAN';

  @override
  String get coachEditorUpdateLabel => 'GUARDAR CAMBIOS';

  @override
  String get coachUpdatePlanSuccess => 'Plan actualizado.';

  @override
  String get coachExercisePicker => 'Buscar ejercicio';

  @override
  String get agendaButtonLabel => 'MI AGENDA';

  @override
  String get athleteNutritionPlanButtonLabel => 'MI PLAN NUTRICIONAL';

  @override
  String get athleteFilesButtonLabel => 'MIS ARCHIVOS';

  @override
  String get athleteNutritionPlanScreenTitle => 'PLAN NUTRICIONAL';

  @override
  String get athleteNutritionChooseOneHint => 'Elegí una';

  @override
  String get athleteNutritionEmptyGroup =>
      'Tu PF todavía no cargó opciones acá.';

  @override
  String get athleteNutritionAllHint => 'Va todo';

  @override
  String get athleteNutritionPlanEmpty =>
      'Tu PF todavía no cargó tu plan nutricional.';

  @override
  String get athleteNutritionPlanLoadError =>
      'No pudimos cargar tu plan nutricional.';

  @override
  String get athleteNutritionNeedsActiveLink =>
      'Necesitás un vínculo activo con un PF para ver tu plan nutricional.';

  @override
  String get trainerNutritionSectionTitle => 'PLAN NUTRICIONAL';

  @override
  String get trainerNutritionSectionLoadCta => '+ Cargar';

  @override
  String get trainerNutritionSectionEditCta => 'Editar';

  @override
  String get trainerNutritionSectionEmpty =>
      'Todavía no le cargaste un plan nutricional.';

  @override
  String get trainerNutritionSectionUntitled => 'Plan nutricional';

  @override
  String trainerNutritionSectionSummary(int count, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comidas',
      one: '1 comida',
    );
    return '$_temp0 · actualizado el $date';
  }

  @override
  String get trainerNutritionLoadError =>
      'No pudimos cargar el plan nutricional.';

  @override
  String get trainerNutritionEditorTitle => 'PLAN NUTRICIONAL';

  @override
  String get trainerNutritionEditorPlanTitleLabel =>
      'Título del plan (opcional)';

  @override
  String get trainerNutritionEditorPlanTitleHint =>
      'Ej: Progresión 4 - Semana 9 en adelante';

  @override
  String get trainerNutritionEditorMealNameHint => 'Nombre de la comida';

  @override
  String get trainerNutritionEditorMealTimeHint => 'Hora';

  @override
  String get trainerNutritionEditorDeleteMealTooltip => 'Eliminar comida';

  @override
  String get trainerNutritionEditorAddMeal => 'AGREGAR COMIDA';

  @override
  String get trainerNutritionEditorGroupNameHint => 'Nombre del grupo';

  @override
  String get trainerNutritionEditorDeleteGroupTooltip => 'Eliminar grupo';

  @override
  String get trainerNutritionEditorAddGroup => '+ Agregar grupo';

  @override
  String get trainerNutritionEditorChooseOne => 'Elegir una';

  @override
  String get trainerNutritionEditorAll => 'Todas';

  @override
  String get trainerNutritionEditorAddOption => '+ Agregar opción';

  @override
  String get trainerNutritionEditorEmptyGroup => 'Sin opciones todavía.';

  @override
  String get trainerNutritionEditorSave => 'GUARDAR PLAN';

  @override
  String get trainerNutritionEditorSaved => 'Plan nutricional guardado.';

  @override
  String get trainerNutritionEditorSaveError =>
      'No pudimos guardar el plan. Probá de nuevo.';

  @override
  String get trainerNutritionEditorStaleReadError =>
      'No pudimos leer el plan guardado. Para no pisarlo, no se puede guardar hasta volver a leerlo.';

  @override
  String get trainerNutritionEditorEmptyPlan =>
      'El plan está vacío. Agregá al menos una comida con nombre.';

  @override
  String get trainerNutritionEditorDiscardTitle => '¿Descartar cambios?';

  @override
  String get trainerNutritionEditorDiscardBody =>
      'Si salís ahora vas a perder los cambios del plan sin guardar.';

  @override
  String get trainerNutritionEditorDiscardConfirm => 'Descartar';

  @override
  String trainerNutritionEditorDeleteTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get trainerNutritionEditorDeleteMealBody =>
      'Se borra la comida con todos sus grupos y opciones.';

  @override
  String get trainerNutritionEditorDeleteGroupBody =>
      'Se borra el grupo con todas sus opciones.';

  @override
  String get trainerNutritionOptionNewTitle => 'NUEVA OPCIÓN';

  @override
  String get trainerNutritionOptionEditTitle => 'EDITAR OPCIÓN';

  @override
  String get trainerNutritionOptionNameLabel => 'ALIMENTO';

  @override
  String get trainerNutritionOptionNameHint => 'Ej: 5 discos de arroz';

  @override
  String get trainerNutritionOptionQuantityLabel => 'CANTIDAD';

  @override
  String get trainerNutritionOptionQuantityHint => 'Ej: 230-240';

  @override
  String get trainerNutritionOptionUnitLabel => 'UNIDAD';

  @override
  String get trainerNutritionOptionUnitHint => 'Ej: grs peso cocido';

  @override
  String get trainerNutritionOptionNotesLabel => 'NOTAS';

  @override
  String get trainerNutritionOptionNotesHint => 'Marca, aclaraciones…';

  @override
  String get trainerNutritionOptionDone => 'LISTO';

  @override
  String get trainerNutritionOptionDelete => 'ELIMINAR OPCIÓN';

  @override
  String get athleteLinkRequired =>
      'No encontramos un vínculo activo con un PF.';

  @override
  String get trainerAcceptsInquiriesTitle => 'Acepto consultas';

  @override
  String get trainerAcceptsInquiriesSubtitle =>
      'Un alumno puede escribirte antes de pedirte el vínculo. Si lo apagás, no te llegan consultas nuevas — las conversaciones ya abiertas siguen.';

  @override
  String get athleteLinkUnconfirmed =>
      'No pudimos confirmar tu vínculo con tu PF.';

  @override
  String get athleteLinkRequiredRetry => 'Reintentar';

  @override
  String get athleteSessionMissing => 'Tu sesión se cerró. Volvé a entrar.';

  @override
  String get athleteFilesScreenTitle => 'MIS ARCHIVOS';

  @override
  String get athleteFilesEmpty =>
      'Tu PF todavía no compartió archivos con vos.';

  @override
  String get athleteFilesLoadError => 'No pudimos cargar tus archivos.';

  @override
  String get agendaScreenTitle => 'Agenda';

  @override
  String get agendaEmptyAvailability => 'Tu PF todavía no configuró horarios.';

  @override
  String get agendaBookingConfirmTitle => 'Confirmar reserva';

  @override
  String agendaBookingConfirmBody(String date, String time) {
    return '¿Confirmar reserva el $date a las $time?';
  }

  @override
  String get agendaBookingConfirmCta => 'Confirmar';

  @override
  String get agendaBookingCancel => 'Cancelar';

  @override
  String get agendaBookingSuccess => 'Reserva confirmada.';

  @override
  String get agendaBookingRaceError =>
      'Ese horario fue reservado justo ahora. Probá con otro.';

  @override
  String get agendaCancellationConfirmTitle => 'Cancelar reserva';

  @override
  String get agendaCancellationConfirmBody => '¿Cancelar esta reserva?';

  @override
  String get agendaCancellationConfirmCta => 'Sí, cancelar';

  @override
  String get agendaCancellationKeep => 'No, mantener';

  @override
  String get agendaCancellationSuccess => 'Reserva cancelada.';

  @override
  String get agendaCancellationTooLate =>
      'No podés cancelar con menos de 24h de anticipación.';

  @override
  String get agendaAthleteCancelCta => 'CANCELAR';

  @override
  String get agendaAthleteCancelConfirmBody =>
      '¿Cancelar esta sesión? Le avisamos a tu PF.';

  @override
  String get agendaBookingCancelledByAthlete =>
      'Reserva cancelada por el alumno.';

  @override
  String get agendaAthleteNotifyTrainerCta => 'AVISAR A MI PF';

  @override
  String get agendaAthleteNotifyHint =>
      'Faltan menos de 24 h: si no podés ir, avisale a tu PF.';

  @override
  String get agendaAthleteChatError =>
      'No pudimos abrir el chat. Probá de nuevo.';

  @override
  String get agendaUpcomingAppointmentsHeading => 'TUS PRÓXIMAS RESERVAS';

  @override
  String get agendaPastAppointmentsHeading => 'TURNOS PASADOS';

  @override
  String get agendaGenericError => 'Hubo un problema. Intentá de nuevo.';

  @override
  String get agendaTrainerEmptyAvailability =>
      'Todavía no configuraste tus horarios de trabajo. Agregá uno para que tus alumnos puedan reservar.';

  @override
  String get agendaConfigureHoursCta => 'CONFIGURAR HORARIOS';

  @override
  String get agendaMyWorkingHoursHeading => 'MIS HORARIOS DE TRABAJO';

  @override
  String get agendaAddRuleCta => 'AGREGAR HORARIO';

  @override
  String get agendaBlockDayCta => 'BLOQUEAR UN DÍA';

  @override
  String get agendaEditorTitle => 'Mis horarios';

  @override
  String get agendaRuleDeleteConfirm =>
      '¿Borrar este horario? Las reservas existentes se mantienen.';

  @override
  String get agendaRuleInvalidWindow =>
      'La hora de fin debe ser posterior al inicio y dejar espacio para al menos un turno.';

  @override
  String agendaRuleOverlap(String day, String start, String end) {
    return 'Ese horario se superpone con otro que ya cargaste: $day, $start – $end.';
  }

  @override
  String get agendaBookingCancelledByCoach =>
      'Reserva cancelada por el entrenador.';

  @override
  String get agendaAttendanceMarkAbsent => 'MARCAR AUSENTE';

  @override
  String get agendaAttendanceUndoAbsent => 'DESHACER AUSENTE';

  @override
  String get agendaAttendanceDefaultHint =>
      'Si no marcás nada, la sesión cuenta como hecha.';

  @override
  String get agendaAttendanceAbsentHint => 'Marcaste que el alumno faltó.';

  @override
  String get agendaAttendanceAbsentStatus => 'Ausente';

  @override
  String get agendaAttendanceError =>
      'No pudimos guardar la asistencia. Probá de nuevo.';

  @override
  String get agendaBlockedDayTitle => 'Día bloqueado';

  @override
  String agendaBlockedDayBodySingle(String date) {
    return 'El $date está marcado como bloqueado en tus horarios. ¿Querés cargar la sesión igual?';
  }

  @override
  String agendaBlockedDayBodyRecurring(int count) {
    return '$count de las fechas caen en días bloqueados. ¿Continuar igual?';
  }

  @override
  String get agendaBlockedDayConfirm => 'Cargar igual';

  @override
  String get agendaConflictTitle => 'Revisá el horario';

  @override
  String agendaConflictOverlapLine(String name, String start, String end) {
    return 'Se superpone con $name ($start – $end).';
  }

  @override
  String agendaConflictOverlapMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Y $count sesiones más.',
      one: 'Y 1 sesión más.',
    );
    return '$_temp0';
  }

  @override
  String get agendaConflictSomeoneElse => 'otra sesión';

  @override
  String get agendaConflictOutsideAvailability =>
      'Queda fuera de tu disponibilidad publicada.';

  @override
  String agendaConflictSeriesOverlap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sesiones de la serie se superponen con otras ya agendadas.',
      one: '1 sesión de la serie se superpone con otra ya agendada.',
    );
    return '$_temp0';
  }

  @override
  String agendaConflictSeriesOutside(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sesiones de la serie quedan fuera de tu disponibilidad publicada.',
      one: '1 sesión de la serie queda fuera de tu disponibilidad publicada.',
    );
    return '$_temp0';
  }

  @override
  String get agendaConflictQuestion => '¿Querés agendarla igual?';

  @override
  String get agendaSlotFreeLabel => 'Disponible';

  @override
  String get agendaSlotBlockedLabel => 'Bloqueado';

  @override
  String agendaSlotBookedByLabel(String athleteName) {
    return 'Reservado por $athleteName';
  }

  @override
  String get agendaCobrarCta => 'COBRAR';

  @override
  String get agendaCobradoLabel => 'Cobrado';

  @override
  String get agendaCobrarMontoLabel => 'MONTO (ARS)';

  @override
  String get agendaCobrarConceptoLabel => 'CONCEPTO';

  @override
  String get agendaCobrarVenceElLabel => 'VENCE EL (OPCIONAL)';

  @override
  String get agendaCobrarVenceElHint => 'Sin fecha de vencimiento';

  @override
  String get agendaCobrarVenceElQuitar => 'Quitar fecha de vencimiento';

  @override
  String get agendaCobrarConfirmCta => 'CONFIRMAR COBRO';

  @override
  String get agendaCobrarCompletaCampos => 'Completá todos los campos.';

  @override
  String get agendaCobrarMontoInvalido => 'Ingresá un monto válido.';

  @override
  String get agendaCobrarSuccess => 'Turno cobrado.';

  @override
  String get agendaCobrarError =>
      'No pudimos registrar el cobro. Probá de nuevo.';

  @override
  String agendaCobrarConceptoDefault(String date) {
    return 'Sesión $date';
  }

  @override
  String agendaCobrarTarifaReferencia(String amount) {
    return 'Tarifa de referencia: $amount';
  }

  @override
  String get workoutSummaryHeaderCompleted => 'BUEN ENTRENO';

  @override
  String get workoutSummaryHeaderAbandoned => 'SESIÓN INTERRUMPIDA';

  @override
  String get workoutStatDuration => 'DURACIÓN';

  @override
  String get workoutStatVolume => 'VOLUMEN';

  @override
  String get workoutStatDurationMin => 'DURACIÓN MIN';

  @override
  String get workoutStatVolumeKg => 'VOLUMEN KG';

  @override
  String get workoutStatSets => 'SETS';

  @override
  String get workoutStatPrsToday => 'PRs HOY';

  @override
  String get workoutStatPrsTodayStub => '—';

  @override
  String get workoutPrsSectionTitle => 'PRS DE LA SESIÓN';

  @override
  String get workoutPrsPlaceholder => 'Próximamente';

  @override
  String get workoutButtonDone => 'LISTO';

  @override
  String get workoutButtonShare => 'COMPARTIR';

  @override
  String get workoutButtonRetry => 'Reintentar';

  @override
  String get workoutButtonBackToWorkout => 'Volver a Entrenar';

  @override
  String get workoutNotFoundTitle => 'Sesión no encontrada';

  @override
  String get workoutErrorTitle => 'No pudimos cargar tu sesión';

  @override
  String get workoutSnackShareSuccess => '¡Post compartido!';

  @override
  String get workoutSnackShareError =>
      'No pudimos compartir tu post. Intentá de nuevo.';

  @override
  String get workoutPostAutoCompleteText => '¡Terminé mi entreno! 💪';

  @override
  String get workoutWeekCompletedTitle => '¡Semana cumplida! 🔥';

  @override
  String workoutWeekCompletedStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Llevás $count semanas de racha.',
      one: '¡Tu primera semana cumplida!',
    );
    return '$_temp0';
  }

  @override
  String get workoutWeekCompletedAction => 'Ver resumen de la semana';

  @override
  String get wellbeingTrendScreenTitle => 'CÓMO ME SENTÍ';

  @override
  String get wellbeingTrendEmptyState =>
      'Todavía no registraste cómo te sentís. Cuando lo hagas, vas a ver tu propia serie acá.';

  @override
  String get wellbeingTrendNeedsMoreData =>
      'Con un solo registro todavía no hay tendencia que mostrar.';

  @override
  String get wellbeingTrendLoadError =>
      'No pudimos cargar tu registro. Probá de nuevo.';

  @override
  String get wellbeingTrendPainHeading => 'DOLOR O MOLESTIA';

  @override
  String wellbeingTrendPainCount(int painCount, int total) {
    return '$painCount de $total registros con dolor';
  }

  @override
  String wellbeingTrendPainCountPrevious(int painCount, int total) {
    return 'Período anterior: $painCount de $total';
  }

  @override
  String get wellbeingTrendAreasHeading => 'ZONAS REGISTRADAS';

  @override
  String get wellbeingTrendPainMark => 'con dolor';

  @override
  String get insightsTileWellbeingTitle => 'Cómo me sentí';

  @override
  String get insightsTileWellbeingSubtitle =>
      'Tu registro de sensación y dolor en el tiempo';

  @override
  String get wellbeingDailyTitle => '¿CÓMO TE SENTÍS HOY?';

  @override
  String get wellbeingDailyPrompt => 'Anotá cómo amanecés, entrenes o no.';

  @override
  String get wellbeingCheckInTitle => '¿CÓMO TE SENTISTE?';

  @override
  String get wellbeingCheckInFromToday => 'Ya lo contaste hoy en Inicio.';

  @override
  String get wellbeingCheckInUseForSession => 'USAR PARA ESTE ENTRENO';

  @override
  String get wellbeingCheckInOptional => 'Opcional. Podés saltearlo.';

  @override
  String get wellbeingFeelingVeryBad => 'Muy mal';

  @override
  String get wellbeingFeelingBad => 'Mal';

  @override
  String get wellbeingFeelingNeutral => 'Normal';

  @override
  String get wellbeingFeelingGood => 'Bien';

  @override
  String get wellbeingFeelingGreat => 'Muy bien';

  @override
  String get wellbeingPainQuestion => '¿Tuviste dolor o molestia?';

  @override
  String get wellbeingPainYes => 'SÍ';

  @override
  String get wellbeingPainNo => 'NO';

  @override
  String get wellbeingPainAreasQuestion => '¿En qué zona?';

  @override
  String get wellbeingPainAreasHint => 'Podés marcar más de una.';

  @override
  String get wellbeingNoteLabel => 'Nota (opcional)';

  @override
  String get wellbeingNoteHint => 'Algo que quieras recordar de hoy';

  @override
  String get wellbeingMedicalDisclaimer =>
      'Si el dolor persiste, consultá a un profesional de la salud.';

  @override
  String get wellbeingSaveButton => 'GUARDAR';

  @override
  String get wellbeingSkipButton => 'AHORA NO';

  @override
  String get wellbeingSavedLabel => 'REGISTRADO';

  @override
  String get wellbeingEditButton => 'Editar';

  @override
  String get wellbeingSaveError =>
      'No pudimos guardar tu registro. Probá de nuevo.';

  @override
  String get shareWorkoutComposerTitle => 'COMPARTIR ENTRENO';

  @override
  String get shareWorkoutComposerHint => '¿Cómo estuvo tu entreno?';

  @override
  String get shareWorkoutComposerPublish => 'PUBLICAR';

  @override
  String get shareWorkoutComposerAddPhoto => 'AGREGAR FOTO';

  @override
  String get shareWorkoutComposerRemovePhoto => 'Quitar foto';

  @override
  String get shareWorkoutComposerPhotoError =>
      'No pudimos usar esa foto. Probá con otra.';

  @override
  String get shareWorkoutComposerPreviewTitle => 'TU ENTRENO';

  @override
  String get postCardWorkoutDetailShow => 'VER DETALLE';

  @override
  String get postCardWorkoutDetailHide => 'OCULTAR DETALLE';

  @override
  String postCardWorkoutDetailTruncated(int count) {
    return 'Se muestran los primeros $count ejercicios.';
  }

  @override
  String get workoutHistorialHeading => 'HISTORIAL';

  @override
  String get coachSessionHistoryInProgress => 'En curso';

  @override
  String get coachSessionHistoryIncomplete => 'Sin completar';

  @override
  String get coachSessionHistoryEmpty =>
      'Este alumno todavía no registró entrenamientos.';

  @override
  String get workoutHistorialEmptyMessage => 'Todavía no entrenaste.';

  @override
  String get workoutHistorialEmptyCta => 'Empezar entrenamiento';

  @override
  String get workoutHistorialErrorMessage => 'No pudimos cargar tu historial.';

  @override
  String get workoutHistorialErrorRetry => 'Reintentar';

  @override
  String get workoutHistorialCardKgSuffix => ' kg';

  @override
  String get workoutHistorialCardMinSuffix => ' min';

  @override
  String get workoutHistorialShowLess => 'Ver menos';

  @override
  String workoutHistorialShowMore(int n) {
    return 'Ver más ($n)';
  }

  @override
  String get workoutHistorialSeeAll => 'Ver todo';

  @override
  String get workoutHistorialFullTitle => 'HISTORIAL';

  @override
  String get workoutDetailStatDuration => 'DURACIÓN';

  @override
  String get workoutDetailStatSets => 'SETS';

  @override
  String get workoutDetailStatVolume => 'VOLUMEN';

  @override
  String get workoutDetailStatDurationMin => 'DURACIÓN MIN';

  @override
  String get workoutDetailStatVolumeKg => 'VOLUMEN KG';

  @override
  String get workoutDetailStatPrsToday => 'PRS HOY';

  @override
  String get workoutDetailPrBadge => 'PR';

  @override
  String get workoutSelfEditorTitle => 'Nueva rutina';

  @override
  String get workoutSelfEditorEditTitle => 'Editar rutina';

  @override
  String get workoutSelfEditorSubmitLabel => 'CREAR RUTINA';

  @override
  String get workoutSelfEditorUpdateLabel => 'GUARDAR CAMBIOS';

  @override
  String get workoutSelfEditorSuccess => 'Rutina creada';

  @override
  String get workoutSelfEditorUpdateSuccess => 'Rutina actualizada';

  @override
  String get workoutSelfEditorNotFound =>
      'Esta rutina ya no existe. Volvé y actualizá la lista.';

  @override
  String get workoutSelfEditorError => 'No pudimos crear la rutina. Reintentá.';

  @override
  String get workoutDiscardError =>
      'No pudimos descartar la sesión. Probá de nuevo.';

  @override
  String get workoutSelfEditorPermissionDenied =>
      'No tenés permisos para hacer esto. Recargá la app.';

  @override
  String get workoutEditStubToast =>
      'Pronto vas a poder editar el contenido. Por ahora podés archivar y crear de nuevo.';

  @override
  String get workoutSelfEditorCapReached =>
      'Llegaste al máximo de 10 rutinas activas.';

  @override
  String get workoutRoutineUseAsBase => 'Usar como base';

  @override
  String get workoutRoutineCustomizeTitle => 'Personalizar rutina';

  @override
  String get workoutRoutineCustomizeSubmitLabel => 'GUARDAR COMO MÍA';

  @override
  String workoutRoutineCopyName(String name) {
    return '$name (mi versión)';
  }

  @override
  String get workoutTabYours => 'TU ENTRENO';

  @override
  String get workoutTabExplore => 'EXPLORAR';

  @override
  String get workoutExploreEmptyAll => 'No hay rutinas todavía.';

  @override
  String get workoutExploreEmptyLevel => 'No hay rutinas para este nivel.';

  @override
  String templatesFilterEmptyDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'No hay plantillas de $days días',
      one: 'No hay plantillas de 1 día',
    );
    return '$_temp0';
  }

  @override
  String templatesFilterEmptyMinutes(String minutes) {
    return 'No hay plantillas de $minutes min o menos';
  }

  @override
  String get templatesFilterEmptyCombination =>
      'Ninguna plantilla cumple todo lo que elegiste a la vez';

  @override
  String get templatesFilterEmptyGoals =>
      'Ninguna plantilla apunta a los objetivos que elegiste';

  @override
  String get templatesFilterEmptyZones =>
      'Ninguna plantilla trabaja las zonas que elegiste';

  @override
  String get templatesFilterEmptyAction => 'Ver todas';

  @override
  String get templatesFilterBarClear => 'Borrar filtros';

  @override
  String get templatesFiltersCleared => 'Filtros borrados';

  @override
  String get templatesFiltersClearError =>
      'No pudimos borrar los filtros. Probá de nuevo.';

  @override
  String get templatesFiltersUndo => 'DESHACER';

  @override
  String get workoutExploreSearchHint =>
      'Buscar por nombre, músculo o ejercicio';

  @override
  String get workoutExploreSearchClear => 'Borrar búsqueda';

  @override
  String workoutExploreSearchEmpty(String query) {
    return 'No encontramos plantillas para «$query»';
  }

  @override
  String get workoutExploreLoadError => 'Hubo un error cargando las rutinas.';

  @override
  String get workoutMisRutinasSectionTitle => 'MIS RUTINAS';

  @override
  String get workoutMisRutinasCta => 'CREAR RUTINA';

  @override
  String get workoutMisRutinasCtaDisabledTooltip =>
      'Llegaste al máximo de 10 rutinas activas. Archivá una para crear otra.';

  @override
  String get workoutMisRutinasEmptyState =>
      'Todavía no creaste ninguna rutina. Tocá CREAR RUTINA para armar la primera.';

  @override
  String get workoutMisRutinasError => 'No pudimos cargar tus rutinas.';

  @override
  String get workoutMisRutinasErrorRetry => 'Reintentar';

  @override
  String get workoutMisRutinasOverflowEdit => 'EDITAR';

  @override
  String get workoutMisRutinasOverflowArchive => 'ELIMINAR';

  @override
  String get workoutMisRutinasOverflowMarkActive => 'MARCAR COMO ACTIVA';

  @override
  String get workoutMisRutinasOverflowUnmarkActive => 'DESMARCAR COMO ACTIVA';

  @override
  String get workoutMisRutinasActiveChip => 'ACTIVA';

  @override
  String get workoutMisRutinasMarkActiveSuccess =>
      'Marcada como tu rutina activa';

  @override
  String get workoutMisRutinasUnmarkActiveSuccess =>
      'Ya no es tu rutina activa';

  @override
  String get workoutMisRutinasActiveError =>
      'No pudimos cambiar el estado. Reintentá.';

  @override
  String get workoutMisRutinasConfirmTitle => 'Eliminar rutina';

  @override
  String get workoutMisRutinasConfirmBody =>
      'La rutina dejará de aparecer en MIS RUTINAS. Tu historial se conserva.';

  @override
  String get workoutMisRutinasConfirmCancel => 'CANCELAR';

  @override
  String get workoutMisRutinasConfirmConfirm => 'ELIMINAR';

  @override
  String get workoutMisRutinasArchiveSuccess => 'Rutina eliminada';

  @override
  String get workoutMisRutinasArchiveError =>
      'No pudimos eliminar la rutina. Reintentá.';

  @override
  String get workoutRutinasCoachChip => 'DE TU COACH';

  @override
  String get workoutPlantillasTrainerChip => 'ENTRENADOR';

  @override
  String get templateRatingsTitle => 'CALIFICACIONES';

  @override
  String get templateRatingsNoneYet =>
      'Todavía nadie calificó esta rutina. ¡Sé el primero!';

  @override
  String templateRatingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count calificaciones',
      one: '1 calificación',
    );
    return '$_temp0';
  }

  @override
  String get templateRatingsMineEmpty => '¿Qué te pareció?';

  @override
  String get templateRatingsMineLabel => 'Tu calificación';

  @override
  String get templateRatingsRateCta => 'CALIFICAR';

  @override
  String get templateRatingsEditCta => 'EDITAR';

  @override
  String get templateRatingsEmpty => 'Todavía no hay comentarios.';

  @override
  String get templateRatingsError => 'No pudimos cargar los comentarios.';

  @override
  String get templateRatingSheetTitle => 'Calificá esta rutina';

  @override
  String get templateRatingSheetTitleEdit => 'Editá tu calificación';

  @override
  String get templateRatingSheetCommentHint =>
      'Contá cómo te fue con esta rutina (opcional)';

  @override
  String get templateRatingSheetCancel => 'CANCELAR';

  @override
  String get templateRatingSheetSubmit => 'ENVIAR';

  @override
  String get templateRatingSheetSuccess => '¡Gracias por calificar!';

  @override
  String get templateRatingSheetError => 'No pudimos guardar tu calificación.';

  @override
  String get workoutSplitFallback => 'Rutina libre';

  @override
  String get workoutPickerMuscleFilter => 'Músculos';

  @override
  String get workoutPickerEquipmentFilter => 'Equipamiento';

  @override
  String get workoutPickerMuscleSheetTitle => 'Grupo muscular';

  @override
  String get workoutPickerEquipmentSheetTitle => 'Tipo de equipo';

  @override
  String get workoutPickerMuscleAll => 'Todos los músculos';

  @override
  String get workoutPickerEquipmentAll => 'Todo el equipamiento';

  @override
  String get workoutPickerEmptyFiltered => 'Ningún ejercicio coincide';

  @override
  String get workoutPickerEmptyFilteredHint =>
      'Probá quitando un filtro o ajustando la búsqueda.';

  @override
  String workoutPickerAddButton(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ejercicios',
      one: 'ejercicio',
    );
    return 'Agregar $countString $_temp0';
  }

  @override
  String get workoutSelfEditorNameHint => 'Mi rutina';

  @override
  String get workoutPickerSheetClear => 'Limpiar';

  @override
  String get workoutPickerSheetApplyAll => 'APLICAR (TODOS)';

  @override
  String workoutPickerSheetApply(int count) {
    return 'APLICAR ($count)';
  }

  @override
  String get appFcmSnackBarActionLabel => 'Ver';

  @override
  String get profileEditPersonalNameRequired => 'Ingresá un nombre';

  @override
  String get profileEditPersonalNameMaxLength => 'Máximo 50 caracteres';

  @override
  String get profileEditPersonalWeightInvalidNumber =>
      'Ingresá un número válido';

  @override
  String get profileEditPersonalWeightOutOfRange =>
      'Ingresá un peso entre 30 y 300 kg';

  @override
  String get profileEditPersonalHeightOutOfRange =>
      'Ingresá una altura entre 120 y 230 cm';

  @override
  String get eliminarCuentaSheetTitle => 'Eliminar cuenta';

  @override
  String get eliminarCuentaSheetBodyPrefix => 'Esta acción es ';

  @override
  String get eliminarCuentaSheetBodyBold => 'irreversible';

  @override
  String get eliminarCuentaSheetBodySuffix =>
      '. Vamos a eliminar tu cuenta, tu perfil, tu historial de entrenamientos, tus posts y tu foto.';

  @override
  String get eliminarCuentaSheetSubscriptionNote =>
      'Si tenés una suscripción paga, se cancela y no se te vuelve a cobrar. No se devuelve el dinero del período en curso.';

  @override
  String get eliminarCuentaSheetDeleteCta => 'ELIMINAR';

  @override
  String get eliminarCuentaSheetCancelCta => 'CANCELAR';

  @override
  String get eliminarCuentaSheetLoadingLabel => 'Eliminando tu cuenta...';

  @override
  String get eliminarCuentaSheetLoadingSubtitle =>
      'Esto puede tardar unos segundos.';

  @override
  String get eliminarCuentaSheetErrorFallback =>
      'No pudimos eliminar tu cuenta. Probá de nuevo.';

  @override
  String get eliminarCuentaSheetRetryLabel => 'Reintentar';

  @override
  String get dashboardResumenDelDiaTitle => 'RESUMEN DEL DÍA';

  @override
  String get dashboardStatPendientes => 'PENDIENTES';

  @override
  String get dashboardStatCompletadas => 'COMPLETADAS';

  @override
  String get dashboardStatCanceladas => 'CANCELADAS';

  @override
  String get dashboardProximasSesionesSectionLabel => 'PRÓXIMAS SESIONES';

  @override
  String get dashboardAgendaTrailingLabel => 'Agenda';

  @override
  String get dashboardEntrenaronHoySectionLabel => 'ENTRENARON HOY';

  @override
  String get dashboardDejarFeedbackLabel => 'Dejar feedback';

  @override
  String get dashboardActividadRecienteSectionLabel => 'ACTIVIDAD RECIENTE';

  @override
  String get dashboardWeekday1 => 'LUNES';

  @override
  String get dashboardWeekday2 => 'MARTES';

  @override
  String get dashboardWeekday3 => 'MIÉRCOLES';

  @override
  String get dashboardWeekday4 => 'JUEVES';

  @override
  String get dashboardWeekday5 => 'VIERNES';

  @override
  String get dashboardWeekday6 => 'SÁBADO';

  @override
  String get dashboardWeekday7 => 'DOMINGO';

  @override
  String get dashboardMonth1 => 'ENERO';

  @override
  String get dashboardMonth2 => 'FEBRERO';

  @override
  String get dashboardMonth3 => 'MARZO';

  @override
  String get dashboardMonth4 => 'ABRIL';

  @override
  String get dashboardMonth5 => 'MAYO';

  @override
  String get dashboardMonth6 => 'JUNIO';

  @override
  String get dashboardMonth7 => 'JULIO';

  @override
  String get dashboardMonth8 => 'AGOSTO';

  @override
  String get dashboardMonth9 => 'SEPTIEMBRE';

  @override
  String get dashboardMonth10 => 'OCTUBRE';

  @override
  String get dashboardMonth11 => 'NOVIEMBRE';

  @override
  String get dashboardMonth12 => 'DICIEMBRE';

  @override
  String get dashboardDateToday => 'Hoy';

  @override
  String get dashboardDateTomorrow => 'Mañana';

  @override
  String get dashboardRechazarLabel => 'RECHAZAR';

  @override
  String get dashboardAceptarLabel => 'ACEPTAR';

  @override
  String get dashboardPagosPorCobrarTitle => 'PAGOS POR COBRAR';

  @override
  String get dashboardCobroTrailingLabel => '+ Cobro';

  @override
  String get dashboardAsignarRutinaLabel => '+ ASIGNAR RUTINA';

  @override
  String get dashboardCobroSueltoTitle => 'COBRO SUELTO';

  @override
  String get dashboardAlumnoLabel => 'ALUMNO';

  @override
  String get dashboardMontoArsLabel => 'MONTO (ARS)';

  @override
  String get dashboardConceptoLabel => 'CONCEPTO';

  @override
  String get dashboardAgregarCobroLabel => 'AGREGAR COBRO';

  @override
  String get dashboardMontoHint => 'Ej: 5000';

  @override
  String get dashboardConceptoHint => 'Ej: Clase de verano';

  @override
  String get dashboardVenceElLabel => 'VENCE EL (OPCIONAL)';

  @override
  String get dashboardVenceElHint => 'Sin fecha de vencimiento';

  @override
  String get dashboardVenceElQuitar => 'Quitar fecha de vencimiento';

  @override
  String get dashboardSeleccionaAlumnoHint => 'Seleccioná un alumno';

  @override
  String get dashboardSinAlumnosActivos => 'No tenés alumnos activos.';

  @override
  String get dashboardMarcarCobradoTitle => '¿Marcar como cobrado?';

  @override
  String get dashboardCancelarLabel => 'Cancelar';

  @override
  String get dashboardCobradoLabel => 'Cobrado';

  @override
  String get dashboardCobroRegistrado => 'Cobro registrado.';

  @override
  String get dashboardCobroError =>
      'Error al registrar el cobro. Intentá de nuevo.';

  @override
  String get dashboardCobroSueltoAgregado => 'Cobro suelto agregado.';

  @override
  String get dashboardCompletaCampos => 'Completá todos los campos.';

  @override
  String get dashboardMontoInvalido => 'Ingresá un monto válido.';

  @override
  String get dashboardGuardarError => 'Error al guardar. Intentá de nuevo.';

  @override
  String get dashboardCadenceMensual => 'Mensual';

  @override
  String get dashboardCadenceSemanal => 'Semanal';

  @override
  String get dashboardCadencePorSesion => 'Por sesión';

  @override
  String get dashboardCadenceSuelto => 'Suelto';

  @override
  String get dashboardAlumnoFallback => 'Alumno';

  @override
  String get dashboardProximamente => 'Próximamente.';

  @override
  String get dashboardIniciaSesion =>
      'Iniciá sesión para ver tus próximos turnos.';

  @override
  String get dashboardCargando => 'Cargando…';

  @override
  String get dashboardErrorTurnos => 'No pudimos cargar tus próximos turnos.';

  @override
  String get dashboardErrorResumen => 'No pudimos cargar el resumen del día.';

  @override
  String get dashboardSinTurnosProximos =>
      'No tenés turnos próximos confirmados.';

  @override
  String get dashboardNadieEntreno => 'Nadie entrenó hoy todavía.';

  @override
  String get athleteDetailSeguimientoEmpty =>
      'Todavía no dejaste seguimiento de este alumno.';

  @override
  String get athleteDetailSeguimientoLoadError =>
      'No pudimos cargar el seguimiento.';

  @override
  String get dashboardFeedbackSheetTitle => 'Dejar feedback';

  @override
  String get dashboardFeedbackPickAthlete =>
      '¿A quién le querés dejar feedback?';

  @override
  String get dashboardFeedbackComposerHint =>
      'Escribí tu devolución del entrenamiento…';

  @override
  String get dashboardFeedbackSave => 'Guardar';

  @override
  String get dashboardFeedbackSaved => 'Feedback guardado';

  @override
  String get dashboardFeedbackSaveError =>
      'No pudimos guardar el feedback. Probá de nuevo.';

  @override
  String get dashboardErrorActividad =>
      'No pudimos cargar la actividad de hoy.';

  @override
  String get dashboardSinActividadReciente =>
      'Sin actividad en los últimos días.';

  @override
  String get dashboardSinCobros => 'Sin cobros pendientes.';

  @override
  String get dashboardErrorCobros => 'No pudimos cargar los cobros.';

  @override
  String get dashboardHolaSinNombre => 'HOLA';

  @override
  String get a11yDashboardAvatarButton => 'Editar tu perfil profesional';

  @override
  String get dashboardSolicitudesPendientesEmpty =>
      'No tenés solicitudes pendientes.';

  @override
  String dashboardSolicitudesPendientesTitle(int count) {
    return 'SOLICITUDES PENDIENTES ($count)';
  }

  @override
  String dashboardHolaConNombre(String name) {
    return 'HOLA, $name';
  }

  @override
  String get reviewSnackBarSuccess => '¡Gracias por tu reseña!';

  @override
  String get plantillasRetryLabel => 'Reintentar';

  @override
  String get profileSetupSaveError =>
      'No pudimos guardar tu perfil. Probá de nuevo.';

  @override
  String get profileSetupCancelDialogTitle =>
      '¿Cancelar la creación de tu cuenta?';

  @override
  String get profileSetupCancelDialogBody =>
      'Vamos a borrar tu cuenta. Esta acción no se puede deshacer.';

  @override
  String get profileSetupCancelAccountError =>
      'No pudimos cancelar la cuenta. Probá de nuevo.';

  @override
  String get verifyMailWrongEmailAction => 'Me equivoqué de mail';

  @override
  String get verifyMailWrongEmailDialogTitle => '¿Te equivocaste de mail?';

  @override
  String get verifyMailWrongEmailDialogBody =>
      'Vamos a borrar esta cuenta para que puedas registrarte de nuevo con el mail correcto. Vas a poder usar el mismo nombre.';

  @override
  String get verifyMailWrongEmailDialogConfirm => 'Borrar cuenta';

  @override
  String get verifyMailWrongEmailDialogBack => 'Volver';

  @override
  String get verifyMailWrongEmailError =>
      'No pudimos borrar la cuenta. Probá de nuevo.';

  @override
  String get profileSetupGymSelectError =>
      'No pudimos cargar ese gimnasio. Probá de nuevo o elegí «OTRO GYM / SIN GYM».';

  @override
  String get reAuthPasswordLabel => 'Contraseña';

  @override
  String get profileGymSearchHint => 'Buscar gym';

  @override
  String get profileEditTrainerTitleEdit => 'Editá tu perfil profesional';

  @override
  String get profileEditTrainerTitleOnboarding =>
      'Completá tu perfil profesional';

  @override
  String get profileEditTrainerSaveSuccess => 'Perfil actualizado.';

  @override
  String get profileEditTrainerSaveError =>
      'No pudimos guardar. Probá de nuevo.';

  @override
  String get profileEditTrainerValidationSpecialty => 'Elegí una especialidad.';

  @override
  String get profileEditTrainerValidationLocation =>
      'Agregá al menos una ubicación o activá clases virtuales.';

  @override
  String get trainerLocationConsentSheetTitle => 'PUBLICAR TU UBICACIÓN';

  @override
  String get trainerLocationConsentSheetBody =>
      'Los atletas van a poder ver dónde entrenás y a qué distancia les queda. Podés apagar esto cuando quieras desde tu perfil profesional.';

  @override
  String get trainerLocationConsentSheetAccept => 'ACEPTAR';

  @override
  String get trainerLocationConsentSheetRevoke => 'APAGAR LA PUBLICACIÓN';

  @override
  String get profileEditTrainerConsentConfirmTitle =>
      '¿Publicar esta ubicación?';

  @override
  String get profileEditTrainerConsentConfirmBody =>
      'Al guardar, esta ubicación va a ser visible para los atletas, con su punto en el mapa y la distancia hasta ellos. Podés apagarla cuando quieras.';

  @override
  String get profileEditTrainerConsentConfirmAccept => 'PUBLICAR';

  @override
  String get profileEditTrainerConsentConfirmCancel => 'CANCELAR';

  @override
  String get profileEditTrainerPublished => 'Visible para los atletas';

  @override
  String get profileEditTrainerNotPublished => 'No publicada';

  @override
  String get legacyPrivacyNoticeTitle =>
      'Actualizamos la Política de Privacidad';

  @override
  String get legacyPrivacyNoticeBody =>
      'Aclaramos cómo tratamos tu ubicación. No cambió nada de lo que recolectamos de vos.';

  @override
  String get legacyPrivacyNoticeAction => 'LEER LA POLÍTICA';

  @override
  String get legacyPrivacyNoticeDismiss => 'Cerrar';

  @override
  String get athleteDetailPlansSection => 'PLANES ASIGNADOS';

  @override
  String get athleteDetailProfileLoadError => 'No pudimos cargar este perfil.';

  @override
  String get athleteDetailPlanDeleteTitle => 'Eliminar plan';

  @override
  String get athleteDetailPlanDeleteCancel => 'Cancelar';

  @override
  String get athleteDetailPlanDeleteConfirm => 'Eliminar';

  @override
  String get athleteDetailPlanDeleteSuccess => 'Plan eliminado.';

  @override
  String get athleteDetailMessageCta => 'MENSAJE';

  @override
  String get newSessionSheetTitle => 'NUEVA SESIÓN';

  @override
  String get newSessionSheetAlumnoLabel => 'ALUMNO';

  @override
  String get newSessionSheetFechaLabel => 'FECHA';

  @override
  String get newSessionSheetHoraLabel => 'HORA DE INICIO';

  @override
  String get newSessionSheetDuracionLabel => 'DURACIÓN (MIN)';

  @override
  String get newSessionSheetNotaLabel => 'NOTA PREVIA (OPCIONAL)';

  @override
  String get newSessionSheetSubmitSingle => 'REGISTRAR SESIÓN';

  @override
  String get newSessionSheetSubmitRecurring => 'REGISTRAR SERIE';

  @override
  String get newSessionSheetDurationError =>
      'Ingresá una duración válida (5–480 min).';

  @override
  String get newSessionSheetNoActiveAthletes => 'No tenés alumnos activos.';

  @override
  String get athleteCoachViewTrainerFallbackName => 'tu Personal Trainer';

  @override
  String get athleteCoachViewLinkError => 'No pudimos cargar tu vínculo.';

  @override
  String get checkInHeader => '¿ESTÁS EN EL GYM HOY?';

  @override
  String get checkInNeutralSubtext => 'Confirma tu entrenamiento de hoy';

  @override
  String get checkInNoButton => 'NO';

  @override
  String get checkInSiButton => 'SÍ, ENTRÉ';

  @override
  String checkInGymSubtext(String gymName) {
    return '$gymName · ¡Detectamos que podés estar entrenando!';
  }

  @override
  String get checkInError =>
      'No pudimos registrar tu check-in. Probá de nuevo.';

  @override
  String get profileCuentaTitle => 'CUENTA';

  @override
  String get profileCuentaSolicitudesTitle => 'Solicitudes de seguidores';

  @override
  String profileCuentaSolicitudesSubtitle(int count) {
    return '$count nuevas';
  }

  @override
  String get profileCuentaDatosPersonalesTitle => 'Datos personales';

  @override
  String get profileCuentaDatosPersonalesSubtitle => 'Editá tu info';

  @override
  String get profileCuentaGimnasioTitle => 'Gimnasio';

  @override
  String get profileCuentaNoGym => 'Sin gym';

  @override
  String get profileCuentaMisRutinasTitle => 'Mis rutinas';

  @override
  String profileCuentaRutinasSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count activas',
      one: '1 activa',
    );
    return '$_temp0';
  }

  @override
  String get chatListTitle => 'MENSAJES';

  @override
  String get chatListDeletedUser => 'Usuario eliminado';

  @override
  String get chatListStartConversation => 'Iniciá la conversación';

  @override
  String get chatListEmptyTitle => 'Sin mensajes todavía';

  @override
  String get chatListEmptyBody =>
      'Le podés escribir a tu PF y a quienes seguís, y a cualquier perfil público desde su perfil. Cuando sigas a alguien, lo vas a ver acá.';

  @override
  String get chatListError => 'No pudimos cargar tus mensajes.';

  @override
  String get chatListRetryLabel => 'Reintentar';

  @override
  String get chatContactsSectionTitle => 'Escribile a…';

  @override
  String get chatContactReasonCoach => 'Tu PF';

  @override
  String get chatContactReasonAthlete => 'Tu alumno';

  @override
  String get chatContactReasonFollowing => 'Lo seguís';

  @override
  String get chatContactsError =>
      'No pudimos cargar a quién le podés escribir.';

  @override
  String get chatContactOpenError =>
      'No pudimos abrir el chat. Probá de nuevo.';

  @override
  String get chatActionArchive => 'Archivar';

  @override
  String get chatActionUnarchive => 'Desarchivar';

  @override
  String get chatActionDelete => 'Eliminar chat';

  @override
  String get chatActionUndo => 'Deshacer';

  @override
  String get chatArchivedToast => 'Chat archivado';

  @override
  String get chatUnarchivedToast => 'Chat desarchivado';

  @override
  String get chatDeletedToast => 'Chat eliminado';

  @override
  String get chatActionError =>
      'No pudimos actualizar el chat. Probá de nuevo.';

  @override
  String get chatDeleteConfirmTitle => '¿Eliminar el chat?';

  @override
  String get chatDeleteConfirmBody =>
      'Se borra el historial sólo para vos: la otra persona lo sigue viendo. Si te vuelve a escribir, el chat reaparece desde ese mensaje.';

  @override
  String get chatActionViewProfile => 'Ver perfil';

  @override
  String chatHeaderProfileA11y(String name) {
    return 'Ver el perfil de $name';
  }

  @override
  String get chatMoreActionsA11y => 'Opciones del chat';

  @override
  String chatArchivedSectionTitle(int count) {
    return 'Archivados · $count';
  }

  @override
  String get chatRelativeJustNow => 'recién';

  @override
  String chatRelativeMinutes(int minutes) {
    return 'hace ${minutes}m';
  }

  @override
  String chatRelativeHours(int hours) {
    return 'hace ${hours}h';
  }

  @override
  String chatRelativeDays(int days) {
    return 'hace ${days}d';
  }

  @override
  String get chatScreenTitleFallback => 'Usuario';

  @override
  String get chatScreenLoadError => 'No pudimos cargar los mensajes.';

  @override
  String get chatScreenComposerHint => 'Escribí un mensaje…';

  @override
  String get chatScreenSendLabel => 'Enviar';

  @override
  String get chatScreenSendError =>
      'No pudimos enviar el mensaje. Probá de nuevo.';

  @override
  String get performanceLogTitle => 'Cargar evaluación';

  @override
  String get performanceLogCancel => 'Cancelar';

  @override
  String get performanceLogSaveCta => 'GUARDAR EVALUACIÓN';

  @override
  String get performanceLogNoSession =>
      'No hay sesión activa. No se puede guardar.';

  @override
  String get performanceLogSaveSuccess => 'Evaluación guardada';

  @override
  String get performanceLogSaveError =>
      'No pudimos guardar la evaluación. Probá de nuevo.';

  @override
  String get performanceLogNotesHint => 'Observaciones del entrenador…';

  @override
  String get performanceLogSectionJumps => 'SALTOS (cm)';

  @override
  String get performanceLogSectionSpeed => 'VELOCIDAD (seg)';

  @override
  String get performanceLogSectionStrength => 'FUERZA 1RM (kg)';

  @override
  String get performanceLogSectionEndurance => 'RESISTENCIA / OTROS';

  @override
  String get performanceLogSectionNotes => 'NOTAS';

  @override
  String get performanceLogFieldCmj => 'CMJ';

  @override
  String get performanceLogFieldSquatJump => 'Squat Jump';

  @override
  String get performanceLogFieldAbalakov => 'Abalakov';

  @override
  String get performanceLogFieldBroadJump => 'Salto largo';

  @override
  String get performanceLogFieldSprint10 => 'Sprint 10m';

  @override
  String get performanceLogFieldSprint20 => '20m';

  @override
  String get performanceLogFieldSprint30 => '30m';

  @override
  String get performanceLogFieldSprint40 => '40m';

  @override
  String get performanceLogFieldSquat1rm => 'Sentadilla';

  @override
  String get performanceLogFieldBenchPress => 'Press banca';

  @override
  String get performanceLogFieldDeadlift => 'Peso muerto';

  @override
  String get performanceLogFieldOverheadPress => 'Press militar';

  @override
  String get performanceLogFieldPullUp => 'Dominada lastrada';

  @override
  String get performanceLogFieldVo2max => 'VO2máx';

  @override
  String get performanceLogFieldCourseNavette => 'Course Navette (nivel)';

  @override
  String get performanceLogFieldCooper => 'Cooper';

  @override
  String get performanceLogFieldSitAndReach => 'Flexibilidad sit-and-reach';

  @override
  String get performanceChartSectionLabel => 'PROGRESO';

  @override
  String get performanceChartEmptyHint =>
      'Cargá otra evaluación para ver el progreso.';

  @override
  String performanceChartSpanDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días',
      one: 'día',
    );
    return '($count $_temp0)';
  }

  @override
  String performanceChartSpanWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'semanas',
      one: 'semana',
    );
    return '($count $_temp0)';
  }

  @override
  String get performanceChartMetricCmj => 'CMJ';

  @override
  String get performanceChartMetricSquatJump => 'Squat Jump';

  @override
  String get performanceChartMetricAbalakov => 'Abalakov';

  @override
  String get performanceChartMetricBroadJump => 'Salto largo';

  @override
  String get performanceChartMetricSprint10 => 'Sprint 10m';

  @override
  String get performanceChartMetricSprint20 => 'Sprint 20m';

  @override
  String get performanceChartMetricSprint30 => 'Sprint 30m';

  @override
  String get performanceChartMetricSprint40 => 'Sprint 40m';

  @override
  String get performanceChartMetricSquat1rm => 'Sentadilla 1RM';

  @override
  String get performanceChartMetricBench1rm => 'Banca 1RM';

  @override
  String get performanceChartMetricDeadlift1rm => 'Peso muerto 1RM';

  @override
  String get performanceChartMetricOverheadPress1rm => 'Press militar 1RM';

  @override
  String get performanceChartMetricPullUp1rm => 'Dominada 1RM';

  @override
  String get performanceChartMetricVo2max => 'VO2máx';

  @override
  String get performanceChartMetricCourseNavette => 'Course Navette';

  @override
  String get performanceChartMetricCooper => 'Cooper';

  @override
  String get performanceChartMetricSitAndReach => 'Flexibilidad';

  @override
  String routineEditorSetsMissingReps(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sets sin reps',
      one: '1 set sin reps',
    );
    return '$_temp0';
  }

  @override
  String get routineEditorEmptyDayTitle => 'DÍA VACÍO';

  @override
  String get routineEditorEmptyDayBody =>
      'Agregá el primer ejercicio y ya queda listo para entrenar.';

  @override
  String routineEditorDayTabA11y(int n, String estado) {
    return 'Día $n$estado';
  }

  @override
  String get routineEditorPlanSheetTitle => 'DATOS DEL PLAN';

  @override
  String get routineEditorPlanSheetA11y => 'Datos del plan';

  @override
  String get routineEditorSubtitleSelfPrivate => 'Tu rutina · solo la ves vos';

  @override
  String get routineEditorSubtitleSelfShared =>
      'Tu rutina · compartida en tu perfil';

  @override
  String get routineEditorSubtitleCustomizing => 'Copia tuya';

  @override
  String get routineEditorSubtitleAssigned => 'Plan asignado';

  @override
  String get routineEditorSubtitleTemplate => 'Plantilla reusable';

  @override
  String routineEditorSubtitleWeeks(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n semanas',
      one: '1 semana',
    );
    return '$_temp0';
  }

  @override
  String routineEditorDayName(int n) {
    return 'Día $n';
  }

  @override
  String get routineEditorAddExercise => 'Agregar ejercicio';

  @override
  String get routineEditorLevelLabel => 'NIVEL';

  @override
  String get routineEditorWeeksLabel => 'SEMANAS';

  @override
  String get routineEditorDaysLabel => 'DÍAS DEL PLAN';

  @override
  String get routineEditorAddWeek => 'Semana';

  @override
  String get routineEditorRemoveLastWeek => 'Quitar última';

  @override
  String get routineEditorDuplicateWeek => 'Duplicar semana';

  @override
  String routineEditorWeekShort(int n) {
    return 'Sem $n';
  }

  @override
  String routineEditorInvalidWeekHint(int week, int day) {
    return 'Sets incompletos en Sem $week · Día $day';
  }

  @override
  String get routineEditorDuplicateWeekTitle => 'Duplicar semana';

  @override
  String routineEditorDuplicateWeekBody(int sourceWeek, int targetWeek) {
    return 'Se copiará la Semana $sourceWeek en la Semana $targetWeek.';
  }

  @override
  String get routineEditorDialogCancel => 'Cancelar';

  @override
  String get routineEditorDialogConfirm => 'Confirmar';

  @override
  String get routineEditorCopyPrescriptionTitle => '¿Copiar sets?';

  @override
  String routineEditorCopyPrescriptionBody(String sourceExercise) {
    return 'Se van a reemplazar los sets de este ejercicio por los de «$sourceExercise».';
  }

  @override
  String get routineEditorSlotMenuCopyPrevious => 'Copiar sets del anterior';

  @override
  String get routineEditorSlotMenuReplace => 'Cambiar ejercicio';

  @override
  String get routineEditorSlotMenuMoveUp => 'Subir';

  @override
  String get routineEditorSlotMenuMoveDown => 'Bajar';

  @override
  String get routineEditorSlotMenuRemove => 'Eliminar';

  @override
  String routineEditorSupersetHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'EJERCICIOS',
      one: 'EJERCICIO',
    );
    return 'SUPERSERIE · $count $_temp0';
  }

  @override
  String get routineEditorSlotMenuHint =>
      'El ⋮ de cada ejercicio tiene cambiar, copiar sets y mover.';

  @override
  String get routineEditorRestLabel => 'Descanso';

  @override
  String get routineEditorAddSet => '+ Agregar set';

  @override
  String get routineEditorFillKgA11y =>
      'Replicar el peso del primer set en todos';

  @override
  String get routineEditorFillKgApplied => 'Peso replicado en todos los sets.';

  @override
  String get routineEditorFillKgEmpty =>
      'Cargá el peso del primer set para poder replicarlo.';

  @override
  String get routineEditorFillKgUndo => 'Deshacer';

  @override
  String get routineEditorFillColumnLabel => 'A TODAS';

  @override
  String get routineEditorFillColumnA11y =>
      'Replicar este valor en toda la columna';

  @override
  String get routineEditorNextCellLabel => 'SIG.';

  @override
  String get routineEditorNextCellA11y => 'Ir a la celda siguiente';

  @override
  String routineEditorAccessoryContext(
      String ejercicio, int set, String campo) {
    return '$ejercicio · set $set · $campo';
  }

  @override
  String get routineEditorFieldKg => 'kg';

  @override
  String get routineEditorFieldReps => 'reps';

  @override
  String routineEditorRepsStepIncreaseA11y(String amount) {
    return 'Sumar $amount repeticiones';
  }

  @override
  String routineEditorRepsStepDecreaseA11y(String amount) {
    return 'Restar $amount repeticiones';
  }

  @override
  String get routineEditorFillColumnEmpty =>
      'Cargá el peso de este set para poder replicarlo.';

  @override
  String routineEditorKgStepIncreaseA11y(String amount) {
    return 'Sumar $amount kilos al peso';
  }

  @override
  String routineEditorKgStepDecreaseA11y(String amount) {
    return 'Restar $amount kilos al peso';
  }

  @override
  String get routineEditorMeasureReps => 'Reps';

  @override
  String get routineEditorMeasureTime => 'Tiempo';

  @override
  String get routineEditorSetTypeNormal => 'Normal';

  @override
  String get routineEditorSetTypeWarmup => 'Entrada en calor (W)';

  @override
  String get routineEditorSetTypeDrop => 'Drop (D)';

  @override
  String get routineEditorSetTypeFailure => 'Al fallo (F)';

  @override
  String get routineEditorNotesLabel => 'Nota para el alumno';

  @override
  String get routineEditorNotesHint => 'Técnica, tempo, RIR…';

  @override
  String get routineEditorSummaryLabel => 'RESUMEN';

  @override
  String get routineEditorSummaryHelp =>
      'Una frase que explique qué es la rutina, para alguien que nunca pisó un gimnasio.';

  @override
  String get routineEditorSummaryHint =>
      'Ej: Empujar, tirar y piernas: cada día trabajás un tipo de movimiento distinto.';

  @override
  String get routineEditorGoalsLabel => 'PARA QUÉ SIRVE';

  @override
  String get routineEditorGoalsHelp =>
      'Opcional. Ayuda a que el alumno encuentre la plantilla cuando busca por objetivo.';

  @override
  String get exerciseNoteFromCoachTag => 'DEL COACH';

  @override
  String routineEditorIncompleteSetsFeedback(String exerciseName) {
    return 'Completá los sets de \"$exerciseName\" antes de guardar.';
  }

  @override
  String get routineDetailNotFound => 'Rutina no encontrada';

  @override
  String get routineDetailNoDaysConfigured =>
      'Esta rutina no tiene días configurados.';

  @override
  String get routineDetailLoadError => 'No pudimos cargar la rutina.';

  @override
  String get routineDetailNoExercisesThisWeek => 'Sin ejercicios esta semana';

  @override
  String get routineDetailNoExercisesThisDay => 'No hay ejercicios en este día';

  @override
  String get routineDetailStatExercises => 'EJERCICIOS';

  @override
  String get routineDetailStatSets => 'SETS';

  @override
  String get routineDetailStatMinutes => 'MINUTOS';

  @override
  String get routineDetailSuperset => 'SUPERSERIE';

  @override
  String routineDetailDayLabel(int day) {
    return 'DÍA $day';
  }

  @override
  String routineDetailWeekLabel(int week) {
    return 'SEM $week';
  }

  @override
  String get routineDetailPlanComplete => 'PLAN COMPLETADO';

  @override
  String get routineDetailCompleted => 'COMPLETADO';

  @override
  String get routineDetailStart => 'EMPEZAR';

  @override
  String get routineDetailRepeat => 'REPETIR';

  @override
  String get routineEditorDeleteScopeTitle =>
      '¿Eliminar solo de esta semana o de todas?';

  @override
  String get routineEditorScopeOnlyThisWeek => 'Solo esta semana';

  @override
  String get routineEditorScopeAllWeeks => 'Todas las semanas';

  @override
  String get routineEditorAddScopeTitle => '¿En qué semanas agregar?';

  @override
  String get routineEditorAddScopeBody =>
      '¿Agregar el ejercicio solo en esta semana o en todas?';

  @override
  String get routineEditorAddOnlyThisWeek => 'Agregar solo en esta semana';

  @override
  String get routineEditorAddAllWeeks => 'Agregar en todas las semanas';

  @override
  String get routineEditorWeekLabel => 'Semana';

  @override
  String get routineEditorLevelSection => 'NIVEL';

  @override
  String get routineEditorWeeksSection => 'SEMANAS';

  @override
  String get routineEditorDaysSection => 'DÍAS DEL PLAN';

  @override
  String get routineEditorNameHint => 'Ej: Fuerza PPL';

  @override
  String get routineEditorSplitHint => 'PPL / Full Body';

  @override
  String routineEditorIncompleteSetsLabel(int weekNumber) {
    return 'Sets incompletos en Sem $weekNumber';
  }

  @override
  String get commonBack => 'Volver';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonLoading => 'Cargando…';

  @override
  String get commonProcessing => 'Procesando…';

  @override
  String get commonWarning => 'Atención';

  @override
  String get chatSendingA11y => 'Enviando…';

  @override
  String get feedMessagesA11y => 'Mensajes';

  @override
  String get feedSearchA11y => 'Buscar';

  @override
  String get feedCreatePostA11y => 'Crear publicación';

  @override
  String get feedFriendRequestsA11y => 'Solicitudes de seguidores';

  @override
  String feedFriendRequestsWithCountA11y(int count) {
    return 'Solicitudes de seguidores, $count pendientes';
  }

  @override
  String get feedPublishingA11y => 'Publicando…';

  @override
  String get searchUsersClearA11y => 'Limpiar búsqueda';

  @override
  String get publicProfileMessageDisabledA11y =>
      'Mensaje (no disponible: esta persona tiene que seguirte)';

  @override
  String get publicProfileStatWorkouts => 'ENTRENOS';

  @override
  String a11yAvatarLabel(String name) {
    return 'Foto de perfil de $name';
  }

  @override
  String get liftRankNone => 'Sin rango';

  @override
  String get liftRankBronze => 'Bronce';

  @override
  String get liftRankSilver => 'Plata';

  @override
  String get liftRankGold => 'Oro';

  @override
  String get liftRankPlatinum => 'Platino';

  @override
  String get liftRankDiamond => 'Diamante';

  @override
  String get liftRankChampion => 'Campeón';

  @override
  String get liftRankTitan => 'Titán';

  @override
  String get liftRankOlympian => 'Olímpico';

  @override
  String liftRankStripTitle(String lift) {
    return 'TU RANGO · $lift';
  }

  @override
  String liftRankStripPosition(int rank, int total) {
    return 'Rango $rank de $total';
  }

  @override
  String get liftRankStripBelowBronze =>
      'Todavía no llegás a Bronce. Seguí sumando kilos.';

  @override
  String get liftRankStripNoLift =>
      'Registrá este levantamiento en un entrenamiento para ver tu rango.';

  @override
  String get liftRankStripNoBodyWeight =>
      'Cargá tu peso corporal para ver tu rango.';

  @override
  String get liftRankStripPending => 'Se calcula con tu próximo entrenamiento.';

  @override
  String a11yRankingRowButtonWithRank(String name, String rank) {
    return 'Ver el perfil de $name, rango $rank';
  }

  @override
  String a11yRankingRowButton(String name) {
    return 'Ver el perfil de $name';
  }

  @override
  String get a11yReactionLike => 'Me gusta';

  @override
  String get a11yReactionFire => 'Fuego';

  @override
  String get a11yReactionClap => 'Aplausos';

  @override
  String a11yReactionCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reacciones',
      one: '1 reacción',
      zero: 'sin reacciones',
    );
    return '$_temp0';
  }

  @override
  String get a11yAvatarLabelGeneric => 'Foto de perfil';

  @override
  String get a11yHomeAvatarButton => 'Ver tu perfil';

  @override
  String homePendingRequestsA11y(int count) {
    return '$count solicitudes pendientes';
  }

  @override
  String get workoutRoutineOptionsA11y => 'Opciones de rutina';

  @override
  String sessionPlayerSetCompleteA11y(int setNumber) {
    return 'Marcar serie $setNumber como completada';
  }

  @override
  String sessionPlayerTechniqueA11y(String exerciseName) {
    return 'Ver técnica de $exerciseName';
  }

  @override
  String get sessionPlayerTimerStartA11y => 'Iniciar temporizador';

  @override
  String get sessionPlayerRemoveSetA11y => 'Eliminar serie';

  @override
  String get routineEditorDeleteDayA11y => 'Eliminar día';

  @override
  String get routineEditorEditDayNameA11y => 'Editar nombre del día';

  @override
  String get routineEditorDayNameLabel => 'NOMBRE DEL DÍA';

  @override
  String get athleteDetailEditPlanA11y => 'Editar plan';

  @override
  String get athleteDetailDeletePlanA11y => 'Eliminar plan';

  @override
  String get coachMapDisabledOnlineA11y => 'Mapa, no disponible en modo Online';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDone => 'Listo';

  @override
  String get publicProfileLoadErrorA11y => 'No pudimos cargar este perfil.';

  @override
  String get authGenericErrorFallback => 'Algo salió mal. Probá de nuevo.';

  @override
  String get agendaNoUpcomingSessions => 'Tu PF todavía no te agendó sesiones.';

  @override
  String get agendaSaveError => 'No pudimos guardar. Probá de nuevo.';

  @override
  String get agendaSaveSuccess => 'Horario guardado.';

  @override
  String get coachHubSectionLoadError => 'No pudimos cargar esta sección.';

  @override
  String get coachHubSignOutError =>
      'No pudimos cerrar sesión. Probá de nuevo.';

  @override
  String get coachHubOnboardingAgeTitle => '¿CUÁNDO NACISTE?';

  @override
  String get coachHubOnboardingAgeBody =>
      'Necesitamos tu fecha de nacimiento para activar tu cuenta de entrenador. Tenés que tener 13 años o más.';

  @override
  String get coachHubOnboardingAgeLabel => 'FECHA DE NACIMIENTO';

  @override
  String get coachHubOnboardingIdentityTitle => '¿CÓMO TE LLAMÁS?';

  @override
  String get coachHubOnboardingIdentityBody =>
      'Este es el nombre con el que te van a ver tus alumnos.';

  @override
  String get coachHubOnboardingFirstNameLabel => 'NOMBRE';

  @override
  String get coachHubOnboardingLastNameLabel => 'APELLIDO';

  @override
  String get coachHubOnboardingFirstNameRequired => 'Ingresá tu nombre';

  @override
  String get coachHubOnboardingLastNameRequired => 'Ingresá tu apellido';

  @override
  String get coachHubOnboardingPfTitle => 'TU PERFIL PROFESIONAL';

  @override
  String get coachHubOnboardingPfBody =>
      'Esto es lo que ven los alumnos cuando te buscan. Lo podés cambiar cuando quieras.';

  @override
  String get coachHubOnboardingPfBioLabel => 'BIO';

  @override
  String get coachHubOnboardingPfSpecialtyLabel => 'ESPECIALIDAD';

  @override
  String get coachHubOnboardingPfRateLabel => 'TARIFA MENSUAL (ARS)';

  @override
  String get coachHubOnboardingPfModalityLabel => 'MODALIDAD';

  @override
  String get coachHubOnboardingPfOnlineSwitch => 'Doy clases online';

  @override
  String get coachHubOnboardingPfModalityRequired =>
      'Activá las clases online o sumá un lugar de entrenamiento.';

  @override
  String get coachHubOnboardingPfLocationsLabel => 'LUGARES DE ENTRENAMIENTO';

  @override
  String get coachHubOnboardingPfLocationSearchLabel => 'BUSCAR UN LUGAR';

  @override
  String get coachHubOnboardingPfLocationSearchHint =>
      'Dirección o nombre del lugar';

  @override
  String get coachHubOnboardingPfLocationSearchButton => 'Buscar';

  @override
  String get coachHubOnboardingPfLocationEmpty =>
      'No encontramos ese lugar. Probá con la dirección completa.';

  @override
  String get coachHubOnboardingPfLocationDuplicate =>
      'Ese lugar ya está en tu lista.';

  @override
  String get coachHubOnboardingPfLocationNetworkError =>
      'No pudimos buscar el lugar. Revisá tu conexión y probá de nuevo.';

  @override
  String get coachHubOnboardingPfLocationConfigError =>
      'La búsqueda de lugares no está disponible en este momento. Si das clases online, podés finalizar igual.';

  @override
  String get coachHubOnboardingPfLocationRetry => 'Reintentar';

  @override
  String get coachHubOnboardingPfLocationFound =>
      'Encontramos el lugar. Ponele el nombre con el que lo van a ver tus alumnos.';

  @override
  String get coachHubOnboardingPfLocationLabelLabel => 'NOMBRE DEL LUGAR';

  @override
  String get coachHubOnboardingPfLocationLabelHint =>
      'Ej: Mi estudio, Parque Sarmiento';

  @override
  String get coachHubOnboardingPfLocationAddButton => 'Agregar lugar';

  @override
  String get coachHubOnboardingPfLocationRemove => 'Quitar lugar';

  @override
  String get coachHubOnboardingPfLocationGymFallback => 'Gimnasio';

  @override
  String get coachHubOnboardingPfFinish => 'Finalizar';

  @override
  String get coachHubOnboardingContinue => 'Continuar';

  @override
  String get coachHubOnboardingSaveError =>
      'No pudimos guardar tus datos. Probá de nuevo.';

  @override
  String get coachHubNotAllowedTitle => 'SOLO PARA ENTRENADORES';

  @override
  String get coachHubNotAllowedBody =>
      'El Coach Hub es solo para entrenadores. Descargá la app de TREINO desde App Store o Play Store e iniciá sesión ahí.';

  @override
  String get coachHubNotAllowedContactPrompt =>
      '¿Querés ser entrenador? Escribile al equipo.';

  @override
  String get coachHubNotAllowedContactCta => 'Contactar al equipo';

  @override
  String get coachHubNotAllowedMailSubject => 'Quiero ser entrenador en TREINO';

  @override
  String get coachHubNotAllowedContactFallback =>
      'No pudimos abrir tu correo. Escribinos a la dirección de arriba.';

  @override
  String get coachHubLoginPrompt =>
      'Ingresá con la cuenta que ya usás en la app móvil.';

  @override
  String get coachHubLoginEmailLabel => 'Email';

  @override
  String get coachHubLoginEmailRequired => 'Ingresá tu email';

  @override
  String get coachHubLoginEmailInvalid => 'Email inválido';

  @override
  String get coachHubLoginPasswordLabel => 'Contraseña';

  @override
  String get coachHubLoginPasswordRequired => 'Ingresá tu contraseña';

  @override
  String get coachHubLoginSubmit => 'INGRESAR';

  @override
  String get coachHubLoginFooter =>
      '¿No tenés cuenta? Creala desde la app móvil TREINO.';

  @override
  String get coachHubLoginGenericError =>
      'No pudimos ingresar. Probá de nuevo.';

  @override
  String get coachHubActionCancel => 'Cancelar';

  @override
  String get coachHubActionConfirm => 'Confirmar';

  @override
  String get coachHubActionPause => 'Pausar';

  @override
  String get coachHubActionResume => 'Reanudar';

  @override
  String get coachHubActionTerminate => 'Terminar';

  @override
  String get coachHubActionTerminateLink => 'Terminar vínculo';

  @override
  String get coachHubActionAccept => 'Aceptar';

  @override
  String get coachHubActionReject => 'Rechazar';

  @override
  String get coachHubDashboardImportPlanCta => 'IMPORTAR PLAN DESDE EXCEL';

  @override
  String get coachHubDashboardFilterActivos => 'ACTIVOS';

  @override
  String get coachHubDashboardFilterPausados => 'PAUSADOS';

  @override
  String get coachHubDashboardFilterHistorial => 'HISTORIAL';

  @override
  String get coachHubDashboardActiveHeader => 'TUS ALUMNOS';

  @override
  String get coachHubDashboardPausedHeader => 'EN PAUSA';

  @override
  String get coachHubDashboardHistoryHeader => 'VÍNCULOS PASADOS';

  @override
  String get coachHubDashboardEmptyActive => 'Sin alumnos activos por ahora.';

  @override
  String get coachHubDashboardEmptyPaused => 'No hay alumnos pausados.';

  @override
  String get coachHubDashboardEmptyHistory =>
      'Sin vínculos terminados todavía.';

  @override
  String coachHubDashboardPendingHeader(int count) {
    return 'SOLICITUDES PENDIENTES · $count';
  }

  @override
  String get coachHubDashboardPendingContext => 'Quiere vincularse con vos';

  @override
  String coachHubDashboardLinkedSince(String date) {
    return 'Vinculado desde $date';
  }

  @override
  String coachHubDashboardPausedOn(String date) {
    return 'Pausado el $date';
  }

  @override
  String get coachHubDashboardPausedFallback => 'Pausado';

  @override
  String get coachHubDashboardPauseLinkTitle => 'Pausar vínculo';

  @override
  String get coachHubDashboardPauseLinkBody =>
      'El alumno verá el plan pero no podrá registrar sesiones nuevas hasta que reanudes el vínculo.';

  @override
  String get coachHubDashboardTerminateLinkTitle => 'Terminar vínculo';

  @override
  String get coachHubDashboardTerminateLinkBody =>
      'Esta acción no se puede deshacer. El historial se conserva.';

  @override
  String get coachHubDashboardResumeLinkTitle => 'Reanudar vínculo';

  @override
  String coachHubDashboardResumeLinkBody(String name) {
    return '¿Reanudar el vínculo con $name?';
  }

  @override
  String get coachHubDashboardResumeLinkBodyFallback => '¿Reanudar el vínculo?';

  @override
  String get coachHubDashboardPauseLinkError => 'No pudimos pausar el vínculo.';

  @override
  String get coachHubDashboardTerminateLinkError =>
      'No pudimos terminar el vínculo.';

  @override
  String get coachHubDashboardResumeLinkError =>
      'No pudimos reanudar el vínculo.';

  @override
  String get coachHubDashboardResumePrecondition =>
      'Este vínculo ya no está disponible.';

  @override
  String get coachHubDashboardResumeUnavailable =>
      'Revisá tu conexión y probá de nuevo.';

  @override
  String get coachHubDashboardAcceptSuccess => 'Vínculo aceptado.';

  @override
  String get coachHubDashboardAcceptError => 'No pudimos aceptar el vínculo.';

  @override
  String get coachHubDashboardAcceptPrecondition =>
      'Esta solicitud ya no está disponible.';

  @override
  String get coachHubDashboardAcceptUnavailable =>
      'Revisá tu conexión y probá de nuevo.';

  @override
  String get coachHubDashboardRejectSuccess => 'Solicitud rechazada.';

  @override
  String get coachHubDashboardRejectError =>
      'No pudimos rechazar la solicitud.';

  @override
  String get coachHubDashboardTerminationReasonDeclined =>
      'Rechazado por el PF';

  @override
  String get coachHubDashboardTerminationReasonByAthlete =>
      'Cancelado por el atleta';

  @override
  String get coachHubDashboardTerminationReasonByTrainer =>
      'Terminado por el PF';

  @override
  String get coachHubDashboardTerminationReasonFallback => 'Vínculo terminado';

  @override
  String get coachHubAlumnosTitle => 'ALUMNOS';

  @override
  String coachHubAlumnosSummary(int total, int active) {
    return '$total en total · $active activos';
  }

  @override
  String get coachHubAlumnosSearchHint => 'Buscar por nombre…';

  @override
  String get coachHubAlumnosFilterAll => 'Vigentes';

  @override
  String get coachHubAlumnosFilterActivos => 'Activos';

  @override
  String get coachHubAlumnosFilterConDeuda => 'Con deuda';

  @override
  String get coachHubAlumnosFilterPausados => 'Pausados';

  @override
  String get coachHubAlumnosFilterInactivos => 'Inactivos';

  @override
  String get coachHubAlumnosEmpty => 'Todavía no tenés alumnos vinculados.';

  @override
  String get coachHubAlumnosEmptyFiltered =>
      'Ningún alumno coincide con el filtro.';

  @override
  String get coachHubAlumnosLoadError => 'No se pudieron cargar los alumnos.';

  @override
  String get coachHubAlumnosProfilesLoadError =>
      'No se pudieron cargar los perfiles.';

  @override
  String get coachHubAlumnosColumnStudent => 'ALUMNO';

  @override
  String get coachHubAlumnosColumnStatus => 'ESTADO';

  @override
  String get coachHubAlumnosColumnLastWorkout => 'ÚLTIMO ENTRENO';

  @override
  String get coachHubAlumnosColumnActions => 'ACCIONES';

  @override
  String get coachHubAlumnosNameFallback => 'Atleta';

  @override
  String get coachHubAlumnosLastWorkoutToday => 'Hoy';

  @override
  String get coachHubAlumnosStatusActive => 'Activo';

  @override
  String get coachHubAlumnosStatusDebt => 'Con deuda';

  @override
  String get coachHubAlumnosStatusBlocked => 'Sin acceso';

  @override
  String get coachHubAlumnosFilterBloqueados => 'Sin acceso';

  @override
  String get coachHubAlumnosBlockedHint =>
      'Superaste el límite de tu plan. Este alumno no cuenta y no podés trabajar con él hasta que regularices.';

  @override
  String get coachHubAlumnosStatusPaused => 'Pausado';

  @override
  String get coachHubAlumnosStatusInactive => 'Inactivo';

  @override
  String get coachHubAlumnosViewTable => 'Tabla';

  @override
  String get coachHubAlumnosViewCards => 'Cards';

  @override
  String coachHubAlumnosDebtAmount(String amount) {
    return 'Debe $amount';
  }

  @override
  String get coachHubAlumnoDetailNotasTitle => 'Notas privadas';

  @override
  String get coachHubAlumnoDetailNotasSubtitle =>
      'Anotá lo que necesites sobre este alumno. Solo vos lo ves.';

  @override
  String get coachHubAlumnoDetailNotasHint =>
      'Ej: Lesión de rodilla derecha, evitar sentadilla profunda…';

  @override
  String get coachHubAlumnoDetailNotasSaveButton => 'GUARDAR';

  @override
  String coachHubAlumnoDetailNotasUpdatedAt(String timestamp) {
    return 'Última edición · $timestamp';
  }

  @override
  String get coachHubAlumnoDetailNotasSaveSuccess => 'Nota guardada.';

  @override
  String get coachHubAlumnoDetailNotasSaveError =>
      'No pudimos guardar la nota. Probá de nuevo.';

  @override
  String get coachHubAlumnoDetailNotasLoadError => 'No pudimos cargar la nota.';

  @override
  String get coachHubAlumnoDetailArchivosTitle => 'Archivos del alumno';

  @override
  String get coachHubAlumnoDetailArchivosSubtitle =>
      'PDFs y fotos que subís sobre este alumno. Elegí cuáles compartís con él.';

  @override
  String get coachHubAlumnoDetailArchivosUploadButton => 'SUBIR ARCHIVO';

  @override
  String get coachHubAlumnoDetailArchivosEmpty =>
      'Todavía no subiste archivos sobre este alumno.';

  @override
  String get coachHubAlumnoDetailArchivosLoadError =>
      'No pudimos cargar los archivos.';

  @override
  String get coachHubAlumnoDetailArchivosUploadSuccess => 'Archivo subido.';

  @override
  String get coachHubAlumnoDetailArchivosUploadError =>
      'No pudimos subir el archivo. Probá de nuevo.';

  @override
  String get coachHubAlumnoDetailArchivosUploadTooLarge =>
      'El archivo supera el máximo de 10 MB.';

  @override
  String get coachHubAlumnoDetailArchivosOpenTooltip => 'Abrir archivo';

  @override
  String get coachHubAlumnoDetailArchivosDeleteTooltip => 'Eliminar';

  @override
  String get coachHubAlumnoDetailArchivosDeleteTitle => '¿Eliminar archivo?';

  @override
  String coachHubAlumnoDetailArchivosDeleteBody(String fileName) {
    return '«$fileName» se va a borrar tanto del Storage como del historial. No se puede deshacer.';
  }

  @override
  String get coachHubAlumnoDetailArchivosDeleteError =>
      'No pudimos eliminar el archivo.';

  @override
  String get coachHubAlumnoDetailArchivosSharedLabel => 'COMPARTIDO';

  @override
  String get coachHubAlumnoDetailArchivosPrivateLabel => 'PRIVADO';

  @override
  String get coachHubAlumnoDetailArchivosShareTooltip =>
      'Compartir con el alumno';

  @override
  String get coachHubAlumnoDetailArchivosUnshareTooltip =>
      'Dejar de compartir con el alumno';

  @override
  String get coachHubAlumnoDetailArchivosShareError =>
      'No pudimos cambiar quién ve el archivo.';

  @override
  String get feedLoadError => 'No pudimos cargar tu feed. Probá de nuevo.';

  @override
  String get createPostLoadError =>
      'No pudimos abrir el editor. Probá de nuevo.';

  @override
  String get insightsLoadError =>
      'No pudimos cargar tus insights. Probá de nuevo.';

  @override
  String get insightsDayStripTodayLabel => 'HOY';

  @override
  String get insightsDayEmptyHint => 'No entrenaste este día.';

  @override
  String get coachDailyHeatmapSectionTitle => 'MÚSCULOS DEL DÍA';

  @override
  String get profileLoadError => 'No pudimos cargar tu perfil. Probá de nuevo.';

  @override
  String get sessionDetailNoSets => 'Esta sesión no tiene sets registrados.';

  @override
  String get sessionFinishedOnWatch =>
      'Terminaste este entrenamiento desde el reloj.';

  @override
  String get sessionLogSetError => 'No pudimos guardar la serie. Reintentá.';

  @override
  String get sessionFinishError =>
      'No pudimos finalizar la sesión. Probá de nuevo.';

  @override
  String get sessionFinishNeedOneSet =>
      'Hacé al menos una serie para poder terminar. Si hoy no vas a entrenar, tocá ABANDONAR.';

  @override
  String get sessionFinishEarlyTitle => '¿TERMINAR IGUAL?';

  @override
  String sessionFinishEarlyMissingHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Te faltan $count series:',
      one: 'Te falta 1 serie:',
    );
    return '$_temp0';
  }

  @override
  String sessionFinishEarlyMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'y $count ejercicios más',
      one: 'y 1 ejercicio más',
    );
    return '$_temp0';
  }

  @override
  String sessionFinishEarlyCounts(int percent) {
    return 'Hiciste el $percent % de la sesión: cuenta como entreno para tu racha y tus rankings.';
  }

  @override
  String sessionFinishEarlyNotCounts(int percent, int minPercent) {
    return 'Hiciste el $percent % de la sesión. Se guarda, pero no cuenta como entreno para tu racha ni tus rankings: hace falta el $minPercent %.';
  }

  @override
  String get sessionFinishEarlyConfirm => 'TERMINAR IGUAL';

  @override
  String get sessionFinishEarlyKeepGoing => 'SEGUIR ENTRENANDO';

  @override
  String get routineEditorMissingName => 'Poné un nombre a la rutina.';

  @override
  String routineEditorMissingExercise(int dayNumber) {
    return 'Agregá al menos un ejercicio al Día $dayNumber.';
  }

  @override
  String get routineEditorMissingReps =>
      'Completá las reps de los sets antes de guardar.';

  @override
  String get routineEditorDuplicateExercise =>
      'Ese ejercicio ya está en el día. Elegí otro.';

  @override
  String get feedPostPublishedSuccess => 'Post publicado.';

  @override
  String get postCardMenuA11y => 'Opciones del post';

  @override
  String get coachHubAlumnosRowActionsA11y => 'Opciones del alumno';

  @override
  String get postCardMenuEdit => 'Editar';

  @override
  String get postCardMenuDelete => 'Eliminar';

  @override
  String get postCardDeleteConfirmTitle => '¿Eliminar este post?';

  @override
  String get postCardDeleteConfirmBody => 'Esta acción no se puede deshacer.';

  @override
  String get postCardDeleteSuccess => 'Post eliminado.';

  @override
  String get postCardDeleteError =>
      'No pudimos eliminar el post. Probá de nuevo.';

  @override
  String get createPostEditTitle => 'EDITAR POST';

  @override
  String get createPostSaveChanges => 'GUARDAR';

  @override
  String get createPostSaveChangesA11y => 'Guardar cambios';

  @override
  String get createPostSavingA11y => 'Guardando…';

  @override
  String get feedPostUpdatedSuccess => 'Cambios guardados.';

  @override
  String get feedRequestSentSuccess => 'Solicitud enviada.';

  @override
  String get feedRequestAcceptedSuccess => 'Solicitud aceptada.';

  @override
  String get feedFriendActionError =>
      'No pudimos completar la acción. Probá de nuevo.';

  @override
  String get profilePersonalSaveSuccess => 'Cambios guardados.';

  @override
  String get profileGymSaveSuccess => 'Gimnasio actualizado.';

  @override
  String get profileGymSaveError =>
      'No pudimos guardar el gimnasio. Probá de nuevo.';

  @override
  String get gymNearbyLocationAffordance =>
      'Activar ubicación para ver gyms cercanos';

  @override
  String get gymNearbyShowMore => 'Ver más';

  @override
  String get gymSearchConfigError =>
      'La búsqueda de gyms no está disponible en esta versión de la app.';

  @override
  String get gymNearbyLoadError => 'No pudimos cargar los gyms cercanos.';

  @override
  String get feedPullToRefreshA11y => 'Deslizá para actualizar';

  @override
  String get logFieldInvalidNumber => 'Ingresá un número válido';

  @override
  String get logFieldOutOfRange => 'El valor está fuera de rango';

  @override
  String get logEmptyRecordWarning =>
      'Completá al menos un dato antes de guardar';

  @override
  String get profileSetupUsernameChecking => 'Verificando disponibilidad…';

  @override
  String get profileSetupUsernameTaken => 'Ese username ya está en uso';

  @override
  String get profileSetupUsernameAvailable => 'Username disponible';

  @override
  String get profileSetupUsernameCheckError =>
      'No pudimos verificar el username. Probá de nuevo.';

  @override
  String get routineEditorDiscardTitle => '¿Descartar cambios?';

  @override
  String get routineEditorDiscardBody =>
      'Si salís ahora vas a perder los cambios sin guardar.';

  @override
  String get routineEditorDiscardConfirm => 'Descartar';

  @override
  String trainerCtaExistingLinkExplanation(String trainerName) {
    return 'Solo podés tener un PF activo. Terminá tu vínculo actual con $trainerName para pedir uno nuevo.';
  }

  @override
  String get coachHubPreviewDiscardTitle => '¿Salir sin guardar el plan?';

  @override
  String get coachHubPreviewDiscardBody =>
      'Vas a perder los ejercicios que mapeaste manualmente.';

  @override
  String get coachHubPreviewDiscardConfirm => 'Salir igual';

  @override
  String get chatAttachMediaLabel => 'Adjuntar';

  @override
  String get chatPickImageLabel => 'Foto';

  @override
  String get chatPickVideoLabel => 'Video';

  @override
  String get chatMediaUploading => 'Subiendo…';

  @override
  String get chatMediaUploadFailed =>
      'No pudimos subir el archivo. Probá de nuevo.';

  @override
  String chatMediaQuotaFull(String maxMb) {
    return 'Llegaste al tope de $maxMb MB en fotos y videos de chat.';
  }

  @override
  String chatMediaFileTooLarge(String fileMb, String maxMb) {
    return 'El archivo pesa $fileMb MB y el máximo es $maxMb MB.';
  }

  @override
  String chatMediaQuotaNotEnough(String fileMb, String remainingMb) {
    return 'El archivo pesa $fileMb MB y te quedan $remainingMb MB de cupo.';
  }

  @override
  String get chatMediaPreviewPhoto => '📷 Foto';

  @override
  String get chatMediaPreviewVideo => '🎥 Video';

  @override
  String get chatMediaViewFullscreen => 'Ver foto';

  @override
  String get chatMediaImageLoadError => 'No pudimos cargar la imagen.';

  @override
  String feedMessagesWithUnreadA11y(int count) {
    return 'Mensajes, $count sin leer';
  }

  @override
  String get chatUnreadA11y => 'Sin leer';

  @override
  String get coachSessionSetLogsTitle => 'SETS';

  @override
  String get coachSessionTapToExpand => 'Ver sets';

  @override
  String get coachSessionSetLogsEmpty =>
      'Esta sesión no tiene sets registrados.';

  @override
  String get coachSessionSetLogsLoadError =>
      'No pudimos cargar los sets. Intentá de nuevo.';

  @override
  String get coachAthleteNoSharePlaceholder =>
      'El alumno no compartió su historial todavía.';

  @override
  String get avatarCropperTitle => 'Recortar foto';

  @override
  String get avatarCropperDone => 'LISTO';

  @override
  String get avatarCropperCancel => 'CANCELAR';

  @override
  String get progressionSectionTitle => 'EVOLUCIÓN POR EJERCICIO';

  @override
  String get progressionMetricPr => 'Peso máximo';

  @override
  String get progressionMetricOneRepMax => '1RM';

  @override
  String get progressionMetricBestSetVolume => 'Mejor serie';

  @override
  String get progressionMetricVolume => 'Volumen';

  @override
  String progressionFrequency(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones en las últimas 8 semanas',
      one: '1 sesión en las últimas 8 semanas',
      zero: 'Sin sesiones en las últimas 8 semanas',
    );
    return '$_temp0';
  }

  @override
  String progressionFrequencyPeriod(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones en este período',
      one: '1 sesión en este período',
      zero: 'Sin sesiones en este período',
    );
    return '$_temp0';
  }

  @override
  String get progressionSinglePointHint =>
      'Necesitás al menos 2 sesiones para ver la evolución.';

  @override
  String get progressionEmptyExercise => 'Sin datos para este ejercicio.';

  @override
  String get progressionEmpty => 'Sin registros de series todavía.';

  @override
  String get progressionPeriodLast30Days => 'Últimos 30 días';

  @override
  String get progressionPeriodThisWeek => 'Esta semana';

  @override
  String get progressionPeriodMonth => 'Este mes';

  @override
  String get muscleDistributionSectionTitle => 'DISTRIBUCIÓN MUSCULAR';

  @override
  String get muscleDistributionCurrentLabel => 'Actual';

  @override
  String get muscleDistributionPreviousLabel => 'Anterior';

  @override
  String get muscleDistributionEmptyState => 'Sin datos para este período.';

  @override
  String get muscleDistributionWorkoutsLabel => 'Entrenos';

  @override
  String get muscleDistributionDurationLabel => 'Duración';

  @override
  String get muscleDistributionVolumeLabel => 'Volumen';

  @override
  String get muscleDistributionSetsLabel => 'Sets';

  @override
  String get personalRecordsSectionTitle => 'RÉCORDS PERSONALES';

  @override
  String get mostFrequentExercisesSectionTitle => 'EJERCICIOS MÁS FRECUENTES';

  @override
  String mostFrequentExercisesSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones',
      one: '1 sesión',
      zero: 'Sin sesiones',
    );
    return '$_temp0';
  }

  @override
  String get mostFrequentExercisesEmpty => 'No hay datos todavía.';

  @override
  String get profileRoutinesAssignedHeader => 'RUTINAS ASIGNADAS POR TU PF';

  @override
  String get profileRoutinesOwnHeader => 'MIS RUTINAS PROPIAS';

  @override
  String get profileRoutinesNoTrainerBody => 'Todavía no tenés un PF asignado.';

  @override
  String get profileRoutinesNoTrainerCta => 'BUSCAR PF';

  @override
  String get profileRoutinesNoOwnBody => 'Todavía no creaste ninguna rutina.';

  @override
  String get profileRoutinesActiveChip => 'ACTIVA';

  @override
  String get profileSectionLegal => 'Legales';

  @override
  String get legalDocumentsTitle => 'Documentos legales';

  @override
  String get legalDocumentsSubtitle => 'Términos, privacidad y más';

  @override
  String get appearanceTitle => 'Apariencia';

  @override
  String get appearanceSystem => 'Sistema';

  @override
  String get appearanceSystemDesc => 'Sigue el tema del dispositivo';

  @override
  String get appearanceLight => 'Claro';

  @override
  String get appearanceDark => 'Oscuro';

  @override
  String get profileSectionAppearance => 'Apariencia';

  @override
  String dashboardGreeting(String name) {
    return 'BUENAS, $name';
  }

  @override
  String get dashboardGreetingPrefix => 'BUENAS, ';

  @override
  String dashboardSummaryLine(int sessions, int paraRevisar, int pagos) {
    return 'Tenés $sessions sesiones hoy, $paraRevisar para revisar, $pagos pagos pendientes';
  }

  @override
  String get dashboardQuickActionNuevoAlumno => 'Nuevo alumno';

  @override
  String get dashboardQuickActionCrearRutina => 'Crear rutina';

  @override
  String dashboardQuickActionMensajes(int count) {
    return 'Mensajes ($count)';
  }

  @override
  String get dashboardQuickActionImportarPlan => 'Importar plan';

  @override
  String get dashboardAlertBannerPlaceholder =>
      'Próximamente: resumen de atención';

  @override
  String get dashboardKpiAlumnosActivos => 'Alumnos activos';

  @override
  String get dashboardKpiIngresoMes => 'Ingreso del mes';

  @override
  String get dashboardKpiAdherencia => 'Adherencia promedio';

  @override
  String dashboardKpiPorCobrar(int count) {
    return 'Por cobrar ($count vencimientos)';
  }

  @override
  String get dashboardPlaceholderSoon => 'Próximamente';

  @override
  String get dashboardAdherenceRingPlaceholder => '--';

  @override
  String get dashboardProximaSesionManana => 'mañana';

  @override
  String get dashboardProximasSesionesEmpty =>
      'No hay sesiones próximas confirmadas.';

  @override
  String get dashboardVencimientosTitle => 'VENCIMIENTOS — 7 DÍAS';

  @override
  String get dashboardVencimientosEmpty => 'Sin pagos vencidos.';

  @override
  String get dashboardVencimientosVerTodos => 'Ver todos los pagos';

  @override
  String get dashboardInactivosTitle => 'ALUMNOS INACTIVOS';

  @override
  String get dashboardInactivosEmpty => 'Sin alumnos inactivos';

  @override
  String get dashboardAlertBannerAllClear => 'Todo al día';

  @override
  String dashboardAlertBannerSummary(
      int vencidos, int solicitudes, int inactivos) {
    String _temp0 = intl.Intl.pluralLogic(
      vencidos,
      locale: localeName,
      other: '$vencidos vencidos',
      one: '1 vencido',
    );
    String _temp1 = intl.Intl.pluralLogic(
      solicitudes,
      locale: localeName,
      other: '$solicitudes solicitudes',
      one: '1 solicitud',
    );
    String _temp2 = intl.Intl.pluralLogic(
      inactivos,
      locale: localeName,
      other: '$inactivos inactivos',
      one: '1 inactivo',
    );
    return '$_temp0 · $_temp1 · $_temp2';
  }

  @override
  String dashboardAdherenceValue(int pct) {
    return '$pct%';
  }

  @override
  String get insightsMonthlyReportTile => 'Reporte mensual';

  @override
  String get monthlyReportTitle => 'REPORTE MENSUAL';

  @override
  String get monthlyReportMetricWorkouts => 'Entrenos';

  @override
  String get monthlyReportMetricDuration => 'Duración';

  @override
  String get monthlyReportMetricVolume => 'Volumen';

  @override
  String get monthlyReportMetricSets => 'Sets';

  @override
  String get monthlyReportDurationUnit => 'min';

  @override
  String get monthlyReportDurationHoursUnit => 'h';

  @override
  String get monthlyReportVolumeUnit => 'kg';

  @override
  String get monthlyReportEmptyHint => 'Sin datos en los últimos 12 meses.';

  @override
  String get monthlyReportByMonthLabel => 'POR MES';

  @override
  String get monthlyReportByDayLabel => 'POR DÍA';

  @override
  String get monthlyReportDailyEmptyHint =>
      'Sin minutos entrenados en este mes.';

  @override
  String get monthlyReportDailyTooltipDayLabel => 'Día';

  @override
  String get monthlyReportLoadError =>
      'No pudimos cargar tu reporte mensual. Probá de nuevo.';

  @override
  String get monthlyVolumeByGroupEmpty => 'No hay sets por grupo en este mes.';

  @override
  String monthlyVolumeByGroupSets(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n sets',
      one: '1 set',
    );
    return '$_temp0';
  }

  @override
  String workoutDaysCalendarStreak(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Racha de $n semanas',
      one: 'Racha de 1 semana',
      zero: 'Sin racha',
    );
    return '$_temp0';
  }

  @override
  String workoutDaysCalendarStreakHint(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Completaste el objetivo de tu rutina $n semanas seguidas.',
      one: 'Completaste el objetivo de tu rutina 1 semana seguida.',
      zero:
          'Cumplí el objetivo de días de tu rutina esta semana y arrancás una racha.',
    );
    return '$_temp0';
  }

  @override
  String get insightsAdvancedStatsHeading => 'Estadísticas avanzadas';

  @override
  String get insightsTileMuscleDistributionTitle => 'Distribución muscular';

  @override
  String get insightsTileMuscleDistributionSubtitle =>
      'Comparativa actual vs. período anterior';

  @override
  String get muscleDistributionScreenTitle => 'DISTRIBUCIÓN MUSCULAR';

  @override
  String get muscleDistributionLoadError =>
      'No pudimos cargar tu distribución muscular. Probá de nuevo.';

  @override
  String get frequentExercisesLoadError =>
      'No pudimos cargar tus ejercicios frecuentes. Probá de nuevo.';

  @override
  String get exerciseProgressionScreenTitle => 'EVOLUCIÓN POR EJERCICIO';

  @override
  String get insightsTileExerciseProgressionTitle => 'Evolución por ejercicio';

  @override
  String get insightsTileExerciseProgressionSubtitle =>
      'Tu progreso en cada ejercicio + records';

  @override
  String get progressionSearchHint => 'Buscar ejercicio…';

  @override
  String get progressionSearchNoResults =>
      'Ningún ejercicio tuyo coincide con la búsqueda.';

  @override
  String get insightsTileMeasurementsTitle => 'Medidas';

  @override
  String get insightsTileMeasurementsSubtitle =>
      'Peso y medidas corporales en el tiempo';

  @override
  String get measurementsScreenTitle => 'MEDIDAS';

  @override
  String get measurementsSelfLogNotesHint => 'Notas (opcional)…';

  @override
  String get measurementsAddSelfLog => 'Cargar medición';

  @override
  String get measurementsProfileCardTitle => 'TUS DATOS';

  @override
  String get measurementsProfileCardHint =>
      'Los cargaste al registrarte. Editalos desde tu perfil.';

  @override
  String get measurementsWeightLabel => 'Peso';

  @override
  String get measurementsHeightLabel => 'Altura';

  @override
  String get measurementsEmptyState =>
      'Todavía no hay mediciones cargadas. Tocá + para registrar la primera y seguir tu evolución.';

  @override
  String get measurementsNeedsMoreData =>
      'Con una sola medición no hay progreso que mostrar. Falta al menos una más.';

  @override
  String get measurementsHistoryTitle => 'HISTORIAL';

  @override
  String get measurementHistoryEditTooltip => 'Editar medición';

  @override
  String get measurementHistoryDeleteTooltip => 'Eliminar medición';

  @override
  String measurementHistoryShowAll(int count) {
    return 'Ver todas ($count)';
  }

  @override
  String get measurementHistoryShowLess => 'Ver menos';

  @override
  String get measurementDeleteConfirmTitle => '¿Eliminar medición?';

  @override
  String measurementDeleteConfirmBody(String date) {
    return 'Se eliminará la medición del $date. Esta acción no se puede deshacer.';
  }

  @override
  String get measurementDeleteConfirmAction => 'Eliminar';

  @override
  String get measurementDeleteSuccess => 'Medición eliminada';

  @override
  String get measurementDeleteError =>
      'No pudimos eliminar la medición. Probá de nuevo.';

  @override
  String get measurementHistorySelfLoggedTag => 'Auto-registro';

  @override
  String get measurementHistoryTrainerLoggedTag => 'Cargada por tu entrenador';

  @override
  String get insightsTileFrequentExercisesTitle => 'Ejercicios frecuentes';

  @override
  String get insightsTileFrequentExercisesSubtitle =>
      'Tus ejercicios más entrenados';

  @override
  String get frequentExercisesScreenTitle => 'EJERCICIOS FRECUENTES';

  @override
  String get insightsTileMonthlyReportSubtitle => 'Resumen de entrenos por mes';

  @override
  String get insightsTileVolumeByGroupTitle => 'Volumen por grupo';

  @override
  String get insightsTileVolumeByGroupSubtitle =>
      'Sets vs. objetivo por grupo muscular';

  @override
  String get volumeByGroupScreenTitle => 'VOLUMEN POR GRUPO';

  @override
  String get volumeByGroupEmptyTarget =>
      'Necesitás una rutina asignada para ver tu volumen objetivo.';

  @override
  String get measurementChartSectionLabel => 'PROGRESO';

  @override
  String measurementChartSpanDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días',
      one: 'día',
    );
    return '($count $_temp0)';
  }

  @override
  String measurementChartSpanWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'semanas',
      one: 'semana',
    );
    return '($count $_temp0)';
  }

  @override
  String get measurementChartMetricWeight => 'Peso';

  @override
  String get measurementChartMetricBodyFat => '% Graso';

  @override
  String get measurementChartMetricMuscleMass => 'Masa muscular';

  @override
  String get measurementChartMetricWaist => 'Cintura';

  @override
  String get measurementChartMetricChest => 'Pecho';

  @override
  String get measurementChartMetricHips => 'Cadera';

  @override
  String get measurementChartMetricShoulders => 'Hombros';

  @override
  String get measurementChartMetricGlutes => 'Glúteos';

  @override
  String get measurementChartMetricBiceps => 'Bíceps';

  @override
  String get measurementChartMetricBicepsFlexed => 'Bíceps flex';

  @override
  String get measurementChartMetricForearm => 'Antebrazo';

  @override
  String get measurementChartMetricUpperThigh => 'Muslo sup';

  @override
  String get measurementChartMetricMidThigh => 'Muslo medio';

  @override
  String get measurementChartMetricCalf => 'Gemelo';

  @override
  String get measurementLogTitleCreate => 'Cargar medición';

  @override
  String get measurementLogTitleEdit => 'Editar medición';

  @override
  String get measurementLogNoSession =>
      'No hay sesión activa. No se puede guardar.';

  @override
  String get measurementLogSaveSuccess => 'Medición guardada';

  @override
  String get measurementLogUpdateSuccess => 'Medición actualizada';

  @override
  String get measurementLogSaveError =>
      'No pudimos guardar la medición. Probá de nuevo.';

  @override
  String get measurementLogSaveCta => 'GUARDAR MEDICIÓN';

  @override
  String get measurementLogUpdateCta => 'GUARDAR CAMBIOS';

  @override
  String get measurementLogSectionBodyComposition => 'COMPOSICIÓN CORPORAL';

  @override
  String get measurementLogSectionNotes => 'NOTAS';

  @override
  String get measurementLogNotesHint => 'Observaciones del entrenador…';

  @override
  String get measurementLogFieldWeight => 'Peso (kg)';

  @override
  String get measurementLogFieldBodyFat => 'Grasa (%)';

  @override
  String get measurementLogFieldMuscleMass => 'Masa muscular (kg)';

  @override
  String get measurementLogCircumferencesTitle => 'CIRCUNFERENCIAS';

  @override
  String get measurementLogCircumferencesHint =>
      'Opcional. Cargá las que quieras.';

  @override
  String get measurementLogGroupTrunk => 'TRONCO';

  @override
  String get measurementLogGroupUpperBody => 'TREN SUPERIOR';

  @override
  String get measurementLogGroupLowerBody => 'TREN INFERIOR';

  @override
  String get measurementLogFieldShoulders => 'Hombros';

  @override
  String get measurementLogFieldChest => 'Pecho';

  @override
  String get measurementLogFieldWaist => 'Cintura';

  @override
  String get measurementLogFieldHips => 'Cadera';

  @override
  String get measurementLogFieldGlutes => 'Glúteos';

  @override
  String get measurementLogFieldBiceps => 'Bíceps';

  @override
  String get measurementLogFieldBicepsFlexed => 'Bíceps (flex)';

  @override
  String get measurementLogFieldForearm => 'Antebrazo';

  @override
  String get measurementLogFieldUpperThigh => 'Muslo superior';

  @override
  String get measurementLogFieldMidThigh => 'Muslo medio';

  @override
  String get measurementLogFieldCalf => 'Gemelo';

  @override
  String get measurementLogBilateralLeftHint => 'I (cm)';

  @override
  String get measurementLogBilateralRightHint => 'D (cm)';

  @override
  String get reviewSheetTitleEdit => 'Editá tu reseña';

  @override
  String reviewSheetTitleThirtyDay(String trainerName) {
    return 'Ya llevás un mes entrenando con $trainerName. ¿Cómo va?';
  }

  @override
  String reviewSheetTitleStandard(String trainerName) {
    return '¿Cómo fue tu experiencia con $trainerName?';
  }

  @override
  String get reviewSheetCommentHint => 'Contanos cómo fue (opcional)';

  @override
  String get reviewSheetCancel => 'CANCELAR';

  @override
  String get reviewSheetSubmit => 'ENVIAR';

  @override
  String get reviewSnackBarError =>
      'No pudimos guardar tu reseña. Probá de nuevo.';

  @override
  String get reviewCtaCreate => 'DEJAR UNA RESEÑA';

  @override
  String get reviewCtaEdit => 'EDITAR MI RESEÑA';

  @override
  String get reviewTrainerFallbackName => 'tu Personal Trainer';

  @override
  String get reviewsSectionTitle => 'RESEÑAS';

  @override
  String get reviewsSectionEmpty => 'Sin reseñas todavía';

  @override
  String get reviewTileDeletedUser => 'Usuario eliminado';

  @override
  String get reviewTileDateToday => 'hoy';

  @override
  String reviewTileDateDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'días',
      one: 'día',
    );
    return 'hace $count $_temp0';
  }

  @override
  String reviewTileDateMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'meses',
      one: 'mes',
    );
    return 'hace $count $_temp0';
  }

  @override
  String get postPrivacySelectorTitle => 'VISIBILIDAD';

  @override
  String get postPrivacyFriends => 'SEGUIDORES';

  @override
  String get postPrivacyGym => 'MI GYM';

  @override
  String get postPrivacyPublic => 'PÚBLICO';

  @override
  String get postPrivacyNoGymHint => 'Asociate a un gym para postear acá';

  @override
  String get suggestedUsersTitle => 'SUGERENCIAS PARA VOS';

  @override
  String get suggestedUserAnonymous => 'Anónimo';

  @override
  String a11ySuggestedUserButton(String name) {
    return 'Ver el perfil de $name';
  }

  @override
  String get notificationHistoryTitle => 'NOTIFICACIONES';

  @override
  String get notificationHistoryEmpty => 'Todavía no tenés notificaciones';

  @override
  String get notificationHistoryError =>
      'No pudimos cargar tus notificaciones.';

  @override
  String notificationPendingRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count solicitudes de seguidor pendientes',
      one: '1 solicitud de seguidor pendiente',
    );
    return '$_temp0';
  }

  @override
  String get notificationBellA11y => 'Abrir notificaciones';

  @override
  String notificationBellWithCountA11y(int count) {
    return 'Abrir notificaciones, $count pendientes';
  }

  @override
  String get postDetailTitle => 'PUBLICACIÓN';

  @override
  String get postDetailUnavailable => 'Este post ya no está disponible.';

  @override
  String feedUnfollowConfirmTitle(String name) {
    return '¿Dejar de seguir a $name?';
  }

  @override
  String get feedUnfollowConfirmAction => 'DEJAR DE SEGUIR';

  @override
  String get feedUnfollowDismiss => 'CANCELAR';

  @override
  String feedCancelRequestConfirmTitle(String name) {
    return '¿Cancelar la solicitud a $name?';
  }

  @override
  String get feedCancelRequestConfirmAction => 'CANCELAR SOLICITUD';

  @override
  String get feedCancelRequestDismiss => 'VOLVER';

  @override
  String get feedFollowButtonFollowA11y => 'Seguir a esta persona';

  @override
  String get feedFollowButtonFollowingA11y =>
      'Siguiendo. Tocá para dejar de seguir';

  @override
  String get feedFollowButtonRequestedA11y =>
      'Solicitud enviada. Tocá para cancelarla';

  @override
  String get feedFollowButtonAcceptA11y => 'Aceptar la solicitud de seguidor';

  @override
  String get feedFollowStartedSuccess => 'Ahora seguís a esta persona.';

  @override
  String get feedSegmentFollowing => 'SEGUIDORES';

  @override
  String get feedEmptyFollowing => 'Todavía no hay posts de quienes seguís';

  @override
  String get chatBlockedComposerNotice =>
      'Bloqueaste a esta persona. Desbloqueala para escribirle.';

  @override
  String get chatBlockedComposerHintA11y => 'No podés escribir en este chat';

  @override
  String get followListTabFollowers => 'SEGUIDORES';

  @override
  String get followListTabFollowing => 'SIGUIENDO';

  @override
  String get followListEmptyFollowers => 'Todavía no tiene seguidores';

  @override
  String get followListEmptyFollowersSelf => 'Todavía no tenés seguidores';

  @override
  String get followListEmptyFollowing => 'Todavía no sigue a nadie';

  @override
  String get followListEmptyFollowingSelf => 'Todavía no seguís a nadie';

  @override
  String get followListLoadError =>
      'No pudimos cargar la lista. Intentá de nuevo.';

  @override
  String get followListOpenFollowersA11y => 'Ver seguidores';

  @override
  String get followListOpenFollowingA11y => 'Ver seguidos';

  @override
  String routineCardDaysPerWeek(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days días/sem',
      one: '1 día/sem',
    );
    return '$_temp0';
  }

  @override
  String routineCardMinutes(String value) {
    return '$value min';
  }

  @override
  String get onboardingCardDismiss => 'ENTENDIDO';

  @override
  String get onboardingCardAthleteHomeTitle => 'TU RESUMEN DEL DÍA';

  @override
  String get onboardingCardAthleteHomeBody =>
      'Acá ves qué te toca entrenar hoy, cómo venís esta semana y tu racha. Si dejaste una sesión a medias, te la ofrece para retomar.';

  @override
  String get onboardingCardAthleteWorkoutTitle => 'ACÁ ARRANCA TU ENTRENO';

  @override
  String get onboardingCardAthleteWorkoutBody =>
      'Tenés tres formas de conseguir una rutina:';

  @override
  String get onboardingCardAthleteWorkoutBullet1 =>
      'El plan de tu entrenador, ya armado y asignado a vos';

  @override
  String get onboardingCardAthleteWorkoutBullet2 =>
      'Una plantilla de TREINO, lista para usar';

  @override
  String get onboardingCardAthleteWorkoutBullet3 =>
      'Tu propia rutina, armada ejercicio por ejercicio';

  @override
  String get onboardingCardAthleteFeedTitle => 'LA PARTE SOCIAL';

  @override
  String get onboardingCardAthleteFeedBody =>
      'Publicá tus entrenamientos y seguí a tus amigos. Al lado tenés Rankings:';

  @override
  String get onboardingCardAthleteFeedBullet1 =>
      'Te compara con la gente de tu gym';

  @override
  String get onboardingCardAthleteFeedBullet2 =>
      'Es opcional: si no lo activás, ni aparecés ni ves a nadie';

  @override
  String get onboardingCardAthleteCoachTitle => 'TU ENTRENADOR';

  @override
  String get onboardingCardAthleteCoachBody =>
      'Buscá y contratá un entrenador cerca tuyo. Vos controlás qué ve de vos:';

  @override
  String get onboardingCardAthleteCoachBullet1 =>
      'Tus entrenamientos los ve apenas aceptás el vínculo';

  @override
  String get onboardingCardAthleteCoachBullet2 =>
      'Tus datos personales y medidas, solo si los activás en Perfil › Privacidad';

  @override
  String get onboardingCardAthleteProfileTitle => 'TU CUENTA';

  @override
  String get onboardingCardAthleteProfileBody =>
      'Tus datos, tus medidas y tu privacidad. Acá decidís qué comparte tu perfil público y qué ve tu entrenador.';

  @override
  String get onboardingCardTrainerHomeTitle => 'TU DÍA';

  @override
  String get onboardingCardTrainerHomeBody =>
      'Tus próximas sesiones, quién entrenó hoy, la actividad reciente de tus alumnos y lo que tenés por cobrar.';

  @override
  String get onboardingCardTrainerWorkoutTitle => 'TUS PLANTILLAS';

  @override
  String get onboardingCardTrainerWorkoutBody =>
      'Tu biblioteca de plantillas propias y el atajo para asignarle un plan a un alumno. El editor completo está en Coach Hub, desde la compu.';

  @override
  String get onboardingCardTrainerFeedTitle => 'LA COMUNIDAD';

  @override
  String get onboardingCardTrainerFeedBody =>
      'El feed social de TREINO. Podés seguir lo que publican tus alumnos y publicar vos también.';

  @override
  String get onboardingCardTrainerCoachTitle => 'ALUMNOS Y AGENDA';

  @override
  String get onboardingCardTrainerCoachBody =>
      'Acá trabajás con tus alumnos. Lo primero que conviene saber:';

  @override
  String get onboardingCardTrainerCoachBullet1 =>
      'El alumno te manda la solicitud a vos desde su app, no al revés';

  @override
  String get onboardingCardTrainerCoachBullet2 =>
      'Abrí un alumno para ver su plan, sus series, su progreso y el chat';

  @override
  String get onboardingCardTrainerCoachBullet3 =>
      'En AGENDA creás turnos sueltos o series que se repiten';

  @override
  String get onboardingCardTrainerProfileTitle => 'TU PERFIL PROFESIONAL';

  @override
  String get onboardingCardTrainerProfileBody =>
      'Así te ven los alumnos que te buscan. Desde acá también:';

  @override
  String get onboardingCardTrainerProfileBullet1 =>
      'Aceptás las solicitudes entrantes de alumnos nuevos';

  @override
  String get onboardingCardTrainerProfileBullet2 =>
      'Configurás tu disponibilidad horaria';

  @override
  String get onboardingTourSkip => 'SALTAR';

  @override
  String get onboardingTourNext => 'SIGUIENTE';

  @override
  String get onboardingTourFinish => 'COMENZAR';

  @override
  String onboardingTourProgress(int current, int total) {
    return 'Paso $current de $total';
  }

  @override
  String get onboardingCustomExerciseCta => 'CREAR MI EJERCICIO';

  @override
  String get templatesOnboardingStep1Title => '¿Cuántos días podés entrenar?';

  @override
  String get templatesOnboardingStep1Body =>
      'Elegí lo que vas a sostener. Guardamos tu respuesta para personalizar lo que te recomendamos.';

  @override
  String get templatesOnboardingStep1Label => 'Días por semana';

  @override
  String get templatesOnboardingStep1Hint =>
      'Todo lo que elijas filtra el catálogo: sólo vas a ver plantillas que cumplan con todo. Si no queda ninguna, podés ver todas.';

  @override
  String get templatesOnboardingStep2Title => '¿Cuánto dura tu sesión?';

  @override
  String get templatesOnboardingStep2Body =>
      '45 minutos reales valen más que una hora ideal. Elegí el tiempo que tenés de verdad.';

  @override
  String get templatesOnboardingStep2Label => 'Minutos por sesión';

  @override
  String get templatesOnboardingStep3Title => '¿Para qué querés entrenar?';

  @override
  String get templatesOnboardingStep3Body =>
      'Nadie elige por split, elige por para qué. Es la respuesta que más nos dice sobre lo que buscás.';

  @override
  String get templatesOnboardingStep3Label =>
      'Objetivos · podés elegir más de uno';

  @override
  String get templatesOnboardingStep4Title => 'Esto no es un examen';

  @override
  String get templatesOnboardingStep4Body =>
      'Guardamos tus respuestas en tu perfil. Esta es opcional: dejala vacía si no tenés preferencia.';

  @override
  String get templatesOnboardingStep4Label => 'Zonas a priorizar · opcional';

  @override
  String get templatesOnboardingCta => 'VER MIS PLANTILLAS';

  @override
  String get templatesOnboardingMinutes30 => '30 MIN';

  @override
  String get templatesOnboardingMinutes30Hint => 'Entro y salgo';

  @override
  String get templatesOnboardingMinutes45 => '45 MIN';

  @override
  String get templatesOnboardingMinutes45Hint => 'Lo de siempre';

  @override
  String get templatesOnboardingMinutes60 => '60 MIN';

  @override
  String get templatesOnboardingMinutes60Hint => 'Hora completa';

  @override
  String get templatesOnboardingMinutes75 => '75 MIN O MÁS';

  @override
  String get templatesOnboardingMinutes75Hint => 'Fuerza';

  @override
  String get templatesGoalHealth => 'SALUD';

  @override
  String get templatesGoalInjuryPrevention => 'PREVENCIÓN';

  @override
  String get templatesGoalAesthetics => 'ESTÉTICA';

  @override
  String get templatesGoalSport => 'DEPORTE';

  @override
  String get templatesGoalWellbeing => 'BIENESTAR';

  @override
  String get templatesZoneBack => 'ESPALDA';

  @override
  String get templatesZoneChest => 'PECHO';

  @override
  String get templatesZoneShoulders => 'HOMBROS';

  @override
  String get templatesZoneGlutes => 'GLÚTEOS';

  @override
  String get templatesZoneQuads => 'CUÁDRICEPS';

  @override
  String get templatesZoneCore => 'CORE';

  @override
  String templatesOnboardingDaysOption(int days) {
    return '$days DÍAS';
  }

  @override
  String get templatesOnboardingBack => 'VOLVER';

  @override
  String get templatesFilterBarAdjust => 'AJUSTAR';

  @override
  String get templatesFilterBarSetUp => 'AJUSTAR MI BÚSQUEDA';

  @override
  String get templatesFilterBarHint =>
      'Filtrado y ordenado según lo que buscás';

  @override
  String get templatesFilterBarHintSorted => 'Ordenado según lo que buscás';

  @override
  String get exerciseFeedbackAction => 'COMENTAR / REPORTAR';

  @override
  String exerciseFeedbackActionA11y(String exerciseName) {
    return 'Comentar o reportar una molestia en $exerciseName';
  }

  @override
  String get exerciseFeedbackSheetTitle => 'CONTALE A TU PF';

  @override
  String exerciseFeedbackSheetAnchorSet(String exerciseName, int setNumber) {
    return '$exerciseName · serie $setNumber';
  }

  @override
  String get exerciseFeedbackKindComment => 'Comentario';

  @override
  String get exerciseFeedbackKindDiscomfort => 'Molestia / dolor';

  @override
  String get exerciseFeedbackDiscomfortNotice =>
      'Tu PF recibe un aviso al toque.';

  @override
  String get exerciseFeedbackTextHint =>
      '¿Qué le querés contar? Ej: en la 3ª me tiró el hombro derecho.';

  @override
  String get exerciseFeedbackPhotoCamera => 'Cámara';

  @override
  String get exerciseFeedbackPhotoGallery => 'Galería';

  @override
  String get exerciseFeedbackPhotoRemove => 'Quitar foto';

  @override
  String get exerciseFeedbackPhotoError =>
      'No pudimos abrir la foto. Probá de nuevo.';

  @override
  String get exerciseFeedbackCancel => 'CANCELAR';

  @override
  String get exerciseFeedbackSubmit => 'ENVIAR';

  @override
  String get exerciseFeedbackSuccess =>
      'Listo. Tu PF lo va a ver junto a la serie.';

  @override
  String get exerciseFeedbackError =>
      'No pudimos guardar tu reporte. Probá de nuevo.';

  @override
  String get exerciseFeedbackNoteTagComment => 'DEL ALUMNO';

  @override
  String get exerciseFeedbackNoteTagDiscomfort => 'MOLESTIA';

  @override
  String get workoutHistorialTopeAlcanzado =>
      'Puede haber entrenamientos más viejos que no entran en esta lista.';

  @override
  String get dashboardActividadTopeAlcanzado =>
      'Puede haber más actividad que no entra en esta lista.';

  @override
  String exerciseFeedbackNoteSetTag(int setNumber) {
    return 'SERIE $setNumber';
  }

  @override
  String get coachSessionFeedbackLoadError =>
      'No pudimos cargar los reportes del alumno.';

  @override
  String get sessionFeedbackLoadError => 'No pudimos cargar tus reportes.';

  @override
  String get routineEditorGoToProblem => 'IR';

  @override
  String get routineEditorGoToProblemA11y => 'Ir al primer problema';

  @override
  String routineEditorFooterSummary(int dias, int sets) {
    String _temp0 = intl.Intl.pluralLogic(
      dias,
      locale: localeName,
      other: '$dias días',
      one: '1 día',
    );
    String _temp1 = intl.Intl.pluralLogic(
      sets,
      locale: localeName,
      other: '$sets sets',
      one: '1 set',
    );
    return '$_temp0 · $_temp1 · todo listo';
  }

  @override
  String get routineEditorProblemMissingName => 'Falta el nombre del plan';

  @override
  String get routineEditorProblemMissingSplit => 'Falta el split';

  @override
  String routineEditorProblemEmptyDay(int dia) {
    return 'Día $dia: sin ejercicios';
  }

  @override
  String routineEditorProblemDuplicate(int dia) {
    return 'Día $dia: ejercicio repetido';
  }

  @override
  String routineEditorProblemIncompleteSets(int dia, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sets sin completar',
      one: '1 set sin completar',
    );
    return 'Día $dia: $_temp0';
  }

  @override
  String routineEditorProblemOtherWeek(int semana, int dia) {
    return 'Semana $semana: día $dia sin completar';
  }

  @override
  String get routineEditorQuickEntryToggle => 'RÁPIDO';

  @override
  String get routineEditorQuickEntryToggleA11y => 'Entrada rápida';

  @override
  String get routineEditorQuickEntryHint => 'banca 4x10 60';

  @override
  String routineEditorQuickEntryWillAdd(int sets, String reps, String peso) {
    String _temp0 = intl.Intl.pluralLogic(
      sets,
      locale: localeName,
      other: '$sets sets',
      one: '1 set',
    );
    return 'Se agrega como $_temp0 × $reps a $peso.';
  }

  @override
  String get routineEditorQuickEntryNoWeight => 'sin peso';

  @override
  String get routineEditorQuickEntryEmptyHint =>
      'Buscá el ejercicio y tocalo. Después escribís 4x10 y el peso.';

  @override
  String get routineEditorQuickEntryPickedHint =>
      '4x10 y el peso. Por set con comas: 4x10,8,6,4 · 55,45,35,25. Por tiempo: 3x30s o 3x1:30. Decimales con punto: 62.5';

  @override
  String get routineEditorQuickEntryAdd => 'AGREGAR';

  @override
  String get routineEditorExerciseSheetTitle => 'ACCIONES';

  @override
  String get routineEditorSlotMenuCollapse => 'Colapsar sets';

  @override
  String get routineEditorSlotMenuExpand => 'Desplegar sets';

  @override
  String get coachTemplateEditorTitle => 'Nueva plantilla';

  @override
  String get coachTemplateEditorEditTitle => 'Editar plantilla';

  @override
  String get coachTemplateEditorSubmit => 'GUARDAR PLANTILLA';

  @override
  String get routineEditorAddNothingNew =>
      'Esos ejercicios ya estaban en el día.';

  @override
  String get routineEditorSupersetNeedsTwo =>
      'Una superserie necesita dos ejercicios. Se agregó uno solo, suelto.';

  @override
  String get routineEditorSlotMenuMergeUp => 'Unir con el de arriba';

  @override
  String get routineEditorSlotMenuUngroup => 'Sacar de la superserie';

  @override
  String get routineEditorSlotMenuMergeDown => 'Unir con el de abajo';

  @override
  String get paywallFreePlanLimitTitle => 'Esto es parte del plan pago';

  @override
  String paywallFreePlanLimitDaysBody(int max) {
    return 'Con el plan gratis armás rutinas de hasta $max días. Las plantillas de principiante del catálogo las seguís completas, sin tope.';
  }

  @override
  String get paywallFreePlanLimitWeeksBody =>
      'Periodizar en varias semanas es parte del plan pago. Con el gratis tu rutina propia va de a una semana.';

  @override
  String paywallFreePlanLimitShapeDaysBody(int actual, int max) {
    return 'Esta rutina tiene $actual días y con el plan gratis guardás hasta $max. Sacá los que sobren y vas a poder guardar los cambios. Entrenarla completa no tiene tope.';
  }

  @override
  String paywallFreePlanLimitShapeWeeksBody(int actual, int max) {
    return 'Esta rutina está periodizada en $actual semanas y con el plan gratis guardás hasta $max. Podés dejarla en $max para guardar los cambios, o pasarte al plan pago. Entrenarla completa no tiene tope.';
  }

  @override
  String get paywallFreePlanLimitUpgrade => 'Ver el plan pago';

  @override
  String get paywallFreePlanLimitDismiss => 'Entendido';

  @override
  String get paywallFreePlanLimitTemplateBody =>
      'Esta plantilla es parte del plan pago. Las de nivel principiante las podés usar completas con el plan gratis.';

  @override
  String paywallFreePlanLimitCustomizeTemplateBody(int max) {
    return 'Personalizar una plantilla del catálogo es parte del plan pago. Con el gratis la seguís tal cual, sin tope de días, o armás tu propia rutina de hasta $max días.';
  }

  @override
  String get workoutPlantillasPremiumChip => 'PLAN PAGO';

  @override
  String get progressionPeriodLast3Months => '3 meses';

  @override
  String get progressionPeriodLast1Year => '1 año';

  @override
  String get workoutRoutineFollow => 'Seguir esta plantilla';

  @override
  String get workoutRoutineFollowing => 'La estas siguiendo';

  @override
  String get workoutRoutineFollowSuccess =>
      'Listo, ahora seguís esta plantilla.';

  @override
  String get workoutRoutineFollowError =>
      'No pudimos marcarla. Probá de nuevo.';

  @override
  String get paywallFreePlanLimitRoutineCountBody =>
      'Con el plan gratis guardás hasta 3 rutinas propias. Las plantillas del catálogo que seguís no ocupan lugar.';

  @override
  String get paywallFreePlanLimitChartHistoryBody =>
      'Con el plan gratis mirás hasta un mes de historial. Los períodos de 3 meses y 1 año son del plan pago.';

  @override
  String get paywallFreePlanLimitProName => 'TREINO Pro';

  @override
  String get paywallFreePlanLimitProTagline =>
      'Todo lo que ya usás, sin los topes del plan gratis.';

  @override
  String paywallFreePlanLimitProBenefitDays(int max) {
    return 'Rutinas de hasta $max días';
  }

  @override
  String paywallFreePlanLimitProBenefitWeeks(int max) {
    return 'Hasta $max semanas, con periodización';
  }

  @override
  String get paywallFreePlanLimitProBenefitTemplates =>
      'Todas las plantillas del catálogo, de principiante a avanzado';

  @override
  String get paywallFreePlanLimitProBenefitCustomize =>
      'Personalizar cualquier plantilla del catálogo';

  @override
  String paywallFreePlanLimitProBenefitRoutines(int max) {
    return 'Hasta $max rutinas propias';
  }

  @override
  String get paywallFreePlanLimitProBenefitCharts =>
      'Gráficos de 3 meses y 1 año';

  @override
  String get paywallFreePlanLimitProMatchTag => 'Lo que buscabas';

  @override
  String get paywallAlumnoTitulo => 'TREINO Pro';

  @override
  String get paywallAlumnoBajada =>
      'Programá en serio: rutinas largas, periodización y todo tu historial.';

  @override
  String get paywallAlumnoPlanMensual => 'Mensual';

  @override
  String get paywallAlumnoPlanAnual => 'Anual';

  @override
  String get paywallAlumnoAhorro => '2 meses gratis';

  @override
  String get paywallAlumnoBeneficio1 => 'Rutinas de hasta 7 días';

  @override
  String get paywallAlumnoBeneficio2 => '16 semanas con periodización';

  @override
  String get paywallAlumnoBeneficio3 => 'Gráficos de 3 meses y 1 año';

  @override
  String get paywallAlumnoBeneficio4 => 'Las plantillas premium del catálogo';

  @override
  String get paywallAlumnoImpuestos =>
      'Tu banco le suma los impuestos argentinos a este precio (IVA y percepción). No los cobra TREINO: los vas a ver en el resumen de tu tarjeta.';

  @override
  String get paywallAlumnoCta => 'Suscribirme';

  @override
  String get paywallAlumnoRestaurar => 'Restaurar compras';

  @override
  String get paywallAlumnoSinPlanes =>
      'No pudimos cargar los planes. Probá de nuevo en un rato.';

  @override
  String get paywallAlumnoReintentar => 'Reintentar';

  @override
  String get paywallAlumnoListo => '¡Listo! Ya tenés TREINO Pro.';

  @override
  String get paywallAlumnoPendiente =>
      'Tu pago quedó pendiente de confirmación. Te avisamos cuando se acredite.';

  @override
  String get paywallAlumnoErrorCompra =>
      'No pudimos completar la compra. No se te cobró nada.';

  @override
  String get paywallAlumnoSinRestaurar =>
      'No encontramos compras para restaurar en esta cuenta.';

  @override
  String get moderationMenuA11y => 'Más opciones';

  @override
  String get moderationReportAction => 'Reportar';

  @override
  String get moderationBlockAction => 'Bloquear';

  @override
  String get moderationReportSheetTitle => '¿Por qué lo reportás?';

  @override
  String get moderationReportReasonHarassment => 'Acoso';

  @override
  String get moderationReportReasonSexualContent => 'Contenido sexual';

  @override
  String get moderationReportReasonViolenceOrSelfHarm =>
      'Violencia o autolesión';

  @override
  String get moderationReportReasonDangerousHealthAdvice =>
      'Consejo de salud peligroso';

  @override
  String get moderationReportReasonImpersonation => 'Suplantación de identidad';

  @override
  String get moderationReportReasonSpam => 'Spam';

  @override
  String get moderationReportReasonThirdPartyData => 'Datos de terceros';

  @override
  String get moderationReportReasonIntellectualProperty =>
      'Propiedad intelectual';

  @override
  String get moderationReportReasonOther => 'Otro';

  @override
  String get moderationReportDetailHint => 'Contanos más (opcional)';

  @override
  String get moderationReportSubmit => 'ENVIAR REPORTE';

  @override
  String get moderationReportCancel => 'CANCELAR';

  @override
  String get moderationReportSuccess => 'Gracias, lo vamos a revisar.';

  @override
  String get moderationReportError =>
      'No pudimos enviar el reporte. Probá de nuevo.';

  @override
  String moderationBlockConfirmTitle(String name) {
    return '¿Bloquear a $name?';
  }

  @override
  String get moderationBlockConfirmBody =>
      'No va a poder escribirte, seguirte ni reaccionar a tus posts.';

  @override
  String get moderationBlockConfirmAction => 'BLOQUEAR';

  @override
  String get moderationBlockDismiss => 'CANCELAR';

  @override
  String moderationBlockSuccess(String name) {
    return 'Bloqueaste a $name.';
  }

  @override
  String get moderationBlockError => 'No pudimos bloquear. Probá de nuevo.';

  @override
  String get moderationBlockedMessage =>
      'Ese texto no se puede publicar porque incumple las Normas de Comunidad. Revisalo y volvé a intentar.';

  @override
  String get privacyTitle => 'Privacidad';

  @override
  String get privacyAnalyticsTitle => 'Analítica de uso';

  @override
  String get privacyAnalyticsSubtitle =>
      'Nos ayuda a entender qué partes de la app se usan.';

  @override
  String get privacyAnalyticsExplainer =>
      'Si la desactivás, TREINO deja de registrar cómo usás la app. No afecta tus entrenamientos, tus datos ni el funcionamiento de nada. Podés volver a activarla cuando quieras. Es una preferencia de ESTE dispositivo: si también entrás al Coach Hub, ahí se configura aparte.';

  @override
  String get privacyAnalyticsCrashNote =>
      'No incluye los reportes de errores: esos los seguimos recibiendo para poder arreglar fallas, y no describen lo que hacés en la app.';

  @override
  String get privacyEntryTitle => 'Analítica, correos y recordatorios';

  @override
  String get privacyPromoEmailsTitle => 'Correos promocionales';

  @override
  String get privacyPromoEmailsSubtitle =>
      'Si lo apagás, no te mandamos más. Los avisos de tu cuenta te siguen llegando.';

  @override
  String get privacyPromoEmailsSaveError =>
      'No pudimos guardar el cambio. Intentá de nuevo.';

  @override
  String get privacyTrainingRemindersTitle => 'Recordatorios de entrenamiento';

  @override
  String get privacyTrainingRemindersSubtitle =>
      'Te avisamos si tu racha está en riesgo o si hace días que no entrenás.';

  @override
  String get privacyTrainingRemindersSaveError =>
      'No pudimos guardar el cambio. Intentá de nuevo.';

  @override
  String customExerciseCounter(int count, int limit) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return '$countString de $limitString ejercicios propios';
  }

  @override
  String templateCounter(int count, int limit) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return '$countString de $limitString plantillas';
  }

  @override
  String get planLimitVerPlanesMovil => 'VER PLANES';

  @override
  String get planLimitEntendido => 'Entendido';

  @override
  String get planLimitPorMes => '/mes';

  @override
  String get planLimitPlanAMedidaTitulo => 'PLAN A MEDIDA';

  @override
  String get planLimitContactanos => 'CONTACTANOS';

  @override
  String get planLimitAlumnosTituloTope => 'LLEGASTE AL LÍMITE DE TU PLAN';

  @override
  String get planLimitAlumnosTituloInactiva => 'TU SUSCRIPCIÓN ESTÁ SUSPENDIDA';

  @override
  String get planLimitAlumnosTituloBaja => 'TU SUSCRIPCIÓN ESTÁ DADA DE BAJA';

  @override
  String get planLimitAlumnosCuerpoInactivaExplicacion =>
      'Mientras tu suscripción no esté al día, tu cuenta funciona con el límite del plan Free. Ningún alumno se elimina.';

  @override
  String planLimitAlumnosCuerpoTopeMovilLimitado(String plan, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit alumnos',
      one: '1 alumno',
    );
    return 'Tu plan $plan incluye $_temp0.';
  }

  @override
  String planLimitAlumnosCuerpoTopeMovilIlimitado(String plan) {
    return 'Tu plan $plan incluye alumnos sin límite.';
  }

  @override
  String get planLimitAlumnosPlanAMedidaCuerpo =>
      'Estás en el plan más grande. Para más de 15 alumnos estamos preparando un plan a tu medida.';

  @override
  String get planLimitAlumnosPlanAMedidaSnack =>
      'Muy pronto vas a poder tener más de 15 alumnos.';

  @override
  String planLimitReactivateTituloMovil(String plan) {
    return 'TU PLAN: $plan';
  }

  @override
  String planLimitReactivateCuerpoMovil(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alumnos',
      one: '1 alumno',
    );
    return 'No está activa. Mientras tanto, tu cuenta tiene el límite del plan Free: $_temp0.';
  }

  @override
  String get planLimitVerEstadoMovil => 'VER ESTADO';

  @override
  String planLimitReactivateEstadoMovil(String estado) {
    return 'Estado: $estado';
  }

  @override
  String get planLimitEstadoActiva => 'activa';

  @override
  String get planLimitEstadoPendiente => 'pendiente de pago';

  @override
  String get planLimitEstadoGracia => 'con pago pendiente';

  @override
  String get planLimitEstadoPausada => 'pausada';

  @override
  String get planLimitEstadoCancelada => 'cancelada';

  @override
  String planLimitAlumnosBeneficioLimitado(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit alumnos',
      one: '1 alumno',
    );
    return 'Hasta $_temp0';
  }

  @override
  String get planLimitAlumnosBeneficioIlimitado => 'Alumnos sin límite';

  @override
  String get planLimitSuscripcionPausadaMovil => 'Tu suscripción está pausada.';

  @override
  String get planLimitSuscripcionBajaMovil =>
      'Tu suscripción está dada de baja.';

  @override
  String get planLimitTrainerTituloEjercicios => 'TOPE DE EJERCICIOS PROPIOS';

  @override
  String get planLimitTrainerTituloPlantillas => 'TOPE DE PLANTILLAS';

  @override
  String planLimitTrainerPasadoTopeEjercicios(
      int count, int limit, int toDelete) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Tenés $_temp0 y tu plan incluye $limit. Conservás todos; para crear uno nuevo, borrá $toDelete.';
  }

  @override
  String planLimitTrainerPasadoTopePlantillas(
      int count, int limit, int toArchive) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plantillas',
      one: '1 plantilla',
    );
    return 'Tenés $_temp0 y tu plan incluye $limit. Conservás todas; para crear una nueva, archivá $toArchive.';
  }

  @override
  String planLimitTrainerInactivaEjercicios(
      String plan, String planEfectivo, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Tu suscripción a $plan no está activa. Mientras tanto, tu plan $planEfectivo incluye $_temp0.';
  }

  @override
  String planLimitTrainerInactivaPlantillas(
      String plan, String planEfectivo, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit plantillas',
      one: '1 plantilla',
    );
    return 'Tu suscripción a $plan no está activa. Mientras tanto, tu plan $planEfectivo incluye $_temp0.';
  }

  @override
  String planLimitTrainerTopeEjerciciosConTier(String plan, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Tu plan $plan incluye $_temp0. Podés editar o borrar los que ya tenés.';
  }

  @override
  String planLimitTrainerTopeEjerciciosGenerico(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Tu plan incluye $_temp0. Podés editar o borrar los que ya tenés.';
  }

  @override
  String planLimitTrainerTopePlantillasConTier(String plan, int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit plantillas',
      one: '1 plantilla',
    );
    return 'Tu plan $plan incluye $_temp0. Podés editar o archivar las que ya tenés.';
  }

  @override
  String planLimitTrainerTopePlantillasGenerico(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit plantillas',
      one: '1 plantilla',
    );
    return 'Tu plan incluye $_temp0. Podés editar o archivar las que ya tenés.';
  }

  @override
  String planLimitTrainerBeneficioEjerciciosLimitado(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit ejercicios propios',
      one: '1 ejercicio propio',
    );
    return 'Hasta $_temp0';
  }

  @override
  String get planLimitTrainerBeneficioEjerciciosIlimitado =>
      'Ejercicios propios sin límite';

  @override
  String planLimitTrainerBeneficioPlantillasLimitado(int limit) {
    String _temp0 = intl.Intl.pluralLogic(
      limit,
      locale: localeName,
      other: '$limit plantillas',
      one: '1 plantilla',
    );
    return 'Hasta $_temp0';
  }

  @override
  String get planLimitTrainerBeneficioPlantillasIlimitado =>
      'Plantillas sin límite';

  @override
  String get planLimitTrainerPlanAMedidaCuerpo =>
      'Estás en el plan más grande. Estamos preparando un plan a tu medida.';

  @override
  String eliminarCuentaSheetTrainerUnlinkNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se van a desvincular $count alumnos. Les avisamos.',
      one: 'Se va a desvincular 1 alumno. Le avisamos.',
    );
    return '$_temp0';
  }

  @override
  String get eliminarCuentaSheetErrorSubscriptionCancel =>
      'No pudimos cancelar tu suscripción, así que tu cuenta no se eliminó. Probá de nuevo en unos minutos.';

  @override
  String get eliminarCuentaSheetErrorNotAllowed =>
      'No pudimos eliminar tu cuenta desde la app. Escribinos y lo resolvemos.';

  @override
  String get eliminarCuentaWebReauthTitle => 'Confirmá tu identidad';

  @override
  String get eliminarCuentaWebReauthPasswordBody =>
      'Por seguridad, ingresá tu contraseña para confirmar que sos vos.';

  @override
  String get eliminarCuentaWebReauthCta => 'CONFIRMAR';

  @override
  String eliminarCuentaWebPopupHint(String provider) {
    return 'Para confirmar que sos vos, se va a abrir una ventana de $provider.';
  }

  @override
  String get coachHubOnboardingPfLocationStaleHint =>
      'Este lugar ya no está disponible. Volvé a elegir este lugar para que te encuentren.';

  @override
  String get appUpdateTitle => 'Actualizá la app';

  @override
  String get appUpdateBody =>
      'Esta versión de TREINO ya no es compatible y puede perder datos de tus rutinas. Actualizala para seguir entrenando.';

  @override
  String get appUpdateCta => 'ACTUALIZAR';

  @override
  String get appUpdateOpenError =>
      'No pudimos abrir la tienda. Buscá TREINO en la App Store o en Google Play.';

  @override
  String get timePickerHelpText => 'Elegí una hora';

  @override
  String logFieldRange(String min, String max, String unit) {
    return 'Entre $min y $max $unit';
  }

  @override
  String inputMaxReached(String max, String unit) {
    return 'Máximo $max $unit';
  }

  @override
  String get performanceLogTitleEdit => 'Editar evaluación';

  @override
  String get performanceLogUpdateCta => 'GUARDAR CAMBIOS';

  @override
  String get performanceLogUpdateSuccess => 'Evaluación actualizada';

  @override
  String get performanceHistoryEditTooltip => 'Editar evaluación';

  @override
  String get performanceHistoryDeleteTooltip => 'Eliminar evaluación';

  @override
  String get performanceHistoryOtherTrainerTag => 'Cargada por otro entrenador';

  @override
  String get performanceDeleteConfirmTitle => '¿Eliminar evaluación?';

  @override
  String performanceDeleteConfirmBody(String date) {
    return 'Se eliminará la evaluación del $date. Esta acción no se puede deshacer.';
  }

  @override
  String get performanceDeleteSuccess => 'Evaluación eliminada';

  @override
  String get performanceDeleteError =>
      'No pudimos eliminar la evaluación. Probá de nuevo.';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get agendaRuleDeleteTitle => '¿Borrar este horario?';

  @override
  String get agendaRuleDeleteBody => 'Las reservas existentes se mantienen.';

  @override
  String get agendaOverrideDeleteTitle => '¿Eliminar esta excepción?';

  @override
  String get onboardingCustomExerciseNotNow => 'AHORA NO';

  @override
  String get authSignOutConfirmTitle => '¿Cerrar sesión?';

  @override
  String get authSignOutConfirmAction => 'Salir';

  @override
  String get sessionRestEndedTitle => 'Terminó el descanso';

  @override
  String get sessionRestEndedBody => 'Volvé a la serie';

  @override
  String get sessionRestCountdownTitle => 'Descanso';

  @override
  String get sessionRestCountdownBody =>
      'Volvé a la serie cuando llegue a cero';

  @override
  String get pdfImportUploadTitle => 'IMPORTAR PLAN';

  @override
  String get pdfImportPrivacyNotice =>
      'Usamos IA para leer tu PDF y armar el plan. No guardamos el archivo. Subí solo los datos de tu alumno que sean necesarios.';

  @override
  String get pdfImportPickFile => 'Elegir PDF';

  @override
  String get pdfImportPickAnother => 'Elegir otro archivo';

  @override
  String get pdfImportProcess => 'PROCESAR PLAN';

  @override
  String get pdfImportProcessingTitle => 'Leyendo tu plan…';

  @override
  String get pdfImportProcessingHint =>
      'Puede tardar hasta un par de minutos. No cierres esta pantalla.';

  @override
  String get pdfImportLeaveTitle => '¿Salir mientras se lee el plan?';

  @override
  String get pdfImportLeaveBody =>
      'Este intento ya cuenta en tu cupo aunque salgas.';

  @override
  String get pdfImportLeaveConfirm => 'Salir';

  @override
  String get pdfImportRetry => 'Reintentar';

  @override
  String get pdfImportErrorTooBig =>
      'El archivo pesa más de 5 MB. Elegí uno más liviano.';

  @override
  String get pdfImportErrorInternal =>
      'No pudimos leer el plan. Probá de nuevo en un rato.';

  @override
  String pdfImportReadSummary(int days, int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days días',
      one: '1 día',
    );
    String _temp1 = intl.Intl.pluralLogic(
      weeks,
      locale: localeName,
      other: '$weeks semanas',
      one: '1 semana',
    );
    return 'Leímos $_temp0 y $_temp1.';
  }

  @override
  String get pdfImportErrorNotPdf => 'El archivo no es un PDF válido.';

  @override
  String get pdfImportErrorTooManyPages =>
      'El PDF tiene más de 20 páginas. Elegí uno más corto.';

  @override
  String get pdfImportErrorEncrypted =>
      'El PDF tiene contraseña. Exportalo sin contraseña y elegilo de nuevo.';

  @override
  String get pdfImportErrorFileUnknown =>
      'No pudimos usar este archivo. Probá con otro.';

  @override
  String pdfImportErrorQuotaWeek(String date, String time) {
    return 'Usaste todas las importaciones de esta semana. Se renueva el $date a las $time.';
  }

  @override
  String pdfImportErrorQuotaDay(String date, String time) {
    return 'Usaste todas las importaciones de hoy. Se renueva el $date a las $time.';
  }

  @override
  String get pdfImportErrorQuotaUnknown =>
      'Usaste todas las importaciones disponibles por ahora.';

  @override
  String get pdfImportErrorTimeout =>
      'La lectura tardó demasiado. Probá de nuevo; si el PDF es largo, probá con menos páginas.';

  @override
  String get pdfImportErrorInvalidPlan =>
      'Leímos el PDF pero no pudimos armar el plan. Este intento ya contó en tu cupo.';

  @override
  String get pdfImportErrorDisabled =>
      'Importar de PDF no está disponible para tu cuenta.';

  @override
  String get pdfImportErrorUnavailable =>
      'Importar de PDF no está disponible por un problema nuestro. No se descontó de tu cupo.';

  @override
  String get pdfImportErrorNotTrainer =>
      'Solo los entrenadores pueden importar planes.';

  @override
  String get pdfImportErrorSignedOut =>
      'Tu sesión se cerró. Volvé a iniciar sesión.';

  @override
  String get pdfImportCta => 'IMPORTAR DE PDF';

  @override
  String pdfImportQuotaRemaining(int week, int day) {
    return 'Te quedan $week esta semana y $day hoy.';
  }
}
