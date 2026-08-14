import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// The bottom bar as the onboarding handoff draws it — a still, onboarding-only
/// rendering.
///
/// It is NOT `TreinoBottomBar`, and deliberately so. The handoff's version
/// differs from production in one visible way (the active tab is a solid accent
/// circle rather than the sliding gradient pill), and production's bar carries
/// a measured decision this must not quietly reverse:
///
///     NO BackdropFilter: blur re-samples on every frame content moves behind
///     the bar (extendBody) and dropped frames on device even at sigma 8
///     (2026-06-11)
///
/// Changing the real bar would restyle every screen in the app on the strength
/// of a mock-up. So the tour draws its own, and the app's nav is left alone.
///
/// ── On the numbers ──────────────────────────────────────────────────────────
/// The handoff quotes this bar as 46pt tall with 5.5pt labels. Those are the
/// mock's post-scale values: the nav is drawn inside the 220x456 mini-screen,
/// not in the 393pt content that gets scaled by 0.56. Dividing back out gives
/// 82 / 41 / 18 / 71 / icon 25 / label 9.8 — and production's label is exactly
/// 10pt, which is what confirms the reading. Taken literally, a 46pt bar with
/// 5.5pt labels would render at half size inside the preview.
class OnboardingNavBar extends StatelessWidget {
  const OnboardingNavBar({super.key, required this.activeIndex});

  /// 0 ENTRENAR · 1 FEED · 2 INICIO · 3 COACH · 4 PERFIL — the real tab order
  /// from `TreinoBottomBar._items`. INICIO is the middle tab, not the first.
  final int activeIndex;

  static const _items = <({IconData icon, IconData iconFill, String label})>[
    (
      icon: TreinoIcon.tabWorkout,
      iconFill: TreinoIcon.tabWorkoutFill,
      label: 'ENTRENAR',
    ),
    (
      icon: TreinoIcon.tabFeed,
      iconFill: TreinoIcon.tabFeedFill,
      label: 'FEED',
    ),
    (
      icon: TreinoIcon.tabHome,
      iconFill: TreinoIcon.tabHomeFill,
      label: 'INICIO',
    ),
    (
      icon: TreinoIcon.tabCoach,
      iconFill: TreinoIcon.tabCoachFill,
      label: 'COACH',
    ),
    (
      icon: TreinoIcon.tabProfile,
      iconFill: TreinoIcon.tabProfileFill,
      label: 'PERFIL',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Container(
        height: 82,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          // High-opacity fill instead of a blur, matching production's choice.
          color: palette.bgCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(41),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: i == activeIndex
                    ? _ActiveTab(item: _items[i])
                    : _InactiveTab(item: _items[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTab extends StatelessWidget {
  const _ActiveTab({required this.item});

  final ({IconData icon, IconData iconFill, String label}) item;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Center(
      child: Container(
        width: 71,
        height: 71,
        decoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.60),
              blurRadius: 32,
            ),
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Ink on accent — `onPrimary: palette.bg`. Dark in dark mode, NOT
            // white, even though it sits on green.
            Icon(item.iconFill, size: 25, color: palette.bg),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: GoogleFonts.barlowCondensed(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                height: 1.0,
                color: palette.bg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InactiveTab extends StatelessWidget {
  const _InactiveTab({required this.item});

  final ({IconData icon, IconData iconFill, String label}) item;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(item.icon, size: 25, color: palette.textMuted),
        const SizedBox(height: 5),
        Text(
          item.label,
          style: GoogleFonts.barlowCondensed(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            height: 1.0,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}
