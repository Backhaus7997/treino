/// Helpers de formato de fechas y montos para la sección Pagos del Coach Hub.
///
/// Extraídos de `alumno_detail_screen.dart` (PR1 — refactor puro, sin cambio
/// de comportamiento). Importados también por `pagos_table.dart` y
/// `alumno_detail_screen.dart`.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:treino/features/payments/domain/athlete_billing.dart';

// ── Meses en español (es-AR) ──────────────────────────────────────────────────

const kMesesLargos = [
  '', // i18n
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

// ── Formatters ────────────────────────────────────────────────────────────────

/// Agrupa una cadena de dígitos de a 3 con "." es-AR (28000 → "28.000").
/// Sin signo ni "$" — usado tanto por [fmtArs] como por el
/// `ThousandsSeparatorInputFormatter` de los TextField de monto.
String groupThousands(String digits) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Monto en pesos con separador de miles es-AR (28000 → "\$28.000").
String fmtArs(int amount) =>
    '${amount < 0 ? '-' : ''}\$${groupThousands(amount.abs().toString())}';

/// "22 mayo" — día + mes en es-AR. // i18n
String fmtDayMonth(DateTime d) => '${d.day} ${kMesesLargos[d.month]}';

/// dd/MM/yyyy — usado en historial de pagos y en otros tabs.
String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ── Lógica de vencimiento ─────────────────────────────────────────────────────

/// Fecha del próximo cobro recurrente según cadencia: 1º del mes que viene
/// (mensual) o lunes de la semana que viene (semanal). `null` para porSesión y
/// suelto (event-driven / ad-hoc, sin fecha fija). // i18n
DateTime? nextDueDate(AthleteBilling b, DateTime now) {
  switch (b.cadence) {
    case BillingCadence.mensual:
      return DateTime(now.year, now.month + 1, 1);
    case BillingCadence.semanal:
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: now.weekday - 1));
      return monday.add(const Duration(days: 7));
    case BillingCadence.porSesion:
    case BillingCadence.suelto:
      return null;
  }
}
