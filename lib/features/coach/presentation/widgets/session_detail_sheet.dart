import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/agenda_providers.dart';
import '../../application/athlete_note_providers.dart';
import '../../domain/agenda_exceptions.dart';
import '../../domain/appointment.dart';
import '../../../../l10n/app_l10n.dart';
import '../agenda_formatters.dart';

class SessionDetailSheet extends ConsumerStatefulWidget {
  const SessionDetailSheet({
    super.key,
    required this.appointment,
    required this.trainerId,
    required this.isPast,
  });

  final Appointment appointment;
  final String trainerId;
  final bool isPast;

  @override
  ConsumerState<SessionDetailSheet> createState() => _SessionDetailSheetState();
}

class _SessionDetailSheetState extends ConsumerState<SessionDetailSheet> {
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
        const SnackBar(content: Text('Notas guardadas.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos guardar. Probá de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelAppointment() async {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    final confirmed = await _localConfirmDialog(
      context,
      palette: palette,
      title: l10n.agendaCancellationConfirmTitle,
      body: l10n.agendaCancellationConfirmBody,
      confirmLabel: l10n.agendaCancellationConfirmCta,
      cancelLabel: l10n.agendaCancellationKeep,
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(appointmentRepositoryProvider).cancel(
            appointment: widget.appointment,
            actorUid: widget.trainerId,
            reason: l10n.agendaBookingCancelledByCoach,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.agendaCancellationSuccess)),
      );
    } on CancellationTooLateException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.agendaCancellationTooLate)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.agendaGenericError)),
      );
    }
  }

  Future<void> _cancelSeries() async {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    final confirmed = await _localConfirmDialog(
      context,
      palette: palette,
      title: 'Cancelar toda la serie',
      body:
          'Se cancelan todas las sesiones futuras de esta serie recurrente (las que faltan más de 24h). No se puede deshacer.',
      confirmLabel: 'Cancelar serie',
      cancelLabel: 'No',
    );
    if (!confirmed || !mounted) return;

    try {
      final n =
          await ref.read(appointmentRepositoryProvider).cancelFutureSeries(
                recurringId: widget.appointment.recurringId!,
                trainerId: widget.trainerId,
                actorUid: widget.trainerId,
                reason: l10n.agendaBookingCancelledByCoach,
              );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(n == 0
              ? 'No había sesiones futuras para cancelar.'
              : 'Se cancelaron $n sesiones de la serie.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.agendaGenericError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final appointment = widget.appointment;

    final end =
        appointment.startsAt.add(Duration(minutes: appointment.durationMin));
    final timeLabel =
        '${AgendaFormatters.formatTime(appointment.startsAt)} – ${AgendaFormatters.formatTime(end)} · ${appointment.durationMin} min';

    final profileAsync =
        ref.watch(userPublicProfileProvider(appointment.athleteId));
    final rawName =
        profileAsync.valueOrNull?.displayName ?? appointment.athleteDisplayName;
    // Fall back to 'Alumno' if rawName looks like a raw UID
    // (20+ chars, no spaces, alphanumeric-ish)
    final isRawUid = rawName.length >= 20 &&
        !rawName.contains(' ') &&
        RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(rawName);
    final athleteName =
        (isRawUid || rawName.trim().isEmpty) ? 'Alumno' : rawName;
    final initials = _initials(athleteName);

    final noteAsync = ref.watch(athleteNoteProvider(
      (trainerId: widget.trainerId, athleteId: appointment.athleteId),
    ));
    final stickyNote = noteAsync.valueOrNull;
    final hasNote = stickyNote != null && stickyNote.note.trim().isNotEmpty;

    final canCancel = !widget.isPast &&
        appointment.startsAt.difference(DateTime.now().toUtc()) >
            const Duration(hours: 24);
    final isWithin24h = !widget.isPast && !canCancel;
    final isRecurring = appointment.recurringId != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Handle bar ─────────────────────────────────────────────
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

              // ── Header: time range ─────────────────────────────────────
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: palette.highlight.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(color: palette.highlight),
                    ),
                    child: Text(
                      'SERIE RECURRENTE',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: palette.highlight,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // ── Athlete row ────────────────────────────────────────────
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/coach/athlete/${appointment.athleteId}');
                },
                child: Row(
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
                        initials,
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
                    Icon(TreinoIcon.forward,
                        size: 16, color: palette.textMuted),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Sticky note banner ─────────────────────────────────────
              if (hasNote) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: palette.warning.withAlpha(28),
                    border: Border.all(color: palette.warning),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(TreinoIcon.warning,
                          size: 16, color: palette.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stickyNote.note,
                          style: GoogleFonts.barlow(
                            fontSize: 13,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Editá esta nota fija en el perfil del alumno.',
                  style: GoogleFonts.barlow(
                    fontSize: 11,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Antes de la sesión ─────────────────────────────────────
              Text(
                'ANTES DE LA SESIÓN',
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
                  hintText: 'Ej: traer banda, viene de lesión de rodilla…',
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

              // ── Recordatorio (post) ────────────────────────────────────
              Text(
                'RECORDATORIO (POST)',
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
                  hintText: 'Ej: subió a 80kg, la próxima bajar volumen…',
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

              // ── Save button ────────────────────────────────────────────
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
                        'GUARDAR NOTAS',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 1.4,
                        ),
                      ),
              ),

              // ── Cancel section ─────────────────────────────────────────
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
                      'CANCELAR RESERVA',
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
                      'No se puede cancelar (menos de 24h).',
                      style: GoogleFonts.barlow(
                        fontSize: 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                // Series teardown — cancels every future occurrence >24h away,
                // even when this single one is within 24h.
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
                      'CANCELAR TODA LA SERIE',
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
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

Future<bool> _localConfirmDialog(
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
