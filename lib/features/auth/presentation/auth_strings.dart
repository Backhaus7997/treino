/// Centralized Spanish (es-AR) copy for all auth screens.
/// Hardcoded strings for Etapa 2; ARB localization deferred to Etapa 6+.
abstract final class AuthStrings {
  // --- Login ---
  static const loginTitle = 'Entrá a tu cuenta';
  static const loginEmailLabel = 'Email';
  static const loginEmailHint = 'tunombre@ejemplo.com';
  static const loginPasswordLabel = 'Contraseña';
  static const loginSubmit = 'Iniciar sesión';
  static const loginForgot = '¿Olvidaste tu contraseña?';
  static const loginNoAccount = '¿Todavía no tenés cuenta?';
  static const loginRegisterLink = 'Registrate';

  // --- Register ---
  static const registerTitle = 'Creá tu cuenta';
  static const registerEmailLabel = 'Email';
  static const registerPasswordLabel = 'Contraseña';
  static const registerPasswordHint =
      'Mínimo 8 caracteres, una letra y un número';
  static const registerConfirmLabel = 'Confirmar contraseña';
  static const registerSubmit = 'Crear cuenta';
  static const registerHasAccount = '¿Ya tenés cuenta?';
  static const registerLoginLink = 'Iniciá sesión';

  // --- Forgot password ---
  static const forgotTitle = 'Recuperar contraseña';
  static const forgotSubtitle =
      'Te enviamos un enlace para que crees una nueva.';
  static const forgotEmailLabel = 'Email';
  static const forgotSubmit = 'Enviar enlace';
  static const forgotBackToLogin = 'Volver al login';

  /// Interpolated at runtime: 'Te enviamos un email a {email}. Revisá tu bandeja de entrada.'
  static String forgotSuccess(String email) =>
      'Te enviamos un email a $email. Revisá tu bandeja de entrada.';

  // --- Validation ---
  static const validationEmailInvalid = 'El email no es válido';
  static const validationPasswordRules =
      'La contraseña debe tener al menos 8 caracteres, una letra y un número';
  static const validationPasswordMismatch = 'Las contraseñas no coinciden';

  // --- Email verification banner ---
  static const verifyBannerTitle = 'Verificá tu email';
  static const verifyBannerSubtitle =
      'Te enviamos un enlace de verificación. Tocá Reenviar si no lo recibiste.';
  static const verifyResend = 'Reenviar';
  static const verifyDismiss = 'Ahora no';

  // --- Profile ---
  static const profileSignOut = 'Cerrar sesión';
}
