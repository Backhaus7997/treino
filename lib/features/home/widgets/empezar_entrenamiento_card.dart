import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import 'home_cta_button.dart';

/// "Empezar Entrenamiento" card.
/// The day label is derived from the real current weekday; the remaining
/// strings are private static const, ready for provider-driven swap without
/// renaming the widget. Zero constructor params; no ref.watch / ref.read.
class EmpezarEntrenamientoCard extends StatelessWidget {
  const EmpezarEntrenamientoCard({super.key});

  static const _heroLabel = 'PUSH';
  static const _subtitle = 'Pecho · Hombros · Tríceps';
  static const _exerciseCount = '6 ejercicios';
  static const _duration = '~55 min';
  static const _ctaLabel = 'EMPEZAR ENTRENAMIENTO';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    // Derive the label from the real current weekday so it never shows a
    // stale "today". `dashboardDateToday` is "Hoy"; uppercased to match the
    // card's all-caps day label style.
    final dayLabel =
        '${l10n.dashboardDateToday.toUpperCase()} · ${_weekdayName(l10n, DateTime.now().weekday)}';

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day label
            Text(
              dayLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                letterSpacing: 1.4,
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 8),
            // Hero workout name
            Text(
              _heroLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 36,
                letterSpacing: 0.5,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            // Muscle groups subtitle
            Text(
              _subtitle,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            // Stat row
            Row(
              children: [
                Icon(TreinoIcon.tabWorkout, size: 16, color: palette.textMuted),
                const SizedBox(width: 8),
                Text(
                  _exerciseCount,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(width: 18),
                Icon(TreinoIcon.clock, size: 16, color: palette.textMuted),
                const SizedBox(width: 8),
                Text(
                  _duration,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            HomeCTAButton(
              label: _ctaLabel,
              leadingIcon: TreinoIcon.play,
              onPressed: () => context.go('/workout'),
            ),
          ],
        ),
      ),
    );
  }
}

String _weekdayName(AppL10n l10n, int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return l10n.dashboardWeekday1;
    case DateTime.tuesday:
      return l10n.dashboardWeekday2;
    case DateTime.wednesday:
      return l10n.dashboardWeekday3;
    case DateTime.thursday:
      return l10n.dashboardWeekday4;
    case DateTime.friday:
      return l10n.dashboardWeekday5;
    case DateTime.saturday:
      return l10n.dashboardWeekday6;
    default:
      return l10n.dashboardWeekday7;
  }
}
