import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_toast.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/agenda_providers.dart';
import '../../domain/appointment.dart';

/// Marcar o deshacer «ausente» sobre una sesión que ya empezó (#1492).
///
/// Lo comparten los dos detalles de sesión del PF en mobile
/// (`SessionDetailSheet` y `AppointmentDetailSheet`); el Coach Hub web tiene
/// su propia versión con el botón del kit.
///
/// El valor vive en un estado local porque los dos sheets reciben un
/// [Appointment] fijo, el del momento en que se abrieron: sin esto el botón no
/// reflejaría su propio cambio hasta cerrar y volver a abrir el sheet.
///
/// Quien lo monta decide CUÁNDO: sólo sobre una sesión `confirmed` que ya
/// empezó. Las reglas no pueden mirar eso (el `startsAt` es wall-clock).
class SessionAttendanceControl extends ConsumerStatefulWidget {
  const SessionAttendanceControl({super.key, required this.appointment});

  final Appointment appointment;

  @override
  ConsumerState<SessionAttendanceControl> createState() =>
      _SessionAttendanceControlState();
}

class _SessionAttendanceControlState
    extends ConsumerState<SessionAttendanceControl> {
  late AppointmentAttendance? _attendance = widget.appointment.attendance;
  bool _saving = false;

  Future<void> _toggle() async {
    if (_saving) return;
    final next = _attendance == null ? AppointmentAttendance.absent : null;
    setState(() => _saving = true);
    try {
      await ref.read(appointmentRepositoryProvider).setAttendance(
            appointmentId: widget.appointment.id,
            attendance: next,
          );
      if (!mounted) return;
      setState(() => _attendance = next);
    } catch (_) {
      if (!mounted) return;
      // Desde el sheet: el toast va por el Overlay raíz y no queda tapado.
      showTreinoToast(
        context,
        AppL10n.of(context).agendaAttendanceError,
        type: TreinoToastType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final absent = _attendance == AppointmentAttendance.absent;
    final v = TreinoButtonTokens.of(context, TreinoButtonVariant.secondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          absent
              ? l10n.agendaAttendanceAbsentHint
              : l10n.agendaAttendanceDefaultHint,
          style: GoogleFonts.barlow(
            fontSize: AppTextSize.caption,
            color: absent ? palette.warning : palette.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        OutlinedButton(
          onPressed: _saving ? null : _toggle,
          style: OutlinedButton.styleFrom(
            backgroundColor: v.background,
            side: BorderSide(color: v.borderColor),
            foregroundColor: v.foreground,
            minimumSize: const Size.fromHeight(48),
            shape: const StadiumBorder(),
          ),
          child: Text(
            absent
                ? l10n.agendaAttendanceUndoAbsent
                : l10n.agendaAttendanceMarkAbsent,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: AppTextSize.body,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
