import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_validators.dart';

/// Gate de edad mínima. Todos los casos inyectan [now]: sin eso, el test del
/// borde ("cumple hoy" contra "los cumple mañana") depende del día en que corra
/// CI y se vuelve flaky exactamente una vez al año, por usuario.
void main() {
  const minAgeError = 'Tenés que tener 13 años para usar TREINO';

  group('validateBornAt', () {
    test('null es inválido — el campo es obligatorio en el alta', () {
      expect(
        ProfileSetupValidators.validateBornAt(null),
        'Ingresá tu fecha de nacimiento',
      );
    });

    test('cumple la edad mínima HOY es válido', () {
      expect(
        ProfileSetupValidators.validateBornAt(
          DateTime.utc(2013, 9, 16),
          now: DateTime(2026, 9, 16),
        ),
        isNull,
      );
    });

    test('la cumple MAÑANA es inválido', () {
      expect(
        ProfileSetupValidators.validateBornAt(
          DateTime.utc(2013, 9, 17),
          now: DateTime(2026, 9, 16),
        ),
        minAgeError,
      );
    });

    test('la cumplió AYER es válido', () {
      expect(
        ProfileSetupValidators.validateBornAt(
          DateTime.utc(2013, 9, 15),
          now: DateTime(2026, 9, 16),
        ),
        isNull,
      );
    });

    // La banda 13-15 es el motivo del cambio de 16 a 13: el caso del club, un
    // entrenador con alumnos de esa edad. SIN estos dos casos, bajar la
    // constante pasa con el valor viejo intacto y nadie se entera.
    group('la banda que el cambio de 16 a 13 habilita', () {
      test('14 años es válido', () {
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2012, 9, 16),
            now: DateTime(2026, 9, 16),
          ),
          isNull,
        );
      });

      test('15 años es válido', () {
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2011, 9, 16),
            now: DateTime(2026, 9, 16),
          ),
          isNull,
        );
      });

      test('12 años sigue siendo inválido — es el piso, no una barrera móvil',
          () {
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2014, 9, 16),
            now: DateTime(2026, 9, 16),
          ),
          minAgeError,
        );
      });
    });

    // El 29/2 rompe las implementaciones que dividen días por 365. Con la edad
    // mínima en 13 el caso además cambió de forma: 2008 + 13 = 2021, que NO es
    // bisiesto, así que ese cumpleaños no existe como fecha. Con 16 sí existía,
    // porque 16 es múltiplo de 4.
    group('nacido un 29 de febrero', () {
      test('el 28/2 de un año no bisiesto todavía NO los tiene', () {
        // Convención deliberada: cumple el 1 de marzo, no el 28 de febrero.
        // Ver el dartdoc de _yearsBetween — atrasar un día nunca deja pasar a
        // quien todavía no tiene la edad.
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2008, 2, 29),
            now: DateTime(2021, 2, 28),
          ),
          minAgeError,
        );
      });

      test('el 1 de marzo siguiente ya los tiene', () {
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2008, 2, 29),
            now: DateTime(2021, 3, 1),
          ),
          isNull,
        );
      });

      test('años después sigue siendo válido, sin excepciones en el código',
          () {
        expect(
          ProfileSetupValidators.validateBornAt(
            DateTime.utc(2008, 2, 29),
            now: DateTime(2026, 2, 28),
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
            DateTime.utc(2013, 9, 16),
            now: DateTime(2026, 9, 16, hour, 30),
          ),
          isNull,
          reason: 'hora $hour debería seguir siendo válido',
        );
      }
    });

    // El mensaje interpola la constante, así que no puede quedar desfasado del
    // número que efectivamente se aplica.
    test('el mensaje nombra la edad que el validador aplica', () {
      expect(
        ProfileSetupValidators.validateBornAt(
          DateTime.utc(2014, 9, 16),
          now: DateTime(2026, 9, 16),
        ),
        contains('${ProfileSetupValidators.kMinAgeYears} años'),
      );
    });
  });
}
