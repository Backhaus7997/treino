// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppL10nEs extends AppL10n {
  AppL10nEs([String locale = 'es']) : super(locale);

  @override
  String get homeAthleteFirstRunTitle => 'Arrancá tu entrenamiento';

  @override
  String get homeAthleteFirstRunBody =>
      'Creá tu primera rutina o buscá un entrenador para empezar.';

  @override
  String get homeAthleteFirstRunCreateCta => 'CREAR RUTINA';

  @override
  String get homeAthleteFirstRunFindTrainerCta => 'Buscar entrenador';

  @override
  String get authSplashTagline => 'ENTRENÁ. COMPARTÍ. CRECÉ.';

  @override
  String get authWelcomeEyebrow => 'ENTRENAMIENTO · GYM · COACH';

  @override
  String get authWelcomeBody =>
      'Cargá tu rutina, ejecutá los sets, seguí a tus pibes y encontrá un coach cerca tuyo.';

  @override
  String get authWelcomeCta => 'EMPEZAR';

  @override
  String get authWelcomeHaveAccount => 'Ya tengo cuenta';

  @override
  String get authWelcomeSignIn => 'Iniciar sesión';

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
  String get authTrainerInquiryDialogTitle => 'Acceso de entrenador';

  @override
  String get authTrainerInquiryDialogBody =>
      'Para alta de entrenador, escribinos a equipo@treino.app';

  @override
  String get authTrainerInquiryDialogClose => 'Cerrar';

  @override
  String get authTermsPlaceholder => 'Próximamente';

  @override
  String get authGoogleLabel => 'GOOGLE';

  @override
  String get authAppleLabel => 'APPLE';

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
  String get coachCtaProximamente => 'Próximamente — Etapa 3';

  @override
  String get coachLocationSheetTitle => 'Permitir ubicación';

  @override
  String get coachLocationSheetBody =>
      'TREINO usa tu ubicación para mostrarte entrenadores cerca tuyo. Tu ubicación no es visible para otros usuarios.';

  @override
  String get coachLocationSheetAccept => 'ACEPTAR';

  @override
  String get coachLocationSheetDeny => 'Ahora no';

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
  String get agendaButtonLabel => 'VER AGENDA DEL PF';

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
  String get agendaBookingCancelledByCoach =>
      'Reserva cancelada por el entrenador.';

  @override
  String get agendaSlotFreeLabel => 'Disponible';

  @override
  String get agendaSlotBlockedLabel => 'Bloqueado';

  @override
  String agendaSlotBookedByLabel(String athleteName) {
    return 'Reservado por $athleteName';
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
  String get workoutHistorialHeading => 'HISTORIAL';

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
  String get workoutSelfEditorPermissionDenied =>
      'No tenés permisos para hacer esto. Recargá la app.';

  @override
  String get workoutEditStubToast =>
      'Pronto vas a poder editar el contenido. Por ahora podés archivar y crear de nuevo.';

  @override
  String get workoutSelfEditorCapReached =>
      'Llegaste al máximo de 10 rutinas activas.';

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
  String get workoutSplitFallback => 'Sin split';

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
      '. Vamos a eliminar tu cuenta, tu perfil, tu historial de entrenamientos y tu foto. Tus posts van a quedar como \"Usuario eliminado\".';

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
  String get dashboardInvitarAlumnoLabel => '+ INVITAR ALUMNO';

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
  String get dashboardSinTurnosProximos =>
      'No tenés turnos próximos confirmados.';

  @override
  String get dashboardNadieEntreno => 'Nadie entrenó hoy todavía.';

  @override
  String get dashboardErrorActividad =>
      'No pudimos cargar la actividad de hoy.';

  @override
  String get dashboardSinCobros => 'Sin cobros pendientes.';

  @override
  String get dashboardErrorCobros => 'No pudimos cargar los cobros.';

  @override
  String get dashboardHolaSinNombre => 'HOLA';

  @override
  String get dashboardInvitarProximamente => 'Invitar alumno — próximamente.';

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
  String get profileCuentaSolicitudesTitle => 'Solicitudes de amistad';

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
    return '$count activas';
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
      'Cuando tengas un vínculo activo con un PF, vas a poder chatear desde acá.';

  @override
  String get chatListError => 'No pudimos cargar tus mensajes.';

  @override
  String get chatListRetryLabel => 'Reintentar';

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
  String get routineEditorSlotMenuReplace => 'Cambiar ejercicio';

  @override
  String get routineEditorSlotMenuMoveUp => 'Subir';

  @override
  String get routineEditorSlotMenuMoveDown => 'Bajar';

  @override
  String get routineEditorSlotMenuRemove => 'Eliminar';

  @override
  String get routineEditorRestLabel => 'Descanso';

  @override
  String get routineEditorAddSet => '+ Agregar set';

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
  String get routineDetailWeekLocked => 'SEMANA BLOQUEADA';

  @override
  String get routineDetailDayLocked => 'DÍA BLOQUEADO';

  @override
  String get routineDetailStart => 'EMPEZAR';

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
  String get feedFriendRequestsA11y => 'Solicitudes de amistad';

  @override
  String feedFriendRequestsWithCountA11y(int count) {
    return 'Solicitudes de amistad, $count pendientes';
  }

  @override
  String get feedPublishingA11y => 'Publicando…';

  @override
  String get searchUsersClearA11y => 'Limpiar búsqueda';

  @override
  String get publicProfileMessageDisabledA11y => 'Mensaje (próximamente)';

  @override
  String a11yAvatarLabel(String name) {
    return 'Foto de perfil de $name';
  }

  @override
  String get a11yAvatarLabelGeneric => 'Foto de perfil';

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
  String get routineEditorDeleteDayA11y => 'Eliminar día';

  @override
  String get routineEditorEditDayNameA11y => 'Editar nombre del día';

  @override
  String get athleteDetailEditPlanA11y => 'Editar plan';

  @override
  String get athleteDetailDeletePlanA11y => 'Eliminar plan';

  @override
  String get coachMapDisabledOnlineA11y => 'Mapa, no disponible en modo Online';

  @override
  String get commonCancel => 'Cancelar';

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
  String get coachHubDashboardAcceptSuccess => 'Vínculo aceptado.';

  @override
  String get coachHubDashboardAcceptError => 'No pudimos aceptar el vínculo.';

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
  String get coachHubAlumnosFilterAll => 'Todos';

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
  String get coachHubAlumnosStatusPaused => 'Pausado';

  @override
  String get coachHubAlumnosStatusInactive => 'Inactivo';

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
  String get coachHubAlumnoDetailArchivosTitle => 'Archivos privados';

  @override
  String get coachHubAlumnoDetailArchivosSubtitle =>
      'PDFs y fotos que subes sobre este alumno. Solo tú los ves.';

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
  String get feedLoadError => 'No pudimos cargar tu feed. Inténtalo de nuevo.';

  @override
  String get createPostLoadError =>
      'No pudimos abrir el editor. Inténtalo de nuevo.';

  @override
  String get insightsLoadError =>
      'No pudimos cargar tus insights. Inténtalo de nuevo.';

  @override
  String get profileLoadError =>
      'No pudimos cargar tu perfil. Inténtalo de nuevo.';

  @override
  String get sessionDetailNoSets => 'Esta sesión no tiene sets registrados.';

  @override
  String get sessionLogSetError =>
      'No pudimos guardar la serie. Inténtalo de nuevo.';

  @override
  String get sessionFinishError =>
      'No pudimos finalizar la sesión. Inténtalo de nuevo.';

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
  String get feedPostPublishedSuccess => 'Post publicado.';

  @override
  String get feedRequestSentSuccess => 'Solicitud enviada.';

  @override
  String get feedRequestAcceptedSuccess => 'Ahora son amigos.';

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
  String get progressionMetricPr => 'PR';

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
  String get progressionSinglePointHint =>
      'Necesitas al menos 2 sesiones para ver la evolución.';

  @override
  String get progressionEmptyExercise => 'Sin datos para este ejercicio.';

  @override
  String get progressionEmpty => 'Sin registros de series todavía.';

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
  String dashboardSummaryLine(int sessions, int paraRevisar, int pagos) {
    return 'Tenés $sessions sesiones hoy, $paraRevisar para revisar, $pagos pagos pendientes';
  }

  @override
  String get dashboardQuickActionNuevoAlumno => '+ Nuevo alumno';

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
  String dashboardInactivosSharingNote(int sharing, int total) {
    return '$sharing de $total con datos compartidos';
  }

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
}

/// The translations for Spanish Castilian, as used in Argentina (`es_AR`).
class AppL10nEsAr extends AppL10nEs {
  AppL10nEsAr() : super('es_AR');

  @override
  String get homeAthleteFirstRunTitle => 'Arrancá tu entrenamiento';

  @override
  String get homeAthleteFirstRunBody =>
      'Creá tu primera rutina o buscá un entrenador para empezar.';

  @override
  String get homeAthleteFirstRunCreateCta => 'CREAR RUTINA';

  @override
  String get homeAthleteFirstRunFindTrainerCta => 'Buscar entrenador';

  @override
  String get authSplashTagline => 'ENTRENÁ. COMPARTÍ. CRECÉ.';

  @override
  String get authWelcomeEyebrow => 'ENTRENAMIENTO · GYM · COACH';

  @override
  String get authWelcomeBody =>
      'Cargá tu rutina, ejecutá los sets, seguí a tus pibes y encontrá un coach cerca tuyo.';

  @override
  String get authWelcomeCta => 'EMPEZAR';

  @override
  String get authWelcomeHaveAccount => 'Ya tengo cuenta';

  @override
  String get authWelcomeSignIn => 'Iniciar sesión';

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
  String get authTrainerInquiryDialogTitle => 'Acceso de entrenador';

  @override
  String get authTrainerInquiryDialogBody =>
      'Para alta de entrenador, escribinos a equipo@treino.app';

  @override
  String get authTrainerInquiryDialogClose => 'Cerrar';

  @override
  String get authTermsPlaceholder => 'Próximamente';

  @override
  String get authGoogleLabel => 'GOOGLE';

  @override
  String get authAppleLabel => 'APPLE';

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
  String get coachCtaProximamente => 'Próximamente — Etapa 3';

  @override
  String get coachLocationSheetTitle => 'Permitir ubicación';

  @override
  String get coachLocationSheetBody =>
      'TREINO usa tu ubicación para mostrarte entrenadores cerca tuyo. Tu ubicación no es visible para otros usuarios.';

  @override
  String get coachLocationSheetAccept => 'ACEPTAR';

  @override
  String get coachLocationSheetDeny => 'Ahora no';

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
  String get agendaButtonLabel => 'VER AGENDA DEL PF';

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
  String get agendaBookingCancelledByCoach =>
      'Reserva cancelada por el entrenador.';

  @override
  String get agendaSlotFreeLabel => 'Disponible';

  @override
  String get agendaSlotBlockedLabel => 'Bloqueado';

  @override
  String agendaSlotBookedByLabel(String athleteName) {
    return 'Reservado por $athleteName';
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
  String get workoutHistorialHeading => 'HISTORIAL';

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
  String get workoutSelfEditorPermissionDenied =>
      'No tenés permisos para hacer esto. Recargá la app.';

  @override
  String get workoutEditStubToast =>
      'Pronto vas a poder editar el contenido. Por ahora podés archivar y crear de nuevo.';

  @override
  String get workoutSelfEditorCapReached =>
      'Llegaste al máximo de 10 rutinas activas.';

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
  String get workoutSplitFallback => 'Sin split';

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
      '. Vamos a eliminar tu cuenta, tu perfil, tu historial de entrenamientos y tu foto. Tus posts van a quedar como \"Usuario eliminado\".';

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
  String get dashboardInvitarAlumnoLabel => '+ INVITAR ALUMNO';

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
  String get dashboardSinTurnosProximos =>
      'No tenés turnos próximos confirmados.';

  @override
  String get dashboardNadieEntreno => 'Nadie entrenó hoy todavía.';

  @override
  String get dashboardErrorActividad =>
      'No pudimos cargar la actividad de hoy.';

  @override
  String get dashboardSinCobros => 'Sin cobros pendientes.';

  @override
  String get dashboardErrorCobros => 'No pudimos cargar los cobros.';

  @override
  String get dashboardHolaSinNombre => 'HOLA';

  @override
  String get dashboardInvitarProximamente => 'Invitar alumno — próximamente.';

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
  String get profileCuentaSolicitudesTitle => 'Solicitudes de amistad';

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
    return '$count activas';
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
      'Cuando tengas un vínculo activo con un PF, vas a poder chatear desde acá.';

  @override
  String get chatListError => 'No pudimos cargar tus mensajes.';

  @override
  String get chatListRetryLabel => 'Reintentar';

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
  String get routineEditorSlotMenuReplace => 'Cambiar ejercicio';

  @override
  String get routineEditorSlotMenuMoveUp => 'Subir';

  @override
  String get routineEditorSlotMenuMoveDown => 'Bajar';

  @override
  String get routineEditorSlotMenuRemove => 'Eliminar';

  @override
  String get routineEditorRestLabel => 'Descanso';

  @override
  String get routineEditorAddSet => '+ Agregar set';

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
  String get routineDetailWeekLocked => 'SEMANA BLOQUEADA';

  @override
  String get routineDetailDayLocked => 'DÍA BLOQUEADO';

  @override
  String get routineDetailStart => 'EMPEZAR';

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
  String get feedFriendRequestsA11y => 'Solicitudes de amistad';

  @override
  String feedFriendRequestsWithCountA11y(int count) {
    return 'Solicitudes de amistad, $count pendientes';
  }

  @override
  String get feedPublishingA11y => 'Publicando…';

  @override
  String get searchUsersClearA11y => 'Limpiar búsqueda';

  @override
  String get publicProfileMessageDisabledA11y => 'Mensaje (próximamente)';

  @override
  String a11yAvatarLabel(String name) {
    return 'Foto de perfil de $name';
  }

  @override
  String get a11yAvatarLabelGeneric => 'Foto de perfil';

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
  String get routineEditorDeleteDayA11y => 'Eliminar día';

  @override
  String get routineEditorEditDayNameA11y => 'Editar nombre del día';

  @override
  String get athleteDetailEditPlanA11y => 'Editar plan';

  @override
  String get athleteDetailDeletePlanA11y => 'Eliminar plan';

  @override
  String get coachMapDisabledOnlineA11y => 'Mapa, no disponible en modo Online';

  @override
  String get commonCancel => 'Cancelar';

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
  String get coachHubDashboardAcceptSuccess => 'Vínculo aceptado.';

  @override
  String get coachHubDashboardAcceptError => 'No pudimos aceptar el vínculo.';

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
  String get coachHubAlumnosFilterAll => 'Todos';

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
  String get coachHubAlumnosStatusPaused => 'Pausado';

  @override
  String get coachHubAlumnosStatusInactive => 'Inactivo';

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
  String get coachHubAlumnoDetailArchivosTitle => 'Archivos privados';

  @override
  String get coachHubAlumnoDetailArchivosSubtitle =>
      'PDFs y fotos que subís sobre este alumno. Solo vos los ves.';

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
  String get feedLoadError => 'No pudimos cargar tu feed. Probá de nuevo.';

  @override
  String get createPostLoadError =>
      'No pudimos abrir el editor. Probá de nuevo.';

  @override
  String get insightsLoadError =>
      'No pudimos cargar tus insights. Probá de nuevo.';

  @override
  String get profileLoadError => 'No pudimos cargar tu perfil. Probá de nuevo.';

  @override
  String get sessionDetailNoSets => 'Esta sesión no tiene sets registrados.';

  @override
  String get sessionLogSetError => 'No pudimos guardar la serie. Reintentá.';

  @override
  String get sessionFinishError =>
      'No pudimos finalizar la sesión. Probá de nuevo.';

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
  String get feedPostPublishedSuccess => 'Post publicado.';

  @override
  String get feedRequestSentSuccess => 'Solicitud enviada.';

  @override
  String get feedRequestAcceptedSuccess => 'Ahora son amigos.';

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
  String get progressionMetricPr => 'PR';

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
  String get progressionSinglePointHint =>
      'Necesitás al menos 2 sesiones para ver la evolución.';

  @override
  String get progressionEmptyExercise => 'Sin datos para este ejercicio.';

  @override
  String get progressionEmpty => 'Sin registros de series todavía.';

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
  String dashboardSummaryLine(int sessions, int paraRevisar, int pagos) {
    return 'Tenés $sessions sesiones hoy, $paraRevisar para revisar, $pagos pagos pendientes';
  }

  @override
  String get dashboardQuickActionNuevoAlumno => '+ Nuevo alumno';

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
  String dashboardInactivosSharingNote(int sharing, int total) {
    return '$sharing de $total con datos compartidos';
  }

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
}
