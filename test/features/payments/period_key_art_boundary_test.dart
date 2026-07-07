import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';

// Regression for the monthly/weekly DOUBLE-BILLING bug at UTC/ART boundaries.
//
// Period keys (`YYYY-MM` and `YYYY-Www`) are the identity a payment is
// deduplicated by. They are CALENDAR concepts and must be derived in Argentina
// wall-clock (UTC-3, no DST), NOT raw UTC. Between 21:00–23:59 ART the UTC day
// is already tomorrow, so a UTC-derived key buckets a payment into the wrong
// month/week. The Cloud Function (generateDuePayments) and the client
// (trainer_dashboard_tab "marcar pagado") would then pick different keys for
// the same physical period and bill twice.
//
// These assertions pin the fix deterministically at the shared-helper level,
// which every writer/reader now routes through via [toArgentina]. The CF mirror
// (functions/src/payments/generate-due-payments.ts) is proven in its own jest.
String _monthKey(DateTime utcInstant) {
  final art = toArgentina(utcInstant);
  return '${art.year}-${art.month.toString().padLeft(2, '0')}';
}

String _weekKey(DateTime utcInstant) =>
    isoWeekPeriodKey(toArgentina(utcInstant));

void main() {
  group('period keys — UTC/ART month boundary', () {
    test('22:00 ART on Jan 31 buckets into January, not UTC-next February', () {
      // Jan 31 22:00 ART == Feb 1 01:00 UTC. The old UTC math gave "2026-02".
      expect(_monthKey(DateTime.utc(2026, 2, 1, 1, 0)), '2026-01');
    });

    test('23:59 ART on Jan 31 is still January', () {
      // Jan 31 23:59 ART == Feb 1 02:59 UTC.
      expect(_monthKey(DateTime.utc(2026, 2, 1, 2, 59)), '2026-01');
    });

    test('00:00 ART on Feb 1 rolls over to February', () {
      // Feb 1 00:00 ART == Feb 1 03:00 UTC.
      expect(_monthKey(DateTime.utc(2026, 2, 1, 3, 0)), '2026-02');
    });

    test('mid-month is unaffected by the shift', () {
      expect(_monthKey(DateTime.utc(2026, 1, 15, 12, 0)), '2026-01');
    });
  });

  group('period keys — UTC/ART ISO-week boundary', () {
    test('Sun 22:00 ART stays in the current ISO week, not UTC-next Monday',
        () {
      // Sun 2026-01-04 22:00 ART == Mon 2026-01-05 01:00 UTC.
      // ART keeps it in ISO week 2026-W01; raw UTC would jump to W02.
      expect(_weekKey(DateTime.utc(2026, 1, 5, 1, 0)), '2026-W01');
    });

    test('Mon 00:00 ART begins the next ISO week', () {
      // Mon 2026-01-05 00:00 ART == Mon 2026-01-05 03:00 UTC.
      expect(_weekKey(DateTime.utc(2026, 1, 5, 3, 0)), '2026-W02');
    });
  });
}
