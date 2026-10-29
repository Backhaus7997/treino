// La línea del cupo del import de PDF dice lo que se puede hacer AHORA: el
// menor de los dos topes. Mostrar los dos por separado se contradecía («te
// quedan 0 esta semana y 2 hoy»).

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/application/pdf_import_quota_provider.dart';
import 'package:treino/features/coach_hub/presentation/widgets/pdf_import_quota_copy.dart';
import 'package:treino/l10n/app_l10n_es.dart';

PdfImportRemaining _r(int week, int day, {int limitW = 15, int limitD = 10}) =>
    (week: week, day: day, limitWeekly: limitW, limitDaily: limitD);

void main() {
  final l10n = AppL10nEs();

  test('frena el semanal (o son iguales): sólo la semana', () {
    expect(pdfImportQuotaText(l10n, _r(2, 2, limitW: 2, limitD: 2)),
        'Te quedan 2 importaciones esta semana.');
    expect(pdfImportQuotaText(l10n, _r(1, 2, limitW: 2, limitD: 2)),
        'Te queda 1 importación esta semana.');
    expect(pdfImportQuotaText(l10n, _r(3, 10)),
        'Te quedan 3 importaciones esta semana.');
  });

  test('frena el diario: lo de hoy, y la semana como dato', () {
    expect(pdfImportQuotaText(l10n, _r(12, 4)),
        'Te quedan 4 hoy · 12 esta semana.');
    expect(pdfImportQuotaText(l10n, _r(12, 1)),
        'Te queda 1 hoy · 12 esta semana.');
  });

  test('sin cupo lo dice ANTES de subir; el semanal manda sobre el diario', () {
    expect(pdfImportQuotaText(l10n, _r(0, 2, limitW: 2, limitD: 2)),
        'No te quedan importaciones esta semana: se renuevan el lunes.');
    expect(pdfImportQuotaText(l10n, _r(0, 0)),
        'No te quedan importaciones esta semana: se renuevan el lunes.');
    expect(pdfImportQuotaText(l10n, _r(5, 0)),
        'No te quedan importaciones hoy: se renuevan mañana.');
  });

  test('con el cartel rojo de cupo agotado a la vista, la línea calla', () {
    expect(
        pdfImportQuotaText(l10n, _r(0, 2), exhaustedBannerShown: true), isNull);
    // Con cupo, el cartel no apaga nada (no puede estar, pero por las dudas).
    expect(pdfImportQuotaText(l10n, _r(3, 10), exhaustedBannerShown: true),
        'Te quedan 3 importaciones esta semana.');
  });
}
