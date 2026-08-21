import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../profile/domain/experience_level.dart';
import '../../domain/routine.dart';
import '../../domain/routine_day_duration.dart';

/// Visual variant of [RoutineCard]. Used to alternate between mint (accent)
/// and magenta (highlight) glow per the design mockup.
enum RoutineCardVariant { accent, highlight }

class RoutineCard extends StatelessWidget {
  const RoutineCard({
    required this.routine,
    this.variant = RoutineCardVariant.accent,
    this.reserveTitleLines = false,
    this.badge,
    super.key,
  });

  final Routine routine;
  final RoutineCardVariant variant;

  /// Optional chip rendered to the right of the icon square (e.g. the
  /// "DE TU COACH" [CoachChip] on the PLANTILLAS grid). Lives INSIDE the
  /// icon row — never overlaid — so it can't collide with the icon on narrow
  /// screens. The row is hard-capped to the icon square's 40px (SizedBox),
  /// so card heights stay deterministic whether the badge is present or not
  /// (see #402). At large accessibility text sizes the card becomes
  /// content-sized instead, so the badge remains fully legible.
  final Widget? badge;

  /// When true, the title block always reserves its full two lines even if
  /// the name fits in one — the card's height stops depending on how long the
  /// routine name is. Grid surfaces (Plantillas 2-up rows) rely on this to
  /// keep row heights aligned without an [IntrinsicHeight] pass per row,
  /// which janked the expanded catalog scroll (#402). Defaults to false so
  /// single-column surfaces (feed, profile) keep their content-sized look.
  final bool reserveTitleLines;

  /// Metadata caption: level, days per week and estimated session length.
  ///
  /// Replaces the old `level · N ej.` line (#639). That exercise count summed
  /// the slots of EVERY day, so a 5-day split read "30 ej." on a card the user
  /// parses as one session — it was not just insufficient, it was wrong. What
  /// the reader actually needs to choose a routine is how many days it asks of
  /// them and how long a session runs; the exact per-day exercise and set
  /// counts already live one tap away, on the detail screen's stat row.
  ///
  /// Duration is omitted entirely when nothing is measurable — never "0 min"
  /// or a dash. Trainer- and community-published routines carry no guaranteed
  /// duration data, so a placeholder there would be noise on exactly the part
  /// of the catalogue that is growing.
  List<String> _metaSegments(AppL10n l10n) {
    final segments = <String>[routine.level.displayNameEs];
    // A routine with no days is a valid but degenerate document (spec
    // SCENARIO-052; the detail screen has its own empty state for it).
    // "0 días/sem" would be noise, so the segment is dropped — same rule the
    // duration below follows.
    if (routine.days.isNotEmpty) {
      segments.add(l10n.routineCardDaysPerWeek(routine.days.length));
    }
    final duration = estimateRoutineSessionMinutes(routine);
    final minutes = duration.minutes;
    if (minutes != null) {
      // "~" marks a computed estimate, same convention the detail screen's
      // MINUTOS tile uses (see RoutineDayDuration).
      segments.add(
        l10n.routineCardMinutes(duration.authored ? '$minutes' : '~$minutes'),
      );
    }
    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final useAccessibleLayout = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    final tint = variant == RoutineCardVariant.highlight
        ? palette.highlight
        : palette.accent;

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: palette.textPrimary,
    );
    StrutStyle? titleStrut;
    if (reserveTitleLines && !useAccessibleLayout) {
      // Strut pins every title line to the style's own metrics even when a
      // glyph falls back to another font (e.g. an emoji in the name) —
      // without it the real line height could exceed the reservation
      // measured below and de-align the row pair again.
      titleStrut = StrutStyle.fromTextStyle(
        _effectiveStyle(context, titleStyle),
        forceStrutHeight: true,
      );
    }
    Widget title = Text(
      routine.name.toUpperCase(),
      style: titleStyle,
      strutStyle: titleStrut,
      maxLines: useAccessibleLayout ? null : 2,
      overflow:
          useAccessibleLayout ? TextOverflow.visible : TextOverflow.ellipsis,
    );
    if (reserveTitleLines && !useAccessibleLayout) {
      // minHeight (not a tight height) so a real two-line title can never be
      // clipped if the measured reservation is off by a sub-pixel.
      title = ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: _twoLinesHeight(context, titleStyle, titleStrut!),
        ),
        child: title,
      );
    }

    // Metadata caption. Three segments no longer fit one line on a 2-up grid
    // card, so it wraps to two — deliberately, because an ellipsis would eat
    // the duration, which is the whole datum #639 adds.
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: palette.textMuted,
    );
    StrutStyle? metaStrut;
    if (reserveTitleLines && !useAccessibleLayout) {
      metaStrut = StrutStyle.fromTextStyle(
        _effectiveStyle(context, metaStyle),
        forceStrutHeight: true,
      );
    }
    Widget meta = Text(
      _metaSegments(AppL10n.of(context)).join(' · '),
      style: metaStyle,
      strutStyle: metaStrut,
      maxLines: useAccessibleLayout ? null : 2,
      overflow:
          useAccessibleLayout ? TextOverflow.visible : TextOverflow.ellipsis,
    );
    if (reserveTitleLines && !useAccessibleLayout) {
      // Same reason the title reserves its lines: on a 2-up grid the caption
      // wraps to one or two lines depending on the routine, and a card whose
      // height tracks its own content de-aligns the row pair again (#402).
      meta = ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: _twoLinesHeight(context, metaStyle, metaStrut!),
        ),
        child: meta,
      );
    }

    // Icon square — tinted background matching the variant.
    final iconSquare = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: tint.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Icon(TreinoIcon.tabWorkout, color: tint, size: 20),
    );

    return TreinoTappable(
      onTap: () => context.push('/workout/routine/${routine.id}'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: tint.withValues(alpha: 0.35), width: 1),
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: 0.18),
              blurRadius: 18,
              spreadRadius: 0,
              offset: Offset.zero,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (badge == null)
              iconSquare
            else if (useAccessibleLayout) ...[
              iconSquare,
              const SizedBox(height: 8),
              badge!,
            ] else
              // Hard 40px cap: without it the row height tracks the chip
              // (Align shrink-wraps under an unbounded cross axis), and at
              // large accessibility text scales the chip outgrows the icon —
              // de-aligning the grid rows. Bounded, FittedBox scales the
              // chip down instead.
              SizedBox(
                height: 40,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    iconSquare,
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: badge,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            title,
            const SizedBox(height: 8),
            meta,
          ],
        ),
      ),
    );
  }

  /// Effective title style resolved the same way [Text] does it
  /// (DefaultTextStyle merge when the style inherits).
  static TextStyle _effectiveStyle(BuildContext context, TextStyle? style) {
    if (style != null && !style.inherit) return style;
    return DefaultTextStyle.of(context).style.merge(style);
  }

  /// Height of exactly two laid-out lines (same effective style,
  /// textScaler and strut the real title uses), so the reserved block matches
  /// what a two-line title occupies. Single O(1) measure per build — unlike
  /// [IntrinsicHeight], it never re-runs a dry-layout over the card subtree.
  static double _twoLinesHeight(
    BuildContext context,
    TextStyle? style,
    StrutStyle strut,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: '\n', style: _effectiveStyle(context, style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      strutStyle: strut,
      maxLines: 2,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
