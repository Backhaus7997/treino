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
class PagosTable extends StatelessWidget {
  const PagosTable({
    super.key,
    required this.payments,
    required this.palette,
  });

  final List<Payment> payments;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
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
                ],
              ),
            ),
        ],
      ),
    );
  }
}
