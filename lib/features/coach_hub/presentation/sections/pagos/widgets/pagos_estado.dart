/// Estado de pago derivado, puro y sin `BuildContext`, para la UI de Pagos
/// del Coach Hub web.
///
/// La función [pagoEstadoOf] no resuelve color: eso queda a cargo de la capa
/// de presentación (palette semántica de `AppPalette`), acá solo se decide
/// estado + etiqueta.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:treino/features/payments/domain/payment.dart';

// ── Estado ────────────────────────────────────────────────────────────────────

/// Estado visual de un pago, alineado con los buckets de
/// `pagosBucketsProvider` (ADR-PGW-002, REQ-VENC-11).
enum PagoEstado { vencido, porVencer, pagado }

// ── Derivación pura ───────────────────────────────────────────────────────────

/// Deriva el [PagoEstado] y una etiqueta legible es-AR para [p] al momento
/// [now].
///
/// Reglas (alineadas con `pagos_buckets_provider.dart`, REQ-VENC-11):
/// - `paid` → `(pagado, 'Pagado')`.
/// - `pending` con `dueAt` no nulo:
///   - si `dueAt` ya pasó → `vencido`, etiqueta `'Vencido Nd'` con N = días
///     de atraso en días de calendario, con mínimo 1 (si el vencimiento fue
///     el mismo día de calendario pero ya pasó la hora, redondea a 1).
///   - si no → `porVencer`, etiqueta relativa: 0 días → `'Hoy'`, 1 día →
///     `'Mañana'`, N días → `'En N días'`.
/// - `pending` con `dueAt` nulo (legado): compara `createdAt` contra el
///   inicio del mes actual, igual que el fallback de `pagosBucketsProvider`.
({PagoEstado estado, String label}) pagoEstadoOf(Payment p, DateTime now) {
  if (p.status == PaymentStatus.paid) {
    return (estado: PagoEstado.pagado, label: 'Pagado'); // i18n
  }

  final dueAt = p.dueAt;
  final nowUtc = now.toUtc();

  if (dueAt != null) {
    final dueUtc = dueAt.toUtc();
    if (dueUtc.isBefore(nowUtc)) {
      final n = _diasDeAtraso(dueUtc, nowUtc);
      return (estado: PagoEstado.vencido, label: 'Vencido ${n}d'); // i18n
    }

    final n = _diasHastaVencimiento(dueUtc, nowUtc);
    final label = switch (n) {
      0 => 'Hoy', // i18n
      1 => 'Mañana', // i18n
      _ => 'En $n días', // i18n
    };
    return (estado: PagoEstado.porVencer, label: label);
  }

  // Legacy fallback (dueAt == null): compara createdAt contra el inicio del
  // mes actual, igual que pagos_buckets_provider.dart.
  final periodStart = DateTime.utc(nowUtc.year, nowUtc.month, 1);
  if (p.createdAt.toUtc().isBefore(periodStart)) {
    return (estado: PagoEstado.vencido, label: 'Vencido'); // i18n
  }
  return (estado: PagoEstado.porVencer, label: 'Pendiente'); // i18n
}

// ── Helpers de días de calendario ─────────────────────────────────────────────

DateTime _fechaSinHora(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Días de atraso de [dueUtc] respecto de [nowUtc], en días de calendario,
/// con mínimo 1 (asume que ya se validó `dueUtc.isBefore(nowUtc)`).
int _diasDeAtraso(DateTime dueUtc, DateTime nowUtc) {
  final diff = _fechaSinHora(nowUtc).difference(_fechaSinHora(dueUtc)).inDays;
  return diff < 1 ? 1 : diff;
}

/// Días de calendario hasta [dueUtc] desde [nowUtc] (asume `dueUtc` no
/// anterior a `nowUtc`).
int _diasHastaVencimiento(DateTime dueUtc, DateTime nowUtc) {
  final diff = _fechaSinHora(dueUtc).difference(_fechaSinHora(nowUtc)).inDays;
  return diff < 0 ? 0 : diff;
}
