import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:treino/core/utils/date_labels.dart';

void main() {
  setUpAll(() async {
    // En la app real esto lo hace GlobalMaterialLocalizations al montar el
    // MaterialApp; acá lo hacemos a mano porque el test es dart puro.
    await initializeDateFormatting();
  });

  group('weekdayInitials', () {
    test('es-AR devuelve las iniciales del diseño, lunes→domingo', () {
      expect(
        weekdayInitials('es_AR'),
        ['L', 'M', 'M', 'J', 'V', 'S', 'D'],
      );
    });

    // Guarda del quirk: DateFormat('EEEEE', 'es_AR') devuelve 'X' para
    // miércoles porque es-AR hereda los narrow weekdays de España. El diseño
    // usa la convención latinoamericana 'M'. Si alguien "simplifica" el helper
    // a EEEEE, este test lo frena.
    test('miércoles es M, no la X del narrow de es-AR', () {
      const miercoles = 2; // índice lunes→domingo
      expect(weekdayInitials('es_AR')[miercoles], 'M');
      expect(weekdayInitials('es_AR')[miercoles], isNot('X'));
    });

    test('se indexa con weekday - DateTime.monday', () {
      // 2026-06-17 es miércoles.
      final wednesday = DateTime(2026, 6, 17);
      expect(
        weekdayInitials('es_AR')[wednesday.weekday - DateTime.monday],
        'M',
      );
      // 2026-06-21 es domingo — el último índice, no el primero.
      final sunday = DateTime(2026, 6, 21);
      expect(
        weekdayInitials('es_AR')[sunday.weekday - DateTime.monday],
        'D',
      );
    });

    test('es locale-aware, no un array es-AR disfrazado', () {
      expect(weekdayInitials('en_US'), ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
    });
  });

  group('weekdayDistinctAbbrevs', () {
    test('es-AR estira sólo los días que colisionan', () {
      expect(
        weekdayDistinctAbbrevs('es_AR'),
        ['L', 'Ma', 'Mi', 'J', 'V', 'S', 'D'],
      );
    });

    test('en_US desambigua martes/jueves y sábado/domingo', () {
      expect(
        weekdayDistinctAbbrevs('en_US'),
        ['M', 'Tu', 'W', 'Th', 'F', 'Sa', 'Su'],
      );
    });

    test('toda abreviatura es única dentro de la semana', () {
      final abbrevs = weekdayDistinctAbbrevs('es_AR');
      expect(abbrevs.toSet(), hasLength(7));
    });
  });

  group('monthAbbrev', () {
    test('es-AR en mayúsculas da los 12 meses del diseño', () {
      final months = [
        for (var m = 1; m <= 12; m++)
          monthAbbrev(DateTime(2026, m), 'es_AR', upperCase: true),
      ];
      expect(months, [
        'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', //
        'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
      ]);
    });

    test('es-AR en casing natural del locale', () {
      expect(monthAbbrev(DateTime(2026, 4, 7), 'es_AR'), 'abr');
    });

    // Guarda del quirk: DateFormat('MMM', 'es_AR') devuelve 'sept' (4 chars)
    // para septiembre. El diseño asume 3 en ejes de charts.
    test('septiembre se trunca a 3 chars, no queda en sept', () {
      expect(monthAbbrev(DateTime(2026, 9), 'es_AR'), 'sep');
      expect(monthAbbrev(DateTime(2026, 9), 'es_AR', upperCase: true), 'SEP');
    });

    test('todos los meses tienen a lo sumo 3 chars', () {
      for (var m = 1; m <= 12; m++) {
        expect(monthAbbrev(DateTime(2026, m), 'es_AR').length,
            lessThanOrEqualTo(3));
      }
    });

    test('es locale-aware, no un array es-AR disfrazado', () {
      expect(monthAbbrev(DateTime(2026), 'en_US'), 'Jan');
      expect(monthAbbrev(DateTime(2026), 'en_US', upperCase: true), 'JAN');
    });
  });
}
