import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../profile/application/user_providers.dart'
    show firestoreProvider;
import '../../application/agenda_providers.dart';
import '../../domain/agenda_exceptions.dart';
import '../../domain/appointment.dart';
import '../../../../l10n/app_l10n.dart';

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
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final appointment = widget.appointment;

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
                final remoteName = snap.data?.data()?['displayName'] as String?;
                final rawName = remoteName ?? appointment.athleteDisplayName;
                final displayName = _looksLikeUid(rawName) ? 'Alumno' : rawName;
                final initials = _initials(displayName);

                return Row(
                  children: [
                    _AvatarInitialsLocal(initials: initials, palette: palette),
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
