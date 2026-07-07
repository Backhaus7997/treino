/// Argentina wall-clock helpers.
///
/// Argentina (America/Argentina/Buenos_Aires) has observed UTC-3 year-round
/// with NO daylight saving since 2009, so a constant offset is correct and the
/// Dart client stays byte-identical with the Cloud Functions.
///
/// CALENDAR concepts — payment period keys, "today"/day buckets, month/week
/// boundaries — MUST be derived in ART, not UTC: between 21:00–23:59 ART the
/// UTC day is already tomorrow, so UTC-day math mis-buckets (a session finished
/// at 23:00 ART lands on "today", though in UTC it is already tomorrow).
/// INSTANTS (createdAt, paidAt, "has it ended yet") stay in true UTC — only the
/// calendar identity shifts.
library;

/// Argentina's fixed UTC offset (UTC-3, no DST).
const argentinaUtcOffset = Duration(hours: 3);

/// Shifts a UTC instant into Argentina wall-clock: the returned [DateTime] is
/// still UTC-flagged, but its calendar fields (year/month/day/weekday) read as
/// ART. Pass a UTC instant (e.g. `x.toUtc()`).
DateTime toArgentina(DateTime utc) => utc.subtract(argentinaUtcOffset);

/// "Now" in Argentina wall-clock. Derive period keys and day buckets from this,
/// never `DateTime.now().toUtc()`.
DateTime argentinaNow() => toArgentina(DateTime.now().toUtc());
