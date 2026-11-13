/// Estado de pago derivado, puro y sin `BuildContext`, para la UI de Pagos
/// del Coach Hub web.
///
/// La función [pagoEstadoOf] no resuelve color: eso queda a cargo de la capa
/// de presentación (palette semántica de `AppPalette`), acá solo se decide
/// estado + etiqueta.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/payments/domain/payment.dart';

// ── Estado ────────────────────────────────────────────────────────────────────

/// Estado visual de un pago, alineado con los buckets de
/// `pagosBucketsProvider` (ADR-PGW-002, REQ-VENC-11).
enum PagoEstado { vencido, porVencer, pagado }

// ── Derivación pura ───────────────────────────────────────────────────────────

/// Deriva el [PagoEstado] y una etiqueta legible es-AR para [p] al momento
/// [now].
///
/// **[now] es wall-clock ART** (`argentinaNow()`), no un instante real: lo
/// pasan así todos los callers y es la convención de `argentina_time.dart`
/// (`mondayOfWeekArt`). `dueAt` es un instante real —los diálogos de cobro lo
/// guardan como el fin del día ART elegido, `4 nov 23:59:59 ART` =
/// `5 nov 02:59:59 UTC`—, así que se lleva al MISMO marco con [toArgentina]
/// antes de compararlo y de contar días. Compararlo en UTC contra un `now` ya
/// corrido a ART dejaba un lado un día adelante del otro: el 4 de noviembre a
/// las 10:00 ART ese pago decía «Mañana», y pasada la medianoche ART seguía
/// «por vencer» hasta las 03:00 (#1824).
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
  final nowArt = now.toUtc();

  if (dueAt != null) {
    // Mismo marco que [now]: ART.
    final dueArt = toArgentina(dueAt.toUtc());
    if (dueArt.isBefore(nowArt)) {
      final n = _diasDeAtraso(dueArt, nowArt);
      return (estado: PagoEstado.vencido, label: 'Vencido ${n}d'); // i18n
    }

    final n = _diasHastaVencimiento(dueArt, nowArt);
    final label = switch (n) {
      0 => 'Hoy', // i18n
      1 => 'Mañana', // i18n
      _ => 'En $n días', // i18n
    };
    return (estado: PagoEstado.porVencer, label: label);
  }

  // Legacy fallback (dueAt == null): compara createdAt contra el inicio del
  // mes actual, igual que pagos_buckets_provider.dart. Sólo alcanza a los pagos
  // sin `dueAt`; es la MISMA regla en los dos lados y no se tocó en #1824.
  final periodStart = DateTime.utc(nowArt.year, nowArt.month, 1);
  if (p.createdAt.toUtc().isBefore(periodStart)) {
    return (estado: PagoEstado.vencido, label: 'Vencido'); // i18n
  }
  return (estado: PagoEstado.porVencer, label: 'Pendiente'); // i18n
}

// ── Helpers de días de calendario ─────────────────────────────────────────────

DateTime _fechaSinHora(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Días de atraso de [dueArt] respecto de [nowArt], en días de calendario,
/// con mínimo 1 (asume que ya se validó `dueArt.isBefore(nowArt)`).
int _diasDeAtraso(DateTime dueArt, DateTime nowArt) {
  final diff = _fechaSinHora(nowArt).difference(_fechaSinHora(dueArt)).inDays;
  return diff < 1 ? 1 : diff;
}

/// Días de calendario hasta [dueArt] desde [nowArt] (asume `dueArt` no
/// anterior a `nowArt`).
int _diasHastaVencimiento(DateTime dueArt, DateTime nowArt) {
  final diff = _fechaSinHora(dueArt).difference(_fechaSinHora(nowArt)).inDays;
  return diff < 0 ? 0 : diff;
}
