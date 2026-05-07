import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import 'treino_icon.dart';

/// Bottom bar de TREINO inspirada en una navbar de iOS 26 con liquid glass:
/// container frosted con blur, pill de gradient que se desliza al tab activo,
/// íconos `TreinoIcon` + labels Barlow Condensed.
class TreinoBottomBar extends StatelessWidget {
  const TreinoBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: palette.bgCard.withOpacity(0.72),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: palette.border),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tabWidth = constraints.maxWidth / _items.length;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
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
                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onTap(i),
                              child: _TabContent(
                                spec: item,
                                active: active,
                                palette: palette,
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
            color: palette.accent.withOpacity(0.35),
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
  });

  final _TabSpec spec;
  final bool active;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = active ? palette.bg : palette.textMuted;
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 220),
      style: GoogleFonts.barlowCondensed(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Icon(
              active ? spec.iconActive : spec.icon,
              key: ValueKey<bool>(active),
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(spec.label),
        ],
      ),
    );
  }
}
