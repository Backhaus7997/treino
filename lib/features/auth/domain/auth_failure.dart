import 'package:firebase_auth/firebase_auth.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_failure.freezed.dart';

@freezed
sealed class AuthFailure with _$AuthFailure implements Exception {
  const AuthFailure._();

  const factory AuthFailure.invalidEmail() = _InvalidEmail;
  const factory AuthFailure.userDisabled() = _UserDisabled;
  const factory AuthFailure.userNotFound() = _UserNotFound;
  const factory AuthFailure.wrongPassword() = _WrongPassword;
  const factory AuthFailure.emailAlreadyInUse() = _EmailAlreadyInUse;
  const factory AuthFailure.weakPassword() = _WeakPassword;
  const factory AuthFailure.tooManyRequests() = _TooManyRequests;
  const factory AuthFailure.networkError() = _NetworkError;
  const factory AuthFailure.signInCancelled() = _SignInCancelled;
  const factory AuthFailure.accountExistsWithDifferentCredential() =
      _AccountExistsWithDifferentCredential;
  const factory AuthFailure.unknown(String code) = _Unknown;
  const factory AuthFailure.profileCreateFailed({Object? cause}) =
      _ProfileCreateFailed;

  // Account deletion variants (Fase 6 Etapa 3 — account-deletion SDD PR#3)
  const factory AuthFailure.requiresRecentLogin() = _RequiresRecentLogin;
  const factory AuthFailure.reAuthFailed({String? provider}) = _ReAuthFailed;
  const factory AuthFailure.deletionFailed({Object? cause}) = _DeletionFailed;

  factory AuthFailure.fromFirebase(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => const AuthFailure.invalidEmail(),
        'user-disabled' => const AuthFailure.userDisabled(),
        'user-not-found' => const AuthFailure.userNotFound(),
        'wrong-password' ||
        'invalid-credential' =>
          const AuthFailure.wrongPassword(),
        'email-already-in-use' => const AuthFailure.emailAlreadyInUse(),
        'weak-password' => const AuthFailure.weakPassword(),
        'too-many-requests' => const AuthFailure.tooManyRequests(),
        'network-request-failed' => const AuthFailure.networkError(),
        'account-exists-with-different-credential' =>
          const AuthFailure.accountExistsWithDifferentCredential(),
        'requires-recent-login' => const AuthFailure.requiresRecentLogin(),
        final code => AuthFailure.unknown(code),
      };

  /// Spanish (es-AR) user copy. Hardcoded; ARB localization deferred to Etapa 6+.
  String get userMessage => switch (this) {
        _InvalidEmail() => 'El email no es válido',
        _UserDisabled() => 'Tu cuenta está deshabilitada. Contactá soporte',
        _UserNotFound() => 'No encontramos una cuenta con ese email',
        _WrongPassword() => 'La contraseña es incorrecta',
        _EmailAlreadyInUse() => 'Ya existe una cuenta con ese email',
        _WeakPassword() => 'La contraseña es muy débil',
        _TooManyRequests() =>
          'Demasiados intentos. Esperá unos minutos e intentá de nuevo',
        _NetworkError() =>
          'Sin conexión. Revisá tu internet e intentá de nuevo',
        _SignInCancelled() => 'Cancelaste el inicio de sesión',
        _AccountExistsWithDifferentCredential() =>
          'Ya existe una cuenta con ese email usando otro método de inicio',
        _Unknown() => 'Algo salió mal. Intentá de nuevo',
        _ProfileCreateFailed() =>
          'Hubo un problema creando tu perfil. Probá de nuevo',
        // i18n: Fase 6 Etapa 3
        _RequiresRecentLogin() =>
          'Tu sesión venció. Tenés que volver a confirmar tu identidad.',
        // i18n: Fase 6 Etapa 3
        _ReAuthFailed() => 'No pudimos verificar tu identidad. Probá de nuevo.',
        // i18n: Fase 6 Etapa 3
        _DeletionFailed() => 'No pudimos eliminar tu cuenta. Probá de nuevo.',
      };
}
