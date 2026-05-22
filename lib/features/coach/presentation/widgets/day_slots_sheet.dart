import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../domain/appointment.dart';
import '../agenda_strings.dart';

/// Bottom-sheet content shown when an athlete taps a calendar day.
///
/// Displays free bookable [slots] as tappable chips plus the athlete's
/// own [existingBookings] for that day highlighted with a "RESERVADO" label.
///
/// - Tap a free chip → shows confirmation dialog → calls [onBookSlot]
/// - Tap a booked chip → shows cancel dialog → calls [onCancelAppointment]
///
/// SCENARIO-501: free slots shown as chips labeled "HH:mm"
/// SCENARIO-502: empty state when no slots/bookings
/// SCENARIO-503: confirmation dialog on chip tap
/// SCENARIO-504: onBookSlot called after confirm
/// SCENARIO-508: own bookings shown with "RESERVADO" label
class DaySlotsSheet extends StatelessWidget {
  const DaySlotsSheet({
    super.key,
    required this.slots,
    required this.existingBookings,
    required this.onBookSlot,
    required this.onCancelAppointment,
    required this.now,
  });

  final List<DateTime> slots;
  final List<Appointment> existingBookings;
  final Future<void> Function(DateTime slot) onBookSlot;
  final Future<void> Function(Appointment appointment) onCancelAppointment;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasContent = slots.isNotEmpty || existingBookings.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sheet handle
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

          if (!hasContent) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  AgendaStrings.emptyAvailability,
                  style: GoogleFonts.barlow(
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ] else ...[
            // Existing bookings section
            if (existingBookings.isNotEmpty) ...[
              Text(
                'RESERVADO',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: existingBookings
                    .map((appt) => _BookedChip(
                          appointment: appt,
                          onCancel: () =>
                              _onCancelTap(context, appt),
                          now: now,
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Free slots section
            if (slots.isNotEmpty) ...[
              Text(
                'HORARIOS DISPONIBLES',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: slots
                    .map(
                      (slot) => ActionChip(
                        label: Text(
                          AgendaStrings.formatTime(slot),
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: palette.textPrimary,
                          ),
                        ),
                        backgroundColor: palette.bgCard,
                        side: BorderSide(color: palette.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onPressed: () => _onSlotTap(context, slot),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _onSlotTap(BuildContext context, DateTime slot) async {
    final confirmed = await _confirmDialog(
      context,
      title: AgendaStrings.bookingConfirmTitle,
      body: AgendaStrings.bookingConfirmBody(slot),
      confirmLabel: AgendaStrings.bookingConfirmCta,
      cancelLabel: AgendaStrings.bookingCancel,
    );
    if (!confirmed) return;
    await onBookSlot(slot);
  }

  Future<void> _onCancelTap(BuildContext context, Appointment appt) async {
    final confirmed = await _confirmDialog(
      context,
      title: AgendaStrings.cancellationConfirmTitle,
      body: AgendaStrings.cancellationConfirmBody,
      confirmLabel: AgendaStrings.cancellationConfirmCta,
      cancelLabel: AgendaStrings.cancellationKeep,
    );
    if (!confirmed) return;
    await onCancelAppointment(appt);
  }
}

// ── Booked chip for own appointments ─────────────────────────────────────────

class _BookedChip extends StatelessWidget {
  const _BookedChip({
    required this.appointment,
    required this.onCancel,
    required this.now,
  });

  final Appointment appointment;
  final VoidCallback onCancel;
  final DateTime now;

  bool get _canCancel =>
      appointment.startsAt.difference(now) > const Duration(hours: 24);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.accent.withAlpha(30),
        border: Border.all(color: palette.accent, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AgendaStrings.formatTime(appointment.startsAt),
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: palette.accent,
            ),
          ),
          if (_canCancel) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCancel,
              child: Icon(Icons.cancel_outlined, size: 16, color: palette.accent),
            ),
          ],
        ],
      ),
    );
  }
}

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
            backgroundColor: palette.accent,
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
