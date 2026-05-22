import 'dart:collection';

import 'appointment.dart';
import 'availability_override.dart';
import 'availability_rule.dart';

/// Computes the list of free (bookable) UTC [DateTime] slots for [forDate].
///
/// Algorithm (ADR-2):
/// 1. If a `block` override exists for [forDate] → return `[]` immediately.
/// 2. Build a [SplayTreeSet]<DateTime> from all rules matching [forDate]'s
///    weekday (ISO: Monday = 1).
/// 3. Add `extra` override windows for [forDate].
/// 4. Remove any slot that coincides exactly with a *confirmed* appointment's
///    `startsAt`. Cancelled appointments do NOT block the slot (ADR-1).
///
/// All generated [DateTime]s are UTC with second == 0, millisecond == 0,
/// microsecond == 0 (minute precision — ADR-7).
///
/// Complexity: O(R·S + O + A) per call (trivial for typical agenda sizes).
List<DateTime> computeFreeSlots({
  required List<AvailabilityRule> rules,
  required List<AvailabilityOverride> overrides,
  required List<Appointment> existingAppointments,
  required DateTime forDate,
}) {
  // Normalise forDate to the UTC date (drop time component).
  final date = DateTime.utc(forDate.year, forDate.month, forDate.day);

  // Step 1: block override check.
  for (final override in overrides) {
    if (override is AvailabilityOverrideBlock) {
      final oDate = override.date;
      if (oDate.year == date.year &&
          oDate.month == date.month &&
          oDate.day == date.day) {
        return const [];
      }
    }
  }

  // ISO weekday: DateTime.weekday returns 1=Monday … 7=Sunday (same as our
  // AvailabilityRule.dayOfWeek convention).
  final weekday = date.weekday;

  // Step 2: build slot set from matching rules.
  final slotSet = SplayTreeSet<DateTime>();
  for (final rule in rules) {
    if (rule.dayOfWeek != weekday) continue;
    _addSlotsFromWindow(
      set: slotSet,
      date: date,
      startHour: rule.startHour,
      startMinute: rule.startMinute,
      endHour: rule.endHour,
      endMinute: rule.endMinute,
      slotDurationMin: rule.slotDurationMin,
    );
  }

  // Step 3: add extra override windows.
  for (final override in overrides) {
    if (override is AvailabilityOverrideExtra) {
      final oDate = override.date;
      if (oDate.year == date.year &&
          oDate.month == date.month &&
          oDate.day == date.day) {
        _addSlotsFromWindow(
          set: slotSet,
          date: date,
          startHour: override.startHour,
          startMinute: override.startMinute,
          endHour: override.endHour,
          endMinute: override.endMinute,
          slotDurationMin: override.slotDurationMin,
        );
      }
    }
  }

  // Step 4: remove confirmed appointments.
  for (final appt in existingAppointments) {
    if (appt.status != AppointmentStatus.confirmed) continue;
    final s = appt.startsAt;
    slotSet.remove(DateTime.utc(s.year, s.month, s.day, s.hour, s.minute));
  }

  return slotSet.toList();
}

/// Generates slots in the half-open window [startHour:startMinute,
/// endHour:endMinute) spaced by [slotDurationMin] and inserts them into [set].
void _addSlotsFromWindow({
  required SplayTreeSet<DateTime> set,
  required DateTime date,
  required int startHour,
  required int startMinute,
  required int endHour,
  required int endMinute,
  required int slotDurationMin,
}) {
  final endTotalMinutes = endHour * 60 + endMinute;
  var currentMinutes = startHour * 60 + startMinute;

  while (currentMinutes + slotDurationMin <= endTotalMinutes) {
    final h = currentMinutes ~/ 60;
    final m = currentMinutes % 60;
    set.add(DateTime.utc(date.year, date.month, date.day, h, m));
    currentMinutes += slotDurationMin;
  }
}
