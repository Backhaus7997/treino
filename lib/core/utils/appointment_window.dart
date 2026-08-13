/// QA-COA-007 / QA-HOME-009 — bounds of the rolling appointment window shared
/// by the coach agenda tab, the trainer dashboard, and the coach-hub web
/// agenda.
///
/// The window spans from the first day of the PREVIOUS month through the first
/// day of the same month next year. Dart's [DateTime] normalizes an
/// out-of-range month, so passing month `0` yields December of the prior year
/// — **no clamp is needed**.
///
/// The old inline expression `now.month - 1 < 1 ? 1 : now.month - 1` clamped
/// January back to January 1st of the current year, so throughout January the
/// previous December's appointments dropped out of the stream (empty calendar
/// dots + timeline, and missing dashboard counts / "próximas sesiones").
///
/// [now] is expected in UTC (callers pass `DateTime.now().toUtc()`); the bounds
/// are UTC to match the appointment `startsAt` range filter.
({DateTime from, DateTime to}) rollingAppointmentWindow(DateTime now) => (
      from: DateTime.utc(now.year, now.month - 1, 1),
      to: DateTime.utc(now.year + 1, now.month, 1),
    );
