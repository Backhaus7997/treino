// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6) — mismo contrato que
// agenda_web_day_list.dart / appointment_detail_dialog.dart.
//
// Slice 2b — cobro por LOTE desde la agenda: un único Payment cubre N turnos
// `confirmed` + no cobrados del MISMO alumno (ver
// AppointmentRepository.billAppointments, transacción atómica: todo o nada).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/utils/argentina_time.dart'
    show argentinaNow, argentinaUtcOffset;
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/agenda_exceptions.dart';
import '../../../../coach/domain/appointment.dart';
import '../../../../coach/presentation/agenda_formatters.dart';
import '../../../../payments/application/billing_providers.dart'
    show athleteBillingProvider;
import '../../../../payments/domain/payment.dart';
import '../pagos/widgets/payment_format.dart' show fmtArs, groupThousands;
import '../pagos/widgets/thousands_input_formatter.dart';

/// Dialog de cobro por LOTE (Slice 2b).
///
/// Reusa el estilo visual del form "Cobrar" de [AppointmentDetailDialog]
/// (Slice 2a, per-turno) — mismos inputs/labels/botones — adaptado a N
/// turnos: monto default = N × tarifa de referencia del alumno (editable),
/// concepto default "N sesiones", "Vence el" opcional con la misma
/// normalización ART→UTC 23:59:59.
///
/// [appointments] ya viene validado por el caller ([AgendaWebDayList] en
/// modo selección): todos `confirmed`, sin `paymentId`, del mismo
/// `athleteId`+`trainerId`. `billAppointments` vuelve a validar todo esto
/// contra Firestore, dentro de la misma transacción, antes de escribir nada
/// — el guard real es ese, no la UI (money-critical).
///
/// Devuelve `true` por `Navigator.pop` si el cobro se confirmó con éxito
/// (para que el caller limpie la selección); `false`/`null` si se
/// canceló/cerró sin cobrar (la selección del caller queda intacta).
class BatchCobrarDialog extends ConsumerStatefulWidget {
  const BatchCobrarDialog({
    super.key,
    required this.appointments,
    required this.trainerId,
    required this.athleteName,
  });

  final List<Appointment> appointments;
  final String trainerId;

  /// Nombre a mostrar, ya resuelto por el caller (mismo fallback que las
  /// tarjetas: perfil público → athleteDisplayName → "Alumno").
  final String athleteName;

  @override
  ConsumerState<BatchCobrarDialog> createState() => _BatchCobrarDialogState();
}

class _BatchCobrarDialogState extends ConsumerState<BatchCobrarDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _conceptController;
  bool _billing = false;
  String? _billingError;

  /// ART calendar day the charge is due (optional) — mismo idiom que
  /// _AddSueltoSheet (Slice 1) / AppointmentDetailDialog (Slice 2a).
  DateTime? _dueDate;

  String get _athleteId => widget.appointments.first.athleteId;
  int get _count => widget.appointments.length;
  String get _sesionesLabel => _count == 1 ? 'sesión' : 'sesiones'; // i18n

  @override
  void initState() {
    super.initState();
    // Prefill AT THIS MOMENT vía ref.read síncrono — mismo idiom que
    // _openCobrarForm en el Slice 2a: nunca se re-prefillea reactivamente
    // después, así que jamás pisa un valor que el trainer esté tipeando.
    // AgendaWebDayList pre-calienta este StreamProvider apenas hay selección
    // activa (ver su build()), así que para cuando el trainer llega a este
    // dialog ya está resuelto — mismo gotcha que documentó el Slice 2a
    // (un StreamProvider recién suscripto sigue en AsyncLoading el primer
    // microtask).
    final billing = ref.read(athleteBillingProvider(_athleteId)).valueOrNull;
    _amountController = TextEditingController(
      text: billing != null
          ? groupThousands((billing.amountArs * _count).toString())
          : '',
    );
    _conceptController =
        TextEditingController(text: '$_count $_sesionesLabel'); // i18n
  }

  @override
  void dispose() {
    _amountController.dispose();
    _conceptController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    // "Hoy" como día calendario ART — misma razón que _AddSueltoSheet: entre
    // 21:00–23:59 ART el día UTC ya es mañana, un floor derivado de UTC
    // bloquearía elegir hoy.
    final todayArt = argentinaNow();
    final floor = DateTime(todayArt.year, todayArt.month, todayArt.day);
    final initial = _dueDate ?? floor;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(floor) ? floor : initial,
      firstDate: floor,
      lastDate: floor.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _confirm() async {
    if (_billing) return; // guard de doble-tap (mismo idiom que Slice 2a).
    final amount = parseGroupedInt(_amountController.text);
    final concept = _conceptController.text.trim();

    if (amount == null || amount <= 0) {
      setState(() => _billingError = 'Ingresá un monto válido.'); // i18n
      return;
    }
    if (concept.isEmpty) {
      setState(() => _billingError = 'Completá todos los campos.'); // i18n
      return;
    }

    setState(() {
      _billing = true;
      _billingError = null;
    });

    // dueAt = fin del día calendario ART elegido, como instante UTC — misma
    // normalización que _AddSueltoSheet (Slice 1) / Slice 2a.
    final dueDate = _dueDate;
    final dueAt = dueDate == null
        ? null
        : DateTime.utc(dueDate.year, dueDate.month, dueDate.day, 23, 59, 59)
            .add(argentinaUtcOffset);

    final payment = Payment(
      id: '',
      trainerId: widget.trainerId,
      athleteId: _athleteId,
      amountArs: amount,
      concept: concept,
      status: PaymentStatus.pending,
      createdAt: DateTime.now().toUtc(),
      dueAt: dueAt,
    );

    try {
      await ref.read(appointmentRepositoryProvider).billAppointments(
            appointments: widget.appointments,
            payment: payment,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppointmentAlreadyBilledException {
      if (!mounted) return;
      setState(() {
        _billing = false;
        _billingError =
            'Uno de los turnos seleccionados ya fue cobrado. Cerrá y volvé a seleccionar.'; // i18n
      });
    } on AppointmentNotConfirmedException {
      if (!mounted) return;
      setState(() {
        _billing = false;
        _billingError =
            'Uno de los turnos seleccionados ya no está confirmado.'; // i18n
      });
    } on AppointmentAthleteMismatchException {
      if (!mounted) return;
      setState(() {
        _billing = false;
        _billingError =
            'Los turnos seleccionados no son todos del mismo alumno.'; // i18n
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _billing = false;
        _billingError =
            'No pudimos registrar el cobro. Probá de nuevo.'; // i18n
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Reactivo: si abrió antes de que resuelva, muestra la tarifa apenas
    // llega (sólo lectura/hint — el monto ya prellenado en initState NO se
    // re-escribe acá, evitando pisar lo que el trainer esté tipeando).
    final billing = ref.watch(athleteBillingProvider(_athleteId)).valueOrNull;

    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: palette.textMuted),
          filled: true,
          fillColor: palette.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.accent, width: 1.5),
          ),
        );

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
        );

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      title: Text(
        'Cobrar $_count $_sesionesLabel', // i18n
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: palette.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.athleteName,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: palette.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              label('MONTO (ARS)'), // i18n
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsSeparatorInputFormatter()],
                style: GoogleFonts.barlow(
                    fontSize: 14, color: palette.textPrimary),
                decoration: deco('Ej: 15000'), // i18n
              ),
              if (billing != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Tarifa de referencia: ${fmtArs(billing.amountArs)} x $_count = ${fmtArs(billing.amountArs * _count)}', // i18n
                  style: GoogleFonts.barlow(
                      fontSize: 12, color: palette.textMuted),
                ),
              ],
              const SizedBox(height: 14),
              label('CONCEPTO'), // i18n
              TextField(
                controller: _conceptController,
                style: GoogleFonts.barlow(
                    fontSize: 14, color: palette.textPrimary),
                decoration: deco('Ej: $_count sesiones'), // i18n
              ),
              const SizedBox(height: 14),
              label('VENCE EL (OPCIONAL)'), // i18n
              InkWell(
                onTap: _pickDueDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: palette.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    children: [
                      Icon(TreinoIcon.calendar,
                          size: 16, color: palette.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _dueDate == null
                              ? 'Sin fecha de vencimiento' // i18n
                              : AgendaFormatters.formatDate(_dueDate!),
                          style: GoogleFonts.barlow(
                            fontSize: 14,
                            color: _dueDate == null
                                ? palette.textMuted
                                : palette.textPrimary,
                          ),
                        ),
                      ),
                      if (_dueDate != null)
                        Semantics(
                          button: true,
                          label: 'Quitar fecha de vencimiento', // i18n
                          child: GestureDetector(
                            onTap: () => setState(() => _dueDate = null),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(TreinoIcon.close,
                                  size: 16, color: palette.textMuted),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_billingError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _billingError!,
                  style: TextStyle(color: palette.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _billing ? null : () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: palette.border),
            foregroundColor: palette.textPrimary,
            shape: const StadiumBorder(),
          ),
          child: Text(
            'Cancelar', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _billing ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.bg,
            shape: const StadiumBorder(),
            disabledBackgroundColor: palette.accent.withValues(alpha: 0.3),
          ),
          child: _billing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.bg,
                  ),
                )
              : Text(
                  'CONFIRMAR COBRO', // i18n
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
        ),
      ],
    );
  }
}
