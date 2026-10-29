import '../../../../l10n/app_l10n.dart';
import '../../application/pdf_import_quota_provider.dart';

/// La línea del cupo de las dos pantallas de subida del PDF (la de la ficha
/// del alumno en mobile y «Importar plan» del Coach Hub).
///
/// Dice cuántas importaciones se pueden hacer AHORA: el menor de los dos
/// topes. Mostrar los dos por separado («te quedan 0 esta semana y 2 hoy»)
/// se contradecía: sin cupo semanal, hoy tampoco se puede. El diario se nombra
/// sólo cuando es el que frena (planes 2 y 3: 10 por día con más por semana);
/// en Free y Plan 1 el diario es igual al semanal y nunca frena antes.
///
/// `null` sin cupo: ahí habla el cartel rojo, que dice cuándo se renueva.
String? pdfImportQuotaText(AppL10n l10n, PdfImportRemaining remaining) {
  final week = remaining.week;
  final day = remaining.day;
  if (week <= 0 || day <= 0) return null;
  if (day < week) return l10n.pdfImportQuotaDayLimited(day, week);
  return l10n.pdfImportQuotaWeek(week);
}
