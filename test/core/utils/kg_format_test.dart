import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/kg_format.dart';

void main() {
  // formatWeightKg es para CAMPOS EDITABLES: sin agrupar y con punto, porque
  // el parser acepta los dos separadores y «5.000» se leería como 5.
  group('formatWeightKg (inputs)', () {
    test('null → empty string (empty editor field)', () {
      expect(formatWeightKg(null), '');
    });

    test('0 renders as plain 0', () {
      expect(formatWeightKg(0), '0');
    });

    test('whole numbers drop the decimal', () {
      expect(formatWeightKg(20.0), '20');
      expect(formatWeightKg(60.0), '60');
      expect(formatWeightKg(100.0), '100');
    });

    test('fractional values keep their decimals as typed', () {
      expect(formatWeightKg(17.5), '17.5');
      expect(formatWeightKg(17.25), '17.25');
      expect(formatWeightKg(0.5), '0.5');
    });

    test('never compacts, even at the top of the plausible range', () {
      expect(formatWeightKg(227.5), '227.5');
      expect(formatWeightKg(500.0), '500');
    });
  });

  group('formatWeightKg — nunca agrupa: un input con «5.000» se lee 5', () {
    test('5000 queda 5000', () => expect(formatWeightKg(5000), '5000'));
  });

  // ── Pantalla: con el locale (#1465, #1481, #1512, #1516) ─────────────────

  group('formatWeightDisplay — es_AR', () {
    String f(double kg) => formatWeightDisplay(kg, 'es_AR');

    test('coma decimal', () {
      expect(f(12.5), '12,5');
      expect(f(88.5), '88,5');
      expect(f(0.5), '0,5');
    });
    test('enteros sin decimal', () {
      expect(f(20), '20');
      expect(f(0), '0');
    });
    test('miles con punto', () {
      expect(f(1000), '1.000');
      expect(f(1234.5), '1.234,5');
    });
    test('hasta dos decimales, como se cargó', () {
      expect(f(17.25), '17,25');
    });
  });

  group('formatWeightDisplay — en', () {
    test('punto decimal y coma de miles', () {
      expect(formatWeightDisplay(12.5, 'en'), '12.5');
      expect(formatWeightDisplay(1234.5, 'en'), '1,234.5');
    });
  });

  group('formatVolumeKg — debajo de 10 000, número completo', () {
    String f(double kg) => formatVolumeKg(kg, 'es_AR');

    test('0 (sesión sólo con peso corporal) es 0, no 0,0', () {
      expect(f(0), '0');
    });
    test('volumen chico fraccionario conserva un decimal', () {
      expect(f(3.2), '3,2');
    });
    test('enteros sin decimal y con separador de miles (#1465)', () {
      expect(f(600), '600');
      expect(f(1800), '1.800');
      expect(f(9600), '9.600');
    });
    test('fraccionarios redondean a un decimal', () {
      expect(f(987.5), '987,5');
      expect(f(999.9), '999,9');
      expect(f(1234.5), '1.234,5');
      expect(f(3880.75), '3.880,8');
    });
    test('justo debajo del umbral sigue completo', () {
      expect(f(9999), '9.999');
      expect(f(9999.5), '9.999,5');
    });
  });

  group('formatVolumeKg — compacto desde 10 000', () {
    String f(double kg) => formatVolumeKg(kg, 'es_AR');

    test('miles exactos sin el ,0 redundante', () {
      expect(f(10000), '10k');
      expect(f(12000), '12k');
      expect(f(100000), '100k');
    });
    test('trunca — un titular nunca infla', () {
      expect(f(20770), '20,7k');
      expect(f(34580), '34,5k');
      expect(f(10099), '10k');
    });
    test('el caso del QA: 66.057,5 → 66k, no «66.0k» (#1516)', () {
      expect(f(66057.5), '66k');
    });
    test('un millón agrupa la parte entera', () {
      expect(f(1234567), '1.234,5k');
    });
  });

  group('formatVolumeKg — en', () {
    test('punto decimal y coma de miles', () {
      expect(formatVolumeKg(1234.5, 'en'), '1,234.5');
      expect(formatVolumeKg(20770, 'en'), '20.7k');
    });
  });

  // Números que no son kg (cm, s, horas, niveles, deltas): mismo criterio que
  // los helpers sueltos que reemplaza — entero sin decimal, si no uno — pero
  // con el locale.
  group('formatNumberDisplay', () {
    test('es_AR: coma decimal, sin ,0 redundante, miles con punto', () {
      expect(formatNumberDisplay(80, 'es_AR'), '80');
      expect(formatNumberDisplay(78.5, 'es_AR'), '78,5');
      expect(formatNumberDisplay(1.66, 'es_AR'),
          '1,7'); // 1.65 es 1.6499… en binario
      expect(formatNumberDisplay(3100, 'es_AR'), '3.100');
      expect(formatNumberDisplay(-12.5, 'es_AR'), '-12,5');
    });
    test('maxDecimals', () {
      expect(formatNumberDisplay(1.784, 'es_AR', maxDecimals: 2), '1,78');
      expect(formatNumberDisplay(2.5, 'es_AR', maxDecimals: 0), '3');
    });
    test('en', () {
      expect(formatNumberDisplay(78.5, 'en'), '78.5');
      expect(formatNumberDisplay(3100, 'en'), '3,100');
    });
  });
}
