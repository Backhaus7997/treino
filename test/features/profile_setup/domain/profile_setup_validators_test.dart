import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_validators.dart';

/// Gate de edad mínima (16). Todos los casos inyectan [now]: sin eso, el test
/// del borde ("cumple 16 hoy" contra "los cumple mañana") depende del día en
/// que corra CI y se vuelve flaky exactamente una vez al año, por usuario.
void main() {
  const minAgeError = 'Tenés que tener 16 años para usar TREINO';

  group('validateBornAt', () {
    test('null es inválido — el campo es obligatorio en el alta', () {
      expect(
        ProfileSetupValidators.validateBornAt(null),
        'Ingresá tu fecha de nacimiento',
      );
    });

    test('cumple 16 HOY es válido', () {
      expect(
        ProfileSetupValidators.validateBornAt(
          DateTime.utc(2010, 9, 16),
          now: DateTime(2026, 9, 16),
        ),
        isNull,
      );
    });

    test('los cumple MAÑANA es inválido', () {
      expect(
        ProfileSetupValidators.validateBornAt(
          DateTime.utc(2010, 9, 17),
          now: DateTime(2026, 9, 16),
        ),
        minAgeError,
      );
    });

    test('los cumplió AYER es válido', () {
      expect(
        ProfileSetupValidators.validateBornAt(
          DateTime.utc(2010, 9, 15),
          now: DateTime(2026, 9, 16),
        ),
        isNull,
      );
    });

    // El 29/2 es el que rompe las implementaciones que dividen días por 365.
    // Va el par completo, no sólo el caso feliz: un test que sólo mira el lado
    // válido pasa igual con la cuenta rota.
    group('nacido un 29 de febrero', () {
      test('el 28/2 del año del 16º cumpleaños todavía NO los tiene', () {
        // 2024 es bisiesto: el cumpleaños existe y cae mañana.
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2008, 2, 29),
            now: DateTime(2024, 2, 28),
          ),
          minAgeError,
        );
      });

      test('el 29/2 del año del 16º cumpleaños ya los tiene', () {
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2008, 2, 29),
            now: DateTime(2024, 2, 29),
          ),
          isNull,
        );
      });

      test('un 28/2 de año NO bisiesto posterior sigue siendo válido', () {
        // 2025 no es bisiesto, así que el 29/2 no existe: el `day >=` tiene
        // que resolverlo solo, sin ninguna excepción en el código.
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2008, 2, 29),
            now: DateTime(2025, 2, 28),
          ),
          isNull,
        );
      });
    });

    test('una fecha futura da el error de fecha futura, no el de edad', () {
      expect(
        ProfileSetupValidators.validateBornAt(
          DateTime.utc(2026, 9, 17),
          now: DateTime(2026, 9, 16),
        ),
        'La fecha no puede ser futura',
      );
    });

    test('130 años es un dedazo en el año, no una persona', () {
      expect(
        ProfileSetupValidators.validateBornAt(
          DateTime.utc(1896, 9, 16),
          now: DateTime(2026, 9, 16),
        ),
        'Fecha inválida',
      );
    });

    // Guarda contra una reescritura con `difference()` o `isAfter`: la hora del
    // día no puede mover el veredicto, porque lo que se compara son días
    // calendario y `bornAt` se persiste como fecha-only UTC.
    test('la hora del día no cambia el veredicto en el día del cumpleaños', () {
      for (final hour in [0, 3, 12, 23]) {
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2010, 9, 16),
            now: DateTime(2026, 9, 16, hour, 30),
          ),
          isNull,
          reason: 'hora $hour debería seguir siendo válido',
        );
      }
    });
  });
}
