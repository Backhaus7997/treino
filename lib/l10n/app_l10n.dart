import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_en.dart';
import 'app_l10n_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('es', 'AR')
  ];

  /// No description provided for @authSplashTagline.
  ///
  /// In es_AR, this message translates to:
  /// **'ENTRENÁ. COMPARTÍ. CRECÉ.'**
  String get authSplashTagline;

  /// No description provided for @authWelcomeEyebrow.
  ///
  /// In es_AR, this message translates to:
  /// **'ENTRENAMIENTO · GYM · COACH'**
  String get authWelcomeEyebrow;

  /// No description provided for @authWelcomeBody.
  ///
  /// In es_AR, this message translates to:
  /// **'Cargá tu rutina, ejecutá los sets, seguí a tus pibes y encontrá un coach cerca tuyo.'**
  String get authWelcomeBody;

  /// No description provided for @authWelcomeCta.
  ///
  /// In es_AR, this message translates to:
  /// **'EMPEZAR'**
  String get authWelcomeCta;

  /// No description provided for @authWelcomeHaveAccount.
  ///
  /// In es_AR, this message translates to:
  /// **'Ya tengo cuenta'**
  String get authWelcomeHaveAccount;

  /// No description provided for @authWelcomeSignIn.
  ///
  /// In es_AR, this message translates to:
  /// **'Iniciar sesión'**
  String get authWelcomeSignIn;

  /// No description provided for @authLoginTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'BIENVENIDO'**
  String get authLoginTitle;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Entrá para seguir tu rutina'**
  String get authLoginSubtitle;

  /// No description provided for @authLoginEmailHint.
  ///
  /// In es_AR, this message translates to:
  /// **'tu@email.com'**
  String get authLoginEmailHint;

  /// No description provided for @authLoginForgot.
  ///
  /// In es_AR, this message translates to:
  /// **'Olvidé la contraseña'**
  String get authLoginForgot;

  /// No description provided for @authLoginCta.
  ///
  /// In es_AR, this message translates to:
  /// **'ENTRAR'**
  String get authLoginCta;

  /// No description provided for @authLoginContinueWith.
  ///
  /// In es_AR, this message translates to:
  /// **'O CONTINUÁ CON'**
  String get authLoginContinueWith;

  /// No description provided for @authLoginNoAccount.
  ///
  /// In es_AR, this message translates to:
  /// **'¿No tenés cuenta?'**
  String get authLoginNoAccount;

  /// No description provided for @authLoginRegisterLink.
  ///
  /// In es_AR, this message translates to:
  /// **'Registrate'**
  String get authLoginRegisterLink;

  /// No description provided for @authLoginTrainerCardTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Sos entrenador?'**
  String get authLoginTrainerCardTitle;

  /// No description provided for @authLoginTrainerCardSubtitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Pedí tu alta al equipo TREINO'**
  String get authLoginTrainerCardSubtitle;

  /// No description provided for @authRegisterAppbar.
  ///
  /// In es_AR, this message translates to:
  /// **'CREAR CUENTA'**
  String get authRegisterAppbar;

  /// No description provided for @authRegisterTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'SUMATE A'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Es gratis. En 30 segundos estás adentro.'**
  String get authRegisterSubtitle;

  /// No description provided for @authRegisterEmailLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'EMAIL'**
  String get authRegisterEmailLabel;

  /// No description provided for @authRegisterPasswordLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'CONTRASEÑA'**
  String get authRegisterPasswordLabel;

  /// No description provided for @authRegisterConfirmPasswordLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'CONFIRMAR CONTRASEÑA'**
  String get authRegisterConfirmPasswordLabel;

  /// No description provided for @authRegisterCta.
  ///
  /// In es_AR, this message translates to:
  /// **'CREAR CUENTA'**
  String get authRegisterCta;

  /// No description provided for @authRegisterDividerOr.
  ///
  /// In es_AR, this message translates to:
  /// **'O'**
  String get authRegisterDividerOr;

  /// No description provided for @authForgotTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'RECUPERAR\nACCESO'**
  String get authForgotTitle;

  /// No description provided for @authForgotBody.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá tu email y te enviamos un link para resetear la contraseña.'**
  String get authForgotBody;

  /// No description provided for @authForgotEmailLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'EMAIL'**
  String get authForgotEmailLabel;

  /// No description provided for @authForgotEmailHint.
  ///
  /// In es_AR, this message translates to:
  /// **'tu@email.com'**
  String get authForgotEmailHint;

  /// No description provided for @authForgotCta.
  ///
  /// In es_AR, this message translates to:
  /// **'ENVIAR LINK'**
  String get authForgotCta;

  /// No description provided for @authForgotSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Si tu email está registrado, te enviamos un link para resetear la contraseña.'**
  String get authForgotSuccess;

  /// No description provided for @authForgotBackToLogin.
  ///
  /// In es_AR, this message translates to:
  /// **'Volver al login'**
  String get authForgotBackToLogin;

  /// No description provided for @authTrainerInquiryDialogTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Acceso de entrenador'**
  String get authTrainerInquiryDialogTitle;

  /// No description provided for @authTrainerInquiryDialogBody.
  ///
  /// In es_AR, this message translates to:
  /// **'Para alta de entrenador, escribinos a equipo@treino.app'**
  String get authTrainerInquiryDialogBody;

  /// No description provided for @authTrainerInquiryDialogClose.
  ///
  /// In es_AR, this message translates to:
  /// **'Cerrar'**
  String get authTrainerInquiryDialogClose;

  /// No description provided for @authTermsPlaceholder.
  ///
  /// In es_AR, this message translates to:
  /// **'Próximamente'**
  String get authTermsPlaceholder;

  /// No description provided for @authGoogleLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'GOOGLE'**
  String get authGoogleLabel;

  /// No description provided for @authAppleLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'APPLE'**
  String get authAppleLabel;

  /// No description provided for @authComingSoonTooltip.
  ///
  /// In es_AR, this message translates to:
  /// **'Próximamente'**
  String get authComingSoonTooltip;

  /// No description provided for @authValidationEmailInvalid.
  ///
  /// In es_AR, this message translates to:
  /// **'El email no es válido'**
  String get authValidationEmailInvalid;

  /// No description provided for @authValidationPasswordRules.
  ///
  /// In es_AR, this message translates to:
  /// **'La contraseña debe tener al menos 8 caracteres, una letra y un número'**
  String get authValidationPasswordRules;

  /// No description provided for @authValidationPasswordMismatch.
  ///
  /// In es_AR, this message translates to:
  /// **'Las contraseñas no coinciden'**
  String get authValidationPasswordMismatch;

  /// No description provided for @authProfileSignOut.
  ///
  /// In es_AR, this message translates to:
  /// **'Cerrar sesión'**
  String get authProfileSignOut;

  /// No description provided for @coachAppBarTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Entrenadores'**
  String get coachAppBarTitle;

  /// No description provided for @coachLoadingLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Cargando entrenadores…'**
  String get coachLoadingLabel;

  /// No description provided for @coachErrorLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar los entrenadores.'**
  String get coachErrorLabel;

  /// No description provided for @coachRetryLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Reintentar'**
  String get coachRetryLabel;

  /// No description provided for @coachEmptyLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'No encontramos entrenadores en tu zona.'**
  String get coachEmptyLabel;

  /// No description provided for @coachMapToggleLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Mapa'**
  String get coachMapToggleLabel;

  /// No description provided for @coachMapProximamente.
  ///
  /// In es_AR, this message translates to:
  /// **'Próximamente'**
  String get coachMapProximamente;

  /// No description provided for @coachDistanceUnknown.
  ///
  /// In es_AR, this message translates to:
  /// **'—'**
  String get coachDistanceUnknown;

  /// No description provided for @coachMonthlyRateUnit.
  ///
  /// In es_AR, this message translates to:
  /// **'/mes'**
  String get coachMonthlyRateUnit;

  /// No description provided for @coachSpecialtyAll.
  ///
  /// In es_AR, this message translates to:
  /// **'Todos'**
  String get coachSpecialtyAll;

  /// No description provided for @coachStatsReviewsLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'RESEÑAS'**
  String get coachStatsReviewsLabel;

  /// No description provided for @coachStatsExperienceLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'AÑOS EXP'**
  String get coachStatsExperienceLabel;

  /// No description provided for @coachStatsStudentsLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'ALUMNOS'**
  String get coachStatsStudentsLabel;

  /// No description provided for @coachStatsPlaceholder.
  ///
  /// In es_AR, this message translates to:
  /// **'—'**
  String get coachStatsPlaceholder;

  /// No description provided for @coachProfileLoadingLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Cargando perfil…'**
  String get coachProfileLoadingLabel;

  /// No description provided for @coachProfileErrorLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar este perfil.'**
  String get coachProfileErrorLabel;

  /// No description provided for @coachProfileNotFoundLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Entrenador no encontrado.'**
  String get coachProfileNotFoundLabel;

  /// No description provided for @coachProfileBioEmpty.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin descripción.'**
  String get coachProfileBioEmpty;

  /// No description provided for @coachProfileRateLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Tarifa mensual'**
  String get coachProfileRateLabel;

  /// No description provided for @coachCtaLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'PEDIR VÍNCULO'**
  String get coachCtaLabel;

  /// No description provided for @coachCtaProximamente.
  ///
  /// In es_AR, this message translates to:
  /// **'Próximamente — Etapa 3'**
  String get coachCtaProximamente;

  /// No description provided for @coachLocationSheetTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Permitir ubicación'**
  String get coachLocationSheetTitle;

  /// No description provided for @coachLocationSheetBody.
  ///
  /// In es_AR, this message translates to:
  /// **'TREINO usa tu ubicación para mostrarte entrenadores cerca tuyo. Tu ubicación no es visible para otros usuarios.'**
  String get coachLocationSheetBody;

  /// No description provided for @coachLocationSheetAccept.
  ///
  /// In es_AR, this message translates to:
  /// **'ACEPTAR'**
  String get coachLocationSheetAccept;

  /// No description provided for @coachLocationSheetDeny.
  ///
  /// In es_AR, this message translates to:
  /// **'Ahora no'**
  String get coachLocationSheetDeny;

  /// No description provided for @coachMiPlanTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'MI PLAN'**
  String get coachMiPlanTitle;

  /// No description provided for @coachMiPlanEmpty.
  ///
  /// In es_AR, this message translates to:
  /// **'No tenés rutina asignada todavía.'**
  String get coachMiPlanEmpty;

  /// No description provided for @coachMiPlanError.
  ///
  /// In es_AR, this message translates to:
  /// **'Error al cargar tu plan.'**
  String get coachMiPlanError;

  /// No description provided for @coachMiPlanFinalizado.
  ///
  /// In es_AR, this message translates to:
  /// **'Plan finalizado'**
  String get coachMiPlanFinalizado;

  /// No description provided for @coachMiPlanCurrent.
  ///
  /// In es_AR, this message translates to:
  /// **'Actual'**
  String get coachMiPlanCurrent;

  /// No description provided for @coachAssignedByPrefix.
  ///
  /// In es_AR, this message translates to:
  /// **'Asignado por '**
  String get coachAssignedByPrefix;

  /// No description provided for @coachAssignedByLoading.
  ///
  /// In es_AR, this message translates to:
  /// **'Asignado por …'**
  String get coachAssignedByLoading;

  /// No description provided for @coachAssignedByError.
  ///
  /// In es_AR, this message translates to:
  /// **'Asignado por un PF'**
  String get coachAssignedByError;

  /// No description provided for @coachCreatePlanCta.
  ///
  /// In es_AR, this message translates to:
  /// **'CREAR PLAN'**
  String get coachCreatePlanCta;

  /// No description provided for @coachCreatePlanSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Plan creado y asignado.'**
  String get coachCreatePlanSuccess;

  /// No description provided for @coachCreatePlanError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos crear el plan. Intentá de nuevo.'**
  String get coachCreatePlanError;

  /// No description provided for @coachAthleteDetailNoPlans.
  ///
  /// In es_AR, this message translates to:
  /// **'Todavía no le asignaste planes.'**
  String get coachAthleteDetailNoPlans;

  /// No description provided for @coachEditorTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Crear plan'**
  String get coachEditorTitle;

  /// No description provided for @coachEditorEditTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Editar plan'**
  String get coachEditorEditTitle;

  /// No description provided for @coachEditorNameLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'NOMBRE'**
  String get coachEditorNameLabel;

  /// No description provided for @coachEditorSplitLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'SPLIT (e.g. PPL)'**
  String get coachEditorSplitLabel;

  /// No description provided for @coachEditorAddDay.
  ///
  /// In es_AR, this message translates to:
  /// **'Agregar día'**
  String get coachEditorAddDay;

  /// No description provided for @coachEditorAddSlot.
  ///
  /// In es_AR, this message translates to:
  /// **'Agregar ejercicio'**
  String get coachEditorAddSlot;

  /// No description provided for @coachEditorAddSuperset.
  ///
  /// In es_AR, this message translates to:
  /// **'+ Superserie'**
  String get coachEditorAddSuperset;

  /// No description provided for @coachEditorSubmit.
  ///
  /// In es_AR, this message translates to:
  /// **'ASIGNAR PLAN'**
  String get coachEditorSubmit;

  /// No description provided for @coachEditorUpdateLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'GUARDAR CAMBIOS'**
  String get coachEditorUpdateLabel;

  /// No description provided for @coachUpdatePlanSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Plan actualizado.'**
  String get coachUpdatePlanSuccess;

  /// No description provided for @coachExercisePicker.
  ///
  /// In es_AR, this message translates to:
  /// **'Buscar ejercicio'**
  String get coachExercisePicker;

  /// No description provided for @agendaButtonLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'VER AGENDA DEL PF'**
  String get agendaButtonLabel;

  /// No description provided for @agendaScreenTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Agenda'**
  String get agendaScreenTitle;

  /// No description provided for @agendaEmptyAvailability.
  ///
  /// In es_AR, this message translates to:
  /// **'Tu PF todavía no configuró horarios.'**
  String get agendaEmptyAvailability;

  /// No description provided for @agendaBookingConfirmTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Confirmar reserva'**
  String get agendaBookingConfirmTitle;

  /// No description provided for @agendaBookingConfirmBody.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Confirmar reserva el {date} a las {time}?'**
  String agendaBookingConfirmBody(String date, String time);

  /// No description provided for @agendaBookingConfirmCta.
  ///
  /// In es_AR, this message translates to:
  /// **'Confirmar'**
  String get agendaBookingConfirmCta;

  /// No description provided for @agendaBookingCancel.
  ///
  /// In es_AR, this message translates to:
  /// **'Cancelar'**
  String get agendaBookingCancel;

  /// No description provided for @agendaBookingSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Reserva confirmada.'**
  String get agendaBookingSuccess;

  /// No description provided for @agendaBookingRaceError.
  ///
  /// In es_AR, this message translates to:
  /// **'Ese horario fue reservado justo ahora. Probá con otro.'**
  String get agendaBookingRaceError;

  /// No description provided for @agendaCancellationConfirmTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Cancelar reserva'**
  String get agendaCancellationConfirmTitle;

  /// No description provided for @agendaCancellationConfirmBody.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Cancelar esta reserva?'**
  String get agendaCancellationConfirmBody;

  /// No description provided for @agendaCancellationConfirmCta.
  ///
  /// In es_AR, this message translates to:
  /// **'Sí, cancelar'**
  String get agendaCancellationConfirmCta;

  /// No description provided for @agendaCancellationKeep.
  ///
  /// In es_AR, this message translates to:
  /// **'No, mantener'**
  String get agendaCancellationKeep;

  /// No description provided for @agendaCancellationSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Reserva cancelada.'**
  String get agendaCancellationSuccess;

  /// No description provided for @agendaCancellationTooLate.
  ///
  /// In es_AR, this message translates to:
  /// **'No podés cancelar con menos de 24h de anticipación.'**
  String get agendaCancellationTooLate;

  /// No description provided for @agendaUpcomingAppointmentsHeading.
  ///
  /// In es_AR, this message translates to:
  /// **'TUS PRÓXIMAS RESERVAS'**
  String get agendaUpcomingAppointmentsHeading;

  /// No description provided for @agendaPastAppointmentsHeading.
  ///
  /// In es_AR, this message translates to:
  /// **'TURNOS PASADOS'**
  String get agendaPastAppointmentsHeading;

  /// No description provided for @agendaGenericError.
  ///
  /// In es_AR, this message translates to:
  /// **'Hubo un problema. Intentá de nuevo.'**
  String get agendaGenericError;

  /// No description provided for @agendaTrainerEmptyAvailability.
  ///
  /// In es_AR, this message translates to:
  /// **'Todavía no configuraste tus horarios de trabajo. Agregá uno para que tus alumnos puedan reservar.'**
  String get agendaTrainerEmptyAvailability;

  /// No description provided for @agendaConfigureHoursCta.
  ///
  /// In es_AR, this message translates to:
  /// **'CONFIGURAR HORARIOS'**
  String get agendaConfigureHoursCta;

  /// No description provided for @agendaMyWorkingHoursHeading.
  ///
  /// In es_AR, this message translates to:
  /// **'MIS HORARIOS DE TRABAJO'**
  String get agendaMyWorkingHoursHeading;

  /// No description provided for @agendaAddRuleCta.
  ///
  /// In es_AR, this message translates to:
  /// **'AGREGAR HORARIO'**
  String get agendaAddRuleCta;

  /// No description provided for @agendaBlockDayCta.
  ///
  /// In es_AR, this message translates to:
  /// **'BLOQUEAR UN DÍA'**
  String get agendaBlockDayCta;

  /// No description provided for @agendaEditorTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Mis horarios'**
  String get agendaEditorTitle;

  /// No description provided for @agendaRuleDeleteConfirm.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Borrar este horario? Las reservas existentes se mantienen.'**
  String get agendaRuleDeleteConfirm;

  /// No description provided for @agendaRuleInvalidWindow.
  ///
  /// In es_AR, this message translates to:
  /// **'La hora de fin debe ser posterior al inicio y dejar espacio para al menos un turno.'**
  String get agendaRuleInvalidWindow;

  /// No description provided for @agendaBookingCancelledByCoach.
  ///
  /// In es_AR, this message translates to:
  /// **'Reserva cancelada por el entrenador.'**
  String get agendaBookingCancelledByCoach;

  /// No description provided for @agendaSlotFreeLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Disponible'**
  String get agendaSlotFreeLabel;

  /// No description provided for @agendaSlotBlockedLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Bloqueado'**
  String get agendaSlotBlockedLabel;

  /// No description provided for @agendaSlotBookedByLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Reservado por {athleteName}'**
  String agendaSlotBookedByLabel(String athleteName);

  /// No description provided for @workoutSummaryHeaderCompleted.
  ///
  /// In es_AR, this message translates to:
  /// **'BUEN ENTRENO'**
  String get workoutSummaryHeaderCompleted;

  /// No description provided for @workoutSummaryHeaderAbandoned.
  ///
  /// In es_AR, this message translates to:
  /// **'SESIÓN INTERRUMPIDA'**
  String get workoutSummaryHeaderAbandoned;

  /// No description provided for @workoutStatDuration.
  ///
  /// In es_AR, this message translates to:
  /// **'DURACIÓN'**
  String get workoutStatDuration;

  /// No description provided for @workoutStatVolume.
  ///
  /// In es_AR, this message translates to:
  /// **'VOLUMEN'**
  String get workoutStatVolume;

  /// No description provided for @workoutStatSets.
  ///
  /// In es_AR, this message translates to:
  /// **'SETS'**
  String get workoutStatSets;

  /// No description provided for @workoutStatPrsToday.
  ///
  /// In es_AR, this message translates to:
  /// **'PRs HOY'**
  String get workoutStatPrsToday;

  /// No description provided for @workoutStatPrsTodayStub.
  ///
  /// In es_AR, this message translates to:
  /// **'—'**
  String get workoutStatPrsTodayStub;

  /// No description provided for @workoutPrsSectionTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'PRS DE LA SESIÓN'**
  String get workoutPrsSectionTitle;

  /// No description provided for @workoutPrsPlaceholder.
  ///
  /// In es_AR, this message translates to:
  /// **'Próximamente'**
  String get workoutPrsPlaceholder;

  /// No description provided for @workoutButtonDone.
  ///
  /// In es_AR, this message translates to:
  /// **'LISTO'**
  String get workoutButtonDone;

  /// No description provided for @workoutButtonShare.
  ///
  /// In es_AR, this message translates to:
  /// **'COMPARTIR'**
  String get workoutButtonShare;

  /// No description provided for @workoutButtonRetry.
  ///
  /// In es_AR, this message translates to:
  /// **'Reintentar'**
  String get workoutButtonRetry;

  /// No description provided for @workoutButtonBackToWorkout.
  ///
  /// In es_AR, this message translates to:
  /// **'Volver a Entrenar'**
  String get workoutButtonBackToWorkout;

  /// No description provided for @workoutNotFoundTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Sesión no encontrada'**
  String get workoutNotFoundTitle;

  /// No description provided for @workoutErrorTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tu sesión'**
  String get workoutErrorTitle;

  /// No description provided for @workoutSnackShareSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'¡Post compartido!'**
  String get workoutSnackShareSuccess;

  /// No description provided for @workoutSnackShareError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos compartir tu post. Intentá de nuevo.'**
  String get workoutSnackShareError;

  /// No description provided for @workoutPostAutoCompleteText.
  ///
  /// In es_AR, this message translates to:
  /// **'¡Terminé mi entreno! 💪'**
  String get workoutPostAutoCompleteText;

  /// No description provided for @workoutHistorialHeading.
  ///
  /// In es_AR, this message translates to:
  /// **'HISTORIAL'**
  String get workoutHistorialHeading;

  /// No description provided for @workoutHistorialEmptyMessage.
  ///
  /// In es_AR, this message translates to:
  /// **'Todavía no entrenaste.'**
  String get workoutHistorialEmptyMessage;

  /// No description provided for @workoutHistorialEmptyCta.
  ///
  /// In es_AR, this message translates to:
  /// **'Empezar entrenamiento'**
  String get workoutHistorialEmptyCta;

  /// No description provided for @workoutHistorialErrorMessage.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tu historial.'**
  String get workoutHistorialErrorMessage;

  /// No description provided for @workoutHistorialErrorRetry.
  ///
  /// In es_AR, this message translates to:
  /// **'Reintentar'**
  String get workoutHistorialErrorRetry;

  /// No description provided for @workoutHistorialCardKgSuffix.
  ///
  /// In es_AR, this message translates to:
  /// **' kg'**
  String get workoutHistorialCardKgSuffix;

  /// No description provided for @workoutHistorialCardMinSuffix.
  ///
  /// In es_AR, this message translates to:
  /// **' min'**
  String get workoutHistorialCardMinSuffix;

  /// No description provided for @workoutHistorialShowLess.
  ///
  /// In es_AR, this message translates to:
  /// **'Ver menos'**
  String get workoutHistorialShowLess;

  /// No description provided for @workoutHistorialShowMore.
  ///
  /// In es_AR, this message translates to:
  /// **'Ver más ({n})'**
  String workoutHistorialShowMore(int n);

  /// No description provided for @workoutDetailStatDuration.
  ///
  /// In es_AR, this message translates to:
  /// **'DURACIÓN'**
  String get workoutDetailStatDuration;

  /// No description provided for @workoutDetailStatSets.
  ///
  /// In es_AR, this message translates to:
  /// **'SETS'**
  String get workoutDetailStatSets;

  /// No description provided for @workoutDetailStatVolume.
  ///
  /// In es_AR, this message translates to:
  /// **'VOLUMEN'**
  String get workoutDetailStatVolume;

  /// No description provided for @workoutDetailStatPrsToday.
  ///
  /// In es_AR, this message translates to:
  /// **'PRS HOY'**
  String get workoutDetailStatPrsToday;

  /// No description provided for @workoutDetailPrBadge.
  ///
  /// In es_AR, this message translates to:
  /// **'PR'**
  String get workoutDetailPrBadge;

  /// No description provided for @workoutSelfEditorTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Nueva rutina'**
  String get workoutSelfEditorTitle;

  /// No description provided for @workoutSelfEditorEditTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Editar rutina'**
  String get workoutSelfEditorEditTitle;

  /// No description provided for @workoutSelfEditorSubmitLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'CREAR RUTINA'**
  String get workoutSelfEditorSubmitLabel;

  /// No description provided for @workoutSelfEditorUpdateLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'GUARDAR CAMBIOS'**
  String get workoutSelfEditorUpdateLabel;

  /// No description provided for @workoutSelfEditorSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Rutina creada'**
  String get workoutSelfEditorSuccess;

  /// No description provided for @workoutSelfEditorUpdateSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Rutina actualizada'**
  String get workoutSelfEditorUpdateSuccess;

  /// No description provided for @workoutSelfEditorNotFound.
  ///
  /// In es_AR, this message translates to:
  /// **'Esta rutina ya no existe. Volvé y actualizá la lista.'**
  String get workoutSelfEditorNotFound;

  /// No description provided for @workoutSelfEditorError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos crear la rutina. Reintentá.'**
  String get workoutSelfEditorError;

  /// No description provided for @workoutSelfEditorPermissionDenied.
  ///
  /// In es_AR, this message translates to:
  /// **'No tenés permisos para hacer esto. Recargá la app.'**
  String get workoutSelfEditorPermissionDenied;

  /// No description provided for @workoutEditStubToast.
  ///
  /// In es_AR, this message translates to:
  /// **'Pronto vas a poder editar el contenido. Por ahora podés archivar y crear de nuevo.'**
  String get workoutEditStubToast;

  /// No description provided for @workoutSelfEditorCapReached.
  ///
  /// In es_AR, this message translates to:
  /// **'Llegaste al máximo de 10 rutinas activas.'**
  String get workoutSelfEditorCapReached;

  /// No description provided for @workoutMisRutinasSectionTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'MIS RUTINAS'**
  String get workoutMisRutinasSectionTitle;

  /// No description provided for @workoutMisRutinasCta.
  ///
  /// In es_AR, this message translates to:
  /// **'CREAR RUTINA'**
  String get workoutMisRutinasCta;

  /// No description provided for @workoutMisRutinasCtaDisabledTooltip.
  ///
  /// In es_AR, this message translates to:
  /// **'Llegaste al máximo de 10 rutinas activas. Archivá una para crear otra.'**
  String get workoutMisRutinasCtaDisabledTooltip;

  /// No description provided for @workoutMisRutinasEmptyState.
  ///
  /// In es_AR, this message translates to:
  /// **'Todavía no creaste ninguna rutina. Tocá CREAR RUTINA para armar la primera.'**
  String get workoutMisRutinasEmptyState;

  /// No description provided for @workoutMisRutinasError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tus rutinas.'**
  String get workoutMisRutinasError;

  /// No description provided for @workoutMisRutinasErrorRetry.
  ///
  /// In es_AR, this message translates to:
  /// **'Reintentar'**
  String get workoutMisRutinasErrorRetry;

  /// No description provided for @workoutMisRutinasOverflowEdit.
  ///
  /// In es_AR, this message translates to:
  /// **'EDITAR'**
  String get workoutMisRutinasOverflowEdit;

  /// No description provided for @workoutMisRutinasOverflowArchive.
  ///
  /// In es_AR, this message translates to:
  /// **'ELIMINAR'**
  String get workoutMisRutinasOverflowArchive;

  /// No description provided for @workoutMisRutinasConfirmTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar rutina'**
  String get workoutMisRutinasConfirmTitle;

  /// No description provided for @workoutMisRutinasConfirmBody.
  ///
  /// In es_AR, this message translates to:
  /// **'La rutina dejará de aparecer en MIS RUTINAS. Tu historial se conserva.'**
  String get workoutMisRutinasConfirmBody;

  /// No description provided for @workoutMisRutinasConfirmCancel.
  ///
  /// In es_AR, this message translates to:
  /// **'CANCELAR'**
  String get workoutMisRutinasConfirmCancel;

  /// No description provided for @workoutMisRutinasConfirmConfirm.
  ///
  /// In es_AR, this message translates to:
  /// **'ELIMINAR'**
  String get workoutMisRutinasConfirmConfirm;

  /// No description provided for @workoutMisRutinasArchiveSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Rutina eliminada'**
  String get workoutMisRutinasArchiveSuccess;

  /// No description provided for @workoutMisRutinasArchiveError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos eliminar la rutina. Reintentá.'**
  String get workoutMisRutinasArchiveError;

  /// No description provided for @workoutSplitFallback.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin split'**
  String get workoutSplitFallback;

  /// No description provided for @workoutPickerMuscleFilter.
  ///
  /// In es_AR, this message translates to:
  /// **'Músculos'**
  String get workoutPickerMuscleFilter;

  /// No description provided for @workoutPickerEquipmentFilter.
  ///
  /// In es_AR, this message translates to:
  /// **'Equipamiento'**
  String get workoutPickerEquipmentFilter;

  /// No description provided for @workoutPickerMuscleSheetTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Grupo muscular'**
  String get workoutPickerMuscleSheetTitle;

  /// No description provided for @workoutPickerEquipmentSheetTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Tipo de equipo'**
  String get workoutPickerEquipmentSheetTitle;

  /// No description provided for @workoutPickerMuscleAll.
  ///
  /// In es_AR, this message translates to:
  /// **'Todos los músculos'**
  String get workoutPickerMuscleAll;

  /// No description provided for @workoutPickerEquipmentAll.
  ///
  /// In es_AR, this message translates to:
  /// **'Todo el equipamiento'**
  String get workoutPickerEquipmentAll;

  /// No description provided for @workoutPickerEmptyFiltered.
  ///
  /// In es_AR, this message translates to:
  /// **'Ningún ejercicio coincide'**
  String get workoutPickerEmptyFiltered;

  /// No description provided for @workoutPickerEmptyFilteredHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Probá quitando un filtro o ajustando la búsqueda.'**
  String get workoutPickerEmptyFilteredHint;

  /// No description provided for @workoutPickerAddButton.
  ///
  /// In es_AR, this message translates to:
  /// **'Agregar {count} {count, plural, =1{ejercicio} other{ejercicios}}'**
  String workoutPickerAddButton(int count);

  /// No description provided for @workoutSelfEditorNameHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Mi rutina'**
  String get workoutSelfEditorNameHint;

  /// No description provided for @workoutPickerSheetClear.
  ///
  /// In es_AR, this message translates to:
  /// **'Limpiar'**
  String get workoutPickerSheetClear;

  /// No description provided for @workoutPickerSheetApplyAll.
  ///
  /// In es_AR, this message translates to:
  /// **'APLICAR (TODOS)'**
  String get workoutPickerSheetApplyAll;

  /// No description provided for @workoutPickerSheetApply.
  ///
  /// In es_AR, this message translates to:
  /// **'APLICAR ({count})'**
  String workoutPickerSheetApply(int count);

  /// No description provided for @appFcmSnackBarActionLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Ver'**
  String get appFcmSnackBarActionLabel;

  /// No description provided for @profileEditPersonalNameRequired.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá un nombre'**
  String get profileEditPersonalNameRequired;

  /// No description provided for @profileEditPersonalNameMaxLength.
  ///
  /// In es_AR, this message translates to:
  /// **'Máximo 50 caracteres'**
  String get profileEditPersonalNameMaxLength;

  /// No description provided for @profileEditPersonalWeightInvalidNumber.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá un número válido'**
  String get profileEditPersonalWeightInvalidNumber;

  /// No description provided for @profileEditPersonalWeightOutOfRange.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá un peso entre 30 y 300 kg'**
  String get profileEditPersonalWeightOutOfRange;

  /// No description provided for @profileEditPersonalHeightOutOfRange.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá una altura entre 120 y 230 cm'**
  String get profileEditPersonalHeightOutOfRange;

  /// No description provided for @eliminarCuentaSheetTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar cuenta'**
  String get eliminarCuentaSheetTitle;

  /// No description provided for @eliminarCuentaSheetBodyPrefix.
  ///
  /// In es_AR, this message translates to:
  /// **'Esta acción es '**
  String get eliminarCuentaSheetBodyPrefix;

  /// No description provided for @eliminarCuentaSheetBodyBold.
  ///
  /// In es_AR, this message translates to:
  /// **'irreversible'**
  String get eliminarCuentaSheetBodyBold;

  /// No description provided for @eliminarCuentaSheetBodySuffix.
  ///
  /// In es_AR, this message translates to:
  /// **'. Vamos a eliminar tu cuenta, tu perfil, tu historial de entrenamientos y tu foto. Tus posts van a quedar como \"Usuario eliminado\".'**
  String get eliminarCuentaSheetBodySuffix;

  /// No description provided for @eliminarCuentaSheetDeleteCta.
  ///
  /// In es_AR, this message translates to:
  /// **'ELIMINAR'**
  String get eliminarCuentaSheetDeleteCta;

  /// No description provided for @eliminarCuentaSheetCancelCta.
  ///
  /// In es_AR, this message translates to:
  /// **'CANCELAR'**
  String get eliminarCuentaSheetCancelCta;

  /// No description provided for @eliminarCuentaSheetLoadingLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminando tu cuenta...'**
  String get eliminarCuentaSheetLoadingLabel;

  /// No description provided for @eliminarCuentaSheetLoadingSubtitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Esto puede tardar unos segundos.'**
  String get eliminarCuentaSheetLoadingSubtitle;

  /// No description provided for @eliminarCuentaSheetErrorFallback.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos eliminar tu cuenta. Probá de nuevo.'**
  String get eliminarCuentaSheetErrorFallback;

  /// No description provided for @eliminarCuentaSheetRetryLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Reintentar'**
  String get eliminarCuentaSheetRetryLabel;

  /// No description provided for @dashboardResumenDelDiaTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'RESUMEN DEL DÍA'**
  String get dashboardResumenDelDiaTitle;

  /// No description provided for @dashboardStatPendientes.
  ///
  /// In es_AR, this message translates to:
  /// **'PENDIENTES'**
  String get dashboardStatPendientes;

  /// No description provided for @dashboardStatCompletadas.
  ///
  /// In es_AR, this message translates to:
  /// **'COMPLETADAS'**
  String get dashboardStatCompletadas;

  /// No description provided for @dashboardStatCanceladas.
  ///
  /// In es_AR, this message translates to:
  /// **'CANCELADAS'**
  String get dashboardStatCanceladas;

  /// No description provided for @dashboardProximasSesionesSectionLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'PRÓXIMAS SESIONES'**
  String get dashboardProximasSesionesSectionLabel;

  /// No description provided for @dashboardAgendaTrailingLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Agenda'**
  String get dashboardAgendaTrailingLabel;

  /// No description provided for @dashboardEntrenaronHoySectionLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'ENTRENARON HOY'**
  String get dashboardEntrenaronHoySectionLabel;

  /// No description provided for @dashboardDejarFeedbackLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Dejar feedback'**
  String get dashboardDejarFeedbackLabel;

  /// No description provided for @dashboardActividadRecienteSectionLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'ACTIVIDAD RECIENTE'**
  String get dashboardActividadRecienteSectionLabel;

  /// No description provided for @dashboardWeekday1.
  ///
  /// In es_AR, this message translates to:
  /// **'LUNES'**
  String get dashboardWeekday1;

  /// No description provided for @dashboardWeekday2.
  ///
  /// In es_AR, this message translates to:
  /// **'MARTES'**
  String get dashboardWeekday2;

  /// No description provided for @dashboardWeekday3.
  ///
  /// In es_AR, this message translates to:
  /// **'MIÉRCOLES'**
  String get dashboardWeekday3;

  /// No description provided for @dashboardWeekday4.
  ///
  /// In es_AR, this message translates to:
  /// **'JUEVES'**
  String get dashboardWeekday4;

  /// No description provided for @dashboardWeekday5.
  ///
  /// In es_AR, this message translates to:
  /// **'VIERNES'**
  String get dashboardWeekday5;

  /// No description provided for @dashboardWeekday6.
  ///
  /// In es_AR, this message translates to:
  /// **'SÁBADO'**
  String get dashboardWeekday6;

  /// No description provided for @dashboardWeekday7.
  ///
  /// In es_AR, this message translates to:
  /// **'DOMINGO'**
  String get dashboardWeekday7;

  /// No description provided for @dashboardMonth1.
  ///
  /// In es_AR, this message translates to:
  /// **'ENERO'**
  String get dashboardMonth1;

  /// No description provided for @dashboardMonth2.
  ///
  /// In es_AR, this message translates to:
  /// **'FEBRERO'**
  String get dashboardMonth2;

  /// No description provided for @dashboardMonth3.
  ///
  /// In es_AR, this message translates to:
  /// **'MARZO'**
  String get dashboardMonth3;

  /// No description provided for @dashboardMonth4.
  ///
  /// In es_AR, this message translates to:
  /// **'ABRIL'**
  String get dashboardMonth4;

  /// No description provided for @dashboardMonth5.
  ///
  /// In es_AR, this message translates to:
  /// **'MAYO'**
  String get dashboardMonth5;

  /// No description provided for @dashboardMonth6.
  ///
  /// In es_AR, this message translates to:
  /// **'JUNIO'**
  String get dashboardMonth6;

  /// No description provided for @dashboardMonth7.
  ///
  /// In es_AR, this message translates to:
  /// **'JULIO'**
  String get dashboardMonth7;

  /// No description provided for @dashboardMonth8.
  ///
  /// In es_AR, this message translates to:
  /// **'AGOSTO'**
  String get dashboardMonth8;

  /// No description provided for @dashboardMonth9.
  ///
  /// In es_AR, this message translates to:
  /// **'SEPTIEMBRE'**
  String get dashboardMonth9;

  /// No description provided for @dashboardMonth10.
  ///
  /// In es_AR, this message translates to:
  /// **'OCTUBRE'**
  String get dashboardMonth10;

  /// No description provided for @dashboardMonth11.
  ///
  /// In es_AR, this message translates to:
  /// **'NOVIEMBRE'**
  String get dashboardMonth11;

  /// No description provided for @dashboardMonth12.
  ///
  /// In es_AR, this message translates to:
  /// **'DICIEMBRE'**
  String get dashboardMonth12;

  /// No description provided for @dashboardDateToday.
  ///
  /// In es_AR, this message translates to:
  /// **'Hoy'**
  String get dashboardDateToday;

  /// No description provided for @dashboardDateTomorrow.
  ///
  /// In es_AR, this message translates to:
  /// **'Mañana'**
  String get dashboardDateTomorrow;

  /// No description provided for @dashboardRechazarLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'RECHAZAR'**
  String get dashboardRechazarLabel;

  /// No description provided for @dashboardAceptarLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'ACEPTAR'**
  String get dashboardAceptarLabel;

  /// No description provided for @dashboardPagosPorCobrarTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'PAGOS POR COBRAR'**
  String get dashboardPagosPorCobrarTitle;

  /// No description provided for @dashboardCobroTrailingLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'+ Cobro'**
  String get dashboardCobroTrailingLabel;

  /// No description provided for @dashboardInvitarAlumnoLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'+ INVITAR ALUMNO'**
  String get dashboardInvitarAlumnoLabel;

  /// No description provided for @dashboardAsignarRutinaLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'+ ASIGNAR RUTINA'**
  String get dashboardAsignarRutinaLabel;

  /// No description provided for @dashboardCobroSueltoTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'COBRO SUELTO'**
  String get dashboardCobroSueltoTitle;

  /// No description provided for @dashboardAlumnoLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'ALUMNO'**
  String get dashboardAlumnoLabel;

  /// No description provided for @dashboardMontoArsLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'MONTO (ARS)'**
  String get dashboardMontoArsLabel;

  /// No description provided for @dashboardConceptoLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'CONCEPTO'**
  String get dashboardConceptoLabel;

  /// No description provided for @dashboardAgregarCobroLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'AGREGAR COBRO'**
  String get dashboardAgregarCobroLabel;

  /// No description provided for @dashboardMontoHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Ej: 5000'**
  String get dashboardMontoHint;

  /// No description provided for @dashboardConceptoHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Ej: Clase de verano'**
  String get dashboardConceptoHint;

  /// No description provided for @dashboardSeleccionaAlumnoHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Seleccioná un alumno'**
  String get dashboardSeleccionaAlumnoHint;

  /// No description provided for @dashboardSinAlumnosActivos.
  ///
  /// In es_AR, this message translates to:
  /// **'No tenés alumnos activos.'**
  String get dashboardSinAlumnosActivos;

  /// No description provided for @dashboardMarcarCobradoTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Marcar como cobrado?'**
  String get dashboardMarcarCobradoTitle;

  /// No description provided for @dashboardCancelarLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Cancelar'**
  String get dashboardCancelarLabel;

  /// No description provided for @dashboardCobradoLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Cobrado'**
  String get dashboardCobradoLabel;

  /// No description provided for @dashboardCobroRegistrado.
  ///
  /// In es_AR, this message translates to:
  /// **'Cobro registrado.'**
  String get dashboardCobroRegistrado;

  /// No description provided for @dashboardCobroError.
  ///
  /// In es_AR, this message translates to:
  /// **'Error al registrar el cobro. Intentá de nuevo.'**
  String get dashboardCobroError;

  /// No description provided for @dashboardCobroSueltoAgregado.
  ///
  /// In es_AR, this message translates to:
  /// **'Cobro suelto agregado.'**
  String get dashboardCobroSueltoAgregado;

  /// No description provided for @dashboardCompletaCampos.
  ///
  /// In es_AR, this message translates to:
  /// **'Completá todos los campos.'**
  String get dashboardCompletaCampos;

  /// No description provided for @dashboardMontoInvalido.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá un monto válido.'**
  String get dashboardMontoInvalido;

  /// No description provided for @dashboardGuardarError.
  ///
  /// In es_AR, this message translates to:
  /// **'Error al guardar. Intentá de nuevo.'**
  String get dashboardGuardarError;

  /// No description provided for @dashboardCadenceMensual.
  ///
  /// In es_AR, this message translates to:
  /// **'Mensual'**
  String get dashboardCadenceMensual;

  /// No description provided for @dashboardCadenceSemanal.
  ///
  /// In es_AR, this message translates to:
  /// **'Semanal'**
  String get dashboardCadenceSemanal;

  /// No description provided for @dashboardCadencePorSesion.
  ///
  /// In es_AR, this message translates to:
  /// **'Por sesión'**
  String get dashboardCadencePorSesion;

  /// No description provided for @dashboardCadenceSuelto.
  ///
  /// In es_AR, this message translates to:
  /// **'Suelto'**
  String get dashboardCadenceSuelto;

  /// No description provided for @dashboardAlumnoFallback.
  ///
  /// In es_AR, this message translates to:
  /// **'Alumno'**
  String get dashboardAlumnoFallback;

  /// No description provided for @dashboardProximamente.
  ///
  /// In es_AR, this message translates to:
  /// **'Próximamente.'**
  String get dashboardProximamente;

  /// No description provided for @dashboardIniciaSesion.
  ///
  /// In es_AR, this message translates to:
  /// **'Iniciá sesión para ver tus próximos turnos.'**
  String get dashboardIniciaSesion;

  /// No description provided for @dashboardCargando.
  ///
  /// In es_AR, this message translates to:
  /// **'Cargando…'**
  String get dashboardCargando;

  /// No description provided for @dashboardErrorTurnos.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tus próximos turnos.'**
  String get dashboardErrorTurnos;

  /// No description provided for @dashboardSinTurnosProximos.
  ///
  /// In es_AR, this message translates to:
  /// **'No tenés turnos próximos confirmados.'**
  String get dashboardSinTurnosProximos;

  /// No description provided for @dashboardNadieEntreno.
  ///
  /// In es_AR, this message translates to:
  /// **'Nadie entrenó hoy todavía.'**
  String get dashboardNadieEntreno;

  /// No description provided for @dashboardErrorActividad.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar la actividad de hoy.'**
  String get dashboardErrorActividad;

  /// No description provided for @dashboardSinCobros.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin cobros pendientes.'**
  String get dashboardSinCobros;

  /// No description provided for @dashboardErrorCobros.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar los cobros.'**
  String get dashboardErrorCobros;

  /// No description provided for @dashboardHolaSinNombre.
  ///
  /// In es_AR, this message translates to:
  /// **'HOLA'**
  String get dashboardHolaSinNombre;

  /// No description provided for @dashboardInvitarProximamente.
  ///
  /// In es_AR, this message translates to:
  /// **'Invitar alumno — próximamente.'**
  String get dashboardInvitarProximamente;

  /// No description provided for @dashboardSolicitudesPendientesTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'SOLICITUDES PENDIENTES ({count})'**
  String dashboardSolicitudesPendientesTitle(int count);

  /// No description provided for @dashboardHolaConNombre.
  ///
  /// In es_AR, this message translates to:
  /// **'HOLA, {name}'**
  String dashboardHolaConNombre(String name);

  /// No description provided for @reviewSnackBarSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'¡Gracias por tu reseña!'**
  String get reviewSnackBarSuccess;

  /// No description provided for @plantillasRetryLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Reintentar'**
  String get plantillasRetryLabel;

  /// No description provided for @profileSetupSaveError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos guardar tu perfil. Probá de nuevo.'**
  String get profileSetupSaveError;

  /// No description provided for @profileSetupCancelDialogTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Cancelar la creación de tu cuenta?'**
  String get profileSetupCancelDialogTitle;

  /// No description provided for @profileSetupCancelDialogBody.
  ///
  /// In es_AR, this message translates to:
  /// **'Vamos a borrar tu cuenta. Esta acción no se puede deshacer.'**
  String get profileSetupCancelDialogBody;

  /// No description provided for @profileSetupCancelAccountError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cancelar la cuenta. Probá de nuevo.'**
  String get profileSetupCancelAccountError;

  /// No description provided for @reAuthPasswordLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Contraseña'**
  String get reAuthPasswordLabel;

  /// No description provided for @profileGymSearchHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Buscar gym'**
  String get profileGymSearchHint;

  /// No description provided for @profileEditTrainerTitleEdit.
  ///
  /// In es_AR, this message translates to:
  /// **'Editá tu perfil profesional'**
  String get profileEditTrainerTitleEdit;

  /// No description provided for @profileEditTrainerTitleOnboarding.
  ///
  /// In es_AR, this message translates to:
  /// **'Completá tu perfil profesional'**
  String get profileEditTrainerTitleOnboarding;

  /// No description provided for @profileEditTrainerSaveSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Perfil actualizado.'**
  String get profileEditTrainerSaveSuccess;

  /// No description provided for @profileEditTrainerSaveError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos guardar. Probá de nuevo.'**
  String get profileEditTrainerSaveError;

  /// No description provided for @profileEditTrainerValidationSpecialty.
  ///
  /// In es_AR, this message translates to:
  /// **'Elegí una especialidad.'**
  String get profileEditTrainerValidationSpecialty;

  /// No description provided for @profileEditTrainerValidationLocation.
  ///
  /// In es_AR, this message translates to:
  /// **'Agregá al menos una ubicación o activá clases virtuales.'**
  String get profileEditTrainerValidationLocation;

  /// No description provided for @athleteDetailPlansSection.
  ///
  /// In es_AR, this message translates to:
  /// **'PLANES ASIGNADOS'**
  String get athleteDetailPlansSection;

  /// No description provided for @athleteDetailProfileLoadError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar este perfil.'**
  String get athleteDetailProfileLoadError;

  /// No description provided for @athleteDetailPlanDeleteTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar plan'**
  String get athleteDetailPlanDeleteTitle;

  /// No description provided for @athleteDetailPlanDeleteCancel.
  ///
  /// In es_AR, this message translates to:
  /// **'Cancelar'**
  String get athleteDetailPlanDeleteCancel;

  /// No description provided for @athleteDetailPlanDeleteConfirm.
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar'**
  String get athleteDetailPlanDeleteConfirm;

  /// No description provided for @athleteDetailPlanDeleteSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Plan eliminado.'**
  String get athleteDetailPlanDeleteSuccess;

  /// No description provided for @athleteDetailMessageCta.
  ///
  /// In es_AR, this message translates to:
  /// **'MENSAJE'**
  String get athleteDetailMessageCta;

  /// No description provided for @newSessionSheetTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'NUEVA SESIÓN'**
  String get newSessionSheetTitle;

  /// No description provided for @newSessionSheetAlumnoLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'ALUMNO'**
  String get newSessionSheetAlumnoLabel;

  /// No description provided for @newSessionSheetFechaLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'FECHA'**
  String get newSessionSheetFechaLabel;

  /// No description provided for @newSessionSheetHoraLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'HORA DE INICIO'**
  String get newSessionSheetHoraLabel;

  /// No description provided for @newSessionSheetDuracionLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'DURACIÓN (MIN)'**
  String get newSessionSheetDuracionLabel;

  /// No description provided for @newSessionSheetNotaLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'NOTA PREVIA (OPCIONAL)'**
  String get newSessionSheetNotaLabel;

  /// No description provided for @newSessionSheetSubmitSingle.
  ///
  /// In es_AR, this message translates to:
  /// **'REGISTRAR SESIÓN'**
  String get newSessionSheetSubmitSingle;

  /// No description provided for @newSessionSheetSubmitRecurring.
  ///
  /// In es_AR, this message translates to:
  /// **'REGISTRAR SERIE'**
  String get newSessionSheetSubmitRecurring;

  /// No description provided for @newSessionSheetDurationError.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá una duración válida (5–480 min).'**
  String get newSessionSheetDurationError;

  /// No description provided for @newSessionSheetNoActiveAthletes.
  ///
  /// In es_AR, this message translates to:
  /// **'No tenés alumnos activos.'**
  String get newSessionSheetNoActiveAthletes;

  /// No description provided for @athleteCoachViewTrainerFallbackName.
  ///
  /// In es_AR, this message translates to:
  /// **'tu Personal Trainer'**
  String get athleteCoachViewTrainerFallbackName;

  /// No description provided for @athleteCoachViewLinkError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tu vínculo.'**
  String get athleteCoachViewLinkError;

  /// No description provided for @checkInHeader.
  ///
  /// In es_AR, this message translates to:
  /// **'¿ESTÁS EN EL GYM HOY?'**
  String get checkInHeader;

  /// No description provided for @checkInNeutralSubtext.
  ///
  /// In es_AR, this message translates to:
  /// **'Confirma tu entrenamiento de hoy'**
  String get checkInNeutralSubtext;

  /// No description provided for @checkInNoButton.
  ///
  /// In es_AR, this message translates to:
  /// **'NO'**
  String get checkInNoButton;

  /// No description provided for @checkInSiButton.
  ///
  /// In es_AR, this message translates to:
  /// **'SÍ, ENTRÉ'**
  String get checkInSiButton;

  /// No description provided for @checkInGymSubtext.
  ///
  /// In es_AR, this message translates to:
  /// **'{gymName} · ¡Detectamos que podés estar entrenando!'**
  String checkInGymSubtext(String gymName);

  /// No description provided for @checkInError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos registrar tu check-in. Probá de nuevo.'**
  String get checkInError;

  /// No description provided for @profileCuentaTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'CUENTA'**
  String get profileCuentaTitle;

  /// No description provided for @profileCuentaSolicitudesTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Solicitudes de amistad'**
  String get profileCuentaSolicitudesTitle;

  /// No description provided for @profileCuentaSolicitudesSubtitle.
  ///
  /// In es_AR, this message translates to:
  /// **'{count} nuevas'**
  String profileCuentaSolicitudesSubtitle(int count);

  /// No description provided for @profileCuentaDatosPersonalesTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Datos personales'**
  String get profileCuentaDatosPersonalesTitle;

  /// No description provided for @profileCuentaDatosPersonalesSubtitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Editá tu info'**
  String get profileCuentaDatosPersonalesSubtitle;

  /// No description provided for @profileCuentaGimnasioTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Gimnasio'**
  String get profileCuentaGimnasioTitle;

  /// No description provided for @profileCuentaNoGym.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin gym'**
  String get profileCuentaNoGym;

  /// No description provided for @profileCuentaMisRutinasTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Mis rutinas'**
  String get profileCuentaMisRutinasTitle;

  /// No description provided for @profileCuentaRutinasSubtitle.
  ///
  /// In es_AR, this message translates to:
  /// **'{count} activas'**
  String profileCuentaRutinasSubtitle(int count);

  /// No description provided for @chatListTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'MENSAJES'**
  String get chatListTitle;

  /// No description provided for @chatListDeletedUser.
  ///
  /// In es_AR, this message translates to:
  /// **'Usuario eliminado'**
  String get chatListDeletedUser;

  /// No description provided for @chatListStartConversation.
  ///
  /// In es_AR, this message translates to:
  /// **'Iniciá la conversación'**
  String get chatListStartConversation;

  /// No description provided for @chatListEmptyTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin mensajes todavía'**
  String get chatListEmptyTitle;

  /// No description provided for @chatListEmptyBody.
  ///
  /// In es_AR, this message translates to:
  /// **'Cuando tengas un vínculo activo con un PF, vas a poder chatear desde acá.'**
  String get chatListEmptyBody;

  /// No description provided for @chatListError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tus mensajes.'**
  String get chatListError;

  /// No description provided for @chatListRetryLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Reintentar'**
  String get chatListRetryLabel;

  /// No description provided for @chatRelativeJustNow.
  ///
  /// In es_AR, this message translates to:
  /// **'recién'**
  String get chatRelativeJustNow;

  /// No description provided for @chatRelativeMinutes.
  ///
  /// In es_AR, this message translates to:
  /// **'hace {minutes}m'**
  String chatRelativeMinutes(int minutes);

  /// No description provided for @chatRelativeHours.
  ///
  /// In es_AR, this message translates to:
  /// **'hace {hours}h'**
  String chatRelativeHours(int hours);

  /// No description provided for @chatRelativeDays.
  ///
  /// In es_AR, this message translates to:
  /// **'hace {days}d'**
  String chatRelativeDays(int days);

  /// No description provided for @chatScreenTitleFallback.
  ///
  /// In es_AR, this message translates to:
  /// **'Usuario'**
  String get chatScreenTitleFallback;

  /// No description provided for @chatScreenLoadError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar los mensajes.'**
  String get chatScreenLoadError;

  /// No description provided for @chatScreenComposerHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Escribí un mensaje…'**
  String get chatScreenComposerHint;

  /// No description provided for @chatScreenSendLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Enviar'**
  String get chatScreenSendLabel;

  /// No description provided for @chatScreenSendError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos enviar el mensaje. Probá de nuevo.'**
  String get chatScreenSendError;

  /// No description provided for @performanceLogTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Cargar evaluación'**
  String get performanceLogTitle;

  /// No description provided for @performanceLogCancel.
  ///
  /// In es_AR, this message translates to:
  /// **'Cancelar'**
  String get performanceLogCancel;

  /// No description provided for @performanceLogSaveCta.
  ///
  /// In es_AR, this message translates to:
  /// **'GUARDAR EVALUACIÓN'**
  String get performanceLogSaveCta;

  /// No description provided for @performanceLogNoSession.
  ///
  /// In es_AR, this message translates to:
  /// **'No hay sesión activa. No se puede guardar.'**
  String get performanceLogNoSession;

  /// No description provided for @performanceLogSaveSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Evaluación guardada'**
  String get performanceLogSaveSuccess;

  /// No description provided for @performanceLogSaveError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos guardar la evaluación. Probá de nuevo.'**
  String get performanceLogSaveError;

  /// No description provided for @performanceLogNotesHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Observaciones del entrenador…'**
  String get performanceLogNotesHint;

  /// No description provided for @performanceLogSectionJumps.
  ///
  /// In es_AR, this message translates to:
  /// **'SALTOS (cm)'**
  String get performanceLogSectionJumps;

  /// No description provided for @performanceLogSectionSpeed.
  ///
  /// In es_AR, this message translates to:
  /// **'VELOCIDAD (seg)'**
  String get performanceLogSectionSpeed;

  /// No description provided for @performanceLogSectionStrength.
  ///
  /// In es_AR, this message translates to:
  /// **'FUERZA 1RM (kg)'**
  String get performanceLogSectionStrength;

  /// No description provided for @performanceLogSectionEndurance.
  ///
  /// In es_AR, this message translates to:
  /// **'RESISTENCIA / OTROS'**
  String get performanceLogSectionEndurance;

  /// No description provided for @performanceLogSectionNotes.
  ///
  /// In es_AR, this message translates to:
  /// **'NOTAS'**
  String get performanceLogSectionNotes;

  /// No description provided for @performanceLogFieldCmj.
  ///
  /// In es_AR, this message translates to:
  /// **'CMJ'**
  String get performanceLogFieldCmj;

  /// No description provided for @performanceLogFieldSquatJump.
  ///
  /// In es_AR, this message translates to:
  /// **'Squat Jump'**
  String get performanceLogFieldSquatJump;

  /// No description provided for @performanceLogFieldAbalakov.
  ///
  /// In es_AR, this message translates to:
  /// **'Abalakov'**
  String get performanceLogFieldAbalakov;

  /// No description provided for @performanceLogFieldBroadJump.
  ///
  /// In es_AR, this message translates to:
  /// **'Salto largo'**
  String get performanceLogFieldBroadJump;

  /// No description provided for @performanceLogFieldSprint10.
  ///
  /// In es_AR, this message translates to:
  /// **'Sprint 10m'**
  String get performanceLogFieldSprint10;

  /// No description provided for @performanceLogFieldSprint20.
  ///
  /// In es_AR, this message translates to:
  /// **'20m'**
  String get performanceLogFieldSprint20;

  /// No description provided for @performanceLogFieldSprint30.
  ///
  /// In es_AR, this message translates to:
  /// **'30m'**
  String get performanceLogFieldSprint30;

  /// No description provided for @performanceLogFieldSprint40.
  ///
  /// In es_AR, this message translates to:
  /// **'40m'**
  String get performanceLogFieldSprint40;

  /// No description provided for @performanceLogFieldSquat1rm.
  ///
  /// In es_AR, this message translates to:
  /// **'Sentadilla'**
  String get performanceLogFieldSquat1rm;

  /// No description provided for @performanceLogFieldBenchPress.
  ///
  /// In es_AR, this message translates to:
  /// **'Press banca'**
  String get performanceLogFieldBenchPress;

  /// No description provided for @performanceLogFieldDeadlift.
  ///
  /// In es_AR, this message translates to:
  /// **'Peso muerto'**
  String get performanceLogFieldDeadlift;

  /// No description provided for @performanceLogFieldOverheadPress.
  ///
  /// In es_AR, this message translates to:
  /// **'Press militar'**
  String get performanceLogFieldOverheadPress;

  /// No description provided for @performanceLogFieldPullUp.
  ///
  /// In es_AR, this message translates to:
  /// **'Dominada lastrada'**
  String get performanceLogFieldPullUp;

  /// No description provided for @performanceLogFieldVo2max.
  ///
  /// In es_AR, this message translates to:
  /// **'VO2máx'**
  String get performanceLogFieldVo2max;

  /// No description provided for @performanceLogFieldCourseNavette.
  ///
  /// In es_AR, this message translates to:
  /// **'Course Navette (nivel)'**
  String get performanceLogFieldCourseNavette;

  /// No description provided for @performanceLogFieldCooper.
  ///
  /// In es_AR, this message translates to:
  /// **'Cooper'**
  String get performanceLogFieldCooper;

  /// No description provided for @performanceLogFieldSitAndReach.
  ///
  /// In es_AR, this message translates to:
  /// **'Flexibilidad sit-and-reach'**
  String get performanceLogFieldSitAndReach;

  /// No description provided for @performanceChartSectionLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'PROGRESO'**
  String get performanceChartSectionLabel;

  /// No description provided for @performanceChartEmptyHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Cargá otra evaluación para ver el progreso.'**
  String get performanceChartEmptyHint;

  /// No description provided for @performanceChartSpanDays.
  ///
  /// In es_AR, this message translates to:
  /// **'({count} {count, plural, =1{día} other{días}})'**
  String performanceChartSpanDays(int count);

  /// No description provided for @performanceChartSpanWeeks.
  ///
  /// In es_AR, this message translates to:
  /// **'({count} {count, plural, =1{semana} other{semanas}})'**
  String performanceChartSpanWeeks(int count);

  /// No description provided for @performanceChartMetricCmj.
  ///
  /// In es_AR, this message translates to:
  /// **'CMJ'**
  String get performanceChartMetricCmj;

  /// No description provided for @performanceChartMetricSquatJump.
  ///
  /// In es_AR, this message translates to:
  /// **'Squat Jump'**
  String get performanceChartMetricSquatJump;

  /// No description provided for @performanceChartMetricAbalakov.
  ///
  /// In es_AR, this message translates to:
  /// **'Abalakov'**
  String get performanceChartMetricAbalakov;

  /// No description provided for @performanceChartMetricBroadJump.
  ///
  /// In es_AR, this message translates to:
  /// **'Salto largo'**
  String get performanceChartMetricBroadJump;

  /// No description provided for @performanceChartMetricSprint10.
  ///
  /// In es_AR, this message translates to:
  /// **'Sprint 10m'**
  String get performanceChartMetricSprint10;

  /// No description provided for @performanceChartMetricSprint20.
  ///
  /// In es_AR, this message translates to:
  /// **'Sprint 20m'**
  String get performanceChartMetricSprint20;

  /// No description provided for @performanceChartMetricSprint30.
  ///
  /// In es_AR, this message translates to:
  /// **'Sprint 30m'**
  String get performanceChartMetricSprint30;

  /// No description provided for @performanceChartMetricSprint40.
  ///
  /// In es_AR, this message translates to:
  /// **'Sprint 40m'**
  String get performanceChartMetricSprint40;

  /// No description provided for @performanceChartMetricSquat1rm.
  ///
  /// In es_AR, this message translates to:
  /// **'Sentadilla 1RM'**
  String get performanceChartMetricSquat1rm;

  /// No description provided for @performanceChartMetricBench1rm.
  ///
  /// In es_AR, this message translates to:
  /// **'Banca 1RM'**
  String get performanceChartMetricBench1rm;

  /// No description provided for @performanceChartMetricDeadlift1rm.
  ///
  /// In es_AR, this message translates to:
  /// **'Peso muerto 1RM'**
  String get performanceChartMetricDeadlift1rm;

  /// No description provided for @performanceChartMetricOverheadPress1rm.
  ///
  /// In es_AR, this message translates to:
  /// **'Press militar 1RM'**
  String get performanceChartMetricOverheadPress1rm;

  /// No description provided for @performanceChartMetricPullUp1rm.
  ///
  /// In es_AR, this message translates to:
  /// **'Dominada 1RM'**
  String get performanceChartMetricPullUp1rm;

  /// No description provided for @performanceChartMetricVo2max.
  ///
  /// In es_AR, this message translates to:
  /// **'VO2máx'**
  String get performanceChartMetricVo2max;

  /// No description provided for @performanceChartMetricCourseNavette.
  ///
  /// In es_AR, this message translates to:
  /// **'Course Navette'**
  String get performanceChartMetricCourseNavette;

  /// No description provided for @performanceChartMetricCooper.
  ///
  /// In es_AR, this message translates to:
  /// **'Cooper'**
  String get performanceChartMetricCooper;

  /// No description provided for @performanceChartMetricSitAndReach.
  ///
  /// In es_AR, this message translates to:
  /// **'Flexibilidad'**
  String get performanceChartMetricSitAndReach;

  /// No description provided for @routineEditorDayName.
  ///
  /// In es_AR, this message translates to:
  /// **'Día {n}'**
  String routineEditorDayName(int n);

  /// No description provided for @routineEditorAddExercise.
  ///
  /// In es_AR, this message translates to:
  /// **'Agregar ejercicio'**
  String get routineEditorAddExercise;

  /// No description provided for @routineEditorLevelLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'NIVEL'**
  String get routineEditorLevelLabel;

  /// No description provided for @routineEditorWeeksLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'SEMANAS'**
  String get routineEditorWeeksLabel;

  /// No description provided for @routineEditorDaysLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'DÍAS DEL PLAN'**
  String get routineEditorDaysLabel;

  /// No description provided for @routineEditorAddWeek.
  ///
  /// In es_AR, this message translates to:
  /// **'Semana'**
  String get routineEditorAddWeek;

  /// No description provided for @routineEditorRemoveLastWeek.
  ///
  /// In es_AR, this message translates to:
  /// **'Quitar última'**
  String get routineEditorRemoveLastWeek;

  /// No description provided for @routineEditorDuplicateWeek.
  ///
  /// In es_AR, this message translates to:
  /// **'Duplicar semana'**
  String get routineEditorDuplicateWeek;

  /// No description provided for @routineEditorWeekShort.
  ///
  /// In es_AR, this message translates to:
  /// **'Sem {n}'**
  String routineEditorWeekShort(int n);

  /// No description provided for @routineEditorInvalidWeekHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Sets incompletos en Sem {week} · Día {day}'**
  String routineEditorInvalidWeekHint(int week, int day);

  /// No description provided for @routineEditorDuplicateWeekTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'Duplicar semana'**
  String get routineEditorDuplicateWeekTitle;

  /// No description provided for @routineEditorDuplicateWeekBody.
  ///
  /// In es_AR, this message translates to:
  /// **'Se copiará la Semana {sourceWeek} en la Semana {targetWeek}.'**
  String routineEditorDuplicateWeekBody(int sourceWeek, int targetWeek);

  /// No description provided for @routineEditorDialogCancel.
  ///
  /// In es_AR, this message translates to:
  /// **'Cancelar'**
  String get routineEditorDialogCancel;

  /// No description provided for @routineEditorDialogConfirm.
  ///
  /// In es_AR, this message translates to:
  /// **'Confirmar'**
  String get routineEditorDialogConfirm;

  /// No description provided for @routineEditorSlotMenuReplace.
  ///
  /// In es_AR, this message translates to:
  /// **'Cambiar ejercicio'**
  String get routineEditorSlotMenuReplace;

  /// No description provided for @routineEditorSlotMenuMoveUp.
  ///
  /// In es_AR, this message translates to:
  /// **'Subir'**
  String get routineEditorSlotMenuMoveUp;

  /// No description provided for @routineEditorSlotMenuMoveDown.
  ///
  /// In es_AR, this message translates to:
  /// **'Bajar'**
  String get routineEditorSlotMenuMoveDown;

  /// No description provided for @routineEditorSlotMenuRemove.
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar'**
  String get routineEditorSlotMenuRemove;

  /// No description provided for @routineEditorRestLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Descanso'**
  String get routineEditorRestLabel;

  /// No description provided for @routineEditorAddSet.
  ///
  /// In es_AR, this message translates to:
  /// **'+ Agregar set'**
  String get routineEditorAddSet;

  /// No description provided for @routineEditorMeasureReps.
  ///
  /// In es_AR, this message translates to:
  /// **'Reps'**
  String get routineEditorMeasureReps;

  /// No description provided for @routineEditorMeasureTime.
  ///
  /// In es_AR, this message translates to:
  /// **'Tiempo'**
  String get routineEditorMeasureTime;

  /// No description provided for @routineEditorSetTypeNormal.
  ///
  /// In es_AR, this message translates to:
  /// **'Normal'**
  String get routineEditorSetTypeNormal;

  /// No description provided for @routineEditorSetTypeWarmup.
  ///
  /// In es_AR, this message translates to:
  /// **'Entrada en calor (W)'**
  String get routineEditorSetTypeWarmup;

  /// No description provided for @routineEditorSetTypeDrop.
  ///
  /// In es_AR, this message translates to:
  /// **'Drop (D)'**
  String get routineEditorSetTypeDrop;

  /// No description provided for @routineEditorSetTypeFailure.
  ///
  /// In es_AR, this message translates to:
  /// **'Al fallo (F)'**
  String get routineEditorSetTypeFailure;

  /// No description provided for @routineDetailNotFound.
  ///
  /// In es_AR, this message translates to:
  /// **'Rutina no encontrada'**
  String get routineDetailNotFound;

  /// No description provided for @routineDetailNoDaysConfigured.
  ///
  /// In es_AR, this message translates to:
  /// **'Esta rutina no tiene días configurados.'**
  String get routineDetailNoDaysConfigured;

  /// No description provided for @routineDetailLoadError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar la rutina.'**
  String get routineDetailLoadError;

  /// No description provided for @routineDetailNoExercisesThisWeek.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin ejercicios esta semana'**
  String get routineDetailNoExercisesThisWeek;

  /// No description provided for @routineDetailNoExercisesThisDay.
  ///
  /// In es_AR, this message translates to:
  /// **'No hay ejercicios en este día'**
  String get routineDetailNoExercisesThisDay;

  /// No description provided for @routineDetailStatExercises.
  ///
  /// In es_AR, this message translates to:
  /// **'EJERCICIOS'**
  String get routineDetailStatExercises;

  /// No description provided for @routineDetailStatSets.
  ///
  /// In es_AR, this message translates to:
  /// **'SETS'**
  String get routineDetailStatSets;

  /// No description provided for @routineDetailStatMinutes.
  ///
  /// In es_AR, this message translates to:
  /// **'MINUTOS'**
  String get routineDetailStatMinutes;

  /// No description provided for @routineDetailSuperset.
  ///
  /// In es_AR, this message translates to:
  /// **'SUPERSERIE'**
  String get routineDetailSuperset;

  /// No description provided for @routineDetailDayLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'DÍA {day}'**
  String routineDetailDayLabel(int day);

  /// No description provided for @routineDetailWeekLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'SEM {week}'**
  String routineDetailWeekLabel(int week);

  /// No description provided for @routineDetailPlanComplete.
  ///
  /// In es_AR, this message translates to:
  /// **'PLAN COMPLETADO'**
  String get routineDetailPlanComplete;

  /// No description provided for @routineDetailCompleted.
  ///
  /// In es_AR, this message translates to:
  /// **'COMPLETADO'**
  String get routineDetailCompleted;

  /// No description provided for @routineDetailWeekLocked.
  ///
  /// In es_AR, this message translates to:
  /// **'SEMANA BLOQUEADA'**
  String get routineDetailWeekLocked;

  /// No description provided for @routineDetailDayLocked.
  ///
  /// In es_AR, this message translates to:
  /// **'DÍA BLOQUEADO'**
  String get routineDetailDayLocked;

  /// No description provided for @routineDetailStart.
  ///
  /// In es_AR, this message translates to:
  /// **'EMPEZAR'**
  String get routineDetailStart;

  /// No description provided for @routineEditorDeleteScopeTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Eliminar solo de esta semana o de todas?'**
  String get routineEditorDeleteScopeTitle;

  /// No description provided for @routineEditorScopeOnlyThisWeek.
  ///
  /// In es_AR, this message translates to:
  /// **'Solo esta semana'**
  String get routineEditorScopeOnlyThisWeek;

  /// No description provided for @routineEditorScopeAllWeeks.
  ///
  /// In es_AR, this message translates to:
  /// **'Todas las semanas'**
  String get routineEditorScopeAllWeeks;

  /// No description provided for @routineEditorAddScopeTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'¿En qué semanas agregar?'**
  String get routineEditorAddScopeTitle;

  /// No description provided for @routineEditorAddScopeBody.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Agregar el ejercicio solo en esta semana o en todas?'**
  String get routineEditorAddScopeBody;

  /// No description provided for @routineEditorAddOnlyThisWeek.
  ///
  /// In es_AR, this message translates to:
  /// **'Agregar solo en esta semana'**
  String get routineEditorAddOnlyThisWeek;

  /// No description provided for @routineEditorAddAllWeeks.
  ///
  /// In es_AR, this message translates to:
  /// **'Agregar en todas las semanas'**
  String get routineEditorAddAllWeeks;

  /// No description provided for @routineEditorWeekLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Semana'**
  String get routineEditorWeekLabel;

  /// No description provided for @routineEditorLevelSection.
  ///
  /// In es_AR, this message translates to:
  /// **'NIVEL'**
  String get routineEditorLevelSection;

  /// No description provided for @routineEditorWeeksSection.
  ///
  /// In es_AR, this message translates to:
  /// **'SEMANAS'**
  String get routineEditorWeeksSection;

  /// No description provided for @routineEditorDaysSection.
  ///
  /// In es_AR, this message translates to:
  /// **'DÍAS DEL PLAN'**
  String get routineEditorDaysSection;

  /// No description provided for @routineEditorNameHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Ej: Fuerza PPL'**
  String get routineEditorNameHint;

  /// No description provided for @routineEditorSplitHint.
  ///
  /// In es_AR, this message translates to:
  /// **'PPL / Full Body'**
  String get routineEditorSplitHint;

  /// No description provided for @routineEditorIncompleteSetsLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Sets incompletos en Sem {weekNumber}'**
  String routineEditorIncompleteSetsLabel(int weekNumber);
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'es':
      {
        switch (locale.countryCode) {
          case 'AR':
            return AppL10nEsAr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'es':
      return AppL10nEs();
  }

  throw FlutterError(
      'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
