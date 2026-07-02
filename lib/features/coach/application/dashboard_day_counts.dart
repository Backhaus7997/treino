/// Pure helpers for classifying today's appointments into the dashboard summary.
///
/// Lifted verbatim from [trainer_dashboard_tab.dart] so the same logic is
/// accessible from both the mobile trainer dashboard and the web Coach Hub
/// dashboard without cross-layer dependencies.
///
/// trainer_dashboard_tab.dart re-exports both symbols so
/// [trainer_dashboard_day_counts_test.dart] (which imports from that file)
/// continues to compile without modification.
library;

import '../domain/appointment.dart';

/// Immutable result of the "Resumen del día" classification.
class DashboardDayCounts {
  const DashboardDayCounts({
    required this.pending,
    required this.done,
    required this.cancelled,
  });

  final int pending;
  final int done;
  final int cancelled;
}

/// Classifies today's appointments into pending / done / cancelled for the
/// dashboard summary.
///
/// A confirmed session counts as `done` only once it has actually ended
/// (`startsAt + durationMin`); while it has not yet ended — including while it
/// is in progress — it counts as `pending`. [now] must be UTC, matching the
/// UTC [Appointment.startsAt].
DashboardDayCounts dashboardDayCounts(
  List<Appointment> all,
  DateTime now,
) {
  final todayAppts = all.where((a) => _isSameLocalDay(a.startsAt, now)).toList();
  DateTime endOf(Appointment a) =>
      a.startsAt.add(Duration(minutes: a.durationMin));
  final pending = todayAppts
      .where((a) =>
          a.status == AppointmentStatus.confirmed && endOf(a).isAfter(now))
      .length;
  final done = todayAppts
      .where((a) =>
          a.status == AppointmentStatus.confirmed && !endOf(a).isAfter(now))
      .length;
  final cancelled =
      todayAppts.where((a) => a.status == AppointmentStatus.cancelled).length;
  return DashboardDayCounts(
    pending: pending,
    done: done,
    cancelled: cancelled,
  );
}

bool _isSameLocalDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
