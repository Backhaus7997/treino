/// Tabela de pagos para a vista web del Coach Hub (trainer-wide).
///
/// Nueva en PR2b. Muestra 6 columnas: ALUMNO · CONCEPTO · MONTO · VENCIMIENTO ·
/// ESTADO · ACCIONES. Acepta callbacks opcionales por fila.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

import 'payment_format.dart';

// ── PagosWebTable ─────────────────────────────────────────────────────────────

/// Tabla de pagos del Coach Hub web. Muestra una fila por [Payment].
///
/// [profiles] mapea `athleteId → UserPublicProfile`; si falta el perfil se
/// muestra el fallback `'Alumno'`. [showActions] controla si se renderizan los
/// botones de acción (Recordar / Marcar pagado) — se ocultan en el tab Pagados.
///
/// REQ-PAGW-TABLE-001, REQ-PAGW-EMPTY-001.
class PagosWebTable extends StatelessWidget {
  const PagosWebTable({
    super.key,
    required this.payments,
    required this.profiles,
    required this.emptyLabel,
    required this.onMarcarPagado,
    required this.onRecordar,
    required this.showActions,
  });

  final List<Payment> payments;

  /// athleteId → UserPublicProfile (o ausente si no se resolvió aún).
  final Map<String, UserPublicProfile> profiles;

  /// Texto descriptivo cuando el bucket está vacío (por-tab, es-AR). // i18n
  final String emptyLabel;

  /// Callback al confirmar "Marcar pagado" para un pago; null → sin acción.
  final void Function(Payment)? onMarcarPagado;

  /// Callback al presionar "Recordar" (envía recordatorio por chat); null → sin acción.
  final void Function(Payment)? onRecordar;

  /// Si `false`, la columna ACCIONES no muestra botones (usado en tab Pagados).
  final bool showActions;

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _displayName(String athleteId) {
    final profile = profiles[athleteId];
    return profile?.displayName?.isNotEmpty == true
        ? profile!.displayName!
        : 'Alumno'; // i18n fallback
  }

  String _estadoLabel(Payment p) {
    if (p.status == PaymentStatus.paid) return 'Pagado'; // i18n
    final now = DateTime.now().toUtc();
    final periodStart = DateTime.utc(now.year, now.month, 1);
    return p.createdAt.toUtc().isBefore(periodStart)
        ? 'Vencido' // i18n
        : 'Pendiente'; // i18n
  }

  Color _estadoColor(Payment p, AppPalette palette) {
    if (p.status == PaymentStatus.paid) return palette.accent;
    final now = DateTime.now().toUtc();
    final periodStart = DateTime.utc(now.year, now.month, 1);
    return p.createdAt.toUtc().isBefore(periodStart)
        ? palette.danger
        : palette.warning;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Empty state
    if (payments.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
      );
    }

    // Header style
    final hStyle = TextStyle(
      color: palette.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );
    // Cell style
    final cStyle = TextStyle(color: palette.textPrimary, fontSize: 13);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('ALUMNO', style: hStyle)), // i18n
                Expanded(
                    flex: 4, child: Text('CONCEPTO', style: hStyle)), // i18n
                Expanded(
                  flex: 2,
                  child: Text('MONTO', // i18n
                      style: hStyle,
                      textAlign: TextAlign.right),
                ),
                Expanded(
                  flex: 2,
                  child: Text('FECHA', // i18n
                      style: hStyle,
                      textAlign: TextAlign.right),
                ),
                Expanded(
                  flex: 2,
                  child: Text('ESTADO', // i18n
                      style: hStyle,
                      textAlign: TextAlign.right),
                ),
                if (showActions) const Expanded(flex: 3, child: SizedBox()),
              ],
            ),
          ),

          // ── Divider ───────────────────────────────────────────────────────
          Divider(height: 1, color: palette.border),

          // ── Data rows ─────────────────────────────────────────────────────
          ...payments.map(
            (p) => _PaymentRow(
              payment: p,
              displayName: _displayName(p.athleteId),
              estadoLabel: _estadoLabel(p),
              estadoColor: _estadoColor(p, palette),
              palette: palette,
              cStyle: cStyle,
              showActions: showActions,
              onMarcarPagado: onMarcarPagado,
              onRecordar: onRecordar,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _PaymentRow ───────────────────────────────────────────────────────────────

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.payment,
    required this.displayName,
    required this.estadoLabel,
    required this.estadoColor,
    required this.palette,
    required this.cStyle,
    required this.showActions,
    required this.onMarcarPagado,
    required this.onRecordar,
  });

  final Payment payment;
  final String displayName;
  final String estadoLabel;
  final Color estadoColor;
  final AppPalette palette;
  final TextStyle cStyle;
  final bool showActions;
  final void Function(Payment)? onMarcarPagado;
  final void Function(Payment)? onRecordar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Alumno
          Expanded(
            flex: 3,
            child: Text(
              displayName,
              overflow: TextOverflow.ellipsis,
              style: cStyle,
            ),
          ),
          // Concepto
          Expanded(
            flex: 4,
            child: Text(
              payment.concept,
              overflow: TextOverflow.ellipsis,
              style: cStyle,
            ),
          ),
          // Monto
          Expanded(
            flex: 2,
            child: Text(
              fmtArs(payment.amountArs),
              style: cStyle,
              textAlign: TextAlign.right,
            ),
          ),
          // Vencimiento
          Expanded(
            flex: 2,
            child: Text(
              fmtDayMonth(payment.createdAt),
              style: cStyle.copyWith(color: palette.textMuted),
              textAlign: TextAlign.right,
            ),
          ),
          // Estado chip
          Expanded(
            flex: 2,
            child: Text(
              estadoLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: estadoColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Acciones
          if (showActions)
            Expanded(
              flex: 3,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (onRecordar != null)
                    _ActionBtn(
                      label: 'Recordar', // i18n
                      color: palette.accent,
                      onPressed: () => onRecordar!(payment),
                    ),
                  if (payment.status == PaymentStatus.pending &&
                      onMarcarPagado != null)
                    _ActionBtn(
                      label: 'Marcar pagado', // i18n
                      color: palette.textMuted,
                      onPressed: () => onMarcarPagado!(payment),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── _ActionBtn ────────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: color,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
