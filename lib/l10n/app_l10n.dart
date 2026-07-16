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

  /// Home first-run empty-state title for an athlete with no routine (usability finding 6).
  ///
  /// In es_AR, this message translates to:
  /// **'Arrancá tu entrenamiento'**
  String get homeAthleteFirstRunTitle;

  /// Home first-run empty-state body offering both the create-routine and find-trainer paths (finding 6).
  ///
  /// In es_AR, this message translates to:
  /// **'Creá tu primera rutina o buscá un entrenador para empezar.'**
  String get homeAthleteFirstRunBody;

  /// Home first-run primary CTA to create a routine (finding 6).
  ///
  /// In es_AR, this message translates to:
  /// **'CREAR RUTINA'**
  String get homeAthleteFirstRunCreateCta;

  /// Home first-run secondary CTA to browse trainers (finding 6).
  ///
  /// In es_AR, this message translates to:
  /// **'Buscar entrenador'**
  String get homeAthleteFirstRunFindTrainerCta;

  /// Home 'Esta Semana' card section title (skeleton, error and loaded states).
  ///
  /// In es_AR, this message translates to:
  /// **'ESTA SEMANA'**
  String get homeEstaSemanaTitle;

  /// Home 'Esta Semana' card error message shown when weekly insights fail to load.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tus insights.'**
  String get homeEstaSemanaLoadError;

  /// Home 'Esta Semana' card header pill label when the athlete has an active streak.
  ///
  /// In es_AR, this message translates to:
  /// **'RACHA ACTUAL'**
  String get homeEstaSemanaHeaderPill;

  /// Home 'Esta Semana' card header pill label in the empty state (no sessions yet).
  ///
  /// In es_AR, this message translates to:
  /// **'PRIMER PASO'**
  String get homeEstaSemanaHeaderPillEmpty;

  /// No description provided for @homeEstaSemanaWeekMonth.
  ///
  /// In es_AR, this message translates to:
  /// **'SEM {week} · {month}'**
  String homeEstaSemanaWeekMonth(int week, String month);

  /// No description provided for @homeEstaSemanaStreakUnit.
  ///
  /// In es_AR, this message translates to:
  /// **'{count, plural, =1{DÍA} other{DÍAS}}'**
  String homeEstaSemanaStreakUnit(int count);

  /// Home 'Esta Semana' card streak subtext shown when the athlete already trained today.
  ///
  /// In es_AR, this message translates to:
  /// **'No rompas la racha — entrenaste hoy.'**
  String get homeEstaSemanaStreakSubtextTrained;

  /// Home 'Esta Semana' card streak subtext shown when the athlete hasn't trained today yet.
  ///
  /// In es_AR, this message translates to:
  /// **'No rompas la racha — entrená hoy.'**
  String get homeEstaSemanaStreakSubtextPending;

  /// Home 'Esta Semana' card period card label for the current week count.
  ///
  /// In es_AR, this message translates to:
  /// **'SEMANA'**
  String get homeEstaSemanaPeriodWeek;

  /// Home 'Esta Semana' card period card label for the current month count.
  ///
  /// In es_AR, this message translates to:
  /// **'MES'**
  String get homeEstaSemanaPeriodMonth;

  /// No description provided for @homeEstaSemanaPeriodUnit.
  ///
  /// In es_AR, this message translates to:
  /// **'{count, plural, =1{entreno} other{entrenos}}'**
  String homeEstaSemanaPeriodUnit(int count);

  /// Home 'Esta Semana' card empty-state title for an athlete with zero sessions.
  ///
  /// In es_AR, this message translates to:
  /// **'TU RACHA\nEMPIEZA ACÁ'**
  String get homeEstaSemanaEmptyTitle;

  /// Home 'Esta Semana' card empty-state body copy encouraging the first workout.
  ///
  /// In es_AR, this message translates to:
  /// **'Cada entrenamiento alimenta tu racha. Hacé el primero y empezá a construir tu progreso.'**
  String get homeEstaSemanaEmptyBody;

  /// Home 'Esta Semana' card empty-state CTA button navigating to routines.
  ///
  /// In es_AR, this message translates to:
  /// **'EXPLORAR RUTINAS  →'**
  String get homeEstaSemanaEmptyCta;

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

  /// No description provided for @agendaCobrarCta.
  ///
  /// In es_AR, this message translates to:
  /// **'COBRAR'**
  String get agendaCobrarCta;

  /// No description provided for @agendaCobradoLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Cobrado'**
  String get agendaCobradoLabel;

  /// No description provided for @agendaCobrarMontoLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'MONTO (ARS)'**
  String get agendaCobrarMontoLabel;

  /// No description provided for @agendaCobrarConceptoLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'CONCEPTO'**
  String get agendaCobrarConceptoLabel;

  /// No description provided for @agendaCobrarVenceElLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'VENCE EL (OPCIONAL)'**
  String get agendaCobrarVenceElLabel;

  /// No description provided for @agendaCobrarVenceElHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin fecha de vencimiento'**
  String get agendaCobrarVenceElHint;

  /// No description provided for @agendaCobrarVenceElQuitar.
  ///
  /// In es_AR, this message translates to:
  /// **'Quitar fecha de vencimiento'**
  String get agendaCobrarVenceElQuitar;

  /// No description provided for @agendaCobrarConfirmCta.
  ///
  /// In es_AR, this message translates to:
  /// **'CONFIRMAR COBRO'**
  String get agendaCobrarConfirmCta;

  /// No description provided for @agendaCobrarCompletaCampos.
  ///
  /// In es_AR, this message translates to:
  /// **'Completá todos los campos.'**
  String get agendaCobrarCompletaCampos;

  /// No description provided for @agendaCobrarMontoInvalido.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá un monto válido.'**
  String get agendaCobrarMontoInvalido;

  /// No description provided for @agendaCobrarSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Turno cobrado.'**
  String get agendaCobrarSuccess;

  /// No description provided for @agendaCobrarError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos registrar el cobro. Probá de nuevo.'**
  String get agendaCobrarError;

  /// No description provided for @agendaCobrarConceptoDefault.
  ///
  /// In es_AR, this message translates to:
  /// **'Sesión {date}'**
  String agendaCobrarConceptoDefault(String date);

  /// No description provided for @agendaCobrarTarifaReferencia.
  ///
  /// In es_AR, this message translates to:
  /// **'Tarifa de referencia: {amount}'**
  String agendaCobrarTarifaReferencia(String amount);

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

  /// No description provided for @workoutHistorialSeeAll.
  ///
  /// In es_AR, this message translates to:
  /// **'Ver todo'**
  String get workoutHistorialSeeAll;

  /// No description provided for @workoutHistorialFullTitle.
  ///
  /// In es_AR, this message translates to:
  /// **'HISTORIAL'**
  String get workoutHistorialFullTitle;

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

  /// No description provided for @workoutMisRutinasOverflowMarkActive.
  ///
  /// In es_AR, this message translates to:
  /// **'MARCAR COMO ACTIVA'**
  String get workoutMisRutinasOverflowMarkActive;

  /// No description provided for @workoutMisRutinasOverflowUnmarkActive.
  ///
  /// In es_AR, this message translates to:
  /// **'DESMARCAR COMO ACTIVA'**
  String get workoutMisRutinasOverflowUnmarkActive;

  /// No description provided for @workoutMisRutinasActiveChip.
  ///
  /// In es_AR, this message translates to:
  /// **'ACTIVA'**
  String get workoutMisRutinasActiveChip;

  /// No description provided for @workoutMisRutinasMarkActiveSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Marcada como tu rutina activa'**
  String get workoutMisRutinasMarkActiveSuccess;

  /// No description provided for @workoutMisRutinasUnmarkActiveSuccess.
  ///
  /// In es_AR, this message translates to:
  /// **'Ya no es tu rutina activa'**
  String get workoutMisRutinasUnmarkActiveSuccess;

  /// No description provided for @workoutMisRutinasActiveError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cambiar el estado. Reintentá.'**
  String get workoutMisRutinasActiveError;

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
  /// **'. Vamos a eliminar tu cuenta, tu perfil, tu historial de entrenamientos, tus posts y tu foto.'**
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

  /// No description provided for @dashboardVenceElLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'VENCE EL (OPCIONAL)'**
  String get dashboardVenceElLabel;

  /// No description provided for @dashboardVenceElHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin fecha de vencimiento'**
  String get dashboardVenceElHint;

  /// No description provided for @dashboardVenceElQuitar.
  ///
  /// In es_AR, this message translates to:
  /// **'Quitar fecha de vencimiento'**
  String get dashboardVenceElQuitar;

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

  /// No description provided for @dashboardSinActividadReciente.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin actividad en los últimos días.'**
  String get dashboardSinActividadReciente;

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
  /// **'{count, plural, =1{1 activa} other{{count} activas}}'**
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

  /// No description provided for @routineEditorNotesLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Nota para el alumno'**
  String get routineEditorNotesLabel;

  /// No description provided for @routineEditorNotesHint.
  ///
  /// In es_AR, this message translates to:
  /// **'Técnica, tempo, RIR…'**
  String get routineEditorNotesHint;

  /// No description provided for @exerciseNoteFromCoachTag.
  ///
  /// In es_AR, this message translates to:
  /// **'DEL COACH'**
  String get exerciseNoteFromCoachTag;

  /// SnackBar shown when the user taps save with at least one incomplete set. Names the first offending exercise.
  ///
  /// In es_AR, this message translates to:
  /// **'Completá los sets de \"{exerciseName}\" antes de guardar.'**
  String routineEditorIncompleteSetsFeedback(String exerciseName);

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

  /// Shared accessibility label / tooltip for icon-only back navigation buttons. Replaces the duplicated literal 'Volver' across auth, feed, workout and chat back affordances (findings 0,2,3,4,15,16,17,20,21,22,24,25,27). There is currently NO generic back key in the ARB.
  ///
  /// In es_AR, this message translates to:
  /// **'Volver'**
  String get commonBack;

  /// Generic accessibility label / tooltip for icon-only close buttons (finding 23 post-workout summary close IconButton). A value 'Cerrar' exists only as the dialog-scoped authTrainerInquiryDialogClose; a reusable generic key is needed for a11y close affordances.
  ///
  /// In es_AR, this message translates to:
  /// **'Cerrar'**
  String get commonClose;

  /// Generic Semantics label for bare loading spinners so screen readers announce loading state (findings 7 coach_hub section/inline spinners, 16 public profile spinner). Existing 'Cargando…' is dashboard-scoped (dashboardCargando); a reusable cross-module key is needed.
  ///
  /// In es_AR, this message translates to:
  /// **'Cargando…'**
  String get commonLoading;

  /// Semantics label for action busy spinners that replace Aceptar/Rechazar buttons mid-request (finding 7 coach_hub _PendingRequestTile).
  ///
  /// In es_AR, this message translates to:
  /// **'Procesando…'**
  String get commonProcessing;

  /// semanticLabel for the unmatched-exercise warning icon in coach_hub plan preview (finding 10 _UnmatchedWarning Icon(TreinoIcon.warning)).
  ///
  /// In es_AR, this message translates to:
  /// **'Atención'**
  String get commonWarning;

  /// Semantics label announced while the chat send button shows a CircularProgressIndicator (finding 4 chat_screen send busy state).
  ///
  /// In es_AR, this message translates to:
  /// **'Enviando…'**
  String get chatSendingA11y;

  /// Accessibility label for the icon-only header messages action in the feed that opens the chat inbox (navigation finding: ChatListScreen was unreachable).
  ///
  /// In es_AR, this message translates to:
  /// **'Mensajes'**
  String get feedMessagesA11y;

  /// Accessibility label for the icon-only header search action in the feed (finding 11 feed_screen search GestureDetector).
  ///
  /// In es_AR, this message translates to:
  /// **'Buscar'**
  String get feedSearchA11y;

  /// Accessibility label for the icon-only create-post '+' action in the feed header (finding 11 feed_screen create GestureDetector).
  ///
  /// In es_AR, this message translates to:
  /// **'Crear publicación'**
  String get feedCreatePostA11y;

  /// Accessibility label for the icon-only friend-requests inbox action in the feed header bell icon (navigation finding: friend-requests inbox was unreachable from the feed/social surface).
  ///
  /// In es_AR, this message translates to:
  /// **'Solicitudes de amistad'**
  String get feedFriendRequestsA11y;

  /// Accessibility label for the feed header friend-requests bell icon when there are pending requests; announces the badge count to screen readers.
  ///
  /// In es_AR, this message translates to:
  /// **'Solicitudes de amistad, {count} pendientes'**
  String feedFriendRequestsWithCountA11y(int count);

  /// Semantics liveRegion/label for the create-post submit spinner state while a post is being published (finding 12 create_post_screen PUBLICAR spinner branch).
  ///
  /// In es_AR, this message translates to:
  /// **'Publicando…'**
  String get feedPublishingA11y;

  /// Accessibility label for the icon-only clear-field button on the user search screen (finding 17). Existing workoutPickerSheetClear='Limpiar' is a different, sheet-scoped action.
  ///
  /// In es_AR, this message translates to:
  /// **'Limpiar búsqueda'**
  String get searchUsersClearA11y;

  /// Semantics label for the disabled MENSAJE stub on the public profile screen, exposed via Semantics(button:true, enabled:false) (finding 16).
  ///
  /// In es_AR, this message translates to:
  /// **'Mensaje (próximamente)'**
  String get publicProfileMessageDisabledA11y;

  /// Parametric Semantics label for user avatars (PostAvatar / HomeHeader avatar) wrapped at call sites so screen readers announce whose photo it is (findings 4,6,7,16,18,19). Fix agents must add the matching @a11yAvatarLabel placeholder metadata (name: String). When the name is null, use a11yAvatarLabelGeneric.
  ///
  /// In es_AR, this message translates to:
  /// **'Foto de perfil de {name}'**
  String a11yAvatarLabel(String name);

  /// Non-parametric avatar Semantics label used when the display name is unavailable/null (findings 4,6,7,16,18,19).
  ///
  /// In es_AR, this message translates to:
  /// **'Foto de perfil'**
  String get a11yAvatarLabelGeneric;

  /// Semantics label for the bell-with-badge in the trainer home header that currently conveys the pending count purely visually (finding 18). Fix agents add the @homePendingRequestsA11y placeholder metadata (count: int).
  ///
  /// In es_AR, this message translates to:
  /// **'{count} solicitudes pendientes'**
  String homePendingRequestsA11y(int count);

  /// tooltip / Semantics label for the icon-only overflow PopupMenuButton in _UserRoutineCard on the workout screen (finding 29 mis_rutinas_section dotsThree).
  ///
  /// In es_AR, this message translates to:
  /// **'Opciones de rutina'**
  String get workoutRoutineOptionsA11y;

  /// Parametric Semantics label for the per-set check toggle in the session player - the single most-tapped action (finding 27). Fix agents add the @ placeholder metadata (setNumber: int).
  ///
  /// In es_AR, this message translates to:
  /// **'Marcar serie {setNumber} como completada'**
  String sessionPlayerSetCompleteA11y(int setNumber);

  /// Parametric Semantics label for the technique info icon button in the session player (finding 27). Fix agents add the @ placeholder metadata (exerciseName: String).
  ///
  /// In es_AR, this message translates to:
  /// **'Ver técnica de {exerciseName}'**
  String sessionPlayerTechniqueA11y(String exerciseName);

  /// Semantics label for the duration 'Iniciar' / timer icon control in the session player (finding 27).
  ///
  /// In es_AR, this message translates to:
  /// **'Iniciar temporizador'**
  String get sessionPlayerTimerStartA11y;

  /// Semantics label for the icon-only remove-set button in the session player (live-set-editing PR2).
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar serie'**
  String get sessionPlayerRemoveSetA11y;

  /// tooltip / Semantics label for the icon-only day-delete trash button in the routine editor (findings 25/26 day-header trash IconButton).
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar día'**
  String get routineEditorDeleteDayA11y;

  /// Tooltip + Semantics label for the icon-only pencil button next to each day's title in the routine editor. Tap turns the title into an inline TextField.
  ///
  /// In es_AR, this message translates to:
  /// **'Editar nombre del día'**
  String get routineEditorEditDayNameA11y;

  /// Accessibility label for the edit-plan icon button in the athlete detail plan card (finding 5).
  ///
  /// In es_AR, this message translates to:
  /// **'Editar plan'**
  String get athleteDetailEditPlanA11y;

  /// Accessibility label for the delete-plan icon button in the athlete detail plan card (finding 5).
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar plan'**
  String get athleteDetailDeletePlanA11y;

  /// Accessibility label announcing why the MAPA toggle is disabled when the trainers list is in Online mode (finding 6).
  ///
  /// In es_AR, this message translates to:
  /// **'Mapa, no disponible en modo Online'**
  String get coachMapDisabledOnlineA11y;

  /// Generic accessibility/action label for a Cancel control.
  ///
  /// In es_AR, this message translates to:
  /// **'Cancelar'**
  String get commonCancel;

  /// Live-region accessibility label for the public profile load-error state (finding 16).
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar este perfil.'**
  String get publicProfileLoadErrorA11y;

  /// Generic auth failure fallback shown when an unexpected (non-AuthFailure) error occurs in forgot-password submit and on splash auth-resolve failure. Reused by findings 0/20 and 1.
  ///
  /// In es_AR, this message translates to:
  /// **'Algo salió mal. Probá de nuevo.'**
  String get authGenericErrorFallback;

  /// Empty state on the athlete agenda screen when there are no upcoming/confirmed sessions (finding 4). Distinct from agendaEmptyAvailability which is about a trainer's own hours.
  ///
  /// In es_AR, this message translates to:
  /// **'Tu PF todavía no te agendó sesiones.'**
  String get agendaNoUpcomingSessions;

  /// Error snackbar when saving an availability rule/override fails in the availability editor sheets (findings 6/24).
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos guardar. Probá de nuevo.'**
  String get agendaSaveError;

  /// Success snackbar after saving an availability rule/override in the availability editor (findings 6/24).
  ///
  /// In es_AR, this message translates to:
  /// **'Horario guardado.'**
  String get agendaSaveSuccess;

  /// Error text for the coach hub dashboard sections (paused/historial/pending requests) that currently swallow loading+error via maybeWhen+orElse (finding 7). Pair with coachRetryLabel for the retry CTA.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar esta sección.'**
  String get coachHubSectionLoadError;

  /// Inline error on the coach-hub not-allowed screen when signOut() fails (finding 8).
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cerrar sesión. Probá de nuevo.'**
  String get coachHubSignOutError;

  /// Coach Hub web login screen — subtitle guiding the trainer to reuse their mobile account.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá con la cuenta que ya usás en la app móvil.'**
  String get coachHubLoginPrompt;

  /// Coach Hub web login screen — email TextFormField label.
  ///
  /// In es_AR, this message translates to:
  /// **'Email'**
  String get coachHubLoginEmailLabel;

  /// Coach Hub web login screen — validation message when the email field is empty.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá tu email'**
  String get coachHubLoginEmailRequired;

  /// Coach Hub web login screen — validation message when the email is malformed (no @).
  ///
  /// In es_AR, this message translates to:
  /// **'Email inválido'**
  String get coachHubLoginEmailInvalid;

  /// Coach Hub web login screen — password TextFormField label.
  ///
  /// In es_AR, this message translates to:
  /// **'Contraseña'**
  String get coachHubLoginPasswordLabel;

  /// Coach Hub web login screen — validation message when the password field is empty.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá tu contraseña'**
  String get coachHubLoginPasswordRequired;

  /// Coach Hub web login screen — primary submit button label.
  ///
  /// In es_AR, this message translates to:
  /// **'INGRESAR'**
  String get coachHubLoginSubmit;

  /// Coach Hub web login screen — footer nudging the user back to the mobile app for signup.
  ///
  /// In es_AR, this message translates to:
  /// **'¿No tenés cuenta? Creala desde la app móvil TREINO.'**
  String get coachHubLoginFooter;

  /// Coach Hub web login screen — fallback error when the auth failure is not a typed AuthFailure with userMessage.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos ingresar. Probá de nuevo.'**
  String get coachHubLoginGenericError;

  /// Coach Hub web — generic Cancel button used across dialogs (pause/terminate/resume link, etc.).
  ///
  /// In es_AR, this message translates to:
  /// **'Cancelar'**
  String get coachHubActionCancel;

  /// Coach Hub web — generic Confirm button used across dialogs (pause/terminate/resume link, etc.).
  ///
  /// In es_AR, this message translates to:
  /// **'Confirmar'**
  String get coachHubActionConfirm;

  /// Coach Hub web — Pause action button/tooltip for trainer↔athlete links.
  ///
  /// In es_AR, this message translates to:
  /// **'Pausar'**
  String get coachHubActionPause;

  /// Coach Hub web — Resume action button/tooltip for paused links.
  ///
  /// In es_AR, this message translates to:
  /// **'Reanudar'**
  String get coachHubActionResume;

  /// Coach Hub web — Terminate action button/tooltip (short form used in row IconAction).
  ///
  /// In es_AR, this message translates to:
  /// **'Terminar'**
  String get coachHubActionTerminate;

  /// Coach Hub web — full-form Terminate label used in dialog CTAs and menu items.
  ///
  /// In es_AR, this message translates to:
  /// **'Terminar vínculo'**
  String get coachHubActionTerminateLink;

  /// Coach Hub web — Accept action on incoming trainer↔athlete link requests.
  ///
  /// In es_AR, this message translates to:
  /// **'Aceptar'**
  String get coachHubActionAccept;

  /// Coach Hub web — Reject action on incoming trainer↔athlete link requests.
  ///
  /// In es_AR, this message translates to:
  /// **'Rechazar'**
  String get coachHubActionReject;

  /// Coach Hub web dashboard — primary CTA to jump into the Excel plan importer.
  ///
  /// In es_AR, this message translates to:
  /// **'IMPORTAR PLAN DESDE EXCEL'**
  String get coachHubDashboardImportPlanCta;

  /// Coach Hub web dashboard — filter chip for currently active links.
  ///
  /// In es_AR, this message translates to:
  /// **'ACTIVOS'**
  String get coachHubDashboardFilterActivos;

  /// Coach Hub web dashboard — filter chip for paused links.
  ///
  /// In es_AR, this message translates to:
  /// **'PAUSADOS'**
  String get coachHubDashboardFilterPausados;

  /// Coach Hub web dashboard — filter chip for terminated links history.
  ///
  /// In es_AR, this message translates to:
  /// **'HISTORIAL'**
  String get coachHubDashboardFilterHistorial;

  /// Coach Hub web dashboard — section header above the active students list.
  ///
  /// In es_AR, this message translates to:
  /// **'TUS ALUMNOS'**
  String get coachHubDashboardActiveHeader;

  /// Coach Hub web dashboard — section header above the paused students list.
  ///
  /// In es_AR, this message translates to:
  /// **'EN PAUSA'**
  String get coachHubDashboardPausedHeader;

  /// Coach Hub web dashboard — section header above the terminated history list.
  ///
  /// In es_AR, this message translates to:
  /// **'VÍNCULOS PASADOS'**
  String get coachHubDashboardHistoryHeader;

  /// Coach Hub web dashboard — empty state when the trainer has zero active links.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin alumnos activos por ahora.'**
  String get coachHubDashboardEmptyActive;

  /// Coach Hub web dashboard — empty state when the trainer has zero paused links.
  ///
  /// In es_AR, this message translates to:
  /// **'No hay alumnos pausados.'**
  String get coachHubDashboardEmptyPaused;

  /// Coach Hub web dashboard — empty state when the trainer has zero terminated links.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin vínculos terminados todavía.'**
  String get coachHubDashboardEmptyHistory;

  /// Coach Hub web dashboard — pending requests section header with a count of requests.
  ///
  /// In es_AR, this message translates to:
  /// **'SOLICITUDES PENDIENTES · {count}'**
  String coachHubDashboardPendingHeader(int count);

  /// Coach Hub web dashboard — subtitle text under each pending request tile explaining the intent.
  ///
  /// In es_AR, this message translates to:
  /// **'Quiere vincularse con vos'**
  String get coachHubDashboardPendingContext;

  /// Coach Hub web dashboard — subtitle on active/history tiles with the acceptance date.
  ///
  /// In es_AR, this message translates to:
  /// **'Vinculado desde {date}'**
  String coachHubDashboardLinkedSince(String date);

  /// Coach Hub web dashboard — subtitle on paused tiles with the pause date.
  ///
  /// In es_AR, this message translates to:
  /// **'Pausado el {date}'**
  String coachHubDashboardPausedOn(String date);

  /// Coach Hub web dashboard — subtitle fallback when the paused link has no pausedAt timestamp.
  ///
  /// In es_AR, this message translates to:
  /// **'Pausado'**
  String get coachHubDashboardPausedFallback;

  /// Coach Hub web dashboard — confirmation dialog title before pausing a link.
  ///
  /// In es_AR, this message translates to:
  /// **'Pausar vínculo'**
  String get coachHubDashboardPauseLinkTitle;

  /// Coach Hub web dashboard — confirmation dialog body for pausing a link. Same copy is used from the alumnos section.
  ///
  /// In es_AR, this message translates to:
  /// **'El alumno verá el plan pero no podrá registrar sesiones nuevas hasta que reanudes el vínculo.'**
  String get coachHubDashboardPauseLinkBody;

  /// Coach Hub web dashboard — confirmation dialog title before terminating a link.
  ///
  /// In es_AR, this message translates to:
  /// **'Terminar vínculo'**
  String get coachHubDashboardTerminateLinkTitle;

  /// Coach Hub web dashboard — confirmation dialog body for terminating a link. Same copy is used from the alumnos section.
  ///
  /// In es_AR, this message translates to:
  /// **'Esta acción no se puede deshacer. El historial se conserva.'**
  String get coachHubDashboardTerminateLinkBody;

  /// Coach Hub web dashboard — confirmation dialog title before resuming a paused link.
  ///
  /// In es_AR, this message translates to:
  /// **'Reanudar vínculo'**
  String get coachHubDashboardResumeLinkTitle;

  /// Coach Hub web dashboard — confirmation body for resuming a paused link with the athlete name.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Reanudar el vínculo con {name}?'**
  String coachHubDashboardResumeLinkBody(String name);

  /// Coach Hub web dashboard — fallback body when we cannot resolve the athlete's display name for the resume confirmation.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Reanudar el vínculo?'**
  String get coachHubDashboardResumeLinkBodyFallback;

  /// Coach Hub web dashboard — snackbar when pause() fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos pausar el vínculo.'**
  String get coachHubDashboardPauseLinkError;

  /// Coach Hub web dashboard — snackbar when terminate() fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos terminar el vínculo.'**
  String get coachHubDashboardTerminateLinkError;

  /// Coach Hub web dashboard — snackbar when resume() fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos reanudar el vínculo.'**
  String get coachHubDashboardResumeLinkError;

  /// Coach Hub web dashboard — snackbar after accepting a pending link request.
  ///
  /// In es_AR, this message translates to:
  /// **'Vínculo aceptado.'**
  String get coachHubDashboardAcceptSuccess;

  /// Coach Hub web dashboard — snackbar when accept() fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos aceptar el vínculo.'**
  String get coachHubDashboardAcceptError;

  /// Coach Hub web dashboard — snackbar after rejecting a pending link request.
  ///
  /// In es_AR, this message translates to:
  /// **'Solicitud rechazada.'**
  String get coachHubDashboardRejectSuccess;

  /// Coach Hub web dashboard — snackbar when reject() fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos rechazar la solicitud.'**
  String get coachHubDashboardRejectError;

  /// Coach Hub web dashboard — history tile subtitle when a link was declined by the trainer at request time.
  ///
  /// In es_AR, this message translates to:
  /// **'Rechazado por el PF'**
  String get coachHubDashboardTerminationReasonDeclined;

  /// Coach Hub web dashboard — history tile subtitle when the athlete ended the link.
  ///
  /// In es_AR, this message translates to:
  /// **'Cancelado por el atleta'**
  String get coachHubDashboardTerminationReasonByAthlete;

  /// Coach Hub web dashboard — history tile subtitle when the trainer ended the link.
  ///
  /// In es_AR, this message translates to:
  /// **'Terminado por el PF'**
  String get coachHubDashboardTerminationReasonByTrainer;

  /// Coach Hub web dashboard — history tile subtitle fallback for unknown termination reasons.
  ///
  /// In es_AR, this message translates to:
  /// **'Vínculo terminado'**
  String get coachHubDashboardTerminationReasonFallback;

  /// Coach Hub web alumnos section — page title in the app bar.
  ///
  /// In es_AR, this message translates to:
  /// **'ALUMNOS'**
  String get coachHubAlumnosTitle;

  /// Coach Hub web alumnos section — summary line above the roster with total count and active count.
  ///
  /// In es_AR, this message translates to:
  /// **'{total} en total · {active} activos'**
  String coachHubAlumnosSummary(int total, int active);

  /// Coach Hub web alumnos section — search field hint text.
  ///
  /// In es_AR, this message translates to:
  /// **'Buscar por nombre…'**
  String get coachHubAlumnosSearchHint;

  /// Coach Hub web alumnos section — 'All' filter chip label.
  ///
  /// In es_AR, this message translates to:
  /// **'Todos'**
  String get coachHubAlumnosFilterAll;

  /// Coach Hub web alumnos section — 'Active' filter chip label. Lowercase spelling to match filter chip vs the dashboard's uppercase filter.
  ///
  /// In es_AR, this message translates to:
  /// **'Activos'**
  String get coachHubAlumnosFilterActivos;

  /// Coach Hub web alumnos section — filter chip for athletes with outstanding payments.
  ///
  /// In es_AR, this message translates to:
  /// **'Con deuda'**
  String get coachHubAlumnosFilterConDeuda;

  /// Coach Hub web alumnos section — filter chip for paused athletes.
  ///
  /// In es_AR, this message translates to:
  /// **'Pausados'**
  String get coachHubAlumnosFilterPausados;

  /// Coach Hub web alumnos section — filter chip for inactive athletes.
  ///
  /// In es_AR, this message translates to:
  /// **'Inactivos'**
  String get coachHubAlumnosFilterInactivos;

  /// Coach Hub web alumnos section — empty state when the trainer has no roster at all.
  ///
  /// In es_AR, this message translates to:
  /// **'Todavía no tenés alumnos vinculados.'**
  String get coachHubAlumnosEmpty;

  /// Coach Hub web alumnos section — empty state when the roster is non-empty but the current filter/search returns zero.
  ///
  /// In es_AR, this message translates to:
  /// **'Ningún alumno coincide con el filtro.'**
  String get coachHubAlumnosEmptyFiltered;

  /// Coach Hub web alumnos section — error state when the roster stream fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No se pudieron cargar los alumnos.'**
  String get coachHubAlumnosLoadError;

  /// Coach Hub web alumnos section — error state when the enrichment profiles query fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No se pudieron cargar los perfiles.'**
  String get coachHubAlumnosProfilesLoadError;

  /// Coach Hub web alumnos section — roster table column header for student name/avatar.
  ///
  /// In es_AR, this message translates to:
  /// **'ALUMNO'**
  String get coachHubAlumnosColumnStudent;

  /// Coach Hub web alumnos section — roster table column header for status badge.
  ///
  /// In es_AR, this message translates to:
  /// **'ESTADO'**
  String get coachHubAlumnosColumnStatus;

  /// Coach Hub web alumnos section — roster table column header for last workout date.
  ///
  /// In es_AR, this message translates to:
  /// **'ÚLTIMO ENTRENO'**
  String get coachHubAlumnosColumnLastWorkout;

  /// Coach Hub web alumnos section — roster table column header for row actions (pause/resume/terminate).
  ///
  /// In es_AR, this message translates to:
  /// **'ACCIONES'**
  String get coachHubAlumnosColumnActions;

  /// Coach Hub web alumnos section — display name fallback when the profile has no displayName.
  ///
  /// In es_AR, this message translates to:
  /// **'Atleta'**
  String get coachHubAlumnosNameFallback;

  /// Coach Hub web alumnos section — cell text when the last workout was today.
  ///
  /// In es_AR, this message translates to:
  /// **'Hoy'**
  String get coachHubAlumnosLastWorkoutToday;

  /// Coach Hub web alumnos section — status badge for active athletes.
  ///
  /// In es_AR, this message translates to:
  /// **'Activo'**
  String get coachHubAlumnosStatusActive;

  /// Coach Hub web alumnos section — status badge for athletes with outstanding payments.
  ///
  /// In es_AR, this message translates to:
  /// **'Con deuda'**
  String get coachHubAlumnosStatusDebt;

  /// Coach Hub web alumnos section — status badge for paused athletes.
  ///
  /// In es_AR, this message translates to:
  /// **'Pausado'**
  String get coachHubAlumnosStatusPaused;

  /// Coach Hub web alumnos section — status badge for inactive athletes.
  ///
  /// In es_AR, this message translates to:
  /// **'Inactivo'**
  String get coachHubAlumnosStatusInactive;

  /// Coach Hub web alumnos section — view-mode toggle, table layout.
  ///
  /// In es_AR, this message translates to:
  /// **'Tabla'**
  String get coachHubAlumnosViewTable;

  /// Coach Hub web alumnos section — view-mode toggle, cards layout.
  ///
  /// In es_AR, this message translates to:
  /// **'Cards'**
  String get coachHubAlumnosViewCards;

  /// Coach Hub web alumnos section — pending debt amount shown on a row/card.
  ///
  /// In es_AR, this message translates to:
  /// **'Debe {amount}'**
  String coachHubAlumnosDebtAmount(String amount);

  /// Coach Hub web alumno detail — title of the Notas privadas tab body.
  ///
  /// In es_AR, this message translates to:
  /// **'Notas privadas'**
  String get coachHubAlumnoDetailNotasTitle;

  /// Coach Hub web alumno detail — subtitle explaining that these notes are private to the trainer, never shown to the athlete.
  ///
  /// In es_AR, this message translates to:
  /// **'Anotá lo que necesites sobre este alumno. Solo vos lo ves.'**
  String get coachHubAlumnoDetailNotasSubtitle;

  /// Coach Hub web alumno detail — hint text inside the empty notes TextField.
  ///
  /// In es_AR, this message translates to:
  /// **'Ej: Lesión de rodilla derecha, evitar sentadilla profunda…'**
  String get coachHubAlumnoDetailNotasHint;

  /// Coach Hub web alumno detail — save button label for the notes tab.
  ///
  /// In es_AR, this message translates to:
  /// **'GUARDAR'**
  String get coachHubAlumnoDetailNotasSaveButton;

  /// Coach Hub web alumno detail — subtle header line showing when the note was last saved.
  ///
  /// In es_AR, this message translates to:
  /// **'Última edición · {timestamp}'**
  String coachHubAlumnoDetailNotasUpdatedAt(String timestamp);

  /// Coach Hub web alumno detail — snackbar shown after a successful save of the private note.
  ///
  /// In es_AR, this message translates to:
  /// **'Nota guardada.'**
  String get coachHubAlumnoDetailNotasSaveSuccess;

  /// Coach Hub web alumno detail — snackbar shown when Firestore write fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos guardar la nota. Probá de nuevo.'**
  String get coachHubAlumnoDetailNotasSaveError;

  /// Coach Hub web alumno detail — error state when the note stream errors.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar la nota.'**
  String get coachHubAlumnoDetailNotasLoadError;

  /// Coach Hub web alumno detail — title of the Archivos tab body.
  ///
  /// In es_AR, this message translates to:
  /// **'Archivos privados'**
  String get coachHubAlumnoDetailArchivosTitle;

  /// Coach Hub web alumno detail — subtitle explaining privacy: only the trainer sees these files, the athlete never does.
  ///
  /// In es_AR, this message translates to:
  /// **'PDFs y fotos que subís sobre este alumno. Solo vos los ves.'**
  String get coachHubAlumnoDetailArchivosSubtitle;

  /// Coach Hub web alumno detail — primary CTA to open the file picker.
  ///
  /// In es_AR, this message translates to:
  /// **'SUBIR ARCHIVO'**
  String get coachHubAlumnoDetailArchivosUploadButton;

  /// Coach Hub web alumno detail — empty state when no files have been uploaded.
  ///
  /// In es_AR, this message translates to:
  /// **'Todavía no subiste archivos sobre este alumno.'**
  String get coachHubAlumnoDetailArchivosEmpty;

  /// Coach Hub web alumno detail — error state when the athlete files stream fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar los archivos.'**
  String get coachHubAlumnoDetailArchivosLoadError;

  /// Coach Hub web alumno detail — snackbar shown after a successful upload.
  ///
  /// In es_AR, this message translates to:
  /// **'Archivo subido.'**
  String get coachHubAlumnoDetailArchivosUploadSuccess;

  /// Coach Hub web alumno detail — snackbar shown when the upload fails (permission-denied, network, etc.).
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos subir el archivo. Probá de nuevo.'**
  String get coachHubAlumnoDetailArchivosUploadError;

  /// Coach Hub web alumno detail — snackbar shown when the picked file exceeds the size cap.
  ///
  /// In es_AR, this message translates to:
  /// **'El archivo supera el máximo de 10 MB.'**
  String get coachHubAlumnoDetailArchivosUploadTooLarge;

  /// Coach Hub web alumno detail — tooltip for the download/open button on each file row.
  ///
  /// In es_AR, this message translates to:
  /// **'Abrir archivo'**
  String get coachHubAlumnoDetailArchivosOpenTooltip;

  /// Coach Hub web alumno detail — tooltip for the delete button on each file row.
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar'**
  String get coachHubAlumnoDetailArchivosDeleteTooltip;

  /// Coach Hub web alumno detail — confirmation dialog title before deleting a file.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Eliminar archivo?'**
  String get coachHubAlumnoDetailArchivosDeleteTitle;

  /// Coach Hub web alumno detail — confirmation body for delete with the file name.
  ///
  /// In es_AR, this message translates to:
  /// **'«{fileName}» se va a borrar tanto del Storage como del historial. No se puede deshacer.'**
  String coachHubAlumnoDetailArchivosDeleteBody(String fileName);

  /// Coach Hub web alumno detail — snackbar when the delete flow fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos eliminar el archivo.'**
  String get coachHubAlumnoDetailArchivosDeleteError;

  /// Feed error branch text, replacing the hardcoded literal repeated 3x in feed_screen.dart (finding 9). Pair with coachRetryLabel for the retry CTA.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tu feed. Probá de nuevo.'**
  String get feedLoadError;

  /// Friendly localized error replacing the raw 'Error: $e' debug placeholder in create_post_screen.dart's AsyncValue.error branch (finding 10). Pair with coachRetryLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos abrir el editor. Probá de nuevo.'**
  String get createPostLoadError;

  /// Insights error branch message, paired with a Reintentar (coachRetryLabel) button calling ref.invalidate(weeklyInsightsProvider) (finding 12).
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tus insights. Probá de nuevo.'**
  String get insightsLoadError;

  /// Label shown on today's tile in the per-day heat-map day-strip (charts-redesign PR2, AD5/REQ:heat-map-per-day), replacing the weekday letter.
  ///
  /// In es_AR, this message translates to:
  /// **'HOY'**
  String get insightsDayStripTodayLabel;

  /// Hint shown under the body silhouette when the selected day in the day-strip has no finished session — the muñeco renders blank (charts-redesign PR2, AD5/REQ:heat-map-per-day).
  ///
  /// In es_AR, this message translates to:
  /// **'No entrenaste este día.'**
  String get insightsDayEmptyHint;

  /// Section header for the shared DailyHeatmapSection (per-day body heat-map + day-strip) in the coach's mobile athlete detail screen (charts-redesign PR2b, AD5).
  ///
  /// In es_AR, this message translates to:
  /// **'MÚSCULOS DEL DÍA'**
  String get coachDailyHeatmapSectionTitle;

  /// Error state for profile_edit_personal_screen's profile load (finding 13) and reusable for the trainer-edit gyms section error (finding 14). Pair with coachRetryLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tu perfil. Probá de nuevo.'**
  String get profileLoadError;

  /// Empty state for session_detail_screen when setLogs is empty (finding 18).
  ///
  /// In es_AR, this message translates to:
  /// **'Esta sesión no tiene sets registrados.'**
  String get sessionDetailNoSets;

  /// Snackbar shown when logging/updating a set fails in the session player (finding 21). Pair with a retry action.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos guardar la serie. Reintentá.'**
  String get sessionLogSetError;

  /// Snackbar when finishSession/abandonSession fails so the user isn't stranded on the player (finding 22).
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos finalizar la sesión. Probá de nuevo.'**
  String get sessionFinishError;

  /// Inline validation hint when the routine name is empty and the save button is disabled (finding 19).
  ///
  /// In es_AR, this message translates to:
  /// **'Poné un nombre a la rutina.'**
  String get routineEditorMissingName;

  /// Inline validation hint when a day has no exercises (finding 19).
  ///
  /// In es_AR, this message translates to:
  /// **'Agregá al menos un ejercicio al Día {dayNumber}.'**
  String routineEditorMissingExercise(int dayNumber);

  /// Inline validation hint when a visible set is missing a valid reps/duration value in a single-week self-routine (finding 19). routineEditorIncompleteSetsFeedback already covers the named-exercise multi-week case.
  ///
  /// In es_AR, this message translates to:
  /// **'Completá las reps de los sets antes de guardar.'**
  String get routineEditorMissingReps;

  /// Success snackbar after publishing a post (finding 25). Shown via the root ScaffoldMessenger since the compose screen pops on success.
  ///
  /// In es_AR, this message translates to:
  /// **'Post publicado.'**
  String get feedPostPublishedSuccess;

  /// Semantics label for the post card overflow (3-dot) menu button, shown only on the viewer's own posts.
  ///
  /// In es_AR, this message translates to:
  /// **'Opciones del post'**
  String get postCardMenuA11y;

  /// Edit action in the post card overflow menu.
  ///
  /// In es_AR, this message translates to:
  /// **'Editar'**
  String get postCardMenuEdit;

  /// Delete action in the post card overflow menu.
  ///
  /// In es_AR, this message translates to:
  /// **'Eliminar'**
  String get postCardMenuDelete;

  /// Title of the confirmation dialog shown before deleting a post.
  ///
  /// In es_AR, this message translates to:
  /// **'¿Eliminar este post?'**
  String get postCardDeleteConfirmTitle;

  /// Body of the confirmation dialog shown before deleting a post.
  ///
  /// In es_AR, this message translates to:
  /// **'Esta acción no se puede deshacer.'**
  String get postCardDeleteConfirmBody;

  /// Success snackbar after deleting a post.
  ///
  /// In es_AR, this message translates to:
  /// **'Post eliminado.'**
  String get postCardDeleteSuccess;

  /// Error snackbar when deleting a post fails.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos eliminar el post. Probá de nuevo.'**
  String get postCardDeleteError;

  /// Header title of the compose screen when editing an existing post (vs. NUEVO POST when creating).
  ///
  /// In es_AR, this message translates to:
  /// **'EDITAR POST'**
  String get createPostEditTitle;

  /// Submit button label in the compose screen header when editing an existing post (vs. PUBLICAR when creating).
  ///
  /// In es_AR, this message translates to:
  /// **'GUARDAR'**
  String get createPostSaveChanges;

  /// Semantics label for the submit button when editing an existing post.
  ///
  /// In es_AR, this message translates to:
  /// **'Guardar cambios'**
  String get createPostSaveChangesA11y;

  /// Semantics label for the submit button while an edit is being saved.
  ///
  /// In es_AR, this message translates to:
  /// **'Guardando…'**
  String get createPostSavingA11y;

  /// Success snackbar shown after successfully editing an existing post.
  ///
  /// In es_AR, this message translates to:
  /// **'Cambios guardados.'**
  String get feedPostUpdatedSuccess;

  /// Success feedback when a friend/follow request is sent from the public profile follow button (findings 25/26).
  ///
  /// In es_AR, this message translates to:
  /// **'Solicitud enviada.'**
  String get feedRequestSentSuccess;

  /// Success feedback when a friend request is accepted (finding 25). Used by the public profile accept action and optionally the inbox accept.
  ///
  /// In es_AR, this message translates to:
  /// **'Ahora son amigos.'**
  String get feedRequestAcceptedSuccess;

  /// Error snackbar for friendship mutations (accept/reject/request/unfriend) that currently swallow errors, in the inbox tile and public profile follow button (findings 11/26).
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos completar la acción. Probá de nuevo.'**
  String get feedFriendActionError;

  /// Success feedback after saving 'Datos personales' (editar personal), matching the trainer-edit pattern (finding 27).
  ///
  /// In es_AR, this message translates to:
  /// **'Cambios guardados.'**
  String get profilePersonalSaveSuccess;

  /// Success feedback after saving the gym selection (finding 27).
  ///
  /// In es_AR, this message translates to:
  /// **'Gimnasio actualizado.'**
  String get profileGymSaveSuccess;

  /// Error snackbar when the gym save fails (currently has no catch) in profile_gym_screen (finding 28).
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos guardar el gimnasio. Probá de nuevo.'**
  String get profileGymSaveError;

  /// gym-selection-v2 AD-1: inline affordance shown in NearbyGymsList when location permission is not granted. Tapping it triggers the rationale sheet.
  ///
  /// In es_AR, this message translates to:
  /// **'Activar ubicación para ver gyms cercanos'**
  String get gymNearbyLocationAffordance;

  /// gym-selection-v2 AD-4: reveals already-fetched nearby rows beyond the initial 8 — a pure local toggle, never a re-request.
  ///
  /// In es_AR, this message translates to:
  /// **'Ver más'**
  String get gymNearbyShowMore;

  /// gym-selection-v2: nearbyGymsProvider fetch-error state. Paired with coachRetryLabel for the retry CTA.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar los gyms cercanos.'**
  String get gymNearbyLoadError;

  /// Semantics/hint label for the RefreshIndicator added to feed segments (finding 1). Optional a11y label for the manual refresh gesture.
  ///
  /// In es_AR, this message translates to:
  /// **'Deslizá para actualizar'**
  String get feedPullToRefreshA11y;

  /// Per-field inline validation error shown when a measurement/performance metric contains non-numeric text instead of silently dropping it (findings 2, 3).
  ///
  /// In es_AR, this message translates to:
  /// **'Ingresá un número válido'**
  String get logFieldInvalidNumber;

  /// Inline validation error when a numeric metric is negative or exceeds sane bounds in the measurement/performance log forms (findings 2, 3).
  ///
  /// In es_AR, this message translates to:
  /// **'El valor está fuera de rango'**
  String get logFieldOutOfRange;

  /// Message shown (or reason GUARDAR is disabled) when the measurement/performance form has no metric filled, preventing an empty record (findings 2, 3, 10).
  ///
  /// In es_AR, this message translates to:
  /// **'Completá al menos un dato antes de guardar'**
  String get logEmptyRecordWarning;

  /// Inline status shown under the step-1 username field while the async @handle availability query is in flight (finding 4).
  ///
  /// In es_AR, this message translates to:
  /// **'Verificando disponibilidad…'**
  String get profileSetupUsernameChecking;

  /// Inline error shown when the chosen @handle is already used by another userPublicProfiles document (finding 4).
  ///
  /// In es_AR, this message translates to:
  /// **'Ese username ya está en uso'**
  String get profileSetupUsernameTaken;

  /// Inline confirmation shown when the async availability check finds the chosen @handle is free (finding 4).
  ///
  /// In es_AR, this message translates to:
  /// **'Username disponible'**
  String get profileSetupUsernameAvailable;

  /// Inline error shown when the @handle availability query fails (network/Firestore error) during profile setup step 1 (finding 4).
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos verificar el username. Probá de nuevo.'**
  String get profileSetupUsernameCheckError;

  /// Title of the confirm dialog shown by PopScope when leaving the routine editor with unsaved edits (finding 7).
  ///
  /// In es_AR, this message translates to:
  /// **'¿Descartar cambios?'**
  String get routineEditorDiscardTitle;

  /// Body of the unsaved-changes confirm dialog in the routine editor (finding 7). Reuses routineEditorDialogCancel for the cancel action.
  ///
  /// In es_AR, this message translates to:
  /// **'Si salís ahora vas a perder los cambios sin guardar.'**
  String get routineEditorDiscardBody;

  /// Destructive confirm action of the unsaved-changes dialog in the routine editor (finding 7).
  ///
  /// In es_AR, this message translates to:
  /// **'Descartar'**
  String get routineEditorDiscardConfirm;

  /// Explanatory text shown in a sheet or inline helper when the contact CTA is blocked because the athlete already has a link with a different trainer (finding 8).
  ///
  /// In es_AR, this message translates to:
  /// **'Solo podés tener un PF activo. Terminá tu vínculo actual con {trainerName} para pedir uno nuevo.'**
  String trainerCtaExistingLinkExplanation(String trainerName);

  /// Title of the confirm dialog shown when leaving the coach-hub plan preview screen with manually-mapped exercises that would be lost (finding 9).
  ///
  /// In es_AR, this message translates to:
  /// **'¿Salir sin guardar el plan?'**
  String get coachHubPreviewDiscardTitle;

  /// Body of the confirm dialog warning the PF that going back from the plan preview discards manual exercise mappings held in the autoDispose parsedPlanProvider (finding 9).
  ///
  /// In es_AR, this message translates to:
  /// **'Vas a perder los ejercicios que mapeaste manualmente.'**
  String get coachHubPreviewDiscardBody;

  /// Destructive confirm action of the coach-hub preview leave-without-saving dialog (finding 9).
  ///
  /// In es_AR, this message translates to:
  /// **'Salir igual'**
  String get coachHubPreviewDiscardConfirm;

  /// No description provided for @chatAttachMediaLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Adjuntar'**
  String get chatAttachMediaLabel;

  /// No description provided for @chatPickImageLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Foto'**
  String get chatPickImageLabel;

  /// No description provided for @chatPickVideoLabel.
  ///
  /// In es_AR, this message translates to:
  /// **'Video'**
  String get chatPickVideoLabel;

  /// No description provided for @chatMediaUploading.
  ///
  /// In es_AR, this message translates to:
  /// **'Subiendo…'**
  String get chatMediaUploading;

  /// No description provided for @chatMediaUploadFailed.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos subir el archivo. Probá de nuevo.'**
  String get chatMediaUploadFailed;

  /// No description provided for @chatMediaPreviewPhoto.
  ///
  /// In es_AR, this message translates to:
  /// **'📷 Foto'**
  String get chatMediaPreviewPhoto;

  /// No description provided for @chatMediaPreviewVideo.
  ///
  /// In es_AR, this message translates to:
  /// **'🎥 Video'**
  String get chatMediaPreviewVideo;

  /// No description provided for @chatMediaViewFullscreen.
  ///
  /// In es_AR, this message translates to:
  /// **'Ver foto'**
  String get chatMediaViewFullscreen;

  /// No description provided for @chatMediaImageLoadError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar la imagen.'**
  String get chatMediaImageLoadError;

  /// Accessibility label for the feed header messages icon when there are unread chats; announces the unread count to screen readers.
  ///
  /// In es_AR, this message translates to:
  /// **'Mensajes, {count} sin leer'**
  String feedMessagesWithUnreadA11y(int count);

  /// Accessibility label for the unread dot indicator shown on a _ChatRow in the chat inbox list.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin leer'**
  String get chatUnreadA11y;

  /// Section heading inside the session expansion tile in the trainer's Entrenamientos tab.
  ///
  /// In es_AR, this message translates to:
  /// **'SETS'**
  String get coachSessionSetLogsTitle;

  /// Call-to-action hint on a finished-session row, inviting the trainer to expand it.
  ///
  /// In es_AR, this message translates to:
  /// **'Ver sets'**
  String get coachSessionTapToExpand;

  /// Empty state shown when the athlete's session has no logged sets.
  ///
  /// In es_AR, this message translates to:
  /// **'Esta sesión no tiene sets registrados.'**
  String get coachSessionSetLogsEmpty;

  /// Generic error shown when loading setLogs fails for a non-permission reason.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar los sets. Intentá de nuevo.'**
  String get coachSessionSetLogsLoadError;

  /// Shown when the trainer receives permission-denied loading setLogs — the athlete has not shared or revoked sharing.
  ///
  /// In es_AR, this message translates to:
  /// **'El alumno no compartió su historial todavía.'**
  String get coachAthleteNoSharePlaceholder;

  /// Toolbar title for the avatar cropper modal (iOS, Android, web).
  ///
  /// In es_AR, this message translates to:
  /// **'Recortar foto'**
  String get avatarCropperTitle;

  /// Confirm button label in the avatar cropper modal.
  ///
  /// In es_AR, this message translates to:
  /// **'LISTO'**
  String get avatarCropperDone;

  /// Cancel button label in the avatar cropper modal.
  ///
  /// In es_AR, this message translates to:
  /// **'CANCELAR'**
  String get avatarCropperCancel;

  /// Section header for the per-exercise progression chart in the coach's athlete detail screen.
  ///
  /// In es_AR, this message translates to:
  /// **'EVOLUCIÓN POR EJERCICIO'**
  String get progressionSectionTitle;

  /// [AD3] Label for the Heaviest Weight metric chip (max weightKg per session) in the progression chart. Renamed from the mislabeled 'PR' — key kept for l10n stability, value updated.
  ///
  /// In es_AR, this message translates to:
  /// **'Peso máximo'**
  String get progressionMetricPr;

  /// [AD2] Label for the Epley-estimated one-rep-max metric chip in the progression chart.
  ///
  /// In es_AR, this message translates to:
  /// **'1RM'**
  String get progressionMetricOneRepMax;

  /// [AD3] Label for the Best Set Volume metric chip (max reps×weightKg of a single set) in the progression chart.
  ///
  /// In es_AR, this message translates to:
  /// **'Mejor serie'**
  String get progressionMetricBestSetVolume;

  /// Label for the Best Session Volume metric chip (Σ reps×weightKg per session) in the progression chart.
  ///
  /// In es_AR, this message translates to:
  /// **'Volumen'**
  String get progressionMetricVolume;

  /// Frecuencia stat label showing session count in the last 8 weeks.
  ///
  /// In es_AR, this message translates to:
  /// **'{count, plural, =0{Sin sesiones en las últimas 8 semanas} =1{1 sesión en las últimas 8 semanas} other{{count} sesiones en las últimas 8 semanas}}'**
  String progressionFrequency(int count);

  /// Hint shown when only 1 data point exists — no trend line can be drawn.
  ///
  /// In es_AR, this message translates to:
  /// **'Necesitás al menos 2 sesiones para ver la evolución.'**
  String get progressionSinglePointHint;

  /// Hint shown when the selected exercise has 0 data points.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin datos para este ejercicio.'**
  String get progressionEmptyExercise;

  /// Empty state shown when the athlete has no setLogs at all (exercise picker not shown).
  ///
  /// In es_AR, this message translates to:
  /// **'Sin registros de series todavía.'**
  String get progressionEmpty;

  /// [AD7] Label for the rolling 30-day chart period option (default) in the progression period selector.
  ///
  /// In es_AR, this message translates to:
  /// **'Últimos 30 días'**
  String get progressionPeriodLast30Days;

  /// [AD7] Label for the current-calendar-week chart period option in the progression period selector.
  ///
  /// In es_AR, this message translates to:
  /// **'Esta semana'**
  String get progressionPeriodThisWeek;

  /// [AD7] Label for the current-calendar-month chart period option in the progression period selector.
  ///
  /// In es_AR, this message translates to:
  /// **'Este mes'**
  String get progressionPeriodMonth;

  /// [AD4] Section header for the muscle distribution radar on the athlete Insights screen.
  ///
  /// In es_AR, this message translates to:
  /// **'DISTRIBUCIÓN MUSCULAR'**
  String get muscleDistributionSectionTitle;

  /// [AD4] Legend entry for the current-period radar series (Hevy: 'Current').
  ///
  /// In es_AR, this message translates to:
  /// **'Actual'**
  String get muscleDistributionCurrentLabel;

  /// [AD4] Legend entry for the previous-period radar series (Hevy: 'Previous').
  ///
  /// In es_AR, this message translates to:
  /// **'Anterior'**
  String get muscleDistributionPreviousLabel;

  /// [AD4] Shown instead of the radar chart when MuscleDistributionInsights.isEmpty (both current and previous windows have zero sets).
  ///
  /// In es_AR, this message translates to:
  /// **'Sin datos para este período.'**
  String get muscleDistributionEmptyState;

  /// [AD4] Workouts stat card label under the muscle distribution radar.
  ///
  /// In es_AR, this message translates to:
  /// **'Entrenos'**
  String get muscleDistributionWorkoutsLabel;

  /// [AD4] Duration stat card label under the muscle distribution radar.
  ///
  /// In es_AR, this message translates to:
  /// **'Duración'**
  String get muscleDistributionDurationLabel;

  /// [AD4] Volume stat card label under the muscle distribution radar.
  ///
  /// In es_AR, this message translates to:
  /// **'Volumen'**
  String get muscleDistributionVolumeLabel;

  /// [AD4] Sets stat card label under the muscle distribution radar.
  ///
  /// In es_AR, this message translates to:
  /// **'Sets'**
  String get muscleDistributionSetsLabel;

  /// [PR4] Section header for the per-exercise Personal Records list (Heaviest Weight/1RM/Best Set Volume/Best Session Volume with first-achieved date), shown below the progression chart.
  ///
  /// In es_AR, this message translates to:
  /// **'RÉCORDS PERSONALES'**
  String get personalRecordsSectionTitle;

  /// [PR4] Section header for the most-frequent-exercises list (Hevy's 'Main exercises'), ranked by session count within the selected chart period.
  ///
  /// In es_AR, this message translates to:
  /// **'EJERCICIOS MÁS FRECUENTES'**
  String get mostFrequentExercisesSectionTitle;

  /// [PR4] Session-count label shown next to each exercise row in the most-frequent-exercises list.
  ///
  /// In es_AR, this message translates to:
  /// **'{count, plural, =0{Sin sesiones} =1{1 sesión} other{{count} sesiones}}'**
  String mostFrequentExercisesSessionCount(int count);

  /// [PR4] Empty state shown when the most-frequent-exercises list has zero entries for the selected period.
  ///
  /// In es_AR, this message translates to:
  /// **'No hay datos todavía.'**
  String get mostFrequentExercisesEmpty;

  /// Section header above the trainer-assigned plans in the Profile › Mis Rutinas screen.
  ///
  /// In es_AR, this message translates to:
  /// **'RUTINAS ASIGNADAS POR TU PF'**
  String get profileRoutinesAssignedHeader;

  /// Section header above the athlete's self-created routines in the Profile › Mis Rutinas screen.
  ///
  /// In es_AR, this message translates to:
  /// **'MIS RUTINAS PROPIAS'**
  String get profileRoutinesOwnHeader;

  /// Empty-state body in the assigned-plans section when the athlete has no trainer-assigned plans.
  ///
  /// In es_AR, this message translates to:
  /// **'Todavía no tenés un PF asignado.'**
  String get profileRoutinesNoTrainerBody;

  /// CTA label in the empty-state of the assigned-plans section — navigates to the trainers directory.
  ///
  /// In es_AR, this message translates to:
  /// **'BUSCAR PF'**
  String get profileRoutinesNoTrainerCta;

  /// Empty-state body in the self-created routines section when the athlete has none.
  ///
  /// In es_AR, this message translates to:
  /// **'Todavía no creaste ninguna rutina.'**
  String get profileRoutinesNoOwnBody;

  /// Chip label shown on the user-created routine card that is currently marked as active by the athlete (UserProfile.activeRoutineId). Mirrors the chip in workoutMisRutinasActiveChip.
  ///
  /// In es_AR, this message translates to:
  /// **'ACTIVA'**
  String get profileRoutinesActiveChip;

  /// Title of the Appearance settings screen and the tile label in the profile settings list.
  ///
  /// In es_AR, this message translates to:
  /// **'Apariencia'**
  String get appearanceTitle;

  /// Label for the System (OS-controlled) theme option in AppearanceScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'Sistema'**
  String get appearanceSystem;

  /// Subtitle shown under the System option in AppearanceScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'Sigue el tema del dispositivo'**
  String get appearanceSystemDesc;

  /// Label for the Light theme option in AppearanceScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'Claro'**
  String get appearanceLight;

  /// Label for the Dark theme option in AppearanceScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'Oscuro'**
  String get appearanceDark;

  /// Section header label for the Appearance group in the profile screen.
  ///
  /// In es_AR, this message translates to:
  /// **'Apariencia'**
  String get profileSectionAppearance;

  /// Welcome greeting shown in the Coach Hub web dashboard WelcomeCard. {name} is the trainer's first name in uppercase.
  ///
  /// In es_AR, this message translates to:
  /// **'BUENAS, {name}'**
  String dashboardGreeting(String name);

  /// Greeting prefix rendered before the trainer's name (styled separately) in the Coach Hub dashboard WelcomeCard. Trailing space is intentional.
  ///
  /// In es_AR, this message translates to:
  /// **'BUENAS, '**
  String get dashboardGreetingPrefix;

  /// Dashboard WelcomeCard summary line combining sessions today, pending requests, and overdue payments.
  ///
  /// In es_AR, this message translates to:
  /// **'Tenés {sessions} sesiones hoy, {paraRevisar} para revisar, {pagos} pagos pendientes'**
  String dashboardSummaryLine(int sessions, int paraRevisar, int pagos);

  /// Quick action button label in the Coach Hub web dashboard WelcomeCard to navigate to the alumnos section.
  ///
  /// In es_AR, this message translates to:
  /// **'+ Nuevo alumno'**
  String get dashboardQuickActionNuevoAlumno;

  /// Quick action button label in the Coach Hub web dashboard WelcomeCard to navigate to routine creation.
  ///
  /// In es_AR, this message translates to:
  /// **'Crear rutina'**
  String get dashboardQuickActionCrearRutina;

  /// Quick action button label in the Coach Hub web dashboard WelcomeCard showing unread message count.
  ///
  /// In es_AR, this message translates to:
  /// **'Mensajes ({count})'**
  String dashboardQuickActionMensajes(int count);

  /// Quick action button label in the Coach Hub web dashboard WelcomeCard to navigate to the Excel plan importer.
  ///
  /// In es_AR, this message translates to:
  /// **'Importar plan'**
  String get dashboardQuickActionImportarPlan;

  /// Placeholder text shown in the alert banner section of the Coach Hub web dashboard (V1, no real notification aggregation yet).
  ///
  /// In es_AR, this message translates to:
  /// **'Próximamente: resumen de atención'**
  String get dashboardAlertBannerPlaceholder;

  /// KPI tile label for the count of active trainer-athlete links in the Coach Hub web dashboard.
  ///
  /// In es_AR, this message translates to:
  /// **'Alumnos activos'**
  String get dashboardKpiAlumnosActivos;

  /// KPI tile label for paid-this-month total ARS in the Coach Hub web dashboard.
  ///
  /// In es_AR, this message translates to:
  /// **'Ingreso del mes'**
  String get dashboardKpiIngresoMes;

  /// KPI tile label for average adherence (placeholder value in V1) in the Coach Hub web dashboard.
  ///
  /// In es_AR, this message translates to:
  /// **'Adherencia promedio'**
  String get dashboardKpiAdherencia;

  /// KPI tile label for overdue payments including count in the Coach Hub web dashboard.
  ///
  /// In es_AR, this message translates to:
  /// **'Por cobrar ({count} vencimientos)'**
  String dashboardKpiPorCobrar(int count);

  /// Generic coming-soon placeholder label used in Coach Hub web dashboard placeholder cards.
  ///
  /// In es_AR, this message translates to:
  /// **'Próximamente'**
  String get dashboardPlaceholderSoon;

  /// Placeholder value shown in the adherencia ring in the Coach Hub web dashboard WelcomeCard (no aggregate provider in V1).
  ///
  /// In es_AR, this message translates to:
  /// **'--'**
  String get dashboardAdherenceRingPlaceholder;

  /// Prefijo de dia para una proxima sesion que ocurre manana (dashboard Hoy, columna derecha de proximas sesiones).
  ///
  /// In es_AR, this message translates to:
  /// **'mañana'**
  String get dashboardProximaSesionManana;

  /// Empty state for the Próximas sesiones section in the Coach Hub web dashboard right column.
  ///
  /// In es_AR, this message translates to:
  /// **'No hay sesiones próximas confirmadas.'**
  String get dashboardProximasSesionesEmpty;

  /// Section title for the Vencimientos 7 días section in the Coach Hub web dashboard right column.
  ///
  /// In es_AR, this message translates to:
  /// **'VENCIMIENTOS — 7 DÍAS'**
  String get dashboardVencimientosTitle;

  /// Empty state for the Vencimientos 7 días section.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin pagos vencidos.'**
  String get dashboardVencimientosEmpty;

  /// Link label to navigate to /pagos from the Vencimientos section.
  ///
  /// In es_AR, this message translates to:
  /// **'Ver todos los pagos'**
  String get dashboardVencimientosVerTodos;

  /// Section title for the Alumnos inactivos placeholder section in the Coach Hub web dashboard right column.
  ///
  /// In es_AR, this message translates to:
  /// **'ALUMNOS INACTIVOS'**
  String get dashboardInactivosTitle;

  /// Empty state for the Alumnos inactivos section when all athletes trained in the last 14 days.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin alumnos inactivos'**
  String get dashboardInactivosEmpty;

  /// Alert banner message when there are no vencidos, pending solicitudes, or inactive athletes.
  ///
  /// In es_AR, this message translates to:
  /// **'Todo al día'**
  String get dashboardAlertBannerAllClear;

  /// Alert banner composed summary line showing vencidos, pending requests, and inactive athletes counts.
  ///
  /// In es_AR, this message translates to:
  /// **'{vencidos, plural, =1{1 vencido} other{{vencidos} vencidos}} · {solicitudes, plural, =1{1 solicitud} other{{solicitudes} solicitudes}} · {inactivos, plural, =1{1 inactivo} other{{inactivos} inactivos}}'**
  String dashboardAlertBannerSummary(
      int vencidos, int solicitudes, int inactivos);

  /// Formatted adherencia percentage value shown in the adherencia ring and KPI tile once the aggregate provider has data.
  ///
  /// In es_AR, this message translates to:
  /// **'{pct}%'**
  String dashboardAdherenceValue(int pct);

  /// [AD6/PR5a] Tile label on InsightsScreen navigating to the Monthly Report screen — Hevy parity 'Monthly Report' entry in Statistics.
  ///
  /// In es_AR, this message translates to:
  /// **'Reporte mensual'**
  String get insightsMonthlyReportTile;

  /// [AD6/PR5a] Header title for the Monthly Report screen.
  ///
  /// In es_AR, this message translates to:
  /// **'REPORTE MENSUAL'**
  String get monthlyReportTitle;

  /// [AD6/PR5a] Workouts metric chip/stat-card label in the Monthly Report chart and summary cards.
  ///
  /// In es_AR, this message translates to:
  /// **'Entrenos'**
  String get monthlyReportMetricWorkouts;

  /// [AD6/PR5a] Duration metric chip/stat-card label in the Monthly Report chart and summary cards.
  ///
  /// In es_AR, this message translates to:
  /// **'Duración'**
  String get monthlyReportMetricDuration;

  /// [AD6/PR5a] Volume metric chip/stat-card label in the Monthly Report chart and summary cards.
  ///
  /// In es_AR, this message translates to:
  /// **'Volumen'**
  String get monthlyReportMetricVolume;

  /// [AD6/PR5a] Sets metric chip/stat-card label in the Monthly Report chart and summary cards.
  ///
  /// In es_AR, this message translates to:
  /// **'Sets'**
  String get monthlyReportMetricSets;

  /// [AD6/PR5a] Unit suffix for duration values displayed in minutes.
  ///
  /// In es_AR, this message translates to:
  /// **'min'**
  String get monthlyReportDurationUnit;

  /// [AD6] Unit suffix for monthly duration totals displayed in hours.
  ///
  /// In es_AR, this message translates to:
  /// **'h'**
  String get monthlyReportDurationHoursUnit;

  /// [AD6/PR5a] Unit suffix for the Volume summary stat card.
  ///
  /// In es_AR, this message translates to:
  /// **'kg'**
  String get monthlyReportVolumeUnit;

  /// [AD6/PR5a] Empty state shown in the Monthly Report bar chart when all 12 months are zero across every metric.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin datos en los últimos 12 meses.'**
  String get monthlyReportEmptyHint;

  /// [AD6] Segmented control label that shows the monthly report grouped by calendar month.
  ///
  /// In es_AR, this message translates to:
  /// **'POR MES'**
  String get monthlyReportByMonthLabel;

  /// [AD6] Segmented control label that shows the monthly report grouped by day.
  ///
  /// In es_AR, this message translates to:
  /// **'POR DÍA'**
  String get monthlyReportByDayLabel;

  /// [AD6] Empty state shown in the daily duration chart when the selected month has no trained minutes.
  ///
  /// In es_AR, this message translates to:
  /// **'Sin minutos entrenados en este mes.'**
  String get monthlyReportDailyEmptyHint;

  /// [AD6] Prefix used in daily duration chart tooltips before the calendar day number.
  ///
  /// In es_AR, this message translates to:
  /// **'Día'**
  String get monthlyReportDailyTooltipDayLabel;

  /// [AD6/PR5a] Error state for the Monthly Report screen's provider load failure. Paired with coachRetryLabel for the retry CTA.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tu reporte mensual. Probá de nuevo.'**
  String get monthlyReportLoadError;

  /// [AD6/PR5b] Week-streak indicator text shown next to the flame icon above the workout-days calendar. Reuses computeStreak's day-count value (same 'racha' terminology as the rest of the app, e.g. esta_semana_card.dart) — NOT a separate week-based streak calculation. Zero is a valid, always-rendered value (not hidden).
  ///
  /// In es_AR, this message translates to:
  /// **'Racha de {n} días'**
  String workoutDaysCalendarStreak(int n);

  /// [stats-hub] Section heading above the tile list on InsightsScreen, between the daily-muscles card and the ESTADÍSTICAS AVANZADAS tiles (Hevy 'Statistics' parity, obs #445).
  ///
  /// In es_AR, this message translates to:
  /// **'Estadísticas avanzadas'**
  String get insightsAdvancedStatsHeading;

  /// [stats-hub] Tile title on InsightsScreen navigating to MuscleDistributionScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'Distribución muscular'**
  String get insightsTileMuscleDistributionTitle;

  /// [stats-hub] One-line subtitle under the Distribución muscular tile.
  ///
  /// In es_AR, this message translates to:
  /// **'Comparativa actual vs. período anterior'**
  String get insightsTileMuscleDistributionSubtitle;

  /// [stats-hub] Header title for the dedicated MuscleDistributionScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'DISTRIBUCIÓN MUSCULAR'**
  String get muscleDistributionScreenTitle;

  /// Error state for the MuscleDistributionScreen's provider load failure. Paired with coachRetryLabel for the retry CTA — same convention as monthlyReportLoadError.
  ///
  /// In es_AR, this message translates to:
  /// **'No pudimos cargar tu distribución muscular. Probá de nuevo.'**
  String get muscleDistributionLoadError;

  /// Header title for the athlete-side ExerciseProgressionScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'EVOLUCIÓN POR EJERCICIO'**
  String get exerciseProgressionScreenTitle;

  /// Tile title on InsightsScreen navigating to ExerciseProgressionScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'Evolución por ejercicio'**
  String get insightsTileExerciseProgressionTitle;

  /// Tile subtitle for the Exercise Progression stats-hub entry.
  ///
  /// In es_AR, this message translates to:
  /// **'Tu progreso en cada ejercicio + records'**
  String get insightsTileExerciseProgressionSubtitle;

  /// Hint of the exercise-progression picker search field. The search runs over the exercises the ATHLETE HAS LOGGED, never the catalogue — see the exercise-progression ADR.
  ///
  /// In es_AR, this message translates to:
  /// **'Buscar ejercicio…'**
  String get progressionSearchHint;

  /// Shown when the picker search matches none of the athletes logged exercises. Wording says tuyo on purpose: an exercise that exists in the catalogue but was never trained has no progression and is intentionally absent.
  ///
  /// In es_AR, this message translates to:
  /// **'Ningún ejercicio tuyo coincide con la búsqueda.'**
  String get progressionSearchNoResults;

  /// Tile title on InsightsScreen navigating to AnthropometryScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'Medidas'**
  String get insightsTileMeasurementsTitle;

  /// Tile subtitle for the Anthropometry stats-hub entry.
  ///
  /// In es_AR, this message translates to:
  /// **'Peso y medidas corporales en el tiempo'**
  String get insightsTileMeasurementsSubtitle;

  /// Header title for the dedicated MeasurementsScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'MEDIDAS'**
  String get measurementsScreenTitle;

  /// Notes field hint in LogMeasurementScreen.selfLog mode — replaces the trainer-mode "Observaciones del entrenador…" copy.
  ///
  /// In es_AR, this message translates to:
  /// **'Notas (opcional)…'**
  String get measurementsSelfLogNotesHint;

  /// Label/tooltip for the "+" affordance on MEDIDAS that opens the athlete self-log form.
  ///
  /// In es_AR, this message translates to:
  /// **'Cargar medición'**
  String get measurementsAddSelfLog;

  /// Title of the card in MeasurementsScreen showing the athlete's own weight + height, read from UserProfile (captured at onboarding Step 4) so they don't re-enter them.
  ///
  /// In es_AR, this message translates to:
  /// **'TUS DATOS'**
  String get measurementsProfileCardTitle;

  /// Small hint under the profile-data card explaining where the weight/height come from and where to edit them.
  ///
  /// In es_AR, this message translates to:
  /// **'Los cargaste al registrarte. Editalos desde tu perfil.'**
  String get measurementsProfileCardHint;

  /// Label for the body-weight value in the profile-data card.
  ///
  /// In es_AR, this message translates to:
  /// **'Peso'**
  String get measurementsWeightLabel;

  /// Label for the height value in the profile-data card.
  ///
  /// In es_AR, this message translates to:
  /// **'Altura'**
  String get measurementsHeightLabel;

  /// Shown below the profile-data card when the athlete has ZERO measurements. Talks about EVOLUTION over time (the chart), not about having no data at all — the profile card above already shows the athlete's weight/height. Both the athlete (self-log, via the + action in this screen's header) and a linked trainer can create measurements — see `match /measurements` in firestore.rules, whose create rule allows `athleteId == uid` OR a trainer-role author.
  ///
  /// In es_AR, this message translates to:
  /// **'Todavía no hay mediciones cargadas. Tocá + para registrar la primera y seguir tu evolución.'**
  String get measurementsEmptyState;

  /// Shown when the athlete has exactly ONE measurement. MeasurementProgressChart requires >= 2 points — distinct from the zero case, which is why it is a separate string.
  ///
  /// In es_AR, this message translates to:
  /// **'Con una sola medición no hay progreso que mostrar. Falta al menos una más.'**
  String get measurementsNeedsMoreData;

  /// [stats-hub] Tile title on InsightsScreen navigating to FrequentExercisesScreen (athlete's own uid).
  ///
  /// In es_AR, this message translates to:
  /// **'Ejercicios frecuentes'**
  String get insightsTileFrequentExercisesTitle;

  /// [stats-hub] One-line subtitle under the Ejercicios frecuentes tile.
  ///
  /// In es_AR, this message translates to:
  /// **'Tus ejercicios más entrenados'**
  String get insightsTileFrequentExercisesSubtitle;

  /// [stats-hub] Header title for the dedicated FrequentExercisesScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'EJERCICIOS FRECUENTES'**
  String get frequentExercisesScreenTitle;

  /// [stats-hub] One-line subtitle under the Reporte mensual tile (title reuses insightsMonthlyReportTile).
  ///
  /// In es_AR, this message translates to:
  /// **'Resumen de entrenos por mes'**
  String get insightsTileMonthlyReportSubtitle;

  /// [stats-hub] Tile title on InsightsScreen navigating to VolumeByGroupScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'Volumen por grupo'**
  String get insightsTileVolumeByGroupTitle;

  /// [stats-hub] One-line subtitle under the Volumen por grupo tile.
  ///
  /// In es_AR, this message translates to:
  /// **'Sets vs. objetivo por grupo muscular'**
  String get insightsTileVolumeByGroupSubtitle;

  /// [stats-hub] Header title for the dedicated VolumeByGroupScreen.
  ///
  /// In es_AR, this message translates to:
  /// **'VOLUMEN POR GRUPO'**
  String get volumeByGroupScreenTitle;
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
