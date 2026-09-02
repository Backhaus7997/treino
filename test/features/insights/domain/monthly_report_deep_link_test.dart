import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/monthly_report_deep_link.dart';

// Contrato del deep link del push mensual. La otra mitad vive en
// `functions/src/__tests__/notify-monthly-report.test.ts`, que fija el mismo
// literal del lado que ARMA la URL. Este archivo fija el lado que la LEE: si
// alguien cambia el formato de un extremo, uno de los dos se pone rojo en vez
// de abrir la pantalla equivocada sin que nadie se entere.

void main() {
  group('parseMonthlyReportMonthParam — el formato del contrato', () {
    test('YYYY-MM válido → día 1 de ese mes', () {
      expect(parseMonthlyReportMonthParam('2026-08'), DateTime(2026, 8));
    });

    test('enero con cero adelante', () {
      expect(parseMonthlyReportMonthParam('2027-01'), DateTime(2027, 1));
    });

    test('diciembre — el caso del push del 1 de enero', () {
      // La función notifica el mes que CERRÓ: corriendo el 1/1/2027 reporta
      // 2026-12. Si este parseo fallara, el push de Año Nuevo abriría la
      // pantalla en el mes equivocado.
      expect(parseMonthlyReportMonthParam('2026-12'), DateTime(2026, 12));
    });
  });

  group('parseMonthlyReportMonthParam — entrada no confiable → null', () {
    // Un deep link llega de un push, de un bookmark viejo o de alguien
    // pegando una URL a mano. Ninguna de estas entradas puede tirar: la
    // pantalla cae al mes más reciente, que es su comportamiento de siempre.
    for (final raw in <String?>[
      null,
      '',
      '2026-8', // mes sin cero adelante — no es el formato del contrato
      '26-08', // año de dos dígitos
      '2026-13', // mes fuera de rango
      '2026-00', // idem
      '2026/08', // separador equivocado
      'agosto',
      '2026-08-15', // fecha completa: el ancla del regex la tiene que rechazar
      ' 2026-08', // con espacio adelante
    ]) {
      test('${raw == null ? 'null' : '"$raw"'} → null', () {
        expect(parseMonthlyReportMonthParam(raw), isNull);
      });
    }
  });
}
