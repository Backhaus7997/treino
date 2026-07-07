// IMPORTANT: This widget MUST NOT import app_l10n.dart (R3 / SCENARIO-PROG-11C
// convention, same as exercise_progression_chart.dart / _section.dart). All
// user-visible strings are injected via [PersonalRecordsListLabels]. The
// mobile caller resolves them from AppL10n; the web caller passes hardcoded
// Spanish strings.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../app/theme/app_palette.dart';
import '../../application/exercise_progression_aggregator.dart';
import '../../domain/exercise_progression.dart';

/// e.g. '10 mar 2025' (es_AR) / '10 Mar 2025' (en). Uses [DateTime]'s own
/// calendar fields directly — no toLocal() — matching the same convention as
/// exercise_progression_chart.dart's `_shortDate`.
String _dateWithYear(DateTime dt, String localeName) =>
    intl.DateFormat('d MMM yyyy', localeName).format(dt);

/// [AD2] The 1RM record is the only one requiring 0.5kg display rounding —
/// same convention as exercise_progression_chart.dart's `_formatMetricValue`.
String _formatValue(double value, {required bool isOneRepMax}) {
  final display = isOneRepMax ? roundToNearestHalfKg(value) : value;
  return display % 1 == 0
      ? display.toStringAsFixed(0)
      : display.toStringAsFixed(1);
}

/// Plain-string label bag for [PersonalRecordsList] — same R3 no-AppL10n
/// convention as [ExerciseProgressionChartLabels].
class PersonalRecordsListLabels {
  const PersonalRecordsListLabels({
    required this.sectionTitle,
    required this.heaviestWeightLabel,
    required this.oneRepMaxLabel,
    required this.bestSetVolumeLabel,
    required this.bestSessionVolumeLabel,
    required this.volumeUnit,
    required this.weightUnit,
    required this.emptyText,
    required this.localeName,
  });

  /// E.g. 'RÉCORDS PERSONALES'.
  final String sectionTitle;

  /// E.g. 'Peso máximo' — same label as the chart's Heaviest Weight metric.
  final String heaviestWeightLabel;

  /// E.g. '1RM'.
  final String oneRepMaxLabel;

  /// E.g. 'Mejor serie'.
  final String bestSetVolumeLabel;

  /// E.g. 'Volumen'.
  final String bestSessionVolumeLabel;

  /// E.g. 'kg·reps' — RD5, used by both volume record types.
  final String volumeUnit;

  /// E.g. 'kg' — used by both weight record types.
  final String weightUnit;

  /// Shown when [PersonalRecordsList.records] is empty.
  final String emptyText;

  /// Locale name for date formatting (e.g. 'es_AR', 'en').
  final String localeName;

  String labelFor(ProgressionRecordType type) {
    switch (type) {
      case ProgressionRecordType.heaviestWeight:
        return heaviestWeightLabel;
      case ProgressionRecordType.oneRepMax:
        return oneRepMaxLabel;
      case ProgressionRecordType.bestSetVolume:
        return bestSetVolumeLabel;
      case ProgressionRecordType.bestSessionVolume:
        return bestSessionVolumeLabel;
    }
  }

  String unitFor(ProgressionRecordType type) {
    switch (type) {
      case ProgressionRecordType.heaviestWeight:
      case ProgressionRecordType.oneRepMax:
        return weightUnit;
      case ProgressionRecordType.bestSetVolume:
      case ProgressionRecordType.bestSessionVolume:
        return volumeUnit;
    }
  }
}

/// [AD3] Per-exercise Personal Records list — Hevy's exercise Summary tab
/// "Personal Records" block: Heaviest Weight / Best 1RM / Best Set Volume /
/// Best Session Volume, each with the date first achieved.
///
/// Shared between the mobile coach shell and the web coach_hub shell (same
/// dedup convention as [ExerciseProgressionSection] — one widget, same data
/// in → same render out).
///
/// - Renders ONLY the record types present in [records] (SCENARIO-PR-LIST-03)
///   — a series with zero data points has no [PersonalRecord] entry (see
///   [derivePersonalRecords]'s empty-input contract).
/// - Empty [records] → [PersonalRecordsListLabels.emptyText], no section
///   title (SCENARIO-PR-LIST-02).
class PersonalRecordsList extends StatelessWidget {
  const PersonalRecordsList({
    super.key,
    required this.records,
    required this.labels,
  });

  final List<PersonalRecord> records;
  final PersonalRecordsListLabels labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    if (records.isEmpty) {
      return Text(
        labels.emptyText,
        style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
      );
    }

    return Column(
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
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < records.length; i++) ...[
                if (i > 0) Divider(color: palette.border, height: 18),
                _PersonalRecordRow(record: records[i], labels: labels),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonalRecordRow extends StatelessWidget {
  const _PersonalRecordRow({required this.record, required this.labels});

  final PersonalRecord record;
  final PersonalRecordsListLabels labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isOneRepMax = record.recordType == ProgressionRecordType.oneRepMax;
    final valStr = _formatValue(record.value, isOneRepMax: isOneRepMax);
    final unit = labels.unitFor(record.recordType);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labels.labelFor(record.recordType),
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _dateWithYear(record.achievedAt, labels.localeName),
                style:
                    GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
              ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              valStr,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: palette.accent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
