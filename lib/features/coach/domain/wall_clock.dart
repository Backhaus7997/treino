/// Wall-clock "now" for the Coach appointments feature.
///
/// ADR-7: [Appointment.startsAt] is stored as *wall-clock UTC* — the trainer's
/// local picker time (year/month/day/hour/minute) written straight into a
/// UTC-flagged [DateTime] with no timezone conversion. Comparing such a value
/// against a REAL UTC instant (`DateTime.now().toUtc()`) is off by the local
/// offset — a fixed 3h in Argentina (UTC-3) — which pulls sessions out of
/// "upcoming" 3h early, shrinks the 24h cancellation window to 21h, and shifts
/// the Hoy/Mañana labels. To compare correctly, "now" must be expressed in the
/// SAME wall-clock frame: the device-local calendar fields, labelled UTC.
///
/// This mirrors the inline pattern already used by `createRecurringByTrainer`
/// (appointment_repository.dart), `_submitSingle` (new_session_sheet.dart) and
/// `day_timeline.dart`. Use it for EVERY comparison against `startsAt`
/// (QA-COA-003).
///
/// The optional [now] parameter exists so tests can inject a fixed clock; it
/// defaults to `DateTime.now()` (device-local).
///
/// NOTE: this is intentionally distinct from `argentinaNow()` (a fixed UTC-3
/// offset from real UTC — see core/utils/argentina_time.dart), which is
/// reserved for ART calendar day-bucketing. `startsAt` comparisons use
/// wall-clock-vs-wall-clock; in Argentina the two coincide.
library;

/// Returns "now" as a wall-clock UTC [DateTime] — the device-local calendar
/// fields (down to the minute) re-labelled as UTC. See the library doc above.
DateTime nowWall({DateTime? now}) {
  final n = now ?? DateTime.now();
  return DateTime.utc(n.year, n.month, n.day, n.hour, n.minute);
}
