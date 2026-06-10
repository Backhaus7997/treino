// T-I18N-008 RED — SCENARIO-769
// AuthFailure.userMessage intentional exclusion from i18n.
//
// Per ADR-I18N-002: domain layer MUST NOT depend on BuildContext.
// userMessage stays hardcoded es-AR forever.
//
// This test verifies:
// 1. Each AuthFailure variant's userMessage is EXACTLY the hardcoded es-AR string
//    (no runtime lookup through AppL10n — the value is const/deterministic).
// 2. The exclusion is documented — this test itself is the living spec for
//    the ADR-I18N-002 decision.
//
// RED: this test references a helper function `authFailureExclusionDocumented()`
// that does NOT exist yet in auth_failure.dart — this guarantees RED at compile.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';

void main() {
  group('AuthFailure.userMessage — ADR-I18N-002 intentional exclusion', () {
    // SCENARIO-769: userMessage is hardcoded, NOT routed through AppL10n.
    // Verify that the exclusion comment is documented in the source via
    // the kAuthFailureI18nExclusionNote sentinel constant.
    test('kAuthFailureI18nExclusionNote sentinel documents the exclusion', () {
      // This references a const that does NOT exist yet — RED.
      expect(
        kAuthFailureI18nExclusionNote,
        contains('intentional exclusion'),
      );
      expect(
        kAuthFailureI18nExclusionNote,
        contains('domain layer cannot receive BuildContext'),
      );
    });

    // SCENARIO-769: existing userMessage values are verbatim es-AR, unchanged.
    test('invalidEmail userMessage is hardcoded es-AR (not routed through ARB)', () {
      const failure = AuthFailure.invalidEmail();
      expect(failure.userMessage, 'El email no es válido');
    });

    test('wrongPassword userMessage is hardcoded es-AR', () {
      const failure = AuthFailure.wrongPassword();
      expect(failure.userMessage, 'La contraseña es incorrecta');
    });

    test('userNotFound userMessage is hardcoded es-AR', () {
      const failure = AuthFailure.userNotFound();
      expect(failure.userMessage, 'No encontramos una cuenta con ese email');
    });

    test('tooManyRequests userMessage is hardcoded es-AR', () {
      const failure = AuthFailure.tooManyRequests();
      expect(
        failure.userMessage,
        'Demasiados intentos. Esperá unos minutos e intentá de nuevo',
      );
    });
  });
}
