// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get notFoundTitle => '';

  @override
  String get notFoundBody => '';

  @override
  String get notFoundCta => '';

  @override
  String get homeAthleteFirstRunTitle => 'Start training';

  @override
  String get homeAthleteFirstRunBody =>
      'Create your first routine or find a trainer to get started.';

  @override
  String get homeAthleteFirstRunCreateCta => 'CREATE ROUTINE';

  @override
  String get homeAthleteFirstRunFindTrainerCta => 'Find a trainer';

  @override
  String get homeEstaSemanaTitle => 'THIS WEEK';

  @override
  String get homeEstaSemanaLoadError => 'We couldn\'t load your insights.';

  @override
  String get homeEstaSemanaHeaderPill => 'CURRENT STREAK';

  @override
  String get homeEstaSemanaHeaderPillEmpty => 'FIRST STEP';

  @override
  String homeEstaSemanaWeekMonth(int week, String month) {
    return 'WK $week · $month';
  }

  @override
  String homeEstaSemanaStreakUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'DAYS',
      one: 'DAY',
    );
    return '$_temp0';
  }

  @override
  String get homeEstaSemanaStreakSubtextTrained =>
      'Don\'t break the streak — you trained today.';

  @override
  String get homeEstaSemanaStreakSubtextPending =>
      'Don\'t break the streak — train today.';

  @override
  String get homeEstaSemanaPeriodWeek => 'WEEK';

  @override
  String get homeEstaSemanaPeriodMonth => 'MONTH';

  @override
  String homeEstaSemanaPeriodUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'workouts',
      one: 'workout',
    );
    return '$_temp0';
  }

  @override
  String get homeEstaSemanaEmptyTitle => 'YOUR STREAK\nSTARTS HERE';

  @override
  String get homeEstaSemanaEmptyBody =>
      'Every workout feeds your streak. Do your first one and start building your progress.';

  @override
  String get homeEstaSemanaEmptyCta => 'EXPLORE ROUTINES  →';

  @override
  String get homeEstaSemanaInsightsCta => 'VIEW INSIGHTS  →';

  @override
  String get homeEstaSemanaHeaderPillResume => 'BACK AT IT';

  @override
  String get homeEstaSemanaResumeTitle => 'YOUR STREAK\nAWAITS';

  @override
  String get homeEstaSemanaResumeBody =>
      'Your history is already built. This week is still at zero — get back in today and keep adding progress.';

  @override
  String get homeEstaSemanaResumeCta => 'BACK TO TRAINING  →';

  @override
  String get authSplashTagline => '';

  @override
  String get authBrandHeadline1Light => 'STOP ';

  @override
  String get authBrandHeadline1Bold => 'GUESSING.';

  @override
  String get authBrandHeadline2Light => 'START ';

  @override
  String get authBrandHeadline2Bold => 'PROGRESSING.';

  @override
  String get authWelcomeEyebrow => '';

  @override
  String get authWelcomeBody =>
      'Your routine, your sets and your loads in one place. With a coach behind you if you want one.';

  @override
  String get authWelcomeCta => '';

  @override
  String get authWelcomeHaveAccount => '';

  @override
  String get authWelcomeSignIn => '';

  @override
  String get authLoginTitle => '';

  @override
  String get authLoginSubtitle => '';

  @override
  String get authLoginEmailHint => '';

  @override
  String get authLoginForgot => '';

  @override
  String get authLoginCta => '';

  @override
  String get authLoginContinueWith => '';

  @override
  String get authLoginNoAccount => '';

  @override
  String get authLoginRegisterLink => '';

  @override
  String get authLoginTrainerCardTitle => '';

  @override
  String get authLoginTrainerCardSubtitle => '';

  @override
  String get authRegisterAppbar => '';

  @override
  String get authRegisterTitle => '';

  @override
  String get authRegisterSubtitle => '';

  @override
  String get authRegisterEmailLabel => '';

  @override
  String get authRegisterPasswordLabel => '';

  @override
  String get authRegisterConfirmPasswordLabel => '';

  @override
  String get authRegisterCta => '';

  @override
  String get authRegisterDividerOr => '';

  @override
  String get authForgotTitle => '';

  @override
  String get authForgotBody => '';

  @override
  String get authForgotEmailLabel => '';

  @override
  String get authForgotEmailHint => '';

  @override
  String get authForgotCta => '';

  @override
  String get authForgotSuccess => '';

  @override
  String get authForgotBackToLogin => '';

  @override
  String get authForgotSpamHint => '';

  @override
  String get authForgotResendCta => '';

  @override
  String authForgotResendIn(int seconds) {
    return '';
  }

  @override
  String get authForgotEditEmail => '';

  @override
  String get authTrainerInquiryDialogTitle => '';

  @override
  String get authTrainerInquiryDialogBody => '';

  @override
  String get authTrainerInquiryDialogClose => '';

  @override
  String get authTermsPlaceholder => '';

  @override
  String get authGoogleLabel => '';

  @override
  String get authAppleLabel => '';

  @override
  String get authComingSoonTooltip => '';

  @override
  String get authValidationEmailInvalid => '';

  @override
  String get authValidationPasswordRules => '';

  @override
  String get authValidationPasswordMismatch => '';

  @override
  String get authProfileSignOut => '';

  @override
  String get coachAppBarTitle => '';

  @override
  String get coachLoadingLabel => '';

  @override
  String get coachErrorLabel => '';

  @override
  String get coachRetryLabel => 'Retry';

  @override
  String get coachEmptyLabel => '';

  @override
  String get coachMapToggleLabel => '';

  @override
  String get coachMapProximamente => '';

  @override
  String get coachDistanceUnknown => '';

  @override
  String get coachMonthlyRateUnit => '';

  @override
  String get coachSpecialtyAll => '';

  @override
  String get coachStatsReviewsLabel => '';

  @override
  String get coachStatsExperienceLabel => '';

  @override
  String get coachStatsStudentsLabel => '';

  @override
  String get coachStatsPlaceholder => '';

  @override
  String get coachProfileLoadingLabel => '';

  @override
  String get coachProfileErrorLabel => '';

  @override
  String get coachProfileNotFoundLabel => '';

  @override
  String get coachProfileBioEmpty => '';

  @override
  String get coachProfileRateLabel => '';

  @override
  String get coachCtaLabel => '';

  @override
  String get coachCtaProximamente => '';

  @override
  String get coachLocationSheetTitle => '';

  @override
  String get coachLocationSheetBody => '';

  @override
  String get coachLocationSheetAccept => '';

  @override
  String get coachLocationSheetDeny => '';

  @override
  String get coachMiPlanTitle => '';

  @override
  String get coachMiPlanEmpty => '';

  @override
  String get coachMiPlanError => '';

  @override
  String get coachMiPlanFinalizado => '';

  @override
  String get coachMiPlanCurrent => '';

  @override
  String get coachAssignedByPrefix => '';

  @override
  String get coachAssignedByLoading => '';

  @override
  String get coachAssignedByError => '';

  @override
  String get coachCreatePlanCta => '';

  @override
  String get coachCreatePlanSuccess => '';

  @override
  String get coachCreatePlanError => '';

  @override
  String get coachAthleteDetailNoPlans => '';

  @override
  String get coachEditorTitle => '';

  @override
  String get coachEditorEditTitle => '';

  @override
  String get coachEditorNameLabel => '';

  @override
  String get coachEditorSplitLabel => '';

  @override
  String get coachEditorAddDay => '';

  @override
  String get coachEditorAddSlot => '';

  @override
  String get coachEditorAddSuperset => '';

  @override
  String get coachEditorSubmit => '';

  @override
  String get coachEditorUpdateLabel => '';

  @override
  String get coachUpdatePlanSuccess => '';

  @override
  String get coachExercisePicker => '';

  @override
  String get agendaButtonLabel => '';

  @override
  String get agendaScreenTitle => '';

  @override
  String get agendaEmptyAvailability => '';

  @override
  String get agendaBookingConfirmTitle => '';

  @override
  String agendaBookingConfirmBody(String date, String time) {
    return '';
  }

  @override
  String get agendaBookingConfirmCta => '';

  @override
  String get agendaBookingCancel => '';

  @override
  String get agendaBookingSuccess => '';

  @override
  String get agendaBookingRaceError => '';

  @override
  String get agendaCancellationConfirmTitle => '';

  @override
  String get agendaCancellationConfirmBody => '';

  @override
  String get agendaCancellationConfirmCta => '';

  @override
  String get agendaCancellationKeep => '';

  @override
  String get agendaCancellationSuccess => '';

  @override
  String get agendaCancellationTooLate => '';

  @override
  String get agendaUpcomingAppointmentsHeading => '';

  @override
  String get agendaPastAppointmentsHeading => '';

  @override
  String get agendaGenericError => '';

  @override
  String get agendaTrainerEmptyAvailability => '';

  @override
  String get agendaConfigureHoursCta => '';

  @override
  String get agendaMyWorkingHoursHeading => '';

  @override
  String get agendaAddRuleCta => '';

  @override
  String get agendaBlockDayCta => '';

  @override
  String get agendaEditorTitle => '';

  @override
  String get agendaRuleDeleteConfirm => '';

  @override
  String get agendaRuleInvalidWindow => '';

  @override
  String get agendaBookingCancelledByCoach => '';

  @override
  String get agendaBlockedDayTitle => '';

  @override
  String agendaBlockedDayBodySingle(String date) {
    return '';
  }

  @override
  String agendaBlockedDayBodyRecurring(int count) {
    return '';
  }

  @override
  String get agendaBlockedDayConfirm => '';

  @override
  String get agendaSlotFreeLabel => '';

  @override
  String get agendaSlotBlockedLabel => '';

  @override
  String agendaSlotBookedByLabel(String athleteName) {
    return '';
  }

  @override
  String get agendaCobrarCta => 'CHARGE';

  @override
  String get agendaCobradoLabel => 'Charged';

  @override
  String get agendaCobrarMontoLabel => 'AMOUNT (ARS)';

  @override
  String get agendaCobrarConceptoLabel => 'CONCEPT';

  @override
  String get agendaCobrarVenceElLabel => 'DUE DATE (OPTIONAL)';

  @override
  String get agendaCobrarVenceElHint => 'No due date';

  @override
  String get agendaCobrarVenceElQuitar => 'Remove due date';

  @override
  String get agendaCobrarConfirmCta => 'CONFIRM CHARGE';

  @override
  String get agendaCobrarCompletaCampos => 'Fill in all fields.';

  @override
  String get agendaCobrarMontoInvalido => 'Enter a valid amount.';

  @override
  String get agendaCobrarSuccess => 'Session charged.';

  @override
  String get agendaCobrarError =>
      'We couldn\'t register the charge. Try again.';

  @override
  String agendaCobrarConceptoDefault(String date) {
    return 'Session $date';
  }

  @override
  String agendaCobrarTarifaReferencia(String amount) {
    return 'Reference rate: $amount';
  }

  @override
  String get workoutSummaryHeaderCompleted => '';

  @override
  String get workoutSummaryHeaderAbandoned => '';

  @override
  String get workoutStatDuration => '';

  @override
  String get workoutStatVolume => '';

  @override
  String get workoutStatDurationMin => '';

  @override
  String get workoutStatVolumeKg => '';

  @override
  String get workoutStatSets => '';

  @override
  String get workoutStatPrsToday => '';

  @override
  String get workoutStatPrsTodayStub => '';

  @override
  String get workoutPrsSectionTitle => '';

  @override
  String get workoutPrsPlaceholder => '';

  @override
  String get workoutButtonDone => '';

  @override
  String get workoutButtonShare => '';

  @override
  String get workoutButtonRetry => '';

  @override
  String get workoutButtonBackToWorkout => '';

  @override
  String get workoutNotFoundTitle => '';

  @override
  String get workoutErrorTitle => '';

  @override
  String get workoutSnackShareSuccess => '';

  @override
  String get workoutSnackShareError => '';

  @override
  String get workoutPostAutoCompleteText => '';

  @override
  String get wellbeingCheckInTitle => 'HOW DID YOU FEEL?';

  @override
  String get wellbeingCheckInOptional => 'Optional. You can skip it.';

  @override
  String get wellbeingFeelingVeryBad => 'Very bad';

  @override
  String get wellbeingFeelingBad => 'Bad';

  @override
  String get wellbeingFeelingNeutral => 'OK';

  @override
  String get wellbeingFeelingGood => 'Good';

  @override
  String get wellbeingFeelingGreat => 'Great';

  @override
  String get wellbeingPainQuestion => 'Any pain or discomfort?';

  @override
  String get wellbeingPainYes => 'YES';

  @override
  String get wellbeingPainNo => 'NO';

  @override
  String get wellbeingPainAreasQuestion => 'Where?';

  @override
  String get wellbeingPainAreasHint => 'You can pick more than one.';

  @override
  String get wellbeingNoteLabel => 'Note (optional)';

  @override
  String get wellbeingNoteHint => 'Anything you want to remember about today';

  @override
  String get wellbeingMedicalDisclaimer =>
      'If the pain persists, see a health professional.';

  @override
  String get wellbeingSaveButton => 'SAVE';

  @override
  String get wellbeingSkipButton => 'NOT NOW';

  @override
  String get wellbeingSavedLabel => 'LOGGED';

  @override
  String get wellbeingEditButton => 'Edit';

  @override
  String get wellbeingSaveError =>
      'We couldn\'t save your check-in. Try again.';

  @override
  String get shareWorkoutComposerTitle => 'SHARE WORKOUT';

  @override
  String get shareWorkoutComposerHint => 'How was your workout?';

  @override
  String get shareWorkoutComposerPublish => 'PUBLISH';

  @override
  String get shareWorkoutComposerAddPhoto => 'ADD PHOTO';

  @override
  String get shareWorkoutComposerRemovePhoto => 'Remove photo';

  @override
  String get shareWorkoutComposerPhotoError =>
      'We couldn\'t use that photo. Try another one.';

  @override
  String get shareWorkoutComposerPreviewTitle => 'YOUR WORKOUT';

  @override
  String get postCardWorkoutDetailShow => 'SHOW DETAIL';

  @override
  String get postCardWorkoutDetailHide => 'HIDE DETAIL';

  @override
  String postCardWorkoutDetailTruncated(int count) {
    return 'Showing the first $count exercises.';
  }

  @override
  String get workoutHistorialHeading => '';

  @override
  String get workoutHistorialEmptyMessage => '';

  @override
  String get workoutHistorialEmptyCta => '';

  @override
  String get workoutHistorialErrorMessage => '';

  @override
  String get workoutHistorialErrorRetry => '';

  @override
  String get workoutHistorialCardKgSuffix => '';

  @override
  String get workoutHistorialCardMinSuffix => '';

  @override
  String get workoutHistorialShowLess => '';

  @override
  String workoutHistorialShowMore(int n) {
    return '';
  }

  @override
  String get workoutHistorialSeeAll => '';

  @override
  String get workoutHistorialFullTitle => '';

  @override
  String get workoutDetailStatDuration => '';

  @override
  String get workoutDetailStatSets => '';

  @override
  String get workoutDetailStatVolume => '';

  @override
  String get workoutDetailStatDurationMin => '';

  @override
  String get workoutDetailStatVolumeKg => '';

  @override
  String get workoutDetailStatPrsToday => '';

  @override
  String get workoutDetailPrBadge => '';

  @override
  String get workoutSelfEditorTitle => '';

  @override
  String get workoutSelfEditorEditTitle => '';

  @override
  String get workoutSelfEditorSubmitLabel => '';

  @override
  String get workoutSelfEditorUpdateLabel => '';

  @override
  String get workoutSelfEditorSuccess => '';

  @override
  String get workoutSelfEditorUpdateSuccess => '';

  @override
  String get workoutSelfEditorNotFound => '';

  @override
  String get workoutSelfEditorError => '';

  @override
  String get workoutDiscardError => '';

  @override
  String get workoutSelfEditorPermissionDenied => '';

  @override
  String get workoutEditStubToast => '';

  @override
  String get workoutSelfEditorCapReached => '';

  @override
  String get workoutTabYours => 'YOUR WORKOUT';

  @override
  String get workoutTabExplore => 'EXPLORE';

  @override
  String get workoutExploreEmptyAll => 'No routines yet.';

  @override
  String get workoutExploreEmptyLevel => 'No routines for this level.';

  @override
  String get workoutExploreLoadError =>
      'Something went wrong loading the routines.';

  @override
  String get workoutMisRutinasSectionTitle => '';

  @override
  String get workoutMisRutinasCta => '';

  @override
  String get workoutMisRutinasCtaDisabledTooltip => '';

  @override
  String get workoutMisRutinasEmptyState => '';

  @override
  String get workoutMisRutinasError => '';

  @override
  String get workoutMisRutinasErrorRetry => '';

  @override
  String get workoutMisRutinasOverflowEdit => '';

  @override
  String get workoutMisRutinasOverflowArchive => '';

  @override
  String get workoutMisRutinasOverflowMarkActive => '';

  @override
  String get workoutMisRutinasOverflowUnmarkActive => '';

  @override
  String get workoutMisRutinasActiveChip => '';

  @override
  String get workoutMisRutinasMarkActiveSuccess => '';

  @override
  String get workoutMisRutinasUnmarkActiveSuccess => '';

  @override
  String get workoutMisRutinasActiveError => '';

  @override
  String get workoutMisRutinasConfirmTitle => '';

  @override
  String get workoutMisRutinasConfirmBody => '';

  @override
  String get workoutMisRutinasConfirmCancel => '';

  @override
  String get workoutMisRutinasConfirmConfirm => '';

  @override
  String get workoutMisRutinasArchiveSuccess => '';

  @override
  String get workoutMisRutinasArchiveError => '';

  @override
  String get workoutRutinasCoachChip => 'FROM YOUR COACH';

  @override
  String get workoutPlantillasTrainerChip => 'TRAINER';

  @override
  String get templateRatingsTitle => 'RATINGS';

  @override
  String get templateRatingsNoneYet =>
      'Nobody has rated this routine yet. Be the first!';

  @override
  String templateRatingsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ratings',
      one: '1 rating',
    );
    return '$_temp0';
  }

  @override
  String get templateRatingsMineEmpty => 'What did you think?';

  @override
  String get templateRatingsMineLabel => 'Your rating';

  @override
  String get templateRatingsRateCta => 'RATE';

  @override
  String get templateRatingsEditCta => 'EDIT';

  @override
  String get templateRatingsEmpty => 'No comments yet.';

  @override
  String get templateRatingsError => 'We couldn\'t load the comments.';

  @override
  String get templateRatingSheetTitle => 'Rate this routine';

  @override
  String get templateRatingSheetTitleEdit => 'Edit your rating';

  @override
  String get templateRatingSheetCommentHint =>
      'Tell others how this routine went (optional)';

  @override
  String get templateRatingSheetCancel => 'CANCEL';

  @override
  String get templateRatingSheetSubmit => 'SUBMIT';

  @override
  String get templateRatingSheetSuccess => 'Thanks for rating!';

  @override
  String get templateRatingSheetError => 'We couldn\'t save your rating.';

  @override
  String get workoutSplitFallback => 'Free-form routine';

  @override
  String get workoutPickerMuscleFilter => '';

  @override
  String get workoutPickerEquipmentFilter => '';

  @override
  String get workoutPickerMuscleSheetTitle => '';

  @override
  String get workoutPickerEquipmentSheetTitle => '';

  @override
  String get workoutPickerMuscleAll => '';

  @override
  String get workoutPickerEquipmentAll => '';

  @override
  String get workoutPickerEmptyFiltered => '';

  @override
  String get workoutPickerEmptyFilteredHint => '';

  @override
  String workoutPickerAddButton(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '';
  }

  @override
  String get workoutSelfEditorNameHint => '';

  @override
  String get workoutPickerSheetClear => '';

  @override
  String get workoutPickerSheetApplyAll => '';

  @override
  String workoutPickerSheetApply(int count) {
    return '';
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
  String get dashboardErrorResumen => 'We couldn\'t load the day summary.';

  @override
  String get dashboardSinTurnosProximos =>
      'No tenés turnos próximos confirmados.';

  @override
  String get dashboardNadieEntreno => 'Nadie entrenó hoy todavía.';

  @override
  String get athleteDetailSeguimientoEmpty =>
      'You haven\'t logged any follow-up for this athlete yet.';

  @override
  String get athleteDetailSeguimientoLoadError =>
      'We couldn\'t load the follow-up log.';

  @override
  String get dashboardFeedbackSheetTitle => 'Leave feedback';

  @override
  String get dashboardFeedbackPickAthlete =>
      'Who do you want to leave feedback for?';

  @override
  String get dashboardFeedbackComposerHint =>
      'Write your notes on the workout…';

  @override
  String get dashboardFeedbackSave => 'Save';

  @override
  String get dashboardFeedbackSaved => 'Feedback saved';

  @override
  String get dashboardFeedbackSaveError =>
      'We couldn\'t save the feedback. Please try again.';

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
  String get a11yDashboardAvatarButton => 'Edit your professional profile';

  @override
  String get dashboardSolicitudesPendientesEmpty =>
      'You have no pending requests.';

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
  String get chatListTitle => '';

  @override
  String get chatListDeletedUser => '';

  @override
  String get chatListStartConversation => '';

  @override
  String get chatListEmptyTitle => '';

  @override
  String get chatListEmptyBody => '';

  @override
  String get chatListError => '';

  @override
  String get chatListRetryLabel => '';

  @override
  String get chatRelativeJustNow => '';

  @override
  String chatRelativeMinutes(int minutes) {
    return '';
  }

  @override
  String chatRelativeHours(int hours) {
    return '';
  }

  @override
  String chatRelativeDays(int days) {
    return '';
  }

  @override
  String get chatScreenTitleFallback => '';

  @override
  String get chatScreenLoadError => '';

  @override
  String get chatScreenComposerHint => '';

  @override
  String get chatScreenSendLabel => '';

  @override
  String get chatScreenSendError => '';

  @override
  String get performanceLogTitle => 'Log assessment';

  @override
  String get performanceLogCancel => 'Cancel';

  @override
  String get performanceLogSaveCta => 'SAVE ASSESSMENT';

  @override
  String get performanceLogNoSession => 'No active session. Can\'t save.';

  @override
  String get performanceLogSaveSuccess => 'Assessment saved';

  @override
  String get performanceLogSaveError =>
      'We couldn\'t save the assessment. Try again.';

  @override
  String get performanceLogNotesHint => 'Trainer notes…';

  @override
  String get performanceLogSectionJumps => 'JUMPS (cm)';

  @override
  String get performanceLogSectionSpeed => 'SPEED (s)';

  @override
  String get performanceLogSectionStrength => 'STRENGTH 1RM (kg)';

  @override
  String get performanceLogSectionEndurance => 'ENDURANCE / OTHER';

  @override
  String get performanceLogSectionNotes => 'NOTES';

  @override
  String get performanceLogFieldCmj => 'CMJ';

  @override
  String get performanceLogFieldSquatJump => 'Squat Jump';

  @override
  String get performanceLogFieldAbalakov => 'Abalakov';

  @override
  String get performanceLogFieldBroadJump => 'Broad jump';

  @override
  String get performanceLogFieldSprint10 => 'Sprint 10m';

  @override
  String get performanceLogFieldSprint20 => '20m';

  @override
  String get performanceLogFieldSprint30 => '30m';

  @override
  String get performanceLogFieldSprint40 => '40m';

  @override
  String get performanceLogFieldSquat1rm => 'Squat';

  @override
  String get performanceLogFieldBenchPress => 'Bench press';

  @override
  String get performanceLogFieldDeadlift => 'Deadlift';

  @override
  String get performanceLogFieldOverheadPress => 'Overhead press';

  @override
  String get performanceLogFieldPullUp => 'Weighted pull-up';

  @override
  String get performanceLogFieldVo2max => 'VO2max';

  @override
  String get performanceLogFieldCourseNavette => 'Beep test (level)';

  @override
  String get performanceLogFieldCooper => 'Cooper';

  @override
  String get performanceLogFieldSitAndReach => 'Sit-and-reach flexibility';

  @override
  String get performanceChartSectionLabel => '';

  @override
  String get performanceChartEmptyHint => '';

  @override
  String performanceChartSpanDays(int count) {
    return '';
  }

  @override
  String performanceChartSpanWeeks(int count) {
    return '';
  }

  @override
  String get performanceChartMetricCmj => '';

  @override
  String get performanceChartMetricSquatJump => '';

  @override
  String get performanceChartMetricAbalakov => '';

  @override
  String get performanceChartMetricBroadJump => '';

  @override
  String get performanceChartMetricSprint10 => '';

  @override
  String get performanceChartMetricSprint20 => '';

  @override
  String get performanceChartMetricSprint30 => '';

  @override
  String get performanceChartMetricSprint40 => '';

  @override
  String get performanceChartMetricSquat1rm => '';

  @override
  String get performanceChartMetricBench1rm => '';

  @override
  String get performanceChartMetricDeadlift1rm => '';

  @override
  String get performanceChartMetricOverheadPress1rm => '';

  @override
  String get performanceChartMetricPullUp1rm => '';

  @override
  String get performanceChartMetricVo2max => '';

  @override
  String get performanceChartMetricCourseNavette => '';

  @override
  String get performanceChartMetricCooper => '';

  @override
  String get performanceChartMetricSitAndReach => '';

  @override
  String routineEditorDayName(int n) {
    return 'Day $n';
  }

  @override
  String get routineEditorAddExercise => 'Add exercise';

  @override
  String get routineEditorLevelLabel => 'LEVEL';

  @override
  String get routineEditorWeeksLabel => 'WEEKS';

  @override
  String get routineEditorDaysLabel => 'PLAN DAYS';

  @override
  String get routineEditorAddWeek => 'Week';

  @override
  String get routineEditorRemoveLastWeek => '';

  @override
  String get routineEditorDuplicateWeek => 'Duplicate week';

  @override
  String routineEditorWeekShort(int n) {
    return 'Wk $n';
  }

  @override
  String routineEditorInvalidWeekHint(int week, int day) {
    return 'Incomplete sets in Wk $week · Day $day';
  }

  @override
  String get routineEditorDuplicateWeekTitle => 'Duplicate week';

  @override
  String routineEditorDuplicateWeekBody(int sourceWeek, int targetWeek) {
    return '';
  }

  @override
  String get routineEditorDialogCancel => '';

  @override
  String get routineEditorDialogConfirm => '';

  @override
  String get routineEditorCopyPrescriptionTitle => 'Copy sets?';

  @override
  String routineEditorCopyPrescriptionBody(String sourceExercise) {
    return 'This exercise\'s sets will be replaced with the ones from “$sourceExercise”.';
  }

  @override
  String get routineEditorSlotMenuCopyPrevious => 'Copy sets from previous';

  @override
  String get routineEditorSlotMenuReplace => 'Change exercise';

  @override
  String get routineEditorSlotMenuMoveUp => 'Move up';

  @override
  String get routineEditorSlotMenuMoveDown => 'Move down';

  @override
  String get routineEditorSlotMenuRemove => 'Remove';

  @override
  String get routineEditorRestLabel => 'Rest';

  @override
  String get routineEditorAddSet => '+ Add set';

  @override
  String get routineEditorFillKgA11y =>
      'Apply the first set\'s weight to every set';

  @override
  String get routineEditorFillKgApplied => 'Weight applied to every set.';

  @override
  String get routineEditorFillKgEmpty =>
      'Enter the first set\'s weight so it can be applied.';

  @override
  String get routineEditorFillKgUndo => 'Undo';

  @override
  String routineEditorKgStepIncreaseA11y(String amount) {
    return 'Add $amount kilos to the weight';
  }

  @override
  String routineEditorKgStepDecreaseA11y(String amount) {
    return 'Take $amount kilos off the weight';
  }

  @override
  String get routineEditorMeasureReps => 'Reps';

  @override
  String get routineEditorMeasureTime => 'Time';

  @override
  String get routineEditorSetTypeNormal => '';

  @override
  String get routineEditorSetTypeWarmup => '';

  @override
  String get routineEditorSetTypeDrop => '';

  @override
  String get routineEditorSetTypeFailure => '';

  @override
  String get routineEditorNotesLabel => 'Note for athlete';

  @override
  String get routineEditorNotesHint => 'Technique, tempo, RIR…';

  @override
  String get exerciseNoteFromCoachTag => 'FROM COACH';

  @override
  String routineEditorIncompleteSetsFeedback(String exerciseName) {
    return '';
  }

  @override
  String get routineDetailNotFound => '';

  @override
  String get routineDetailNoDaysConfigured => '';

  @override
  String get routineDetailLoadError => '';

  @override
  String get routineDetailNoExercisesThisWeek => '';

  @override
  String get routineDetailNoExercisesThisDay => '';

  @override
  String get routineDetailStatExercises => '';

  @override
  String get routineDetailStatSets => '';

  @override
  String get routineDetailStatMinutes => '';

  @override
  String get routineDetailSuperset => '';

  @override
  String routineDetailDayLabel(int day) {
    return '';
  }

  @override
  String routineDetailWeekLabel(int week) {
    return '';
  }

  @override
  String get routineDetailPlanComplete => '';

  @override
  String get routineDetailCompleted => '';

  @override
  String get routineDetailStart => '';

  @override
  String get routineDetailRepeat => 'REPEAT';

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
  String get routineEditorWeekLabel => 'Week';

  @override
  String get routineEditorLevelSection => 'LEVEL';

  @override
  String get routineEditorWeeksSection => 'WEEKS';

  @override
  String get routineEditorDaysSection => 'PLAN DAYS';

  @override
  String get routineEditorNameHint => '';

  @override
  String get routineEditorSplitHint => '';

  @override
  String routineEditorIncompleteSetsLabel(int weekNumber) {
    return '';
  }

  @override
  String get commonBack => 'Back';

  @override
  String get commonClose => 'Close';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonProcessing => 'Processing…';

  @override
  String get commonWarning => 'Warning';

  @override
  String get chatSendingA11y => 'Sending…';

  @override
  String get feedMessagesA11y => 'Messages';

  @override
  String get feedSearchA11y => 'Search';

  @override
  String get feedCreatePostA11y => 'Create post';

  @override
  String get feedFriendRequestsA11y => 'Follower requests';

  @override
  String feedFriendRequestsWithCountA11y(int count) {
    return 'Follower requests, $count pending';
  }

  @override
  String get feedPublishingA11y => 'Publishing…';

  @override
  String get searchUsersClearA11y => 'Clear search';

  @override
  String get publicProfileMessageDisabledA11y => 'Message (coming soon)';

  @override
  String a11yAvatarLabel(String name) {
    return 'Profile photo of $name';
  }

  @override
  String a11yRankingRowButton(String name) {
    return 'View $name\'s profile';
  }

  @override
  String get a11yReactionLike => 'Like';

  @override
  String get a11yReactionFire => 'Fire';

  @override
  String get a11yReactionClap => 'Applause';

  @override
  String a11yReactionCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reactions',
      one: '1 reaction',
      zero: 'no reactions',
    );
    return '$_temp0';
  }

  @override
  String get a11yAvatarLabelGeneric => 'Profile photo';

  @override
  String get a11yHomeAvatarButton => 'View your profile';

  @override
  String homePendingRequestsA11y(int count) {
    return '$count pending requests';
  }

  @override
  String get workoutRoutineOptionsA11y => 'Routine options';

  @override
  String sessionPlayerSetCompleteA11y(int setNumber) {
    return 'Mark set $setNumber as completed';
  }

  @override
  String sessionPlayerTechniqueA11y(String exerciseName) {
    return 'View technique for $exerciseName';
  }

  @override
  String get sessionPlayerTimerStartA11y => 'Start timer';

  @override
  String get sessionPlayerRemoveSetA11y => 'Remove set';

  @override
  String get routineEditorDeleteDayA11y => 'Delete day';

  @override
  String get routineEditorEditDayNameA11y => '';

  @override
  String get athleteDetailEditPlanA11y => 'Edit plan';

  @override
  String get athleteDetailDeletePlanA11y => 'Delete plan';

  @override
  String get coachMapDisabledOnlineA11y => 'Map, unavailable in Online mode';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get publicProfileLoadErrorA11y => 'We couldn\'t load this profile.';

  @override
  String get authGenericErrorFallback =>
      'Something went wrong. Please try again.';

  @override
  String get agendaNoUpcomingSessions =>
      'Your coach hasn\'t scheduled any sessions yet.';

  @override
  String get agendaSaveError => 'We couldn\'t save. Please try again.';

  @override
  String get agendaSaveSuccess => 'Schedule saved.';

  @override
  String get coachHubSectionLoadError => 'We couldn\'t load this section.';

  @override
  String get coachHubSignOutError =>
      'We couldn\'t sign you out. Please try again.';

  @override
  String get coachHubLoginPrompt =>
      'Sign in with the same account you use on the mobile app.';

  @override
  String get coachHubLoginEmailLabel => 'Email';

  @override
  String get coachHubLoginEmailRequired => 'Enter your email';

  @override
  String get coachHubLoginEmailInvalid => 'Invalid email';

  @override
  String get coachHubLoginPasswordLabel => 'Password';

  @override
  String get coachHubLoginPasswordRequired => 'Enter your password';

  @override
  String get coachHubLoginSubmit => 'SIGN IN';

  @override
  String get coachHubLoginFooter =>
      'No account yet? Create one from the TREINO mobile app.';

  @override
  String get coachHubLoginGenericError =>
      'We couldn\'t sign you in. Please try again.';

  @override
  String get coachHubActionCancel => 'Cancel';

  @override
  String get coachHubActionConfirm => 'Confirm';

  @override
  String get coachHubActionPause => 'Pause';

  @override
  String get coachHubActionResume => 'Resume';

  @override
  String get coachHubActionTerminate => 'End';

  @override
  String get coachHubActionTerminateLink => 'End link';

  @override
  String get coachHubActionAccept => 'Accept';

  @override
  String get coachHubActionReject => 'Reject';

  @override
  String get coachHubDashboardImportPlanCta => 'IMPORT PLAN FROM EXCEL';

  @override
  String get coachHubDashboardFilterActivos => 'ACTIVE';

  @override
  String get coachHubDashboardFilterPausados => 'PAUSED';

  @override
  String get coachHubDashboardFilterHistorial => 'HISTORY';

  @override
  String get coachHubDashboardActiveHeader => 'YOUR ATHLETES';

  @override
  String get coachHubDashboardPausedHeader => 'PAUSED';

  @override
  String get coachHubDashboardHistoryHeader => 'PAST LINKS';

  @override
  String get coachHubDashboardEmptyActive => 'No active athletes yet.';

  @override
  String get coachHubDashboardEmptyPaused => 'No paused athletes.';

  @override
  String get coachHubDashboardEmptyHistory => 'No terminated links yet.';

  @override
  String coachHubDashboardPendingHeader(int count) {
    return 'PENDING REQUESTS · $count';
  }

  @override
  String get coachHubDashboardPendingContext => 'Wants to connect with you';

  @override
  String coachHubDashboardLinkedSince(String date) {
    return 'Linked since $date';
  }

  @override
  String coachHubDashboardPausedOn(String date) {
    return 'Paused on $date';
  }

  @override
  String get coachHubDashboardPausedFallback => 'Paused';

  @override
  String get coachHubDashboardPauseLinkTitle => 'Pause link';

  @override
  String get coachHubDashboardPauseLinkBody =>
      'The athlete will still see the plan but won\'t be able to log new sessions until you resume the link.';

  @override
  String get coachHubDashboardTerminateLinkTitle => 'End link';

  @override
  String get coachHubDashboardTerminateLinkBody =>
      'This action can\'t be undone. History is preserved.';

  @override
  String get coachHubDashboardResumeLinkTitle => 'Resume link';

  @override
  String coachHubDashboardResumeLinkBody(String name) {
    return 'Resume the link with $name?';
  }

  @override
  String get coachHubDashboardResumeLinkBodyFallback => 'Resume the link?';

  @override
  String get coachHubDashboardPauseLinkError => 'We couldn\'t pause the link.';

  @override
  String get coachHubDashboardTerminateLinkError =>
      'We couldn\'t end the link.';

  @override
  String get coachHubDashboardResumeLinkError =>
      'We couldn\'t resume the link.';

  @override
  String get coachHubDashboardResumePrecondition =>
      'This link is no longer available.';

  @override
  String get coachHubDashboardResumeUnavailable =>
      'Check your connection and try again.';

  @override
  String get coachHubDashboardAcceptSuccess => 'Link accepted.';

  @override
  String get coachHubDashboardAcceptError => 'We couldn\'t accept the link.';

  @override
  String get coachHubDashboardAcceptPrecondition =>
      'This request is no longer available.';

  @override
  String get coachHubDashboardAcceptUnavailable =>
      'Check your connection and try again.';

  @override
  String get coachHubDashboardRejectSuccess => 'Request rejected.';

  @override
  String get coachHubDashboardRejectError => 'We couldn\'t reject the request.';

  @override
  String get coachHubDashboardTerminationReasonDeclined =>
      'Declined by the coach';

  @override
  String get coachHubDashboardTerminationReasonByAthlete =>
      'Ended by the athlete';

  @override
  String get coachHubDashboardTerminationReasonByTrainer =>
      'Ended by the coach';

  @override
  String get coachHubDashboardTerminationReasonFallback => 'Link ended';

  @override
  String get coachHubAlumnosTitle => 'ATHLETES';

  @override
  String coachHubAlumnosSummary(int total, int active) {
    return '$total total · $active active';
  }

  @override
  String get coachHubAlumnosSearchHint => 'Search by name…';

  @override
  String get coachHubAlumnosFilterAll => 'All';

  @override
  String get coachHubAlumnosFilterActivos => 'Active';

  @override
  String get coachHubAlumnosFilterConDeuda => 'Overdue';

  @override
  String get coachHubAlumnosFilterPausados => 'Paused';

  @override
  String get coachHubAlumnosFilterInactivos => 'Inactive';

  @override
  String get coachHubAlumnosEmpty => 'You don\'t have any linked athletes yet.';

  @override
  String get coachHubAlumnosEmptyFiltered => 'No athlete matches the filter.';

  @override
  String get coachHubAlumnosLoadError => 'We couldn\'t load your athletes.';

  @override
  String get coachHubAlumnosProfilesLoadError =>
      'We couldn\'t load the profiles.';

  @override
  String get coachHubAlumnosColumnStudent => 'ATHLETE';

  @override
  String get coachHubAlumnosColumnStatus => 'STATUS';

  @override
  String get coachHubAlumnosColumnLastWorkout => 'LAST WORKOUT';

  @override
  String get coachHubAlumnosColumnActions => 'ACTIONS';

  @override
  String get coachHubAlumnosNameFallback => 'Athlete';

  @override
  String get coachHubAlumnosLastWorkoutToday => 'Today';

  @override
  String get coachHubAlumnosStatusActive => 'Active';

  @override
  String get coachHubAlumnosStatusDebt => 'Overdue';

  @override
  String get coachHubAlumnosStatusBlocked => 'Blocked';

  @override
  String get coachHubAlumnosFilterBloqueados => 'Blocked';

  @override
  String get coachHubAlumnosBlockedHint =>
      'You are over your plan limit. This athlete does not count and you cannot work with them until you resolve it.';

  @override
  String get coachHubAlumnosStatusPaused => 'Paused';

  @override
  String get coachHubAlumnosStatusInactive => 'Inactive';

  @override
  String get coachHubAlumnosViewTable => 'Table';

  @override
  String get coachHubAlumnosViewCards => 'Cards';

  @override
  String coachHubAlumnosDebtAmount(String amount) {
    return 'Owes $amount';
  }

  @override
  String get coachHubAlumnoDetailNotasTitle => 'Private notes';

  @override
  String get coachHubAlumnoDetailNotasSubtitle =>
      'Write down whatever you need about this athlete. Only you can see it.';

  @override
  String get coachHubAlumnoDetailNotasHint =>
      'e.g. Right knee injury, avoid deep squats…';

  @override
  String get coachHubAlumnoDetailNotasSaveButton => 'SAVE';

  @override
  String coachHubAlumnoDetailNotasUpdatedAt(String timestamp) {
    return 'Last edited · $timestamp';
  }

  @override
  String get coachHubAlumnoDetailNotasSaveSuccess => 'Note saved.';

  @override
  String get coachHubAlumnoDetailNotasSaveError =>
      'We couldn\'t save the note. Please try again.';

  @override
  String get coachHubAlumnoDetailNotasLoadError =>
      'We couldn\'t load the note.';

  @override
  String get coachHubAlumnoDetailArchivosTitle => 'Private files';

  @override
  String get coachHubAlumnoDetailArchivosSubtitle =>
      'PDFs and photos you upload about this athlete. Only you can see them.';

  @override
  String get coachHubAlumnoDetailArchivosUploadButton => 'UPLOAD FILE';

  @override
  String get coachHubAlumnoDetailArchivosEmpty =>
      'You haven\'t uploaded any files about this athlete yet.';

  @override
  String get coachHubAlumnoDetailArchivosLoadError =>
      'We couldn\'t load the files.';

  @override
  String get coachHubAlumnoDetailArchivosUploadSuccess => 'File uploaded.';

  @override
  String get coachHubAlumnoDetailArchivosUploadError =>
      'We couldn\'t upload the file. Please try again.';

  @override
  String get coachHubAlumnoDetailArchivosUploadTooLarge =>
      'The file exceeds the 10 MB limit.';

  @override
  String get coachHubAlumnoDetailArchivosOpenTooltip => 'Open file';

  @override
  String get coachHubAlumnoDetailArchivosDeleteTooltip => 'Delete';

  @override
  String get coachHubAlumnoDetailArchivosDeleteTitle => 'Delete file?';

  @override
  String coachHubAlumnoDetailArchivosDeleteBody(String fileName) {
    return '«$fileName» will be removed from Storage and from the history. This can\'t be undone.';
  }

  @override
  String get coachHubAlumnoDetailArchivosDeleteError =>
      'We couldn\'t delete the file.';

  @override
  String get feedLoadError => 'We couldn\'t load your feed. Please try again.';

  @override
  String get createPostLoadError =>
      'We couldn\'t open the editor. Please try again.';

  @override
  String get insightsLoadError =>
      'We couldn\'t load your insights. Please try again.';

  @override
  String get insightsDayStripTodayLabel => 'TODAY';

  @override
  String get insightsDayEmptyHint => 'No workout logged this day.';

  @override
  String get coachDailyHeatmapSectionTitle => 'MUSCLES OF THE DAY';

  @override
  String get profileLoadError =>
      'We couldn\'t load your profile. Please try again.';

  @override
  String get sessionDetailNoSets => 'This session has no logged sets.';

  @override
  String get sessionFinishedOnWatch =>
      'You finished this workout on your watch.';

  @override
  String get sessionLogSetError =>
      'We couldn\'t save the set. Please try again.';

  @override
  String get sessionFinishError =>
      'We couldn\'t finish the session. Please try again.';

  @override
  String get routineEditorMissingName => 'Give your routine a name.';

  @override
  String routineEditorMissingExercise(int dayNumber) {
    return 'Add at least one exercise to Day $dayNumber.';
  }

  @override
  String get routineEditorMissingReps =>
      'Fill in the reps for your sets before saving.';

  @override
  String get routineEditorDuplicateExercise =>
      'Ese ejercicio ya está en el día. Elegí otro.';

  @override
  String get feedPostPublishedSuccess => 'Post published.';

  @override
  String get postCardMenuA11y => 'Post options';

  @override
  String get coachHubAlumnosRowActionsA11y => '';

  @override
  String get postCardMenuEdit => 'Edit';

  @override
  String get postCardMenuDelete => 'Delete';

  @override
  String get postCardDeleteConfirmTitle => 'Delete this post?';

  @override
  String get postCardDeleteConfirmBody => 'This action can\'t be undone.';

  @override
  String get postCardDeleteSuccess => 'Post deleted.';

  @override
  String get postCardDeleteError =>
      'We couldn\'t delete the post. Please try again.';

  @override
  String get createPostEditTitle => 'EDIT POST';

  @override
  String get createPostSaveChanges => 'SAVE';

  @override
  String get createPostSaveChangesA11y => 'Save changes';

  @override
  String get createPostSavingA11y => 'Saving…';

  @override
  String get feedPostUpdatedSuccess => 'Changes saved.';

  @override
  String get feedRequestSentSuccess => 'Request sent.';

  @override
  String get feedRequestAcceptedSuccess => 'Request accepted.';

  @override
  String get feedFriendActionError =>
      'We couldn\'t complete the action. Please try again.';

  @override
  String get profilePersonalSaveSuccess => 'Changes saved.';

  @override
  String get profileGymSaveSuccess => 'Gym updated.';

  @override
  String get profileGymSaveError =>
      'We couldn\'t save your gym. Please try again.';

  @override
  String get gymNearbyLocationAffordance =>
      'Turn on location to see nearby gyms';

  @override
  String get gymNearbyShowMore => 'Show more';

  @override
  String get gymNearbyLoadError => 'We couldn\'t load nearby gyms.';

  @override
  String get feedPullToRefreshA11y => 'Pull to refresh';

  @override
  String get logFieldInvalidNumber => 'Enter a valid number';

  @override
  String get logFieldOutOfRange => 'Value is out of range';

  @override
  String get logEmptyRecordWarning =>
      'Fill in at least one value before saving';

  @override
  String get profileSetupUsernameChecking => 'Checking availability…';

  @override
  String get profileSetupUsernameTaken => 'That username is already taken';

  @override
  String get profileSetupUsernameAvailable => 'Username available';

  @override
  String get profileSetupUsernameCheckError =>
      'We couldn\'t check the username. Try again.';

  @override
  String get routineEditorDiscardTitle => 'Discard changes?';

  @override
  String get routineEditorDiscardBody =>
      'If you leave now you\'ll lose your unsaved changes.';

  @override
  String get routineEditorDiscardConfirm => 'Discard';

  @override
  String trainerCtaExistingLinkExplanation(String trainerName) {
    return 'You can only have one active trainer. End your current link with $trainerName to request a new one.';
  }

  @override
  String get coachHubPreviewDiscardTitle => 'Leave without saving the plan?';

  @override
  String get coachHubPreviewDiscardBody =>
      'You\'ll lose the exercises you matched manually.';

  @override
  String get coachHubPreviewDiscardConfirm => 'Leave anyway';

  @override
  String get chatAttachMediaLabel => 'Attach';

  @override
  String get chatPickImageLabel => 'Photo';

  @override
  String get chatPickVideoLabel => 'Video';

  @override
  String get chatMediaUploading => 'Uploading…';

  @override
  String get chatMediaUploadFailed =>
      'We couldn\'t upload the file. Please try again.';

  @override
  String get chatMediaPreviewPhoto => '📷 Photo';

  @override
  String get chatMediaPreviewVideo => '🎥 Video';

  @override
  String get chatMediaViewFullscreen => 'View photo';

  @override
  String get chatMediaImageLoadError => 'We couldn\'t load the image.';

  @override
  String feedMessagesWithUnreadA11y(int count) {
    return 'Messages, $count unread';
  }

  @override
  String get chatUnreadA11y => 'Unread';

  @override
  String get coachSessionSetLogsTitle => 'SETS';

  @override
  String get coachSessionTapToExpand => 'View sets';

  @override
  String get coachSessionSetLogsEmpty => 'This session has no logged sets.';

  @override
  String get coachSessionSetLogsLoadError =>
      'Could not load sets. Please try again.';

  @override
  String get coachAthleteNoSharePlaceholder =>
      'The athlete has not shared their history yet.';

  @override
  String get avatarCropperTitle => '';

  @override
  String get avatarCropperDone => '';

  @override
  String get avatarCropperCancel => '';

  @override
  String get progressionSectionTitle => 'PROGRESS BY EXERCISE';

  @override
  String get progressionMetricPr => 'Heaviest weight';

  @override
  String get progressionMetricOneRepMax => '1RM';

  @override
  String get progressionMetricBestSetVolume => 'Best set';

  @override
  String get progressionMetricVolume => 'Volume';

  @override
  String progressionFrequency(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions in the last 8 weeks',
      one: '1 session in the last 8 weeks',
      zero: 'No sessions in the last 8 weeks',
    );
    return '$_temp0';
  }

  @override
  String progressionFrequencyPeriod(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions in this period',
      one: '1 session in this period',
      zero: 'No sessions in this period',
    );
    return '$_temp0';
  }

  @override
  String get progressionSinglePointHint =>
      'You need at least 2 sessions to see the trend.';

  @override
  String get progressionEmptyExercise => 'No data for this exercise.';

  @override
  String get progressionEmpty => 'No set records yet.';

  @override
  String get progressionPeriodLast30Days => 'Last 30 days';

  @override
  String get progressionPeriodThisWeek => 'This week';

  @override
  String get progressionPeriodMonth => 'This month';

  @override
  String get muscleDistributionSectionTitle => 'MUSCLE DISTRIBUTION';

  @override
  String get muscleDistributionCurrentLabel => 'Current';

  @override
  String get muscleDistributionPreviousLabel => 'Previous';

  @override
  String get muscleDistributionEmptyState => 'No data for this period.';

  @override
  String get muscleDistributionWorkoutsLabel => 'Workouts';

  @override
  String get muscleDistributionDurationLabel => 'Duration';

  @override
  String get muscleDistributionVolumeLabel => 'Volume';

  @override
  String get muscleDistributionSetsLabel => 'Sets';

  @override
  String get personalRecordsSectionTitle => 'PERSONAL RECORDS';

  @override
  String get mostFrequentExercisesSectionTitle => 'MOST FREQUENT EXERCISES';

  @override
  String mostFrequentExercisesSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
      zero: 'No sessions',
    );
    return '$_temp0';
  }

  @override
  String get mostFrequentExercisesEmpty => 'No data yet.';

  @override
  String get profileRoutinesAssignedHeader => '';

  @override
  String get profileRoutinesOwnHeader => '';

  @override
  String get profileRoutinesNoTrainerBody => '';

  @override
  String get profileRoutinesNoTrainerCta => '';

  @override
  String get profileRoutinesNoOwnBody => '';

  @override
  String get profileRoutinesActiveChip => '';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceSystemDesc => 'Follows the device theme';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get profileSectionAppearance => 'Appearance';

  @override
  String dashboardGreeting(String name) {
    return '';
  }

  @override
  String get dashboardGreetingPrefix => '';

  @override
  String dashboardSummaryLine(int sessions, int paraRevisar, int pagos) {
    return '';
  }

  @override
  String get dashboardQuickActionNuevoAlumno => '';

  @override
  String get dashboardQuickActionCrearRutina => '';

  @override
  String dashboardQuickActionMensajes(int count) {
    return '';
  }

  @override
  String get dashboardQuickActionImportarPlan => '';

  @override
  String get dashboardAlertBannerPlaceholder => '';

  @override
  String get dashboardKpiAlumnosActivos => '';

  @override
  String get dashboardKpiIngresoMes => '';

  @override
  String get dashboardKpiAdherencia => '';

  @override
  String dashboardKpiPorCobrar(int count) {
    return '';
  }

  @override
  String get dashboardPlaceholderSoon => '';

  @override
  String get dashboardAdherenceRingPlaceholder => '';

  @override
  String get dashboardProximaSesionManana => 'tomorrow';

  @override
  String get dashboardProximasSesionesEmpty => '';

  @override
  String get dashboardVencimientosTitle => '';

  @override
  String get dashboardVencimientosEmpty => '';

  @override
  String get dashboardVencimientosVerTodos => '';

  @override
  String get dashboardInactivosTitle => '';

  @override
  String get dashboardInactivosEmpty => '';

  @override
  String get dashboardAlertBannerAllClear => '';

  @override
  String dashboardAlertBannerSummary(
      int vencidos, int solicitudes, int inactivos) {
    String _temp0 = intl.Intl.pluralLogic(
      vencidos,
      locale: localeName,
      other: '$vencidos overdue',
      one: '1 overdue',
    );
    String _temp1 = intl.Intl.pluralLogic(
      solicitudes,
      locale: localeName,
      other: '$solicitudes requests',
      one: '1 request',
    );
    String _temp2 = intl.Intl.pluralLogic(
      inactivos,
      locale: localeName,
      other: '$inactivos inactive',
      one: '1 inactive',
    );
    return '$_temp0 · $_temp1 · $_temp2';
  }

  @override
  String dashboardAdherenceValue(int pct) {
    return '';
  }

  @override
  String get insightsMonthlyReportTile => 'Monthly Report';

  @override
  String get monthlyReportTitle => 'MONTHLY REPORT';

  @override
  String get monthlyReportMetricWorkouts => 'Workouts';

  @override
  String get monthlyReportMetricDuration => 'Duration';

  @override
  String get monthlyReportMetricVolume => 'Volume';

  @override
  String get monthlyReportMetricSets => 'Sets';

  @override
  String get monthlyReportDurationUnit => 'min';

  @override
  String get monthlyReportDurationHoursUnit => 'h';

  @override
  String get monthlyReportVolumeUnit => 'kg';

  @override
  String get monthlyReportEmptyHint => 'No data in the last 12 months.';

  @override
  String get monthlyReportByMonthLabel => 'BY MONTH';

  @override
  String get monthlyReportByDayLabel => 'BY DAY';

  @override
  String get monthlyReportDailyEmptyHint => 'No trained minutes in this month.';

  @override
  String get monthlyReportDailyTooltipDayLabel => 'Day';

  @override
  String get monthlyReportLoadError =>
      'We couldn\'t load your monthly report. Try again.';

  @override
  String workoutDaysCalendarStreak(int n) {
    return '';
  }

  @override
  String get insightsAdvancedStatsHeading => 'Advanced statistics';

  @override
  String get insightsTileMuscleDistributionTitle => 'Muscle distribution';

  @override
  String get insightsTileMuscleDistributionSubtitle =>
      'Current vs. previous period comparison';

  @override
  String get muscleDistributionScreenTitle => 'MUSCLE DISTRIBUTION';

  @override
  String get muscleDistributionLoadError =>
      'We couldn\'t load your muscle distribution. Try again.';

  @override
  String get frequentExercisesLoadError => '';

  @override
  String get exerciseProgressionScreenTitle => 'EXERCISE PROGRESSION';

  @override
  String get insightsTileExerciseProgressionTitle => 'Exercise progression';

  @override
  String get insightsTileExerciseProgressionSubtitle =>
      'Your progress per exercise + records';

  @override
  String get progressionSearchHint => 'Search exercise…';

  @override
  String get progressionSearchNoResults =>
      'None of your exercises match the search.';

  @override
  String get insightsTileMeasurementsTitle => 'Body measurements';

  @override
  String get insightsTileMeasurementsSubtitle =>
      'Body weight and measurements over time';

  @override
  String get measurementsScreenTitle => 'BODY MEASUREMENTS';

  @override
  String get measurementsSelfLogNotesHint => 'Notes (optional)…';

  @override
  String get measurementsAddSelfLog => 'Log measurement';

  @override
  String get measurementsProfileCardTitle => 'YOUR DATA';

  @override
  String get measurementsProfileCardHint =>
      'You entered these when you signed up. Edit them from your profile.';

  @override
  String get measurementsWeightLabel => 'Weight';

  @override
  String get measurementsHeightLabel => 'Height';

  @override
  String get measurementsEmptyState =>
      'No measurements logged yet. Tap + to record your first one and track your progress.';

  @override
  String get measurementsNeedsMoreData =>
      'A single measurement is not enough to show progress. At least one more is needed.';

  @override
  String get measurementsHistoryTitle => 'HISTORY';

  @override
  String get measurementHistoryEditTooltip => 'Edit measurement';

  @override
  String get measurementHistoryDeleteTooltip => 'Delete measurement';

  @override
  String measurementHistoryShowAll(int count) {
    return 'Show all ($count)';
  }

  @override
  String get measurementHistoryShowLess => 'Show less';

  @override
  String get measurementDeleteConfirmTitle => 'Delete measurement?';

  @override
  String measurementDeleteConfirmBody(String date) {
    return 'The measurement from $date will be deleted. This action cannot be undone.';
  }

  @override
  String get measurementDeleteConfirmAction => 'Delete';

  @override
  String get measurementDeleteSuccess => 'Measurement deleted';

  @override
  String get measurementDeleteError =>
      'We couldn\'t delete the measurement. Try again.';

  @override
  String get measurementHistorySelfLoggedTag => 'Self-logged';

  @override
  String get measurementHistoryTrainerLoggedTag => 'Logged by your trainer';

  @override
  String get insightsTileFrequentExercisesTitle => 'Frequent exercises';

  @override
  String get insightsTileFrequentExercisesSubtitle =>
      'Your most-trained exercises';

  @override
  String get frequentExercisesScreenTitle => 'FREQUENT EXERCISES';

  @override
  String get insightsTileMonthlyReportSubtitle => 'Monthly workout summary';

  @override
  String get insightsTileVolumeByGroupTitle => 'Volume by muscle group';

  @override
  String get insightsTileVolumeByGroupSubtitle =>
      'Sets vs. target per muscle group';

  @override
  String get volumeByGroupScreenTitle => 'VOLUME BY GROUP';

  @override
  String get volumeByGroupEmptyTarget =>
      'You need an assigned routine to see your target volume.';

  @override
  String get measurementChartSectionLabel => 'PROGRESS';

  @override
  String measurementChartSpanDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '($count $_temp0)';
  }

  @override
  String measurementChartSpanWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'weeks',
      one: 'week',
    );
    return '($count $_temp0)';
  }

  @override
  String get measurementChartMetricWeight => 'Weight';

  @override
  String get measurementChartMetricBodyFat => 'Body fat %';

  @override
  String get measurementChartMetricMuscleMass => 'Muscle mass';

  @override
  String get measurementChartMetricWaist => 'Waist';

  @override
  String get measurementChartMetricChest => 'Chest';

  @override
  String get measurementChartMetricHips => 'Hips';

  @override
  String get measurementChartMetricShoulders => 'Shoulders';

  @override
  String get measurementChartMetricGlutes => 'Glutes';

  @override
  String get measurementChartMetricBiceps => 'Biceps';

  @override
  String get measurementChartMetricBicepsFlexed => 'Biceps flex';

  @override
  String get measurementChartMetricForearm => 'Forearm';

  @override
  String get measurementChartMetricUpperThigh => 'Upper thigh';

  @override
  String get measurementChartMetricMidThigh => 'Mid thigh';

  @override
  String get measurementChartMetricCalf => 'Calf';

  @override
  String get measurementLogTitleCreate => 'Log measurement';

  @override
  String get measurementLogTitleEdit => 'Edit measurement';

  @override
  String get measurementLogNoSession => 'No active session. Can\'t save.';

  @override
  String get measurementLogSaveSuccess => 'Measurement saved';

  @override
  String get measurementLogUpdateSuccess => 'Measurement updated';

  @override
  String get measurementLogSaveError =>
      'We couldn\'t save the measurement. Try again.';

  @override
  String get measurementLogSaveCta => 'SAVE MEASUREMENT';

  @override
  String get measurementLogUpdateCta => 'SAVE CHANGES';

  @override
  String get measurementLogSectionBodyComposition => 'BODY COMPOSITION';

  @override
  String get measurementLogSectionNotes => 'NOTES';

  @override
  String get measurementLogNotesHint => 'Trainer notes…';

  @override
  String get measurementLogFieldWeight => 'Weight (kg)';

  @override
  String get measurementLogFieldBodyFat => 'Body fat (%)';

  @override
  String get measurementLogFieldMuscleMass => 'Muscle mass (kg)';

  @override
  String get measurementLogCircumferencesTitle => 'CIRCUMFERENCES';

  @override
  String get measurementLogCircumferencesHint =>
      'Optional. Log the ones you want.';

  @override
  String get measurementLogGroupTrunk => 'TRUNK';

  @override
  String get measurementLogGroupUpperBody => 'UPPER BODY';

  @override
  String get measurementLogGroupLowerBody => 'LOWER BODY';

  @override
  String get measurementLogFieldShoulders => 'Shoulders';

  @override
  String get measurementLogFieldChest => 'Chest';

  @override
  String get measurementLogFieldWaist => 'Waist';

  @override
  String get measurementLogFieldHips => 'Hips';

  @override
  String get measurementLogFieldGlutes => 'Glutes';

  @override
  String get measurementLogFieldBiceps => 'Biceps';

  @override
  String get measurementLogFieldBicepsFlexed => 'Biceps (flexed)';

  @override
  String get measurementLogFieldForearm => 'Forearm';

  @override
  String get measurementLogFieldUpperThigh => 'Upper thigh';

  @override
  String get measurementLogFieldMidThigh => 'Mid thigh';

  @override
  String get measurementLogFieldCalf => 'Calf';

  @override
  String get measurementLogBilateralLeftHint => 'L (cm)';

  @override
  String get measurementLogBilateralRightHint => 'R (cm)';

  @override
  String get reviewSheetTitleEdit => 'Edit your review';

  @override
  String reviewSheetTitleThirtyDay(String trainerName) {
    return 'You\'ve been training with $trainerName for a month. How\'s it going?';
  }

  @override
  String reviewSheetTitleStandard(String trainerName) {
    return 'How was your experience with $trainerName?';
  }

  @override
  String get reviewSheetCommentHint => 'Tell us how it went (optional)';

  @override
  String get reviewSheetCancel => 'CANCEL';

  @override
  String get reviewSheetSubmit => 'SUBMIT';

  @override
  String get reviewSnackBarError => 'We couldn\'t save your review. Try again.';

  @override
  String get reviewCtaCreate => 'LEAVE A REVIEW';

  @override
  String get reviewCtaEdit => 'EDIT MY REVIEW';

  @override
  String get reviewTrainerFallbackName => 'your personal trainer';

  @override
  String get reviewsSectionTitle => 'REVIEWS';

  @override
  String get reviewsSectionEmpty => 'No reviews yet';

  @override
  String get reviewTileDeletedUser => 'Deleted user';

  @override
  String get reviewTileDateToday => 'today';

  @override
  String reviewTileDateDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0 ago';
  }

  @override
  String reviewTileDateMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months',
      one: '1 month',
    );
    return '$_temp0 ago';
  }

  @override
  String get postPrivacySelectorTitle => 'VISIBILITY';

  @override
  String get postPrivacyFriends => 'FOLLOWERS';

  @override
  String get postPrivacyGym => 'MY GYM';

  @override
  String get postPrivacyPublic => 'PUBLIC';

  @override
  String get postPrivacyNoGymHint => 'Join a gym to post here';

  @override
  String get suggestedUsersTitle => 'PEOPLE FROM YOUR GYM';

  @override
  String get suggestedUserAnonymous => 'Anonymous';

  @override
  String a11ySuggestedUserButton(String name) {
    return 'View $name\'s profile';
  }

  @override
  String get notificationHistoryTitle => 'NOTIFICATIONS';

  @override
  String get notificationHistoryEmpty =>
      'You don\'t have any notifications yet';

  @override
  String get notificationHistoryError =>
      'We couldn\'t load your notifications.';

  @override
  String notificationPendingRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending follower requests',
      one: '1 pending follower request',
    );
    return '$_temp0';
  }

  @override
  String get notificationBellA11y => 'Open notifications';

  @override
  String notificationBellWithCountA11y(int count) {
    return 'Open notifications, $count pending';
  }

  @override
  String get postDetailTitle => 'POST';

  @override
  String get postDetailUnavailable => 'This post is no longer available.';

  @override
  String feedUnfollowConfirmTitle(String name) {
    return 'Unfollow $name?';
  }

  @override
  String get feedUnfollowConfirmAction => 'UNFOLLOW';

  @override
  String get feedUnfollowDismiss => 'CANCEL';

  @override
  String feedCancelRequestConfirmTitle(String name) {
    return 'Cancel your request to $name?';
  }

  @override
  String get feedCancelRequestConfirmAction => 'CANCEL REQUEST';

  @override
  String get feedCancelRequestDismiss => 'BACK';

  @override
  String get feedFollowButtonFollowA11y => 'Follow this person';

  @override
  String get feedFollowButtonFollowingA11y => 'Following. Tap to unfollow';

  @override
  String get feedFollowButtonRequestedA11y => 'Request sent. Tap to cancel it';

  @override
  String get feedFollowButtonAcceptA11y => 'Accept follower request';

  @override
  String get feedFollowStartedSuccess => 'You\'re now following this person.';

  @override
  String get feedSegmentFollowing => 'FOLLOWERS';

  @override
  String get feedEmptyFollowing => 'No posts yet from people you follow';

  @override
  String get chatBlockedComposerNotice =>
      'To message them, this person needs to follow you.';

  @override
  String get chatBlockedComposerHintA11y => 'You can\'t write in this chat';

  @override
  String get followListTabFollowers => 'FOLLOWERS';

  @override
  String get followListTabFollowing => 'FOLLOWING';

  @override
  String get followListEmptyFollowers => 'No followers yet';

  @override
  String get followListEmptyFollowersSelf => 'You have no followers yet';

  @override
  String get followListEmptyFollowing => 'Not following anyone yet';

  @override
  String get followListEmptyFollowingSelf => 'You\'re not following anyone yet';

  @override
  String get followListLoadError => 'We couldn\'t load the list. Try again.';

  @override
  String get followListOpenFollowersA11y => 'View followers';

  @override
  String get followListOpenFollowingA11y => 'View following';

  @override
  String routineCardDaysPerWeek(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days/week',
      one: '1 day/week',
    );
    return '$_temp0';
  }

  @override
  String routineCardMinutes(String value) {
    return '$value min';
  }
}
