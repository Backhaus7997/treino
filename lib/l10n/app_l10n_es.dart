// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppL10nEs extends AppL10n {
  AppL10nEs([String locale = 'es']) : super(locale);

  @override
  String get authSplashTagline => '';

  @override
  String get authWelcomeEyebrow => '';

  @override
  String get authWelcomeBody => '';

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
}

/// The translations for Spanish Castilian, as used in Argentina (`es_AR`).
class AppL10nEsAr extends AppL10nEs {
  AppL10nEsAr() : super('es_AR');

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
}
