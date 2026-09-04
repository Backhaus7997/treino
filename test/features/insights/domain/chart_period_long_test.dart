// Períodos largos de los gráficos: 3 meses y 1 año.
//
// La aritmética va con el constructor de calendario y NUNCA con
// `.add(Duration(days: n))` — un día local no siempre dura 24h en zonas con
// horario de verano. Argentina no lo observa desde 2009, pero el selector es
// UI compartida y tiene que ser correcto en cualquier zona.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/chart_period.dart';

void main() {
  group('last3m — 3 meses rodantes', () {
    test('la ventana actual es inclusiva de los dos lados', () {
      // Del 15/9 hacia atrás 3 meses da el 15/6; +1 día lo hace inclusivo, así
      // que arranca el 16/6. Sin ese +1 la ventana cubriría 3 meses y un día.
      final w = ChartPeriod.last3m.windowFor(DateTime.utc(2026, 9, 15));
      expect(w.currentStart, DateTime.utc(2026, 6, 16));
      expect(w.currentEnd, DateTime.utc(2026, 9, 15));
    });

    test('la ventana previa no se solapa con la actual', () {
      final w = ChartPeriod.last3m.windowFor(DateTime.utc(2026, 9, 15));
      expect(w.previousEnd, DateTime.utc(2026, 6, 15));
      expect(w.previousEnd.isBefore(w.currentStart), isTrue);
      expect(w.previousStart, DateTime.utc(2026, 3, 16));
    });

    test('cruza el año hacia atrás', () {
      // Febrero 2026 menos 3 meses cae en noviembre de 2025.
      final w = ChartPeriod.last3m.windowFor(DateTime.utc(2026, 2, 10));
      expect(w.currentStart, DateTime.utc(2025, 11, 11));
      expect(w.currentEnd, DateTime.utc(2026, 2, 10));
    });

    test('el 31 de un mes cuyo -3 no tiene 31 no explota', () {
      // 31/5 - 3 meses = 31/2, que el constructor normaliza al 3/3. Lo que
      // importa es que devuelva una fecha válida y ordenada, no que adivine
      // una intención imposible.
      final w = ChartPeriod.last3m.windowFor(DateTime.utc(2026, 5, 31));
      expect(w.currentStart.isBefore(w.currentEnd), isTrue);
      expect(w.previousEnd.isBefore(w.currentStart), isTrue);
      expect(w.previousStart.isBefore(w.previousEnd), isTrue);
    });

    test('ignora la hora del día', () {
      final aMedianoche =
          ChartPeriod.last3m.windowFor(DateTime.utc(2026, 9, 15));
      final aLaTarde =
          ChartPeriod.last3m.windowFor(DateTime.utc(2026, 9, 15, 18, 42, 7));
      expect(aLaTarde, aMedianoche);
    });
  });

  group('last1y — 12 meses rodantes', () {
    test('un año exacto, inclusivo', () {
      final w = ChartPeriod.last1y.windowFor(DateTime.utc(2026, 9, 15));
      expect(w.currentStart, DateTime.utc(2025, 9, 16));
      expect(w.currentEnd, DateTime.utc(2026, 9, 15));
    });

    test('la previa es el año anterior, sin solaparse', () {
      final w = ChartPeriod.last1y.windowFor(DateTime.utc(2026, 9, 15));
      expect(w.previousEnd, DateTime.utc(2025, 9, 15));
      expect(w.previousStart, DateTime.utc(2024, 9, 16));
      expect(w.previousEnd.isBefore(w.currentStart), isTrue);
    });

    test('el 29 de febrero de un bisiesto da una fecha válida', () {
      final w = ChartPeriod.last1y.windowFor(DateTime.utc(2028, 2, 29));
      expect(w.currentEnd, DateTime.utc(2028, 2, 29));
      expect(w.currentStart.isBefore(w.currentEnd), isTrue);
    });
  });

  group('invariantes que valen para TODOS los períodos', () {
    final anclas = [
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 2, 28),
      DateTime.utc(2026, 5, 31),
      DateTime.utc(2026, 9, 15),
      DateTime.utc(2026, 12, 31),
    ];

    test('la ventana previa siempre termina antes de que empiece la actual',
        () {
      for (final p in ChartPeriod.values) {
        for (final now in anclas) {
          final w = p.windowFor(now);
          expect(w.previousEnd.isBefore(w.currentStart), isTrue,
              reason: '$p en $now se solapa');
        }
      }
    });

    test('start nunca es posterior a end', () {
      for (final p in ChartPeriod.values) {
        for (final now in anclas) {
          final w = p.windowFor(now);
          expect(w.currentStart.isAfter(w.currentEnd), isFalse, reason: '$p');
          expect(w.previousStart.isAfter(w.previousEnd), isFalse, reason: '$p');
        }
      }
    });

    test('el default sigue siendo last30d', () {
      // Pineado: agregar períodos NO puede cambiar con qué abre la pantalla.
      expect(ChartPeriod.defaultPeriod, ChartPeriod.last30d);
    });

    test('los tres períodos originales conservan su posición en el selector',
        () {
      // El selector renderiza `values` en orden. Reordenar movería de lugar
      // pills que el usuario ya tiene aprendidas.
      expect(ChartPeriod.values.take(3).toList(), [
        ChartPeriod.last30d,
        ChartPeriod.thisWeek,
        ChartPeriod.month,
      ]);
    });
  });

  group('cuál es el período más largo', () {
    test('1 año cubre más que 3 meses, y 3 meses más que 30 días', () {
      final now = DateTime.utc(2026, 9, 15);
      final d30 = ChartPeriod.last30d.windowFor(now).currentStart;
      final m3 = ChartPeriod.last3m.windowFor(now).currentStart;
      final y1 = ChartPeriod.last1y.windowFor(now).currentStart;
      expect(m3.isBefore(d30), isTrue);
      expect(y1.isBefore(m3), isTrue);
    });
  });
}
