import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../profile/application/user_providers.dart'
    show firestoreProvider;
import '../../application/agenda_providers.dart';
import '../../domain/appointment.dart';
import '../../domain/availability_override.dart';
import '../../domain/compute_free_slots.dart';
import '../../../../l10n/app_l10n.dart';
import '../agenda_formatters.dart';
import 'session_detail_sheet.dart';

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
        now: DateTime.now().toUtc(),
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
              AgendaFormatters.formatDate(day),
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
            label: AppL10n.of(context).agendaSlotBlockedLabel,
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
    required this.now,
  });

  final List<_SlotEntry> entries;
  final String trainerId;
  final AppPalette palette;

  /// Reference instant for the past/upcoming distinction (UTC).
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // Fixed 3-column grid so every slot lines up in even columns regardless
    // of free (one line) vs booked (time + name). Shrink-wrapped — the sheet
    // sizes to content.
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.8,
      children: entries.map((entry) => _buildChip(context, entry)).toList(),
    );
  }

  Widget _buildChip(BuildContext context, _SlotEntry entry) {
    final timeLabel = AgendaFormatters.formatTime(entry.time);
    // "Past" = the slot's start time is at or before now. Whole past days fall
    // out of this naturally (every slot that day is before now).
    final isPast = !entry.time.isAfter(now);

    switch (entry.state) {
      case _SlotState.free:
        return _SlotChip(
          label: timeLabel,
          color: isPast ? palette.textMuted : palette.accent,
          backgroundColor:
              isPast ? palette.bgCard : palette.accent.withAlpha(30),
          borderColor: isPast ? palette.border : palette.accent,
        );

      case _SlotState.booked:
        final appt = entry.appointment!;
        return _BookedSlotChip(
          time: timeLabel,
          athleteName: appt.athleteDisplayName,
          appointment: appt,
          trainerId: trainerId,
          palette: palette,
          // On-brand: reserved = magenta (highlight). Past = muted gray, but
          // the name/detail stays visible so the trainer keeps the record.
          accentColor: isPast ? palette.textMuted : palette.highlight,
          isPast: isPast,
        );

      case _SlotState.blocked:
        return _SlotChip(
          label: AppL10n.of(context).agendaSlotBlockedLabel,
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
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w600,
          fontSize: 15,
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
    required this.accentColor,
    required this.isPast,
  });

  final String time;
  final String athleteName;
  final Appointment appointment;
  final String trainerId;
  final AppPalette palette;

  /// Reserved chips are magenta (on-brand `highlight`) when upcoming, muted
  /// gray when the session has already passed.
  final Color accentColor;
  final bool isPast;

  @override
  ConsumerState<_BookedSlotChip> createState() => _BookedSlotChipState();
}

class _BookedSlotChipState extends ConsumerState<_BookedSlotChip> {
  /// Live Firestore stream for the athlete's public profile.
  ///
  /// We use a STREAM rather than a one-shot Future for two reasons:
  /// 1. Survives stale-cache scenarios — if the device's Firestore cache
  ///    held `null` (from pre-backfill read), the stream emits cache-first
  ///    then immediately re-emits when the server responds with the doc.
  ///    A `get()` Future would return whichever source resolves first and
  ///    stop there.
  /// 2. Auto-updates if the athlete renames themselves — chip stays in
  ///    sync without manual invalidation.
  ///
  /// Bypasses the cached `userPublicProfileProvider` deliberately.
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
    final accent = widget.accentColor;

    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppPalette.of(context).bgCard,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => SessionDetailSheet(
          appointment: widget.appointment,
          trainerId: widget.trainerId,
          isPast: widget.isPast,
        ),
      ),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: widget.isPast ? widget.palette.bgCard : accent.withAlpha(30),
          border: Border.all(color: accent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.time,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: accent,
              ),
            ),
            const SizedBox(height: 2),
            StreamBuilder<DocumentSnapshot<Map<String, Object?>>>(
              stream: _profileStream,
              builder: (ctx, snap) {
                final remoteName = snap.data?.data()?['displayName'] as String?;
                final name = remoteName ?? widget.athleteName;
                return Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    fontSize: 11,
                    color: accent,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
