import 'dart:math' as math;

import '../domain/appointment.dart';

/// Overlap layout for the Coach agenda timelines.
///
/// Extracted verbatim from `widgets/day_timeline.dart` so the packing algorithm
/// can be unit-tested with plain `test()` instead of only through a forced
/// viewport `WidgetTester`, and reused by the Coach Hub web weekly grid.
/// Pure presentation helper — same role as `AgendaFormatters`, no Flutter
/// import.
///
/// Overlaps are a FEATURE: appointments use an auto-id precisely so several
/// athletes can share a start time, so packing them side by side is mandatory.
///
/// ADR-7: [Appointment.startsAt] is wall-clock UTC. This algorithm keys purely
/// on `hour * 60 + minute` and is therefore day-blind — callers must partition
/// by calendar day BEFORE calling [computeSessionLayout].
///
/// Placement of one session inside its overlap cluster.
class SessionLayout {
  SessionLayout({required this.appointment});

  final Appointment appointment;

  /// 0-based lane inside the cluster.
  int columnIndex = 0;

  /// Lane count shared by every session of the cluster (uniform block width).
  int columnCount = 1;
}

/// Assigns each session in [sessions] a lane so overlapping sessions render
/// side by side.
///
/// Returns the sessions SORTED (earlier start first, ties broken by longer
/// duration first) — not in input order.
List<SessionLayout> computeSessionLayout(List<Appointment> sessions) {
  if (sessions.isEmpty) return [];

  // Sort: earlier start first; ties broken by longer duration first.
  final sorted = sessions.map((a) => SessionLayout(appointment: a)).toList()
    ..sort((a, b) {
      final aStart =
          a.appointment.startsAt.hour * 60 + a.appointment.startsAt.minute;
      final bStart =
          b.appointment.startsAt.hour * 60 + b.appointment.startsAt.minute;
      if (aStart != bStart) return aStart.compareTo(bStart);
      return b.appointment.durationMin.compareTo(a.appointment.durationMin);
    });

  // Build clusters of transitively-overlapping sessions.
  final clusters = <List<SessionLayout>>[];
  final clusterMaxEnd = <int>[];

  for (final layout in sorted) {
    final appt = layout.appointment;
    final startMin = appt.startsAt.hour * 60 + appt.startsAt.minute;
    final endMin = startMin + appt.durationMin;

    if (clusters.isNotEmpty && startMin < clusterMaxEnd.last) {
      clusters.last.add(layout);
      clusterMaxEnd[clusterMaxEnd.length - 1] =
          math.max(clusterMaxEnd.last, endMin);
    } else {
      clusters.add([layout]);
      clusterMaxEnd.add(endMin);
    }
  }

  // For each cluster assign columns greedily.
  for (final cluster in clusters) {
    // Each entry: last end minute of the column.
    final columnEnds = <int>[];

    for (final layout in cluster) {
      final appt = layout.appointment;
      final startMin = appt.startsAt.hour * 60 + appt.startsAt.minute;
      final endMin = startMin + appt.durationMin;

      int assignedCol = -1;
      for (int ci = 0; ci < columnEnds.length; ci++) {
        if (columnEnds[ci] <= startMin) {
          assignedCol = ci;
          columnEnds[ci] = endMin;
          break;
        }
      }
      if (assignedCol == -1) {
        assignedCol = columnEnds.length;
        columnEnds.add(endMin);
      }

      layout.columnIndex = assignedCol;
    }

    // All sessions in cluster share the same column count.
    final colCount = columnEnds.length;
    for (final layout in cluster) {
      layout.columnCount = colCount;
    }
  }

  return sorted;
}
