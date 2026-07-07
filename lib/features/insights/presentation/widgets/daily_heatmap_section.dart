// IMPORTANT: This widget MUST NOT import app_l10n.dart (same R3 rule as
// exercise_progression_section.dart / SCENARIO-PROG-11C). All user-visible
// strings are injected via [DailyHeatmapSectionLabels]. The mobile coach
// shell resolves them from AppL10n; the web coach_hub shell passes hardcoded
// Spanish strings.
//
// [AD5][REQ:heat-map-per-day] Shared section-level widget so BOTH coach
// shells render the alumno's per-day body heat-map + day-strip + per-day
// summary identically given the same data (same dedup pattern as AD1's
// ExerciseProgressionSection) — thin wrappers per shell inject their own
// label bag, the section itself owns the `_selectedDay` state and all
// provider wiring.
//
// Explicit [athleteId] flows into `athleteDayInsightsProvider` /
// `athleteLast7DaysInsightsProvider` — NEVER `currentUidProvider`. Those
// providers are uid-explicit by design (PR2a) specifically so this section
// can reuse them verbatim for a coach viewing an alumno that is NOT the
// signed-in user.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/day_insights_providers.dart';
import '../../domain/muscle_group.dart';
import 'body_silhouette_placeholder.dart';
import 'day_strip_labels.dart';
import 'day_strip_navigator.dart';

/// Plain-string label bag for [DailyHeatmapSection]. NEVER imports AppL10n
/// (same rule as [ExerciseProgressionSectionLabels]).
@immutable
class DailyHeatmapSectionLabels {
  const DailyHeatmapSectionLabels({
    required this.sectionTitle,
    required this.dayStripLabels,
  });

  /// E.g. 'MÚSCULOS DEL DÍA'.
  final String sectionTitle;

  /// Forwarded to [DayStripNavigator].
  final DayStripLabels dayStripLabels;
}

/// Per-day body heat-map + day-strip navigator + per-day muscle-group
/// summary — shared between the athlete's own Insights screen (2a, inlined
/// as `_DailyMusclesCard`) and BOTH coach shells' athlete-detail screens
/// (2b, this widget).
///
/// [targetByGroup] is deliberately left at [BodySilhouettePlaceholder]'s
/// default (`{}`) — see PR2a's apply-progress "Design decision on
/// intensity": a weekly/routine target as a per-day denominator would
/// visually under-tint every fully-trained day. Trained groups render at the
/// existing orphan-intensity fallback, a binary trained/untrained signal.
/// This is a documented deviation, not an oversight — do not "fix" it here.
class DailyHeatmapSection extends StatefulWidget {
  const DailyHeatmapSection({
    super.key,
    required this.athleteId,
    required this.labels,
  });

  final String athleteId;
  final DailyHeatmapSectionLabels labels;

  @override
  State<DailyHeatmapSection> createState() => _DailyHeatmapSectionState();
}

class _DailyHeatmapSectionState extends State<DailyHeatmapSection> {
  late DateTime _selectedDay = _todayOnly();

  static DateTime _todayOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final palette = AppPalette.of(context);
        final labels = widget.labels;
        final athleteId = widget.athleteId;

        final stripAsync =
            ref.watch(athleteLast7DaysInsightsProvider(athleteId));
        final selectedAsync = ref.watch(
          athleteDayInsightsProvider((uid: athleteId, day: _selectedDay)),
        );

        return Container(
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labels.sectionTitle,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              stripAsync.when(
                loading: () => const SizedBox(
                  height: 64,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (days) => DayStripNavigator(
                  days: days,
                  selectedDay: _selectedDay,
                  onDaySelected: (day) => setState(() => _selectedDay = day),
                  labels: labels.dayStripLabels,
                ),
              ),
              const SizedBox(height: 14),
              selectedAsync.when(
                loading: () => const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                // [UX-back-view] `showBack: true` renders bodyfront +
                // bodyback side by side — that pair needs more horizontal
                // room than the old single-body 160px column had next to
                // it. Stacked (silhouette full-width ABOVE the sets list)
                // instead of the old Row-beside-list layout, mirroring how
                // the athlete's own `_DailyMusclesCard` (and home's
                // `EstaSemanaCard`) lay out the same `showBack: true`
                // silhouette — avoids a RenderFlex overflow at narrow
                // widths.
                data: (dayInsights) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BodySilhouettePlaceholder(
                      width: double.infinity,
                      height: 220,
                      showBack: true,
                      setsByGroup: dayInsights.setsByGroup,
                      label: dayInsights.isEmpty
                          ? labels.dayStripLabels.emptyDayHint
                          : null,
                    ),
                    const SizedBox(height: 14),
                    for (final group in MuscleGroupDisplay.displayOrder)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _MuscleSetsRow(
                          group: group,
                          sets: dayInsights.setsByGroup[group] ?? 0,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MuscleSetsRow extends StatelessWidget {
  const _MuscleSetsRow({required this.group, required this.sets});
  final MuscleGroupDisplay group;
  final int sets;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasSets = sets > 0;
    final dotColor = hasSets ? palette.accent : palette.textMuted;
    final labelColor = hasSets ? palette.textPrimary : palette.textMuted;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            group.displayLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.8,
              color: labelColor,
            ),
          ),
        ),
        Text(
          '$sets',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: labelColor,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'SETS',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 0.6,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}
