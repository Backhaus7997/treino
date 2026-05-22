import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach/domain/compute_free_slots.dart';

void main() {
  // Helper: build a DateTime at minute-precision (ADR-7).
  DateTime slot(int year, int month, int day, int hour, int minute) =>
      DateTime.utc(year, month, day, hour, minute);

  // Monday 2026-06-01 (dayOfWeek == 1 in ISO).
  final kMonday = DateTime.utc(2026, 6, 1);

  group('computeFreeSlots', () {
    // SCENARIO-517 (formerly SCENARIO-485 in task numbering):
    // A single rule for a given weekday generates the correct slot count.
    test(
      'SCENARIO-517: single rule on matching weekday generates correct slots',
      () {
        // Rule: Monday 09:00–11:00, 60 min slots → 2 slots (09:00, 10:00).
        final rule = AvailabilityRule(
          id: 'r1',
          trainerId: 'tA',
          dayOfWeek: 1, // Monday
          startHour: 9,
          startMinute: 0,
          endHour: 11,
          endMinute: 0,
          slotDurationMin: 60,
        );

        final slots = computeFreeSlots(
          rules: [rule],
          overrides: [],
          existingAppointments: [],
          forDate: kMonday,
        );

        expect(slots, hasLength(2));
        expect(slots[0], slot(2026, 6, 1, 9, 0));
        expect(slots[1], slot(2026, 6, 1, 10, 0));
      },
    );

    // SCENARIO-518 (formerly SCENARIO-486):
    // A `block` override drops all slots for the date.
    test('SCENARIO-518: block override returns empty list', () {
      final rule = AvailabilityRule(
        id: 'r1',
        trainerId: 'tA',
        dayOfWeek: 1,
        startHour: 9,
        startMinute: 0,
        endHour: 11,
        endMinute: 0,
        slotDurationMin: 60,
      );
      final blockOverride = AvailabilityOverride.block(
        id: 'o1',
        trainerId: 'tA',
        date: kMonday,
      );

      final slots = computeFreeSlots(
        rules: [rule],
        overrides: [blockOverride],
        existingAppointments: [],
        forDate: kMonday,
      );

      expect(slots, isEmpty);
    });

    // SCENARIO-519 (formerly SCENARIO-487):
    // An `extra` override adds ad-hoc slots outside of regular rules.
    test('SCENARIO-519: extra override adds ad-hoc slots', () {
      // No rules for this day, only an extra override adding 07:00 slot.
      final extraOverride = AvailabilityOverride.extra(
        id: 'o2',
        trainerId: 'tA',
        date: kMonday,
        startHour: 7,
        startMinute: 0,
        endHour: 8,
        endMinute: 0,
        slotDurationMin: 60,
      );

      final slots = computeFreeSlots(
        rules: [],
        overrides: [extraOverride],
        existingAppointments: [],
        forDate: kMonday,
      );

      expect(slots, hasLength(1));
      expect(slots.single, slot(2026, 6, 1, 7, 0));
    });

    // SCENARIO-500 (derived from REQ-026 survivor rule):
    // An existing confirmed appointment removes that slot from free list.
    test(
      'SCENARIO-500: confirmed appointment removes its slot from free list',
      () {
        final rule = AvailabilityRule(
          id: 'r1',
          trainerId: 'tA',
          dayOfWeek: 1,
          startHour: 9,
          startMinute: 0,
          endHour: 11,
          endMinute: 0,
          slotDurationMin: 60,
        );
        final existing = Appointment(
          id: 'tA_${slot(2026, 6, 1, 9, 0).millisecondsSinceEpoch}',
          trainerId: 'tA',
          athleteId: 'aB',
          athleteDisplayName: 'Juan',
          startsAt: slot(2026, 6, 1, 9, 0),
          durationMin: 60,
          status: AppointmentStatus.confirmed,
        );

        final slots = computeFreeSlots(
          rules: [rule],
          overrides: [],
          existingAppointments: [existing],
          forDate: kMonday,
        );

        // 09:00 is taken; only 10:00 remains.
        expect(slots, hasLength(1));
        expect(slots.single, slot(2026, 6, 1, 10, 0));
      },
    );

    // Overlap deduplification — overlapping rules produce unique slots.
    test('overlapping rules deduplicate slots', () {
      // Two rules that overlap at 10:00.
      final rule1 = AvailabilityRule(
        id: 'r1',
        trainerId: 'tA',
        dayOfWeek: 1,
        startHour: 9,
        startMinute: 0,
        endHour: 11,
        endMinute: 0,
        slotDurationMin: 60,
      );
      final rule2 = AvailabilityRule(
        id: 'r2',
        trainerId: 'tA',
        dayOfWeek: 1,
        startHour: 10,
        startMinute: 0,
        endHour: 12,
        endMinute: 0,
        slotDurationMin: 60,
      );

      final slots = computeFreeSlots(
        rules: [rule1, rule2],
        overrides: [],
        existingAppointments: [],
        forDate: kMonday,
      );

      // 09:00, 10:00 (shared), 11:00 — deduplicated = 3 unique slots.
      expect(slots, hasLength(3));
      expect(slots[0], slot(2026, 6, 1, 9, 0));
      expect(slots[1], slot(2026, 6, 1, 10, 0));
      expect(slots[2], slot(2026, 6, 1, 11, 0));
    });

    // ADR-7: all generated slots have second == 0, millisecond == 0,
    // microsecond == 0 (minute precision invariant).
    test('ADR-7: all generated slots are minute-precise', () {
      final rule = AvailabilityRule(
        id: 'r1',
        trainerId: 'tA',
        dayOfWeek: 1,
        startHour: 9,
        startMinute: 0,
        endHour: 11,
        endMinute: 0,
        slotDurationMin: 30,
      );

      final slots = computeFreeSlots(
        rules: [rule],
        overrides: [],
        existingAppointments: [],
        forDate: kMonday,
      );

      for (final s in slots) {
        expect(s.second, 0, reason: 'slot $s has non-zero second');
        expect(s.millisecond, 0, reason: 'slot $s has non-zero millisecond');
        expect(s.microsecond, 0, reason: 'slot $s has non-zero microsecond');
      }
    });

    // Cancelled appointments do NOT remove the slot from free list.
    test('cancelled appointment does not remove slot', () {
      final rule = AvailabilityRule(
        id: 'r1',
        trainerId: 'tA',
        dayOfWeek: 1,
        startHour: 9,
        startMinute: 0,
        endHour: 10,
        endMinute: 0,
        slotDurationMin: 60,
      );
      final cancelled = Appointment(
        id: 'tA_${slot(2026, 6, 1, 9, 0).millisecondsSinceEpoch}',
        trainerId: 'tA',
        athleteId: 'aB',
        athleteDisplayName: 'Juan',
        startsAt: slot(2026, 6, 1, 9, 0),
        durationMin: 60,
        status: AppointmentStatus.cancelled,
      );

      final slots = computeFreeSlots(
        rules: [rule],
        overrides: [],
        existingAppointments: [cancelled],
        forDate: kMonday,
      );

      // Slot at 09:00 is free (only cancelled, not confirmed).
      expect(slots, hasLength(1));
      expect(slots.single, slot(2026, 6, 1, 9, 0));
    });
  });
}
