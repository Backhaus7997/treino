/// Tabla de historial de pagos de un alumno para la sección Pagos del Coach Hub.
///
/// Extraído de `alumno_detail_screen.dart` (PR1 — refactor puro, sin cambio de
/// comportamiento). Columnas: FECHA · CONCEPTO · MONTO · ESTADO.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/payments/domain/payment.dart';

import 'payment_format.dart';

/// Historial de pagos de un alumno en formato tabla compacta.
///
/// [onRecordar] — callback opcional por fila; cuando no es null aparece
/// el botón "Recordar" solo en filas con status `pending`.
class PagosTable extends StatelessWidget {
  const PagosTable({
    super.key,
    required this.payments,
    required this.palette,
    this.onRecordar,
  });

  final List<Payment> payments;
  final AppPalette palette;

  /// Callback al presionar "Recordar" (envía recordatorio por chat); null → sin botón. // i18n
  final void Function(Payment)? onRecordar;

  @override
  Widget build(BuildContext context) {
    final hasRecordar = onRecordar != null;
    final h = TextStyle(
        color: palette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5);
    final c = TextStyle(color: palette.textPrimary, fontSize: 13);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                // i18n (encabezados)
                Expanded(flex: 3, child: Text('FECHA', style: h)),
                Expanded(flex: 4, child: Text('CONCEPTO', style: h)),
                Expanded(
                  flex: 3,
                  child: Text('MONTO', style: h, textAlign: TextAlign.right),
                ),
                Expanded(
                  flex: 3,
                  child: Text('ESTADO', style: h, textAlign: TextAlign.right),
                ),
                if (hasRecordar) const Expanded(flex: 3, child: SizedBox()),
              ],
            ),
          ),
          for (final p in payments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(fmtDate(p.createdAt), style: c),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(p.concept,
                        overflow: TextOverflow.ellipsis, style: c),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(fmtArs(p.amountArs),
                        style: c, textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      p.status == PaymentStatus.paid
                          ? 'Pagado'
                          : 'Pendiente', // i18n
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: p.status == PaymentStatus.paid
                            ? palette.accent
                            : palette.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (hasRecordar)
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: p.status == PaymentStatus.pending
                            ? TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  minimumSize: Size.zero,
                                ),
                                onPressed: () => onRecordar!(p),
                                child: Text(
                                  'Recordar', // i18n
                                  style: TextStyle(
                                    color: palette.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
