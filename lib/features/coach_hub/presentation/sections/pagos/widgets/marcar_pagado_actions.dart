/// Acciones de pago (marcar pagado / registrar pago) para la sección Pagos del
/// Coach Hub.
///
/// Extraído de `alumno_detail_screen.dart` (PR1 — refactor puro, sin cambio de
/// comportamiento). `isoWeekPeriodKey` se re-importa desde
/// `pagos_por_cobrar_provider.dart` — NO duplicado.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/chat/application/chat_providers.dart'
    show chatForOtherUidProvider, chatRepositoryProvider;
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show CobroPendiente, isoWeekPeriodKey;
import 'package:treino/features/payments/application/payment_providers.dart'
    show paymentRepositoryProvider;
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

import 'payment_format.dart';
import 'registrar_pago_dialog.dart';

// ── Helpers internos ──────────────────────────────────────────────────────────

/// Muestra un SnackBar con [msg].
void pagoSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Construye un Payment pagado para settlear un cobro recurrente. El [periodKey]
/// debe matchear el que computa `pagosPorCobrarProvider` (month/ISO-week) para
/// que el cobro desaparezca tras marcarlo; `null` para porSesión (sin período).
Payment paidPaymentFor(
  String trainerId,
  CobroPendiente cobro,
  DateTime now,
  String? periodKey,
) =>
    Payment(
      id: '',
      trainerId: trainerId,
      athleteId: cobro.athleteId,
      amountArs: cobro.amountArs,
      concept: cobro.concept,
      status: PaymentStatus.paid,
      periodKey: periodKey,
      createdAt: now,
      paidAt: now,
    );

// ── Acciones públicas ─────────────────────────────────────────────────────────

/// Muestra confirmación y, si el trainer acepta, marca el cobro como pagado
/// en Firestore según la cadencia (suelto → markManyPaid; recurrente → add con
/// periodKey correspondiente).
Future<void> marcarPagado(
    BuildContext context, WidgetRef ref, CobroPendiente cobro) async {
  final palette = AppPalette.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.bgCard,
      title: Text('¿Marcar como cobrado?', // i18n
          style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18)),
      content: Text('${cobro.concept} — ${fmtArs(cobro.amountArs)}',
          style: TextStyle(color: palette.textMuted, fontSize: 14)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', // i18n
                style: TextStyle(color: palette.textMuted))),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Cobrado', // i18n
                style: TextStyle(
                    color: palette.accent, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final trainerId = ref.read(currentUidProvider);
  if (trainerId == null) return;
  final repo = ref.read(paymentRepositoryProvider);
  final now = DateTime.now().toUtc();
  try {
    switch (cobro.cadence) {
      case BillingCadence.suelto:
        await repo.markManyPaid(cobro.pendingPaymentIds, now);
      case BillingCadence.mensual:
        await repo.add(paidPaymentFor(trainerId, cobro, now,
            '${now.year}-${now.month.toString().padLeft(2, '0')}'));
      case BillingCadence.semanal:
        await repo
            .add(paidPaymentFor(trainerId, cobro, now, isoWeekPeriodKey(now)));
      case BillingCadence.porSesion:
        await repo.add(paidPaymentFor(trainerId, cobro, now, null));
    }
    if (context.mounted) {
      pagoSnack(context, 'Cobro registrado.'); // i18n
    }
  } catch (_) {
    if (context.mounted) {
      pagoSnack(context, 'No pudimos guardar. Intentá de nuevo.'); // i18n
    }
  }
}

// ── Acciones PR2b ─────────────────────────────────────────────────────────────

/// Muestra confirmación y, si el trainer acepta, marca un [Payment] ad-hoc
/// como pagado via `markManyPaid([p.id], now)`.
///
/// Distinto de [marcarPagado] (cadencia-aware para CobroPendiente). Esta acción
/// es para pagos directos del tab Vencidos/Por vencer de la tabla web.
///
/// REQ-PAGW-ACTION-001.
Future<void> marcarPagadoDoc(
    BuildContext context, WidgetRef ref, Payment payment) async {
  final palette = AppPalette.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.bgCard,
      title: Text('¿Marcar como cobrado?', // i18n
          style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18)),
      content: Text('${payment.concept} — ${fmtArs(payment.amountArs)}',
          style: TextStyle(color: palette.textMuted, fontSize: 14)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', // i18n
                style: TextStyle(color: palette.textMuted))),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Cobrado', // i18n
                style: TextStyle(
                    color: palette.accent, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final repo = ref.read(paymentRepositoryProvider);
  final now = DateTime.now().toUtc();
  try {
    await repo.markManyPaid([payment.id], now);
    if (context.mounted) {
      pagoSnack(context, 'Cobro registrado.'); // i18n
    }
  } catch (_) {
    if (context.mounted) {
      pagoSnack(context, 'No pudimos guardar. Intentá de nuevo.'); // i18n
    }
  }
}

/// Construye el mensaje de recordatorio de pago.
///
/// Incluye monto en es-AR, concepto, y alias de pago del trainer si no es
/// null/vacío. Puro (sin side-effects) — testeable unitariamente.
///
/// REQ-PAGW-ACTION-002.
String reminderText({
  required int amount,
  required String concept,
  required String? paymentAlias,
}) {
  final monto = fmtArs(amount);
  final buf =
      StringBuffer('Hola! Te recuerdo el pago de $concept por $monto.'); // i18n
  if (paymentAlias != null && paymentAlias.isNotEmpty) {
    buf.write(' Podés transferir a: $paymentAlias'); // i18n
  }
  return buf.toString();
}

/// Envía un recordatorio de pago al alumno por el **chat in-app**.
///
/// Muestra un diálogo con el mensaje pre-cargado y editable; al confirmar,
/// resuelve (creando si hace falta) el chat PF↔alumno vía [chatForOtherUidProvider]
/// y lo envía con [ChatRepository.sendMessage]. El CF `notifyOnChatMessage` le
/// manda el push al alumno. Reusa el chat existente — sin backend nuevo, y sin
/// depender del teléfono del alumno.
///
/// REQ-PAGW-ACTION-002.
Future<void> recordar(
  BuildContext context,
  WidgetRef ref,
  Payment payment,
  String? paymentAlias,
) async {
  final initial = reminderText(
    amount: payment.amountArs,
    concept: payment.concept,
    paymentAlias: paymentAlias,
  );
  final text = await showDialog<String>(
    context: context,
    builder: (_) => _RecordarDialog(initialText: initial),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;

  final trainerId = ref.read(currentUidProvider);
  if (trainerId == null) return;
  try {
    final chat =
        await ref.read(chatForOtherUidProvider(payment.athleteId).future);
    await ref.read(chatRepositoryProvider).sendMessage(
          chatId: chat.chatId,
          senderId: trainerId,
          text: text.trim(),
        );
    if (context.mounted) {
      pagoSnack(context, 'Recordatorio enviado por chat.'); // i18n
    }
  } catch (_) {
    if (context.mounted) {
      pagoSnack(context, 'No pudimos enviar el recordatorio.'); // i18n
    }
  }
}

/// Diálogo que muestra el recordatorio pre-cargado y editable antes de enviarlo
/// por el chat. Devuelve el texto final (al presionar Enviar) o `null` (Cancelar).
class _RecordarDialog extends StatefulWidget {
  const _RecordarDialog({required this.initialText});

  final String initialText;

  @override
  State<_RecordarDialog> createState() => _RecordarDialogState();
}

class _RecordarDialogState extends State<_RecordarDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AlertDialog(
      backgroundColor: palette.bgCard,
      title: Text(
        'Enviar recordatorio por chat', // i18n
        style: TextStyle(
          color: palette.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      content: TextField(
        controller: _controller,
        minLines: 2,
        maxLines: 5,
        autofocus: true,
        style: TextStyle(color: palette.textPrimary),
        decoration: InputDecoration(
          hintText: 'Mensaje para el alumno', // i18n
          hintStyle: TextStyle(color: palette.textMuted),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancelar', // i18n
              style: TextStyle(color: palette.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text('Enviar', // i18n
              style: TextStyle(
                  color: palette.accent, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Abre `RegistrarPagoDialog` y, si el trainer confirma, crea un Payment pagado
/// ad-hoc para el alumno [athleteId].
Future<void> registrarPago(
    BuildContext context, WidgetRef ref, String athleteId) async {
  final result = await showDialog<({int amount, String concept})>(
    context: context,
    builder: (_) => const RegistrarPagoDialog(),
  );
  if (result == null) return;

  final trainerId = ref.read(currentUidProvider);
  if (trainerId == null) return;
  final now = DateTime.now().toUtc();
  try {
    await ref.read(paymentRepositoryProvider).add(Payment(
          id: '',
          trainerId: trainerId,
          athleteId: athleteId,
          amountArs: result.amount,
          concept: result.concept,
          status: PaymentStatus.paid,
          createdAt: now,
          paidAt: now,
        ));
    if (context.mounted) {
      pagoSnack(context, 'Pago registrado.'); // i18n
    }
  } catch (_) {
    if (context.mounted) {
      pagoSnack(context, 'No pudimos guardar. Intentá de nuevo.'); // i18n
    }
  }
}
