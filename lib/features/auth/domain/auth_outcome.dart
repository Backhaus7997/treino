import 'package:firebase_auth/firebase_auth.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_outcome.freezed.dart';

/// Result of any successful auth flow (email, Apple, Google, ...).
///
/// [user] is the authenticated [User] from Firebase.
/// [isNewUser] is `true` if Firebase reports `additionalUserInfo.isNewUser`,
/// false otherwise (or when the SDK didn't return additionalUserInfo on a
/// cached-credential path). Etapa 6 (ProfileSetup) will branch on this.
@freezed
class AuthOutcome with _$AuthOutcome {
  const factory AuthOutcome({
    required User user,
    required bool isNewUser,
  }) = _AuthOutcome;
}
