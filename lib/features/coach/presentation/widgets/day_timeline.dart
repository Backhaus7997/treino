import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/agenda_providers.dart';
import '../../domain/appointment.dart';
import '../agenda_formatters.dart';
import 'new_session_sheet.dart';
import 'session_detail_sheet.dart';

// ── Layout constants ──────────────────────────────────────────────────────────

const double _kHourHeight = 64.0;
const double _kPxPerMin = _kHourHeight / 60.0;
const double _kGutter = 52.0;
const double _kMinBlockH = 30.0;
const double _kRightPad = 8.0;

// ── Internal data classes ─────────────────────────────────────────────────────

class _SessionLayout {
  _SessionLayout({required this.appointment});

  final Appointment appointment;
  int columnIndex = 0;
  int columnCount = 1;
}

// ── DayTimeline ───────────────────────────────────────────────────────────────

/// A Microsoft-Teams-style day timeline that renders confirmed appointments
/// as blocks on an hour grid for the given [day]. Renders below the month
/// calendar inside [TrainerAgendaTab].
///
/// ADR-7: [startsAt] is wall-clock UTC — UTC fields map directly to local
/// clock time. The now-line uses [DateTime.now()] local fields.
class DayTimeline extends ConsumerStatefulWidget {
  const DayTimeline({
    super.key,
    required this.trainerId,
    required this.day,
    required this.rangeFrom,
    required this.rangeTo,
  });

  /// Trainer whose appointments are displayed.
  final String trainerId;

  /// The calendar day being displayed. Only y/m/d are used.
  final DateTime day;

  /// Stream window start — same range passed to the appointments provider.
  final DateTime rangeFrom;

  /// Stream window end — same range passed to the appointments provider.
  final DateTime rangeTo;

  @override
  ConsumerState<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends ConsumerState<DayTimeline> {
  final ScrollController _controller = ScrollController();

  /// Auto-scroll once per displayed day (reset when the day changes), after
  /// the appointment data lands so the hour range (and thus the offset) is
  /// final.
  bool _didAutoScroll = false;

  @override
  void didUpdateWidget(DayTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = oldWidget.day;
    final n = widget.day;
    if (o.year != n.year || o.month != n.month || o.day != n.day) {
      _didAutoScroll = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final apptAsync = ref.watch(
      trainerAppointmentsStreamProvider(
        TrainerAppointmentsKey(
          trainerId: widget.trainerId,
          fromDate: widget.rangeFrom,
          toDate: widget.rangeTo,
        ),
      ),
    );

    // Gracefully degrade while loading — still show the empty grid.
    final allAppointments = apptAsync.valueOrNull ?? const <Appointment>[];

    // Filter: confirmed AND same y/m/d (using UTC fields per ADR-7).
    final sessions = allAppointments.where((a) {
      if (a.status != AppointmentStatus.confirmed) return false;
      final d = a.startsAt;
      return d.year == widget.day.year &&
          d.month == widget.day.month &&
          d.day == widget.day.day;
    }).toList();

    // ── Hour range ────────────────────────────────────────────────────────────
    int startHour = 7;
    int endHour = 22;

    for (final s in sessions) {
      startHour = math.min(startHour, s.startsAt.hour);
      final endM = s.startsAt.hour * 60 + s.startsAt.minute + s.durationMin;
      endHour = math.max(endHour, (endM / 60).ceil());
    }

    startHour = startHour.clamp(0, 23);
    endHour = endHour.clamp(1, 24);
    if (endHour <= startHour) endHour = startHour + 1;

    final totalMin = (endHour - startHour) * 60;
    final contentHeight = totalMin * _kPxPerMin;

    // ── "Now" line ────────────────────────────────────────────────────────────
    final now = DateTime.now(); // local clock
    final nowMinutes = now.hour * 60 + now.minute;
    final isToday = now.year == widget.day.year &&
        now.month == widget.day.month &&
        now.day == widget.day.day;
    final showNowLine =
        isToday && nowMinutes >= startHour * 60 && nowMinutes <= endHour * 60;

    // Wall-clock "now" for isPast comparisons (ADR-7).
    final nowWall =
        DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);

    // ── Overlap layout ────────────────────────────────────────────────────────
    final layouts = _computeLayout(sessions);

    // ── Auto-scroll to "now" (today) or the first session, once data lands ──
    // Runs once per displayed day. We wait for hasValue so the hour range is
    // final (early sessions can lower startHour and shift every offset).
    if (!_didAutoScroll && apptAsync.hasValue) {
      _didAutoScroll = true;
      double target = 0;
      if (showNowLine) {
        // Put "now" ~100px below the top so there's context above it.
        target = (nowMinutes - startHour * 60) * _kPxPerMin - 100;
      } else if (sessions.isNotEmpty) {
        final firstStart = sessions
            .map((s) => s.startsAt.hour * 60 + s.startsAt.minute)
            .reduce(math.min);
        target = (firstStart - startHour * 60) * _kPxPerMin - 40;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final max = _controller.position.maxScrollExtent;
        _controller.jumpTo(target.clamp(0.0, max));
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return SingleChildScrollView(
          controller: _controller,
          child: SizedBox(
            height: contentHeight,
            child: Stack(
              children: [
                // ── a. Background tap layer ───────────────────────────────────
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final localY = details.localPosition.dy;
                      final mins = startHour * 60 + (localY / _kPxPerMin);
                      final rounded = (mins / 15).round() * 15;
                      final h = (rounded ~/ 60).clamp(0, 23);
                      final m = rounded % 60;
                      _openNewSessionSheet(
                        context,
                        TimeOfDay(hour: h, minute: m),
                      );
                    },
                    child: const SizedBox.expand(),
                  ),
                ),

                // ── b. Hour grid ──────────────────────────────────────────────
                ..._buildGrid(
                  palette: palette,
                  startHour: startHour,
                  endHour: endHour,
                ),

                // ── c. Session blocks ─────────────────────────────────────────
                ..._buildBlocks(
                  context: context,
                  ref: ref,
                  layouts: layouts,
                  startHour: startHour,
                  totalWidth: totalWidth,
                  palette: palette,
                  nowWall: nowWall,
                ),

                // ── d. Now line ───────────────────────────────────────────────
                if (showNowLine)
                  _buildNowLine(
                    palette: palette,
                    nowMinutes: nowMinutes,
                    startHour: startHour,
                    totalWidth: totalWidth,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Grid lines + labels ─────────────────────────────────────────────────────

  List<Widget> _buildGrid({
    required AppPalette palette,
    required int startHour,
    required int endHour,
  }) {
    final widgets = <Widget>[];

    for (int h = startHour; h <= endHour; h++) {
      final top = (h - startHour) * _kHourHeight;

      // Full-hour line
      widgets.add(
        Positioned(
          top: top,
          left: _kGutter,
          right: 0,
          child: Container(height: 1, color: palette.border),
        ),
      );

      // Hour label (positioned so the text sits just above the line)
      if (h < endHour || h == startHour) {
        widgets.add(
          Positioned(
            top: top - 8,
            left: 0,
            width: _kGutter - 8,
            child: Text(
              '${h.toString().padLeft(2, '0')}:00',
              textAlign: TextAlign.right,
              style: GoogleFonts.barlowCondensed(
                fontSize: 11,
                color: palette.textMuted,
              ),
            ),
          ),
        );
      }

      // Half-hour faint line
      if (h < endHour) {
        widgets.add(
          Positioned(
            top: top + _kHourHeight / 2,
            left: _kGutter,
            right: 0,
            child: Container(
              height: 1,
              color: palette.border.withAlpha(60),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  // ── Session blocks ──────────────────────────────────────────────────────────

  List<Widget> _buildBlocks({
    required BuildContext context,
    required WidgetRef ref,
    required List<_SessionLayout> layouts,
    required int startHour,
    required double totalWidth,
    required AppPalette palette,
    required DateTime nowWall,
  }) {
    final availW = totalWidth - _kGutter - _kRightPad;

    return layouts.map((layout) {
      final appt = layout.appointment;
      final startMin = appt.startsAt.hour * 60 + appt.startsAt.minute;
      final top = (startMin - startHour * 60) * _kPxPerMin;
      final blockHeight = math.max(appt.durationMin * _kPxPerMin, _kMinBlockH);
      final endsAt = appt.startsAt.add(Duration(minutes: appt.durationMin));

      final colW = availW / layout.columnCount;
      final left = _kGutter + layout.columnIndex * colW;
      final width = colW - 2;

      final isPast = appt.startsAt.isBefore(nowWall);

      // Name resolution via userPublicProfileProvider
      final profileAsync = ref.watch(userPublicProfileProvider(appt.athleteId));
      final rawName =
          profileAsync.valueOrNull?.displayName ?? appt.athleteDisplayName;
      final isRawUid = rawName.length >= 20 &&
          !rawName.contains(' ') &&
          RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(rawName);
      final athleteName =
          (isRawUid || rawName.trim().isEmpty) ? 'Alumno' : rawName;

      // Progressive disclosure by block height: the start time always shows,
      // then the name, then the end time last — each only when there's
      // vertical room, which keeps short blocks from overflowing.
      final fitsName = blockHeight >= 44;
      final fitsEnd = blockHeight >= 60;

      return Positioned(
        top: top,
        left: left,
        width: width,
        height: blockHeight,
        child: GestureDetector(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            backgroundColor: AppPalette.of(context).bgCard,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => SessionDetailSheet(
              appointment: appt,
              trainerId: widget.trainerId,
              isPast: isPast,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: palette.highlight.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent stripe
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: palette.highlight,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                ),
                // Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AgendaFormatters.formatTime(appt.startsAt),
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: palette.highlight,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (fitsName) ...[
                          const SizedBox(height: 2),
                          Text(
                            athleteName,
                            style: GoogleFonts.barlow(
                              fontSize: 11,
                              color: palette.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (fitsEnd) ...[
                          const SizedBox(height: 2),
                          Text(
                            AgendaFormatters.formatTime(endsAt),
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                              color: palette.highlight.withAlpha(180),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  // ── Now line ────────────────────────────────────────────────────────────────

  Widget _buildNowLine({
    required AppPalette palette,
    required int nowMinutes,
    required int startHour,
    required double totalWidth,
  }) {
    final top = (nowMinutes - startHour * 60) * _kPxPerMin - 1;
    const dotSize = 8.0;
    const dotLeft = _kGutter - dotSize / 2 - 6;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Horizontal line from gutter onward
            Positioned(
              left: _kGutter,
              right: 0,
              top: 0,
              child: Container(height: 2, color: palette.accent),
            ),
            // Circle dot in the gutter
            Positioned(
              left: dotLeft,
              top: -(dotSize / 2) + 1,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Open new session sheet ──────────────────────────────────────────────────

  void _openNewSessionSheet(BuildContext context, TimeOfDay initialTime) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => NewSessionSheet(
        initialDate: widget.day,
        initialTime: initialTime,
      ),
    );
  }
}

// ── Overlap layout algorithm ──────────────────────────────────────────────────

List<_SessionLayout> _computeLayout(List<Appointment> sessions) {
  if (sessions.isEmpty) return [];

  // Sort: earlier start first; ties broken by longer duration first.
  final sorted = sessions.map((a) => _SessionLayout(appointment: a)).toList()
    ..sort((a, b) {
      final aStart =
          a.appointment.startsAt.hour * 60 + a.appointment.startsAt.minute;
      final bStart =
          b.appointment.startsAt.hour * 60 + b.appointment.startsAt.minute;
      if (aStart != bStart) return aStart.compareTo(bStart);
      return b.appointment.durationMin.compareTo(a.appointment.durationMin);
    });

  // Build clusters of transitively-overlapping sessions.
  final clusters = <List<_SessionLayout>>[];
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
