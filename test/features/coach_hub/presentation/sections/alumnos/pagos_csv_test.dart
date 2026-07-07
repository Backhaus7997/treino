import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart'
    show buildPagosCsv;
import 'package:treino/features/payments/domain/payment.dart';

// Guards the pagos-history CSV export against formula injection (CSV injection).
// `concept` is free text; a cell starting with = + - @ (or tab/CR) is run as a
// FORMULA by Excel/Sheets. buildPagosCsv must prefix such cells with a single
// quote so they are treated as literal text — while keeping RFC-4180 quoting.

Payment _payment({required String concept, int amountArs = 28000}) => Payment(
      id: 'p1',
      trainerId: 't1',
      athleteId: 'a1',
      amountArs: amountArs,
      concept: concept,
      status: PaymentStatus.paid,
      createdAt: DateTime.utc(2026, 6, 1),
    );

void main() {
  group('buildPagosCsv — CSV formula-injection guard', () {
    test('a concept starting with = is prefixed with a quote', () {
      final csv = buildPagosCsv([_payment(concept: '=1+2')]);
      expect(csv, contains('"\'=1+2"'));
    });

    test('the +, -, @ formula leads are all neutralized', () {
      expect(buildPagosCsv([_payment(concept: '+1')]), contains('"\'+1"'));
      expect(buildPagosCsv([_payment(concept: '-cmd')]), contains('"\'-cmd"'));
      expect(buildPagosCsv([_payment(concept: '@SUM')]), contains('"\'@SUM"'));
    });

    test('a classic HYPERLINK exfil payload is neutralized', () {
      final csv =
          buildPagosCsv([_payment(concept: '=HYPERLINK("http://x","c")')]);
      // Leading quote makes the whole thing literal; internal quotes doubled.
      expect(csv, contains('"\'=HYPERLINK(""http://x"",""c"")"'));
    });

    test('a benign concept is left untouched', () {
      final csv = buildPagosCsv([_payment(concept: 'Mensual Junio 2026')]);
      expect(csv, contains('"Mensual Junio 2026"'));
      expect(csv, isNot(contains("'Mensual")));
    });

    test('RFC-4180 quote-escaping still applies to embedded quotes/commas', () {
      final csv = buildPagosCsv([_payment(concept: 'Plan "Premium", anual')]);
      expect(csv, contains('"Plan ""Premium"", anual"'));
    });

    test('a numeric amount is not falsely prefixed', () {
      final csv = buildPagosCsv([_payment(concept: 'x', amountArs: 28000)]);
      expect(csv, contains('"28000"'));
      expect(csv, isNot(contains("'28000")));
    });

    test('header row is present', () {
      expect(buildPagosCsv(const []),
          startsWith('FECHA,CONCEPTO,MONTO,ESTADO,PERÍODO'));
    });
  });
}
