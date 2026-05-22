import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/availability_repository.dart';
import '../data/appointment_repository.dart';
import '../domain/appointment.dart';
import '../domain/availability_override.dart';
import '../domain/availability_rule.dart';
import '../domain/compute_free_slots.dart';

part 'agenda_providers.freezed.dart';

// ─── Key classes for multi-param providers ────────────────────────────────

/// Key for [overridesStreamProvider] — wraps trainerId + date range.
@freezed
class OverridesKey with _$OverridesKey {
  const factory OverridesKey({
    required String trainerId,
    required DateTime fromDate,
    required DateTime toDate,
  }) = _OverridesKey;
}

/// Key for [trainerAppointmentsStreamProvider] — wraps trainerId + date range.
@freezed
class TrainerAppointmentsKey with _$TrainerAppointmentsKey {
  const factory TrainerAppointmentsKey({
    required String trainerId,
    required DateTime fromDate,
    required DateTime toDate,
  }) = _TrainerAppointmentsKey;
}

/// Key for [freeSlotsProvider] — combines all needed inputs.
@freezed
class FreeSlotsKey with _$FreeSlotsKey {
  const factory FreeSlotsKey({
    required String trainerId,
    required DateTime forDate,
    required DateTime fromDate,
    required DateTime toDate,
  }) = _FreeSlotsKey;
}

// ─── Repository providers ─────────────────────────────────────────────────

final availabilityRepositoryProvider = Provider<AvailabilityRepository>(
  (ref) => AvailabilityRepository(firestore: ref.read(firestoreProvider)),
);

final appointmentRepositoryProvider = Provider<AppointmentRepository>(
  (ref) => AppointmentRepository(firestore: ref.read(firestoreProvider)),
);

// ─── Stream providers ─────────────────────────────────────────────────────

/// Real-time stream of availability rules for a trainer. ADR-3.
final availabilityRulesStreamProvider = StreamProvider.autoDispose
    .family<List<AvailabilityRule>, String>((ref, trainerId) {
  return ref
      .read(availabilityRepositoryProvider)
      .watchRules(trainerId);
});

/// Real-time stream of overrides for a trainer within a date range. ADR-3.
final overridesStreamProvider = StreamProvider.autoDispose
    .family<List<AvailabilityOverride>, OverridesKey>((ref, key) {
  return ref
      .read(availabilityRepositoryProvider)
      .watchOverrides(key.trainerId, key.fromDate, key.toDate);
});

/// Real-time stream of confirmed appointments for an athlete. ADR-3.
final appointmentsForAthleteStreamProvider = StreamProvider.autoDispose
    .family<List<Appointment>, String>((ref, athleteId) {
  return ref
      .read(appointmentRepositoryProvider)
      .watchForAthlete(athleteId);
});

/// Real-time stream of confirmed appointments for a trainer within a date range. ADR-3.
final trainerAppointmentsStreamProvider = StreamProvider.autoDispose
    .family<List<Appointment>, TrainerAppointmentsKey>((ref, key) {
  return ref
      .read(appointmentRepositoryProvider)
      .watchForTrainer(
        key.trainerId,
        fromDate: key.fromDate,
        toDate: key.toDate,
      );
});

// ─── Derived providers ────────────────────────────────────────────────────

/// Computes free bookable slots for a specific date.
///
/// Derived from [availabilityRulesStreamProvider], [overridesStreamProvider],
/// and [trainerAppointmentsStreamProvider] via [computeFreeSlots]. ADR-2, ADR-3.
final freeSlotsProvider = Provider.autoDispose
    .family<List<DateTime>, FreeSlotsKey>((ref, key) {
  final rulesAsync = ref.watch(availabilityRulesStreamProvider(key.trainerId));
  final overridesAsync = ref.watch(overridesStreamProvider(
    OverridesKey(
      trainerId: key.trainerId,
      fromDate: key.fromDate,
      toDate: key.toDate,
    ),
  ));
  final appointmentsAsync = ref.watch(trainerAppointmentsStreamProvider(
    TrainerAppointmentsKey(
      trainerId: key.trainerId,
      fromDate: key.fromDate,
      toDate: key.toDate,
    ),
  ));

  final rules = rulesAsync.valueOrNull ?? const [];
  final overrides = overridesAsync.valueOrNull ?? const [];
  final appointments = appointmentsAsync.valueOrNull ?? const [];

  return computeFreeSlots(
    rules: rules,
    overrides: overrides,
    existingAppointments: appointments,
    forDate: key.forDate,
  );
});
