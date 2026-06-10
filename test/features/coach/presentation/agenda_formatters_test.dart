// T-I18N-010 RED — SCENARIO-776, SCENARIO-777
// agenda_formatters.dart extraction tests.
//
// Verifies that AgendaFormatters class exists with the three utility
// members extracted from AgendaStrings:
//   - formatDate(DateTime)
//   - formatTime(DateTime)
//   - dayOfWeekLabels (Map<int, String>)
//
// This test FAILS RED because agenda_formatters.dart does not exist yet.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/presentation/agenda_formatters.dart';

void main() {
  group('AgendaFormatters — SCENARIO-776, SCENARIO-777', () {
    // ── formatDate ────────────────────────────────────────────────────────────

    test('formatDate returns dd/MM/yyyy format', () {
      final dt = DateTime(2025, 3, 5, 10, 30);
      expect(AgendaFormatters.formatDate(dt), '05/03/2025');
    });

    test('formatDate pads day and month with leading zero', () {
      final dt = DateTime(2025, 1, 7, 8, 0);
      expect(AgendaFormatters.formatDate(dt), '07/01/2025');
    });

    test('formatDate does not apply toLocal() — reads fields directly', () {
      // Store a UTC datetime that represents Argentina wall-clock 09:00 on 2025-06-15.
      // If toLocal() is applied (subtracts 3h), day might be different. Here we assert
      // raw field read.
      final dt = DateTime.utc(2025, 6, 15, 9, 0);
      expect(AgendaFormatters.formatDate(dt), '15/06/2025');
    });

    // ── formatTime ────────────────────────────────────────────────────────────

    test('formatTime returns HH:mm format', () {
      final dt = DateTime(2025, 3, 5, 14, 5);
      expect(AgendaFormatters.formatTime(dt), '14:05');
    });

    test('formatTime pads hour and minute with leading zero', () {
      final dt = DateTime(2025, 1, 1, 9, 3);
      expect(AgendaFormatters.formatTime(dt), '09:03');
    });

    test('formatTime does not apply toLocal() — reads fields directly', () {
      final dt = DateTime.utc(2025, 6, 15, 8, 0);
      expect(AgendaFormatters.formatTime(dt), '08:00');
    });

    // ── dayOfWeekLabels ───────────────────────────────────────────────────────

    test('dayOfWeekLabels has 7 entries (ISO weekday 1-7)', () {
      expect(AgendaFormatters.dayOfWeekLabels.length, 7);
    });

    test('dayOfWeekLabels maps 1=Lunes through 7=Domingo', () {
      expect(AgendaFormatters.dayOfWeekLabels[1], 'Lunes');
      expect(AgendaFormatters.dayOfWeekLabels[2], 'Martes');
      expect(AgendaFormatters.dayOfWeekLabels[3], 'Miércoles');
      expect(AgendaFormatters.dayOfWeekLabels[4], 'Jueves');
      expect(AgendaFormatters.dayOfWeekLabels[5], 'Viernes');
      expect(AgendaFormatters.dayOfWeekLabels[6], 'Sábado');
      expect(AgendaFormatters.dayOfWeekLabels[7], 'Domingo');
    });
  });
}
