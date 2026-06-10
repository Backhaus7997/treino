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
