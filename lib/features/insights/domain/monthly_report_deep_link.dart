/// Contrato del deep link del reporte mensual.
///
/// El push "tu reporte de <mes> está listo" lo arma la Cloud Function
/// `notifyMonthlyReport` (`functions/src/notifications/notify-monthly-report.ts`)
/// como `/home/insights/monthly?month=YYYY-MM`, con el mes REPORTADO — el que
/// cerró, no el que recién arranca. Las dos mitades tienen un test cada una
/// clavado sobre ese literal: si alguien cambia el formato de un lado, el otro
/// se pone rojo en vez de abrir la pantalla equivocada en silencio.
library;

/// `YYYY-MM` con mes de dos dígitos. Anclado en los dos extremos: sin `^…$`,
/// `2026-08-cualquier-cosa` matchearía.
final _monthParam = RegExp(r'^(\d{4})-(\d{2})$');

/// Parsea el `?month=` del deep link del reporte mensual.
///
/// Devuelve `null` ante cualquier cosa que no sea exactamente `YYYY-MM` con un
/// mes entre 1 y 12: ausente, vacío, con basura, con `2026-13`. Un deep link es
/// entrada NO confiable —llega de un push, de un bookmark viejo, de alguien
/// pegando una URL a mano— y la pantalla ya sabe caer al mes más reciente
/// cuando no le pasan nada. Tirar acá sería romper la navegación por un
/// parámetro decorativo.
///
/// El día se fija en 1 porque la pantalla sólo lee año y mes, y así el valor
/// queda idéntico al ancla que usa `MonthlyReportPoint.month`.
DateTime? parseMonthlyReportMonthParam(String? raw) {
  if (raw == null) return null;

  final match = _monthParam.firstMatch(raw);
  if (match == null) return null;

  final month = int.parse(match.group(2)!);
  if (month < 1 || month > 12) return null;

  return DateTime(int.parse(match.group(1)!), month);
}
