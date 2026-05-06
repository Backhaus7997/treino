/// Centralized Spanish (es-AR) copy for all auth screens.
/// Hardcoded strings for Etapa 2; ARB localization deferred to Etapa 6+.
abstract final class AuthStrings {
  // --- Splash ---
  static const splashTagline = 'ENTRENÁ. COMPARTÍ. CRECÉ.';

  // --- Welcome ---
  static const welcomeEyebrow = 'ENTRENAMIENTO · GYM · COACH';
  static const welcomeHeadlinePart1 = 'MOVÉS EL HIERRO.';
  static const welcomeHeadlinePart2 = 'NOSOTROS EL RESTO.';
  static const welcomeBody =
      'Cargá tu rutina, ejecutá los sets, seguí a tus pibes y encontrá un coach cerca tuyo.';
  static const welcomeCta = 'EMPEZAR';
  static const welcomeHaveAccount = 'Ya tengo cuenta';
  static const welcomeSignIn = 'Iniciar sesión';

  // --- Login ---
  static const loginTitle = 'BIENVENIDO';
  static const loginSubtitle = 'Entrá para seguir tu rutina';
  static const loginEmailLabel = 'EMAIL';
  static const loginEmailHint = 'tu@email.com';
  static const loginPasswordLabel = 'CONTRASEÑA';
  static const loginPasswordHint = '';
  static const loginForgot = 'Olvidé la contraseña';
  static const loginCta = 'ENTRAR';
  static const loginContinueWith = 'O CONTINUÁ CON';
  static const loginNoAccount = '¿No tenés cuenta?';
  static const loginRegisterLink = 'Registrate';
  static const loginTrainerCardTitle = '¿Sos entrenador?';
  static const loginTrainerCardSubtitle = 'Pedí tu alta al equipo TREINO';

  // --- Register ---
  static const registerAppbar = 'CREAR CUENTA';
  static const registerTitle = 'SUMATE A TREINO';
  static const registerSubtitle = 'Es gratis. En 30 segundos estás adentro.';
  static const registerNameLabel = 'NOMBRE';
  static const registerNameHint = 'Tu nombre';
  static const registerEmailLabel = 'EMAIL';
  static const registerPasswordLabel = 'CONTRASEÑA';
  static const registerCta = 'CREAR CUENTA';
  static const registerDividerOr = 'O';

  // --- Forgot password ---
  static const forgotTitle = 'RECUPERAR\nACCESO';
  static const forgotBody =
      'Ingresá tu email y te enviamos un link para resetear la contraseña.';
  static const forgotEmailLabel = 'EMAIL';
  static const forgotEmailHint = 'tu@email.com';
  static const forgotCta = 'ENVIAR LINK';
  static const forgotSuccess =
      'Si tu email está registrado, te enviamos un link para resetear la contraseña.';
  static const forgotBackToLogin = 'Volver al login';

  // --- Trainer inquiry dialog ---
  static const trainerInquiryDialogTitle = 'Acceso de entrenador';
  static const trainerInquiryDialogBody =
      'Para alta de entrenador, escribinos a equipo@treino.app';
  static const trainerInquiryDialogClose = 'Cerrar';

  // --- Terms ---
  static const termsPlaceholder = 'Próximamente';

  // --- Social ---
  static const googleLabel = 'GOOGLE';
  static const appleLabel = 'APPLE';
  static const comingSoonTooltip = 'Próximamente';

  // --- Validation ---
  static const validationEmailInvalid = 'El email no es válido';
  static const validationPasswordRules =
      'La contraseña debe tener al menos 8 caracteres, una letra y un número';
  static const validationPasswordMismatch = 'Las contraseñas no coinciden';
  static const validationNameRequired = 'Ingresá tu nombre';

  // --- Profile ---
  static const profileSignOut = 'Cerrar sesión';
}
