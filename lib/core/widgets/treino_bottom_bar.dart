import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import 'treino_icon.dart';

/// Bottom bar de TREINO: pill flotante translúcida (fill de alta opacidad,
/// SIN blur — ver nota en el build), pill de gradient que se desliza al tab
/// activo, íconos `TreinoIcon` + labels Barlow Condensed.
class TreinoBottomBar extends StatelessWidget {
  const TreinoBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.coachUnreadCount = 0,
    this.feedUnreadCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Count of unread chats with the athlete's coach — shown as a badge on
  /// the COACH tab (index 3). Pass 0 (default) to hide the badge.
  final int coachUnreadCount;

  /// Count of unread chats with friends (user↔user, social) — shown as a
  /// badge on the FEED tab (index 1) so the user sees the alert without
  /// having to open the tab first. Pass 0 (default) to hide the badge.
  final int feedUnreadCount;

  static const List<_TabSpec> _items = [
    _TabSpec(
      label: 'ENTRENAR',
      icon: TreinoIcon.tabWorkout,
      iconActive: TreinoIcon.tabWorkoutFill,
    ),
    _TabSpec(
      label: 'FEED',
      icon: TreinoIcon.tabFeed,
      iconActive: TreinoIcon.tabFeedFill,
    ),
    _TabSpec(
      label: 'INICIO',
      icon: TreinoIcon.tabHome,
      iconActive: TreinoIcon.tabHomeFill,
    ),
    _TabSpec(
      label: 'COACH',
      icon: TreinoIcon.tabCoach,
      iconActive: TreinoIcon.tabCoachFill,
    ),
    _TabSpec(
      label: 'PERFIL',
      icon: TreinoIcon.tabProfile,
      iconActive: TreinoIcon.tabProfileFill,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        // Generous side/bottom margins lift the pill off the edges
        // (WhatsApp-style floating bar) — content scrolls visibly around it.
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: DecoratedBox(
          // Shadow lives OUTSIDE the ClipRRect — inside it gets clipped away.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: palette.bg.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(36),
            // NO BackdropFilter: blur re-samples on every frame content moves
            // behind the bar (extendBody) and dropped frames on device even at
            // sigma 8 (2026-06-11). A high-opacity fill keeps the translucent
            // floating look on the dark theme at zero per-frame cost.
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: palette.bgCard.withValues(alpha: 0.93),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: palette.border),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tabWidth = constraints.maxWidth / _items.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: AppMotion.slow,
                        curve: AppMotion.standard,
                        left: tabWidth * currentIndex + 8,
                        top: 8,
                        bottom: 8,
                        width: tabWidth - 16,
                        child: _PillHighlight(palette: palette),
                      ),
                      Row(
                        children: List.generate(_items.length, (i) {
                          final item = _items[i];
                          final active = i == currentIndex;
                          // Index 1 = FEED (social chats), index 3 = COACH
                          // (chats with the athlete's linked trainer). The
                          // two badges are mutually exclusive by construction
                          // — see `unreadFromFriendsProvider` and
                          // `unreadFromCoachProvider`.
                          final badgeCount = switch (i) {
                            1 => feedUnreadCount,
                            3 => coachUnreadCount,
                            _ => 0,
                          };
                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onTap(i),
                              child: _TabContent(
                                spec: item,
                                active: active,
                                palette: palette,
                                badgeCount: badgeCount,
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({
    required this.label,
    required this.icon,
    required this.iconActive,
  });

  final String label;
  final IconData icon;
  final IconData iconActive;
}

class _PillHighlight extends StatelessWidget {
  const _PillHighlight({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accent,
            Color.lerp(palette.accent, palette.highlight, 0.25)!,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.spec,
    required this.active,
    required this.palette,
    this.badgeCount = 0,
  });

  final _TabSpec spec;
  final bool active;
  final AppPalette palette;

  /// When > 0, renders a count badge over the tab icon.
  /// Values above 99 are shown as '99+'.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = active ? palette.bg : palette.textMuted;
    return AnimatedDefaultTextStyle(
      duration: AppMotion.base,
      style: GoogleFonts.barlowCondensed(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
      // Horizontal padding matches the pill's 8px margin on each side of the
      // tab (see AnimatedPositioned: left = tabWidth*i + 8, width = tabWidth
      // - 16). Without this, the label's box is `tabWidth` wide but the pill
      // is `tabWidth - 16` — so on the active tab, characters that extend
      // past the pill are rendered in `palette.bg` (near-black) over the
      // dark navbar bg and read as clipped (ENTRENAR → ENTRENR). Keeping the
      // label inside the pill box guarantees readable contrast everywhere.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: AppMotion.base,
                  switchInCurve: AppMotion.standard,
                  switchOutCurve: AppMotion.exit,
                  child: Icon(
                    active ? spec.iconActive : spec.icon,
                    key: ValueKey<bool>(active),
                    color: color,
                    size: 22,
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.barlow(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: palette.bg,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // FittedBox scales the label down to fit the pill width on
            // narrow tabs / >100% system text scaling rather than clipping.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(spec.label),
            ),
          ],
        ),
      ),
    );
  }
}
