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
