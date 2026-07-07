import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/argentina_time.dart';

// Contract of the shared ART wall-clock helper. Both the payment period keys
// (W1) and the dashboard "today" buckets (W2) depend on this being a fixed -3h
// shift, so pin it directly here — independently of any consumer.
void main() {
  group('argentina_time', () {
    test('argentinaUtcOffset is a fixed UTC-3 (no DST)', () {
      expect(argentinaUtcOffset, const Duration(hours: 3));
    });

    test('toArgentina shifts a UTC instant back 3 hours', () {
      expect(
        toArgentina(DateTime.utc(2026, 6, 17, 1, 0)),
        DateTime.utc(2026, 6, 16, 22, 0),
      );
    });

    test('a UTC instant past midnight is the previous ART calendar day', () {
      // 02:00 UTC == 23:00 ART of the previous day.
      final art = toArgentina(DateTime.utc(2026, 6, 16, 2, 0));
      expect(art.day, 15);
      expect(art.hour, 23);
    });

    test('the -3h shift rolls back across a year boundary', () {
      // 2026-01-01 00:00 UTC == 2025-12-31 21:00 ART.
      final art = toArgentina(DateTime.utc(2026, 1, 1, 0, 0));
      expect(art, DateTime.utc(2025, 12, 31, 21, 0));
    });
  });
}
