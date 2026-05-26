import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../../profile/domain/user_public_profile.dart';
import '../../application/agenda_providers.dart';
import '../../domain/agenda_exceptions.dart';
import '../../domain/appointment.dart';
import '../../domain/availability_override.dart';
import '../../domain/compute_free_slots.dart';
import '../agenda_strings.dart';

/// Slot state from the trainer's perspective.
enum _SlotState { free, booked, blocked }

/// A slot entry computed for a given day.
class _SlotEntry {
  const _SlotEntry({
    required this.time,
    required this.state,
    this.appointment,
  });

  final DateTime time;
  final _SlotState state;
  final Appointment? appointment;
}

/// Bottom-sheet content shown when a trainer taps a calendar day.
///
/// Shows ALL slots for that day — free (verde), booked (azul + athlete name),
/// or blocked (gris). Booked slots can be cancelled (with 24h gate).
///
/// SCENARIO-520: free slots shown as green chips
/// SCENARIO-521: booked slots show athlete name in blue chip
/// SCENARIO-522: booked slot tap → action menu → cancel
/// SCENARIO-524: blocked day shows "Bloqueado" chip (gris)
class TrainerDayDetailSheet extends ConsumerWidget {
  const TrainerDayDetailSheet({
    super.key,
    required this.trainerId,
    required this.day,
    required this.rangeFrom,
    required this.rangeTo,
  });

  final String trainerId;

  /// The calendar day — must be UTC midnight (`DateTime.utc(y, m, d)`).
  final DateTime day;

  final DateTime rangeFrom;
  final DateTime rangeTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    final rulesAsync = ref.watch(availabilityRulesStreamProvider(trainerId));
    final overridesAsync = ref.watch(
      overridesStreamProvider(OverridesKey(
        trainerId: trainerId,
        fromDate: rangeFrom,
        toDate: rangeTo,
      )),
    );
    final appointmentsAsync = ref.watch(
      trainerAppointmentsStreamProvider(TrainerAppointmentsKey(
        trainerId: trainerId,
        fromDate: rangeFrom,
        toDate: rangeTo,
      )),
    );

    final rules = rulesAsync.valueOrNull ?? const [];
    final overrides = overridesAsync.valueOrNull ?? const [];
    final appointments = appointmentsAsync.valueOrNull ?? const [];

    // Check if this day is fully blocked by an override.
    final isBlocked = overrides.any((o) {
      if (o is! AvailabilityOverrideBlock) return false;
      return o.date.year == day.year &&
          o.date.month == day.month &&
          o.date.day == day.day;
    });

    if (isBlocked) {
      return _sheet(
        context,
        palette,
        child: _BlockedState(palette: palette),
      );
    }

    // Compute all slots for this day (free + booked combined).
    // We need ALL slots, not just free ones. To do this, we compute free slots
    // (which excludes confirmed appointments) and then layer confirmed
    // appointments back in.
    final freeSlots = computeFreeSlots(
      rules: rules,
      overrides: overrides,
      existingAppointments: appointments,
      forDate: day,
    );

    // Confirmed appointments on this day.
    final dayAppointments = appointments.where((a) {
      if (a.status != AppointmentStatus.confirmed) return false;
      final d = a.startsAt.toUtc();
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();

    if (freeSlots.isEmpty && dayAppointments.isEmpty) {
      return _sheet(
        context,
        palette,
        child: _EmptyState(palette: palette),
      );
    }

    // Build combined sorted slot list.
    final slotEntries = <_SlotEntry>[];

    for (final slot in freeSlots) {
      slotEntries.add(_SlotEntry(time: slot, state: _SlotState.free));
    }

    for (final appt in dayAppointments) {
      final t = appt.startsAt.toUtc();
      slotEntries.add(_SlotEntry(
        time: DateTime.utc(t.year, t.month, t.day, t.hour, t.minute),
        state: _SlotState.booked,
        appointment: appt,
      ));
    }

    slotEntries.sort((a, b) => a.time.compareTo(b.time));

    return _sheet(
      context,
      palette,
      child: _SlotList(
        entries: slotEntries,
        trainerId: trainerId,
        palette: palette,
      ),
    );
  }

  Widget _sheet(BuildContext context, AppPalette palette,
      {required Widget child}) {
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
            // Day label
            Text(
              AgendaStrings.formatDate(day),
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            child,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'Sin turnos para este día.',
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
      ),
    );
  }
}

// ── Blocked state ─────────────────────────────────────────────────────────────

class _BlockedState extends StatelessWidget {
  const _BlockedState({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          _SlotChip(
            label: AgendaStrings.slotBlockedLabel,
            color: palette.textMuted,
            backgroundColor: palette.bgCard,
            borderColor: palette.border,
          ),
        ],
      ),
    );
  }
}

// ── Slot list ─────────────────────────────────────────────────────────────────

class _SlotList extends StatelessWidget {
  const _SlotList({
    required this.entries,
    required this.trainerId,
    required this.palette,
  });

  final List<_SlotEntry> entries;
  final String trainerId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.map((entry) => _buildChip(context, entry)).toList(),
    );
  }

  Widget _buildChip(BuildContext context, _SlotEntry entry) {
    final timeLabel = AgendaStrings.formatTime(entry.time);

    switch (entry.state) {
      case _SlotState.free:
        return _SlotChip(
          label: timeLabel,
          color: const Color(0xFF2CE5A2), // mint green
          backgroundColor: const Color(0xFF2CE5A2).withAlpha(30),
          borderColor: const Color(0xFF2CE5A2),
        );

      case _SlotState.booked:
        final appt = entry.appointment!;
        return _BookedSlotChip(
          time: timeLabel,
          athleteName: appt.athleteDisplayName,
          appointment: appt,
          trainerId: trainerId,
          palette: palette,
        );

      case _SlotState.blocked:
        return _SlotChip(
          label: AgendaStrings.slotBlockedLabel,
          color: palette.textMuted,
          backgroundColor: palette.bgCard,
          borderColor: palette.border,
        );
    }
  }
}

// ── Slot chip ─────────────────────────────────────────────────────────────────

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String label;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: color,
        ),
      ),
    );
  }
}

// ── Booked slot chip ──────────────────────────────────────────────────────────

class _BookedSlotChip extends ConsumerStatefulWidget {
  const _BookedSlotChip({
    required this.time,
    required this.athleteName,
    required this.appointment,
    required this.trainerId,
    required this.palette,
  });

  final String time;
  final String athleteName;
  final Appointment appointment;
  final String trainerId;
  final AppPalette palette;

  @override
  ConsumerState<_BookedSlotChip> createState() => _BookedSlotChipState();
}

class _BookedSlotChipState extends ConsumerState<_BookedSlotChip> {
  /// Fresh one-shot fetch via the repository — BYPASSES the cached
  /// `userPublicProfileProvider`. The cached provider is a non-autoDispose
  /// FutureProvider: if the first read happened before the user's profile
  /// was backfilled, it cached `null` forever within the app session, even
  /// after the backfill. This fetch reads Firestore fresh every time the
  /// sheet opens (initState fires once per chip mount).
  late final Future<UserPublicProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = ref
        .read(userPublicProfileRepositoryProvider)
        .get(widget.appointment.athleteId);
  }

  @override
  Widget build(BuildContext context) {
    final appointment = widget.appointment;
    final canCancel = appointment.startsAt.difference(DateTime.now().toUtc()) >
        const Duration(hours: 24);

    return GestureDetector(
      onTap: () => _showActionMenu(context, ref, canCancel),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(30),
          border: Border.all(color: Colors.blue),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.time,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.blue,
              ),
            ),
            FutureBuilder<UserPublicProfile?>(
              future: _profileFuture,
              builder: (ctx, snap) {
                final name = snap.data?.displayName ?? widget.athleteName;
                return Text(
                  name,
                  style: GoogleFonts.barlow(
                    fontSize: 11,
                    color: Colors.blue.withAlpha(200),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActionMenu(
    BuildContext context,
    WidgetRef ref,
    bool canCancel,
  ) async {
    final palette = AppPalette.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.person_outline, color: palette.textPrimary),
              title: Text(
                'Ver alumno',
                style: GoogleFonts.barlow(color: palette.textPrimary),
              ),
              onTap: () => Navigator.of(ctx).pop('ver-alumno'),
            ),
            if (canCancel)
              ListTile(
                leading: Icon(Icons.cancel_outlined, color: palette.highlight),
                title: Text(
                  AgendaStrings.cancellationConfirmCta,
                  style: GoogleFonts.barlow(color: palette.highlight),
                ),
                onTap: () => Navigator.of(ctx).pop('cancelar'),
              )
            else
              ListTile(
                leading: Icon(Icons.cancel_outlined, color: palette.textMuted),
                title: Text(
                  'Cancelar reserva (no disponible — menos de 24h)',
                  style: GoogleFonts.barlow(color: palette.textMuted),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!context.mounted) return;
    if (action == 'cancelar') {
      await _cancelAppointment(context, ref);
    } else if (action == 'ver-alumno') {
      // Close the day-detail sheet first, then push athlete detail.
      Navigator.of(context).pop();
      context.push('/coach/athlete/${widget.appointment.athleteId}');
    }
  }

  Future<void> _cancelAppointment(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirmDialog(
      context,
      title: AgendaStrings.cancellationConfirmTitle,
      body: AgendaStrings.cancellationConfirmBody,
      confirmLabel: AgendaStrings.cancellationConfirmCta,
      cancelLabel: AgendaStrings.cancellationKeep,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(appointmentRepositoryProvider).cancel(
            appointment: widget.appointment,
            actorUid: widget.trainerId,
            reason: AgendaStrings.bookingCancelledByCoach,
          );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close detail sheet
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AgendaStrings.cancellationSuccess)),
      );
    } on CancellationTooLateException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AgendaStrings.cancellationTooLate)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AgendaStrings.genericError)),
      );
    }
  }
}

// ── Dialog helper ─────────────────────────────────────────────────────────────

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
