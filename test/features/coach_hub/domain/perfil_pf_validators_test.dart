// SCENARIO-CHW-ONB-064: los validadores del perfil profesional son una sola
// fuente de verdad para las tarjetas del Hub y el onboarding.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/domain/perfil_pf_validators.dart';

void main() {
  group('validarBio', () {
    test('vacía y en blanco piden una bio', () {
      expect(validarBio(''), 'Escribí una bio.');
      expect(validarBio('     '), 'Escribí una bio.');
    });

    test('19 caracteres falla, 20 pasa', () {
      expect(validarBio('a' * 19), 'Al menos 20 caracteres.');
      expect(validarBio('a' * 20), isNull);
    });

    test('280 pasa, 281 falla', () {
      expect(validarBio('a' * 280), isNull);
      expect(validarBio('a' * 281), isNotNull);
    });

    test('mide el texto recortado', () {
      expect(validarBio('  ${'a' * 19}  '), 'Al menos 20 caracteres.');
      expect(validarBio('  ${'a' * 20}  '), isNull);
    });
  });

  group('validarPrecio', () {
    test('vacío y no entero', () {
      expect(validarPrecio(''), 'Ingresá un precio.');
      expect(validarPrecio('  '), 'Ingresá un precio.');
      expect(validarPrecio('12,5'), 'Ingresá un número entero.');
      expect(validarPrecio('abc'), 'Ingresá un número entero.');
    });

    test('499 falla, 500 pasa', () {
      expect(validarPrecio('499'), 'Mínimo \$500.');
      expect(validarPrecio('500'), isNull);
    });

    test('999999 pasa, 1000000 falla', () {
      expect(validarPrecio('999999'), isNull);
      expect(validarPrecio('1000000'), 'Máximo \$999999.');
    });

    test('mide el texto recortado', () {
      expect(validarPrecio(' 500 '), isNull);
    });
  });
}
