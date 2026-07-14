import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/argentina_time.dart'
    show argentinaNow, argentinaUtcOffset;
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtArs;
import '../../../payments/application/billing_providers.dart'
    show athleteBillingProvider;
import '../../../payments/domain/payment.dart';
import '../../../profile/application/user_providers.dart'
    show firestoreProvider;
import '../../application/agenda_providers.dart';
import '../../domain/agenda_exceptions.dart';
import '../../domain/appointment.dart';
import '../agenda_formatters.dart';

/// Bottom-sheet content showing the full detail of a single [Appointment].
///
/// Displays athlete info (resolved via live Firestore stream), date, time
/// range, duration, and status. Provides "Ver perfil del alumno" and
/// "Cancelar turno" actions (with the 24h gate).
class AppointmentDetailSheet extends ConsumerStatefulWidget {
  const AppointmentDetailSheet({
    super.key,
    required this.appointment,
    required this.trainerId,
  });

  final Appointment appointment;
  final String trainerId;

  @override
  ConsumerState<AppointmentDetailSheet> createState() =>
      _AppointmentDetailSheetState();
}

class _AppointmentDetailSheetState
    extends ConsumerState<AppointmentDetailSheet> {
  /// Live Firestore stream for the athlete's public profile — same rationale
  /// as _BookedSlotChipState in trainer_day_detail_sheet.dart: survives
  /// stale-cache scenarios and keeps the name in sync if the athlete renames.
  late final Stream<DocumentSnapshot<Map<String, Object?>>> _profileStream;

  // ── Cobrar (Slice 2a — Agenda→cobro bridge) ───────────────────────────────
  final _amountController = TextEditingController();
  final _conceptController = TextEditingController();
  bool _showCobrarForm = false;
  bool _billing = false;
  String? _billingError;

  /// ART calendar day the charge is due (optional) — same idiom as
  /// _AddSueltoSheet (Slice 1): only y/m/d are meaningful, [_confirmCobrar]
  /// expands it to 23:59:59 ART.
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _profileStream = ref
        .read(firestoreProvider)
        .collection('userPublicProfiles')
        .doc(widget.appointment.athleteId)
        .snapshots();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _conceptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final appointment = widget.appointment;

    // Pre-warm the athlete's reference-rate stream from the moment the sheet
    // opens, so it's already resolved by the time the trainer taps COBRAR —
    // _openCobrarForm reads it via ref.read() (synchronous), and a
    // StreamProvider that had NEVER been watched before would still read as
    // AsyncLoading right after its first subscription (the first event needs
    // at least one microtask turn to arrive). Same fix as the web dialog
    // counterpart (appointment_detail_dialog.dart).
    ref.watch(athleteBillingProvider(appointment.athleteId));

    final canCancel = appointment.startsAt.difference(DateTime.now().toUtc()) >
        const Duration(hours: 24);

    final endTime =
        appointment.startsAt.add(Duration(minutes: appointment.durationMin));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        // SingleChildScrollView: the Cobrar form (Slice 2a) adds enough
        // height that this sheet's Column can overflow on shorter phone
        // viewports (and further still with the keyboard open) — this makes
        // the content scrollable instead of clipping the confirm button.
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle ────────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // ── Title ─────────────────────────────────────────────────────
              Text(
                'Detalle del turno',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              // ── Athlete header ────────────────────────────────────────────
              StreamBuilder<DocumentSnapshot<Map<String, Object?>>>(
                stream: _profileStream,
                builder: (ctx, snap) {
                  final remoteName =
                      snap.data?.data()?['displayName'] as String?;
                  final rawName = remoteName ?? appointment.athleteDisplayName;
                  final displayName =
                      _looksLikeUid(rawName) ? 'Alumno' : rawName;
                  final initials = _initials(displayName);

                  return Row(
                    children: [
                      _AvatarInitialsLocal(
                          initials: initials, palette: palette),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          displayName,
                          style: GoogleFonts.barlow(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: palette.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              // ── Detail card ───────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: palette.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Fecha',
                      value: _formatDateFull(appointment.startsAt),
                      palette: palette,
                    ),
                    _Divider(palette: palette),
                    _DetailRow(
                      label: 'Horario',
                      value:
                          '${_formatTime(appointment.startsAt)} – ${_formatTime(endTime)}',
                      palette: palette,
                    ),
                    _Divider(palette: palette),
                    _DetailRow(
                      label: 'Duración',
                      value: '${appointment.durationMin} min',
                      palette: palette,
                    ),
                    _Divider(palette: palette),
                    _StatusRow(palette: palette, status: appointment.status),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // ── Actions ───────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/coach/athlete/${appointment.athleteId}');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    'VER PERFIL DEL ALUMNO',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // ── Cobrar (Slice 2a — Agenda→cobro bridge) ────────────────────
              if (appointment.status == AppointmentStatus.confirmed) ...[
                if (appointment.paymentId != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(color: palette.accent),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(TreinoIcon.checkCircleFill,
                            size: 18, color: palette.accent),
                        const SizedBox(width: 8),
                        Text(
                          AppL10n.of(context).agendaCobradoLabel,
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: palette.accent,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (!_showCobrarForm)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => _openCobrarForm(ref),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: palette.accent),
                        foregroundColor: palette.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9999),
                        ),
                      ),
                      child: Text(
                        AppL10n.of(context).agendaCobrarCta,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  )
                else
                  _buildCobrarForm(context, ref, palette),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed:
                      canCancel ? () => _cancelAppointment(context, ref) : null,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: canCancel ? palette.highlight : palette.border,
                    ),
                    foregroundColor:
                        canCancel ? palette.highlight : palette.textMuted,
                    disabledForegroundColor: palette.textMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    canCancel
                        ? 'CANCELAR TURNO'
                        : 'CANCELAR TURNO (menos de 24h)',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.8,
                      color: canCancel ? palette.highlight : palette.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelAppointment(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final confirmed = await _confirmDialog(
      context,
      title: l10n.agendaCancellationConfirmTitle,
      body: l10n.agendaCancellationConfirmBody,
      confirmLabel: l10n.agendaCancellationConfirmCta,
      cancelLabel: l10n.agendaCancellationKeep,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(appointmentRepositoryProvider).cancel(
            appointment: widget.appointment,
            actorUid: widget.trainerId,
            reason: l10n.agendaBookingCancelledByCoach,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.agendaCancellationSuccess)),
      );
    } on CancellationTooLateException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.agendaCancellationTooLate)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.agendaGenericError)),
      );
    }
  }

  // ── Cobrar (Slice 2a) ─────────────────────────────────────────────────────

  void _openCobrarForm(WidgetRef ref) {
    final appt = widget.appointment;
    // Prefill from the athlete's reference rate AT THIS MOMENT — no reactive
    // re-prefill afterwards, so it never clobbers a value the trainer is
    // mid-typing. No config → field starts empty (designed fallback).
    final billing =
        ref.read(athleteBillingProvider(appt.athleteId)).valueOrNull;
    _amountController.text =
        billing != null ? billing.amountArs.toString() : '';
    _conceptController.text = AppL10n.of(context).agendaCobrarConceptoDefault(
      AgendaFormatters.formatDate(appt.startsAt),
    );
    setState(() {
      _showCobrarForm = true;
      _billingError = null;
    });
  }

  void _closeCobrarForm() {
    setState(() {
      _showCobrarForm = false;
      _billingError = null;
      _dueDate = null;
      _amountController.clear();
      _conceptController.clear();
    });
  }

  Future<void> _pickDueDate() async {
    // "Today" as an ART calendar day — same rationale as _AddSueltoSheet.
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

  Future<void> _confirmCobrar(BuildContext context, WidgetRef ref) async {
    if (_billing) return;
    final l10n = AppL10n.of(context);
    final appt = widget.appointment;
    final amount = int.tryParse(_amountController.text.trim());
    final concept = _conceptController.text.trim();

    if (amount == null || amount <= 0) {
      setState(() => _billingError = l10n.agendaCobrarMontoInvalido);
      return;
    }
    if (concept.isEmpty) {
      setState(() => _billingError = l10n.agendaCobrarCompletaCampos);
      return;
    }

    setState(() {
      _billing = true;
      _billingError = null;
    });

    // dueAt = end of the chosen ART calendar day, as a UTC instant — same
    // normalization as _AddSueltoSheet (Slice 1).
    final dueDate = _dueDate;
    final dueAt = dueDate == null
        ? null
        : DateTime.utc(dueDate.year, dueDate.month, dueDate.day, 23, 59, 59)
            .add(argentinaUtcOffset);

    final payment = Payment(
      id: '',
      trainerId: widget.trainerId,
      athleteId: appt.athleteId,
      amountArs: amount,
      concept: concept,
      status: PaymentStatus.pending,
      createdAt: DateTime.now().toUtc(),
      dueAt: dueAt,
    );

    try {
      await ref.read(appointmentRepositoryProvider).billAppointment(
            appointment: appt,
            payment: payment,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.agendaCobrarSuccess)),
      );
    } catch (_) {
      // Covers AppointmentAlreadyBilledException, AppointmentNotConfirmedException
      // and any other failure — the repository transaction guarantees the
      // Payment + paymentId link never diverge, so a single generic retry
      // message is safe here (see appointment_detail_dialog.dart's web
      // counterpart for more granular per-exception copy).
      if (!mounted) return;
      setState(() {
        _billing = false;
        _billingError = l10n.agendaCobrarError;
      });
    }
  }

  Widget _buildCobrarForm(
    BuildContext context,
    WidgetRef ref,
    AppPalette palette,
  ) {
    final l10n = AppL10n.of(context);
    final appt = widget.appointment;
    final billing =
        ref.watch(athleteBillingProvider(appt.athleteId)).valueOrNull;

    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: palette.textMuted),
          filled: true,
          fillColor: palette.bgCard,
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
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.8,
              color: palette.textMuted,
            ),
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label(l10n.agendaCobrarMontoLabel),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.barlow(color: palette.textPrimary),
            decoration: deco('5000'),
          ),
          if (billing != null) ...[
            const SizedBox(height: 6),
            Text(
              l10n.agendaCobrarTarifaReferencia(fmtArs(billing.amountArs)),
              style: GoogleFonts.barlow(fontSize: 12, color: palette.textMuted),
            ),
          ],
          const SizedBox(height: 14),
          label(l10n.agendaCobrarConceptoLabel),
          TextField(
            controller: _conceptController,
            style: GoogleFonts.barlow(color: palette.textPrimary),
            decoration: deco(l10n.agendaCobrarConceptoLabel),
          ),
          const SizedBox(height: 14),
          label(l10n.agendaCobrarVenceElLabel),
          InkWell(
            onTap: _pickDueDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Icon(TreinoIcon.calendar, size: 16, color: palette.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dueDate == null
                          ? l10n.agendaCobrarVenceElHint
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
                      label: l10n.agendaCobrarVenceElQuitar,
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _billing ? null : _closeCobrarForm,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.border),
                    foregroundColor: palette.textPrimary,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(l10n.agendaBookingCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      _billing ? null : () => _confirmCobrar(context, ref),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
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
                          l10n.agendaCobrarConfirmCta,
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Detail card rows ──────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.8,
              color: palette.textMuted,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.palette, required this.status});

  final AppPalette palette;
  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final label =
        status == AppointmentStatus.confirmed ? 'Confirmado' : 'Cancelado';
    final color = status == AppointmentStatus.confirmed
        ? palette.accent
        : palette.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'ESTADO',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.8,
              color: palette.textMuted,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Divider(color: palette.border, height: 1, thickness: 1);
  }
}

// ── Local avatar ──────────────────────────────────────────────────────────────

class _AvatarInitialsLocal extends StatelessWidget {
  const _AvatarInitialsLocal({required this.initials, required this.palette});
  final String initials;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.bgCard,
        border: Border.all(color: palette.accent, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: 0.5,
          color: palette.accent,
        ),
      ),
    );
  }
}

// ── Confirm dialog ────────────────────────────────────────────────────────────

Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final palette = AppPalette.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        title,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: palette.textPrimary,
        ),
      ),
      content: Text(
        body,
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            cancelLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: palette.textPrimary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.highlight,
            foregroundColor: palette.bg,
          ),
          child: Text(
            confirmLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _kSpanishDaysShort = <String>[
  '',
  'Lun',
  'Mar',
  'Mié',
  'Jue',
  'Vie',
  'Sáb',
  'Dom',
];

const _kSpanishMonthsShort = <String>[
  '',
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// Formats a [DateTime] as e.g. "Lun 2 jun" — same UTC convention as the
/// rest of the dashboard (no .toLocal() calls).
String _formatDateFull(DateTime dt) {
  final dayName = _kSpanishDaysShort[dt.weekday];
  final monthName = _kSpanishMonthsShort[dt.month];
  return '$dayName ${dt.day} $monthName';
}

String _formatTime(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _initials(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '·';
  final parts = clean.split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  if (parts[0].length >= 2) {
    return parts[0].substring(0, 2).toUpperCase();
  }
  return parts[0].toUpperCase();
}

bool _looksLikeUid(String s) {
  if (s.length < 20) return false;
  if (s.contains(' ')) return false;
  final alphaNumeric = RegExp(r'^[a-zA-Z0-9]+$');
  return alphaNumeric.hasMatch(s);
}
