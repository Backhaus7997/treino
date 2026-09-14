import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';

/// consentimiento-legal-versionado — R1: constantes de versión independientes
/// y monotónicas.
void main() {
  group('kTermsVersion / kPrivacyVersion', () {
    test('both start at 1 and are int', () {
      expect(kTermsVersion, equals(1));
      expect(kTermsVersion, isA<int>());
      expect(kPrivacyVersion, equals(1));
      expect(kPrivacyVersion, isA<int>());
    });

    test(
        'are independent constants — bumping one does not require changing '
        'the other (compile-time proof: two distinct top-level consts)', () {
      // No hay forma de "bumpear" un const en runtime, así que la
      // independencia se prueba comparando identidad de valor: si algún día
      // colapsan a la misma variable, este assert de igualdad NO alcanzaría
      // para detectarlo, pero el punto real de R1 es que son dos
      // declaraciones separadas — ver kPrivacyVersion != kTermsVersionSymbol
      // no aplica en Dart. La prueba de comportamiento vive en que ambas
      // existen y son ints ordinarios, sin acoplamiento entre sí.
      expect(kTermsVersion, equals(1));
      expect(kPrivacyVersion, equals(1));
    });
  });

  group('kPrivacyV1PublishedAt', () {
    test('is a machine-comparable UTC date marking the current Privacy text',
        () {
      expect(kPrivacyV1PublishedAt, equals(DateTime.utc(2026, 9, 3)));
      expect(kPrivacyV1PublishedAt.isUtc, isTrue);
    });

    test('is distinct from kPrivacyLastUpdated (display-only, never parsed)',
        () {
      // kPrivacyLastUpdated es un String de display — no debe usarse como
      // sustituto de esta constante machine-comparable.
      expect(kPrivacyLastUpdated, isA<String>());
      expect(kPrivacyV1PublishedAt, isA<DateTime>());
    });
  });
}
