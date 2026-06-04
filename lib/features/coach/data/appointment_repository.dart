import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/agenda_exceptions.dart';
import '../domain/appointment.dart';

/// Firestore-backed repository for booking and managing appointments.
///
/// Appointments are stored at `appointments/{trainerId}_{startsAtMs}`.
/// The deterministic doc ID follows ADR-5 + ADR-7.
class AppointmentRepository {
  AppointmentRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _appointments =>
      _firestore.collection('appointments');

  // ─── book ─────────────────────────────────────────────────────────────────
  //
  // ADR-5: use a Firestore transaction to avoid race conditions.
  // ADR-1: if the slot was previously cancelled, flip status → confirmed,
  //        update athlete fields, clear cancelledAt/cancelledBy, and
  //        PRESERVE the cancellationLog array (audit trail).
  // SCENARIO-489: new slot → create doc with status=confirmed.
  // SCENARIO-490: slot exists status=confirmed → throw SlotAlreadyTakenException.
  // SCENARIO-491-amended: slot exists status=cancelled → flip, preserve log.
  // SCENARIO-496: doc ID is exactly '${trainerId}_${startsAt.millisecondsSinceEpoch}'.

  Future<Appointment> book({
    required String trainerId,
    required String athleteId,
    required String athleteDisplayName,
    required DateTime startsAt,
    required int durationMin,
  }) async {
    final startsAtMs = startsAt.millisecondsSinceEpoch;
    final docId = '${trainerId}_$startsAtMs';
    final docRef = _appointments.doc(docId);

    return _firestore.runTransaction<Appointment>((txn) async {
      final snap = await txn.get(docRef);

      if (snap.exists) {
        final data = snap.data()!;
        final status = data['status'] as String?;

        if (status == 'confirmed') {
          throw SlotAlreadyTakenException(docId);
        }

        // status == 'cancelled' → ADR-1 flip.
        // Do NOT include 'cancellationLog' in the update map to preserve it.
        txn.update(docRef, {
          'status': 'confirmed',
          'athleteId': athleteId,
          'athleteDisplayName': athleteDisplayName,
          'cancelledAt': null,
          'cancelledBy': null,
        });

        // Reconstruct the updated Appointment from existing + new fields.
        final updatedData = {
          ...data,
          'id': docId,
          'status': 'confirmed',
          'athleteId': athleteId,
          'athleteDisplayName': athleteDisplayName,
          'cancelledAt': null,
          'cancelledBy': null,
        };
        return Appointment.fromJson(updatedData);
      } else {
        // New slot — create.
        final appt = Appointment.create(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: startsAt,
          durationMin: durationMin,
        );
        txn.set(docRef, appt.toJson());
        return appt;
      }
    });
  }

  // ─── createByTrainer ────────────────────────────────────────────────────────
  //
  // Trainer-driven scheduling (new model 2026-06-03): the trainer registers a
  // session directly. Uses a Firestore AUTO-ID — NOT the deterministic
  // `{trainerId}_{startsAtMs}` slot id — so the same time can hold more than one
  // athlete (overlapping sessions are allowed by design). No race transaction:
  // there is no contention, the trainer owns the schedule.

  Future<Appointment> createByTrainer({
    required String trainerId,
    required String athleteId,
    required String athleteDisplayName,
    required DateTime startsAt,
    required int durationMin,
    String? noteBefore,
  }) async {
    // Minute precision, wall-clock UTC (ADR-7 convention — no toLocal()).
    final normalized = DateTime.utc(
      startsAt.year,
      startsAt.month,
      startsAt.day,
      startsAt.hour,
      startsAt.minute,
    );
    final docRef = _appointments.doc(); // auto-id
    final trimmedNote = noteBefore?.trim();
    final appt = Appointment(
      id: docRef.id,
      trainerId: trainerId,
      athleteId: athleteId,
      athleteDisplayName: athleteDisplayName,
      startsAt: normalized,
      durationMin: durationMin,
      status: AppointmentStatus.confirmed,
      noteBefore:
          (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote,
    );
    await docRef.set(appt.toJson());
    return appt;
  }

  // ─── createRecurringByTrainer ─────────────────────────────────────────────────
  //
  // Materializes one session per matching weekday within [fromDate]..[untilDate]
  // (inclusive, date-level), all at [startHour]:[startMinute] for [durationMin].
  // Occurrences in the past (before "now", wall-clock) are skipped. Each session
  // gets an auto-id; the whole set is written in a single WriteBatch. Returns how
  // many sessions were created.

  Future<int> createRecurringByTrainer({
    required String trainerId,
    required String athleteId,
    required String athleteDisplayName,
    required Set<int> weekdays, // DateTime.weekday: 1=Mon .. 7=Sun
    required int startHour,
    required int startMinute,
    required int durationMin,
    required DateTime fromDate,
    required DateTime untilDate,
    String? noteBefore,
  }) async {
    final now = DateTime.now();
    final nowWall =
        DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
    final trimmedNote = noteBefore?.trim();
    final note =
        (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote;

    final batch = _firestore.batch();
    var count = 0;
    // One shared id for every occurrence of this series, so the trainer can
    // later "cancel all future" without a separate series document.
    final recurringId = _appointments.doc().id;

    var cursor = DateTime.utc(fromDate.year, fromDate.month, fromDate.day);
    final end = DateTime.utc(untilDate.year, untilDate.month, untilDate.day);

    while (!cursor.isAfter(end)) {
      if (weekdays.contains(cursor.weekday)) {
        final startsAt = DateTime.utc(
            cursor.year, cursor.month, cursor.day, startHour, startMinute);
        if (startsAt.isAfter(nowWall)) {
          final docRef = _appointments.doc(); // auto-id
          final appt = Appointment(
            id: docRef.id,
            trainerId: trainerId,
            athleteId: athleteId,
            athleteDisplayName: athleteDisplayName,
            startsAt: startsAt,
            durationMin: durationMin,
            status: AppointmentStatus.confirmed,
            noteBefore: note,
            recurringId: recurringId,
          );
          batch.set(docRef, appt.toJson());
          count++;
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    if (count > 0) {
      await batch.commit();
    }
    return count;
  }

  // ─── cancel ───────────────────────────────────────────────────────────────
  //
  // REQ-007: cancellation must be >24h before startsAt.
  // ADR-1: appends to cancellationLog, sets cancelledAt/cancelledBy.
  // SCENARIO-492: cancellation succeeds when >24h ahead.
  // SCENARIO-493: throws CancellationTooLateException when <24h ahead.

  Future<void> cancel({
    required Appointment appointment,
    required String actorUid,
    String? reason,
  }) async {
    final remaining = appointment.startsAt.difference(DateTime.now().toUtc());
    if (remaining < const Duration(hours: 24)) {
      throw CancellationTooLateException(appointment.id);
    }

    final docRef = _appointments.doc(appointment.id);
    final logEntry = <String, Object?>{
      'byUid': actorUid,
      'atMs': DateTime.now().toUtc().millisecondsSinceEpoch,
      if (reason != null) 'reason': reason,
    };

    await docRef.update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': actorUid,
      'cancellationLog': FieldValue.arrayUnion([logEntry]),
    });
  }

  // ─── cancelFutureSeries ─────────────────────────────────────────────────────
  //
  // Cancels every FUTURE confirmed occurrence of the recurring series
  // [recurringId] owned by [trainerId] that is still >24h away (same gate as the
  // per-session cancel + Firestore rules Path 1). Occurrences within 24h or
  // already past are left untouched. Returns how many were cancelled.

  Future<int> cancelFutureSeries({
    required String recurringId,
    required String trainerId,
    required String actorUid,
    String? reason,
  }) async {
    final now = DateTime.now();
    final nowWall =
        DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
    final realNow = now.toUtc();

    // Reuses the existing (trainerId, status, startsAt) composite index.
    final snap = await _appointments
        .where('trainerId', isEqualTo: trainerId)
        .where('status', isEqualTo: 'confirmed')
        .where('startsAt', isGreaterThanOrEqualTo: Timestamp.fromDate(nowWall))
        .get();

    final batch = _firestore.batch();
    var count = 0;
    for (final d in snap.docs) {
      final appt = Appointment.fromJson({...d.data(), 'id': d.id});
      if (appt.recurringId != recurringId) continue;
      // Only the occurrences the rule will accept (>24h ahead). The batch is
      // atomic, so a single <24h write would reject the whole commit — a small
      // safety margin absorbs the client→server latency near the boundary.
      if (appt.startsAt.difference(realNow) <=
          const Duration(hours: 24, minutes: 2)) {
        continue;
      }
      batch.update(d.reference, {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelledBy': actorUid,
        'cancellationLog': FieldValue.arrayUnion([
          <String, Object?>{
            'byUid': actorUid,
            'atMs': realNow.millisecondsSinceEpoch,
            if (reason != null) 'reason': reason,
          },
        ]),
      });
      count++;
    }
    if (count > 0) {
      await batch.commit();
    }
    return count;
  }

  // ─── updateNotes ──────────────────────────────────────────────────────────

  /// Trainer-only: update the coaching notes on an appointment. Other fields
  /// stay untouched (Firestore rules enforce status/athleteId/trainerId/startsAt
  /// immutability for this path).
  Future<void> updateNotes({
    required String appointmentId,
    String? noteBefore,
    String? noteAfter,
  }) async {
    await _appointments.doc(appointmentId).update({
      'noteBefore': noteBefore,
      'noteAfter': noteAfter,
    });
  }

  // ─── watchForAthlete ──────────────────────────────────────────────────────
  //
  // SCENARIO-494: streams confirmed appointments for athleteId.

  Stream<List<Appointment>> watchForAthlete(String athleteId) {
    return _appointments
        .where('athleteId', isEqualTo: athleteId)
        .where('status', isEqualTo: 'confirmed')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Appointment.fromJson({...d.data(), 'id': d.id}))
            .toList());
  }

  // ─── watchForTrainer ──────────────────────────────────────────────────────
  //
  // SCENARIO-495: streams confirmed appointments for trainerId in date range.

  Stream<List<Appointment>> watchForTrainer(
    String trainerId, {
    required DateTime fromDate,
    required DateTime toDate,
  }) {
    return _appointments
        .where('trainerId', isEqualTo: trainerId)
        .where('status', isEqualTo: 'confirmed')
        .where('startsAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(fromDate.toUtc()))
        .where('startsAt',
            isLessThanOrEqualTo: Timestamp.fromDate(toDate.toUtc()))
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Appointment.fromJson({...d.data(), 'id': d.id}))
            .toList());
  }
}
