// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR1 — Ver turnos (read-only agenda viewer).
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/appointment.dart';
import '../../../../coach/presentation/agenda_formatters.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import 'agenda_web_helpers.dart';

// ─── AppointmentDetailDialog ──────────────────────────────────────────────────

/// Dialog de detalle de turno — idioma web (AlertDialog, ADR-AGW-3).
///
/// Reemplaza SessionDetailSheet (bottom sheet mobile).
/// La fila del alumno es NO tappeable en PR1 (ADR-AGW-8): la navegación
/// /alumnos/{id} pertenece a la rama chat-web-v1.
///
/// Soporta: rango horario, badge SERIE RECURRENTE, notas (antes/después),
/// GUARDAR NOTAS, CANCELAR RESERVA (>24h), cancelar toda la serie, Cerrar.
class AppointmentDetailDialog extends ConsumerStatefulWidget {
  const AppointmentDetailDialog({
    super.key,
    required this.appointment,
    required this.trainerId,
    required this.isPast,
  });

  final Appointment appointment;
  final String trainerId;
  final bool isPast;

  @override
  ConsumerState<AppointmentDetailDialog> createState() =>
      _AppointmentDetailDialogState();
}

class _AppointmentDetailDialogState
    extends ConsumerState<AppointmentDetailDialog> {
  late final TextEditingController _beforeController;
  late final TextEditingController _afterController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _beforeController =
        TextEditingController(text: widget.appointment.noteBefore ?? '');
    _afterController =
        TextEditingController(text: widget.appointment.noteAfter ?? '');
  }

  @override
  void dispose() {
    _beforeController.dispose();
    _afterController.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final before = _beforeController.text.trim();
      final after = _afterController.text.trim();
      await ref.read(appointmentRepositoryProvider).updateNotes(
            appointmentId: widget.appointment.id,
            noteBefore: before.isEmpty ? null : before,
            noteAfter: after.isEmpty ? null : after,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notas guardadas.')), // i18n
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No pudimos guardar. Probá de nuevo.')), // i18n
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelAppointment() async {
    final palette = AppPalette.of(context);
    final confirmed = await confirmActionDialog(
      context,
      palette: palette,
      title: 'Cancelar reserva', // i18n
      body: '¿Cancelar esta sesión? El alumno será notificado.', // i18n
      confirmLabel: 'Cancelar sesión', // i18n
      cancelLabel: 'Mantener', // i18n
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(appointmentRepositoryProvider).cancel(
            appointment: widget.appointment,
            actorUid: widget.trainerId,
            reason: 'Cancelado por el coach', // i18n
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión cancelada.')), // i18n
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos cancelar la sesión.')), // i18n
      );
    }
  }

  Future<void> _cancelSeries() async {
    final palette = AppPalette.of(context);
    final confirmed = await confirmActionDialog(
      context,
      palette: palette,
      title: 'Cancelar toda la serie', // i18n
      body:
          'Se cancelan todas las sesiones futuras de esta serie recurrente (las que faltan más de 24h). No se puede deshacer.', // i18n
      confirmLabel: 'Cancelar serie', // i18n
      cancelLabel: 'No', // i18n
    );
    if (!confirmed || !mounted) return;

    try {
      final n =
          await ref.read(appointmentRepositoryProvider).cancelFutureSeries(
                recurringId: widget.appointment.recurringId!,
                trainerId: widget.trainerId,
                actorUid: widget.trainerId,
                reason: 'Cancelado por el coach', // i18n
              );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'No había sesiones futuras para cancelar.' // i18n
                : 'Se cancelaron $n sesiones de la serie.', // i18n
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos cancelar la serie.')), // i18n
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final appt = widget.appointment;

    final end = appt.startsAt.add(Duration(minutes: appt.durationMin));
    final timeLabel =
        '${AgendaFormatters.formatTime(appt.startsAt)} – ${AgendaFormatters.formatTime(end)} · ${appt.durationMin} min'; // i18n

    final profileAsync = ref.watch(userPublicProfileProvider(appt.athleteId));
    final rawName =
        profileAsync.valueOrNull?.displayName ?? appt.athleteDisplayName;
    final athleteName = (isRawUid(rawName) || rawName.trim().isEmpty)
        ? 'Alumno'
        : rawName; // i18n

    final canCancel = !widget.isPast &&
        appt.startsAt.difference(DateTime.now().toUtc()) >
            const Duration(hours: 24);
    final isWithin24h = !widget.isPast && !canCancel;
    final isRecurring = appt.recurringId != null;

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rango horario
          Text(
            timeLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: palette.textPrimary,
            ),
          ),
          if (isRecurring) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.highlight.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: palette.highlight),
              ),
              child: Text(
                'SERIE RECURRENTE', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: palette.highlight,
                ),
              ),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Athlete row — NON-TAPPABLE (ADR-AGW-8) ──────────────────
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.accent.withAlpha(40),
                      border: Border.all(color: palette.accent),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials(athleteName),
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      athleteName,
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Sin ícono de chevron — no es tappeable (ADR-AGW-8).
                ],
              ),
              const SizedBox(height: 16),

              // ── Antes de la sesión ────────────────────────────────────
              Text(
                'ANTES DE LA SESIÓN', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _beforeController,
                maxLines: 3,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  hintText:
                      'Ej: traer banda, viene de lesión de rodilla…', // i18n
                  hintStyle: TextStyle(color: palette.textMuted),
                  filled: true,
                  fillColor: palette.bg,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Recordatorio (post) ───────────────────────────────────
              Text(
                'RECORDATORIO (POST)', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _afterController,
                maxLines: 3,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  hintText:
                      'Ej: subió a 80kg, la próxima bajar volumen…', // i18n
                  hintStyle: TextStyle(color: palette.textMuted),
                  filled: true,
                  fillColor: palette.bg,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Guardar notas ─────────────────────────────────────────
              ElevatedButton(
                onPressed: _saving ? null : _saveNotes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  disabledBackgroundColor:
                      palette.accent.withValues(alpha: 0.3),
                ),
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.bg,
                        ),
                      )
                    : Text(
                        'GUARDAR NOTAS', // i18n
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 1.4,
                        ),
                      ),
              ),

              // ── Cancelar ─────────────────────────────────────────────
              if (!widget.isPast) ...[
                const SizedBox(height: 12),
                if (canCancel)
                  OutlinedButton(
                    onPressed: _cancelAppointment,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: palette.highlight),
                      foregroundColor: palette.highlight,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'CANCELAR RESERVA', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 1.4,
                      ),
                    ),
                  )
                else if (isWithin24h)
                  Center(
                    child: Text(
                      'No se puede cancelar (menos de 24h).', // i18n
                      style: GoogleFonts.barlow(
                        fontSize: 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                if (isRecurring) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _cancelSeries,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: palette.danger),
                      foregroundColor: palette.danger,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'CANCELAR TODA LA SERIE', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: palette.textMuted),
          child: Text(
            'Cerrar', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Confirm dialog (local helper) ───────────────────────────────────────────

/// Dialog de confirmación reutilizable — idioma web (AlertDialog).
/// Mirror del helper en session_detail_sheet.dart pero sin depender de AppL10n.
Future<bool> confirmActionDialog(
  BuildContext context, {
  required AppPalette palette,
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) async {
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
