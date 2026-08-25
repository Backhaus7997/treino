/// The pieces the trainer previews are built from.
///
/// Unlike the athlete previews, these do NOT embed the app's real screens.
/// That is a deliberate reversal, and it is worth stating why: the athlete
/// previews mount real widgets inside a nested `ProviderScope`, and every bug
/// that reached a device came out of that seam — a `ListView` handed unbounded
/// height rendered the Coach slide EMPTY and froze the tour, `miCuotaProvider`
/// threw a Riverpod scoping assertion across the middle of a slide, and
/// `PostCard` silently dropped its photo because it loads over the network.
///
/// The trainer handoff does not ask for real widgets — it specifies the pixels
/// directly, and the data it wants is deliberately populated sample data that
/// no real account would produce. So these are drawn. No providers, no
/// viewports inherited from screens written for a full phone, no network
/// images: the entire class of failure is gone by construction.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../app/theme/tokens/primitives.dart';

/// Card shell: `bgCard`, hairline border, r-20 by default.
class TCard extends StatelessWidget {
  const TCard({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;

  /// Accent for the cards the handoff outlines in accent.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: borderColor ?? palette.border),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// A section title with an optional accent action on the right.
class TSectionHeader extends StatelessWidget {
  const TSectionHeader({super.key, required this.title, this.action});

  final String title;
  final String? action;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.barlowCondensed(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: palette.textPrimary,
            ),
          ),
        ),
        if (action case final a?) ...[
          const SizedBox(width: 8),
          Text(
            a,
            style: GoogleFonts.barlow(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.accent,
            ),
          ),
          const SizedBox(width: 2),
          Icon(TreinoIcon.chevronRight, size: 13, color: palette.accent),
        ],
      ],
    );
  }
}

/// Circular avatar with initials.
class TAvatar extends StatelessWidget {
  const TAvatar({
    super.key,
    required this.initials,
    this.size = 34,
    this.gradient = true,
    this.solid,
    this.ring = false,
  });

  final String initials;
  final double size;

  /// The accent→highlight gradient the app uses for people without a photo.
  final bool gradient;

  /// Overrides [gradient] with a flat fill (the handoff uses highlight for the
  /// coach's own avatar on slide 5).
  final Color? solid;

  /// Accent outline instead of a fill — the coach's own avatar on slide 1.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring ? null : (solid ?? (gradient ? null : palette.bgCard)),
        gradient: (!ring && solid == null && gradient)
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.accent, palette.highlight],
              )
            : null,
        border: ring ? Border.all(color: palette.accent, width: 1.5) : null,
      ),
      child: Text(
        initials,
        style: GoogleFonts.barlowCondensed(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          height: 1.0,
          // Initials on an accent-ish surface take `palette.bg` — dark ink in
          // dark mode, never white. On the ring variant the fill is the page,
          // so the text keeps its normal colour.
          color: ring ? palette.accent : palette.bg,
        ),
      ),
    );
  }
}

/// Small rounded chip.
class TChip extends StatelessWidget {
  const TChip({
    super.key,
    required this.label,
    required this.color,
    this.filled = false,
    this.fontSize = 10,
  });

  final String label;
  final Color color;

  /// Solid [color] background with `palette.bg` text, versus a tinted pill with
  /// coloured text.
  final bool filled;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          height: 1.0,
          color: filled ? palette.bg : color,
        ),
      ),
    );
  }
}

/// Full-width pill button.
class TButton extends StatelessWidget {
  const TButton({
    super.key,
    required this.label,
    this.icon,
    this.filled = true,
    this.outlineColor,
    this.height = 40,
  });

  final String label;
  final IconData? icon;

  /// Accent fill with `palette.bg` foreground, versus an outline.
  final bool filled;
  final Color? outlineColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final border = outlineColor ?? palette.border;
    // Ink on accent — `onPrimary: palette.bg`.
    final fg = filled ? palette.bg : (outlineColor ?? palette.textPrimary);

    return Container(
      width: double.infinity,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? palette.accent : Colors.transparent,
        border: filled ? null : Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon case final i?) ...[
            Icon(i, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.barlowCondensed(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-line text block used by list rows.
class TRowText extends StatelessWidget {
  const TRowText({
    super.key,
    required this.title,
    this.subtitle,
    this.titleCondensed = false,
  });

  final String title;
  final String? subtitle;
  final bool titleCondensed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleCondensed
              ? GoogleFonts.barlowCondensed(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: palette.textPrimary,
                )
              : GoogleFonts.barlow(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
        ),
        if (subtitle case final s?) ...[
          const SizedBox(height: 2),
          Text(
            s,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.barlow(
              fontSize: 12,
              color: palette.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// Hairline separator between rows inside a card.
class THairline extends StatelessWidget {
  const THairline({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(height: 1, color: palette.border);
  }
}
