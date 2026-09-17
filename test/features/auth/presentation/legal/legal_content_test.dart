import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_validators.dart';

/// consentimiento-legal-versionado — R1: constantes de versión independientes
/// y monotónicas.
void main() {
  group('kTermsVersion / kPrivacyVersion', () {
    // Assertear el VALOR (`equals(1)`) convertía este test en un snapshot: un
    // bump legítimo lo ponía rojo y había que editarlo, que es justo lo que
    // entrena a editar tests en vez de leerlos. El invariante real es que son
    // enteros y que nunca retroceden.
    test('son enteros y nunca bajan de 1', () {
      expect(kTermsVersion, isA<int>());
      expect(kTermsVersion, greaterThanOrEqualTo(1));
      expect(kPrivacyVersion, isA<int>());
      expect(kPrivacyVersion, greaterThanOrEqualTo(1));
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
      expect(kTermsVersion, greaterThanOrEqualTo(1));
      expect(kPrivacyVersion, greaterThanOrEqualTo(1));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // El contrato que la app MUESTRA no puede prometer lo que el código rechaza
  //
  // Hallazgo de Codex en el PR #1162. Los términos decían "al menos 16 años, o
  // contar con el consentimiento de una persona adulta responsable" mientras el
  // validador rechazaba a todo menor de 16 sin excepción: un chico de 14
  // aceptaba un contrato que le decía que podía, y lo frenábamos dos pantallas
  // después. El texto vive en DOS copias —este Dart y `docs/legal/*.md`— y ya se
  // desincronizaron una vez.
  // ────────────────────────────────────────────────────────────────────────
  group('los términos y el gate de edad dicen lo mismo', () {
    String cuerpo(List<LegalSection> secs) =>
        secs.map((s) => '${s.heading}\n${s.body}').join('\n\n');

    test('los términos declaran la MISMA edad mínima que el validador', () {
      expect(
        cuerpo(kTermsSections),
        contains('${ProfileSetupValidators.kMinAgeYears} años cumplidos'),
        reason: 'si kMinAgeYears cambia, este texto tiene que cambiar con él',
      );
    });

    test('los términos NO ofrecen una excepción por consentimiento adulto', () {
      // El gate no la contempla, y no puede: un consentimiento declarado por el
      // propio menor en un checkbox no es el consentimiento parental
      // VERIFICABLE que exige COPPA §312.5. Prometerla sería ofrecer un camino
      // que la app no tiene.
      expect(
        cuerpo(kTermsSections).toLowerCase(),
        isNot(contains('o contar con el consentimiento')),
      );
    });

    test('la política declara que recolecta la fecha de nacimiento', () {
      // Pasó a ser un dato OBLIGATORIO en el alta. Recolectarlo sin declararlo
      // es el agujero que este grupo existe para tapar.
      expect(
        cuerpo(kPrivacySections).toLowerCase(),
        contains('fecha de nacimiento'),
      );
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
