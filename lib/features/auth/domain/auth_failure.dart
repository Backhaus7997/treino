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
  const factory AuthFailure.unknown(String code) = _Unknown;

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
        _Unknown() => 'Algo salió mal. Intentá de nuevo',
      };
}
