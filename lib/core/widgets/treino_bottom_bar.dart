import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import 'treino_icon.dart';

class TreinoBottomBar extends StatelessWidget {
  const TreinoBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              return Expanded(
                child: _BarItem(
                  label: item.label,
                  icon: item.icon,
                  iconActive: item.iconActive,
                  active: i == currentIndex,
                  onTap: () => onTap(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

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

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.label,
    required this.icon,
    required this.iconActive,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData iconActive;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = active ? palette.accent : palette.textMuted;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(active ? iconActive : icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
