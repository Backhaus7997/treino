import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../domain/muscle_group.dart';

/// Monthly set volume split across the 10 canonical muscle display groups.
///
/// Unlike the weekly volume card, this surface intentionally has no target:
/// turning a weekly prescription into a monthly target would invent semantics
/// around partial weeks. Bars therefore express only RELATIVE distribution
/// inside the selected month; its largest group fills the track.
class MonthlyVolumeByGroupCard extends StatelessWidget {
  const MonthlyVolumeByGroupCard({
    super.key,
    required this.setsByGroup,
  });

  final Map<MuscleGroupDisplay, int> setsByGroup;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final visibleGroups = MuscleGroupDisplay.displayOrder
        .where((group) => (setsByGroup[group] ?? 0) > 0)
        .toList(growable: false);
    final maxSets = visibleGroups.fold<int>(
      0,
      (maximum, group) =>
          (setsByGroup[group] ?? 0) > maximum ? setsByGroup[group]! : maximum,
    );

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.volumeByGroupScreenTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          if (visibleGroups.isEmpty)
            Text(
              l10n.monthlyVolumeByGroupEmpty,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
            )
          else
            for (final group in visibleGroups)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _MonthlyVolumeBarRow(
                  label: group.displayLabel,
                  sets: setsByGroup[group]!,
                  maxSets: maxSets,
                  valueLabel: l10n.monthlyVolumeByGroupSets(
                    setsByGroup[group]!,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MonthlyVolumeBarRow extends StatelessWidget {
  const _MonthlyVolumeBarRow({
    required this.label,
    required this.sets,
    required this.maxSets,
    required this.valueLabel,
  });

  final String label;
  final int sets;
  final int maxSets;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final ratio = maxSets == 0 ? 0.0 : sets / maxSets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: palette.bg,
            valueColor: AlwaysStoppedAnimation(palette.accent),
          ),
        ),
      ],
    );
  }
}
